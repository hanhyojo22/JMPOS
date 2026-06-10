import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedTables = new Set([
  "products",
  "sales",
  "users",
  "audit_logs",
  "shifts",
  "shift_readings",
]);
type AdminClient = SupabaseClient;
type SyncBody = {
  storeId?: string;
  queueKey?: string;
  tableName?: string;
  localId?: string;
  operation?: string;
  payload?: Record<string, unknown>;
  mirrorRow?: Record<string, unknown>;
  baseRevision?: number;
  forceDelete?: boolean;
  localQueueId?: number;
  createdAt?: string;
  updatedAt?: string;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = (await req.json()) as SyncBody;
    const storeId = uuid(body.storeId);
    const queueKey = text(body.queueKey, 240);
    const tableName = text(body.tableName, 40);
    const localId = text(body.localId, 120);
    const operation = body.operation === "delete" ? "delete" : "upsert";
    const baseRevision = nonNegativeInt(body.baseRevision);
    const forceDelete = operation === "delete" && body.forceDelete === true;
    if (!storeId || !queueKey || !allowedTables.has(tableName) || !localId) {
      return json({ error: "Valid sync event fields are required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Sync apply service is not configured" }, 500);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { token, userId } = await authenticatedUser(admin, req);
    await assertStoreMember(admin, storeId, userId);
    const device = await activeDevice(admin, storeId, userId, token);
    const eventVersion = text(body.updatedAt, 80) || crypto.randomUUID();
    const eventId = `${storeId}:${queueKey}:${eventVersion}`;

    const { data: existingEvent, error: existingEventError } = await admin
      .from("pos_sync_events")
      .select("applied_revision")
      .eq("event_id", eventId)
      .maybeSingle();
    if (existingEventError) throw existingEventError;
    if (
      existingEvent?.applied_revision !== null &&
      existingEvent?.applied_revision !== undefined
    ) {
      return json({
        applied: true,
        revision: Number(existingEvent.applied_revision),
        alreadyApplied: true,
      });
    }

    const { data: current, error: currentError } = await admin
      .from(tableName)
      .select("revision, deleted_at")
      .eq("store_id", storeId)
      .eq("local_id", localId)
      .maybeSingle();
    if (currentError) throw currentError;

    const currentRevision = Number(current?.revision ?? 0);
    const currentIsDeleted = Boolean(current?.deleted_at);
    const canReuseDeletedLocalId = operation === "upsert" && currentIsDeleted;
    if (
      !forceDelete && !canReuseDeletedLocalId &&
      currentRevision !== baseRevision
    ) {
      return await conflictResponse(admin, {
        storeId,
        deviceId: device.id,
        tableName,
        localId,
        operation,
        baseRevision,
        cloudRevision: currentRevision,
      });
    }

    const appliedRevision = currentRevision + 1;
    const now = new Date().toISOString();
    if (operation === "delete") {
      if (current) {
        const { data: applied, error } = await admin
          .from(tableName)
          .update({
            revision: appliedRevision,
            deleted_at: now,
            deleted_by_device_id: device.id,
            operation,
            sync_event_id: eventId,
            cloud_updated_at: now,
          })
          .eq("store_id", storeId)
          .eq("local_id", localId)
          .eq("revision", currentRevision)
          .select("revision")
          .maybeSingle();
        if (error) throw error;
        if (!applied) {
          return await conflictResponse(admin, {
            storeId,
            deviceId: device.id,
            tableName,
            localId,
            operation,
            baseRevision,
            cloudRevision: await cloudRevision(
              admin,
              tableName,
              storeId,
              localId,
            ),
          });
        }
      }
    } else {
      const mirrorRow = body.mirrorRow ?? {};
      const nextRow = {
        ...mirrorRow,
        store_id: storeId,
        local_id: localId,
        revision: appliedRevision,
        deleted_at: null,
        deleted_by_device_id: null,
        operation,
        sync_event_id: eventId,
        cloud_updated_at: now,
      };
      if (current) {
        const { data: applied, error } = await admin
          .from(tableName)
          .update(nextRow)
          .eq("store_id", storeId)
          .eq("local_id", localId)
          .eq("revision", currentRevision)
          .select("revision")
          .maybeSingle();
        if (error) throw error;
        if (!applied) {
          return await conflictResponse(admin, {
            storeId,
            deviceId: device.id,
            tableName,
            localId,
            operation,
            baseRevision,
            cloudRevision: await cloudRevision(
              admin,
              tableName,
              storeId,
              localId,
            ),
          });
        }
      } else {
        const { error } = await admin.from(tableName).insert(nextRow);
        if (error?.code === "23505") {
          return await conflictResponse(admin, {
            storeId,
            deviceId: device.id,
            tableName,
            localId,
            operation,
            baseRevision,
            cloudRevision: await cloudRevision(
              admin,
              tableName,
              storeId,
              localId,
            ),
          });
        }
        if (error) throw error;
      }
    }

    const { error: eventError } = await admin.from("pos_sync_events").upsert({
      event_id: eventId,
      store_id: storeId,
      device_id: device.id,
      local_queue_id: body.localQueueId ?? null,
      table_name: tableName,
      local_id: localId,
      operation,
      payload: JSON.stringify(body.payload ?? {}),
      base_revision: baseRevision,
      applied_revision: appliedRevision,
      created_at: body.createdAt ?? now,
      updated_at: body.updatedAt ?? now,
    }, { onConflict: "event_id" });
    if (eventError) throw eventError;

    return json({ applied: true, revision: appliedRevision });
  } catch (error) {
    const details = errorDetails(error);
    return json(
      {
        error: details.message,
        code: details.code,
        details: details.details,
        hint: details.hint,
      },
      error instanceof HttpError ? error.status : 500,
    );
  }
});

async function cloudRevision(
  admin: AdminClient,
  tableName: string,
  storeId: string,
  localId: string,
) {
  const { data, error } = await admin
    .from(tableName)
    .select("revision")
    .eq("store_id", storeId)
    .eq("local_id", localId)
    .maybeSingle();
  if (error) throw error;
  return Number(data?.revision ?? 0);
}

async function conflictResponse(
  admin: AdminClient,
  conflict: {
    storeId: string;
    deviceId: string;
    tableName: string;
    localId: string;
    operation: string;
    baseRevision: number;
    cloudRevision: number;
  },
) {
  const { error } = await admin.from("pos_sync_conflicts").insert({
    store_id: conflict.storeId,
    device_id: conflict.deviceId,
    table_name: conflict.tableName,
    local_id: conflict.localId,
    operation: conflict.operation,
    base_revision: conflict.baseRevision,
    cloud_revision: conflict.cloudRevision,
  });
  if (error) throw error;
  return json({
    code: "SYNC_CONFLICT",
    error: "Cloud row changed on another device",
    tableName: conflict.tableName,
    localId: conflict.localId,
    currentRevision: conflict.cloudRevision,
  }, 409);
}

async function authenticatedUser(admin: AdminClient, req: Request) {
  const token = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) throw new HttpError("Missing authorization token", 401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError("Invalid authorization token", 401);
  }
  return { token, userId: data.user.id };
}

async function assertStoreMember(
  admin: AdminClient,
  storeId: string,
  userId: string,
) {
  const { data, error } = await admin
    .from("store_members")
    .select("store_id")
    .eq("store_id", storeId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError("Store access denied", 403);
}

async function activeDevice(
  admin: AdminClient,
  storeId: string,
  userId: string,
  token: string,
) {
  const sessionId = jwtSessionId(token);
  if (!sessionId) throw new HttpError("Cloud session id is missing", 401);
  const { data, error } = await admin
    .from("store_devices")
    .select("id, revoked_at, store_invites(status, license_expires_at)")
    .eq("store_id", storeId)
    .eq("cloud_session_user_id", userId)
    .eq("cloud_session_id", sessionId)
    .is("revoked_at", null)
    .maybeSingle();
  if (error) throw error;
  const invite = Array.isArray(data?.store_invites)
    ? data.store_invites[0]
    : data?.store_invites;
  if (
    !data || !invite || (invite.status !== "active" && invite.status !== "used")
  ) {
    throw new HttpError("This device is not authorized for cloud sync", 403);
  }
  if (
    invite.license_expires_at &&
    new Date(invite.license_expires_at) <= new Date()
  ) {
    throw new HttpError("This license has expired", 403);
  }
  return data;
}

function jwtSessionId(token: string) {
  try {
    const payload = token.split(".")[1];
    if (!payload) return "";
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const decoded = JSON.parse(
      atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")),
    ) as Record<string, unknown>;
    return uuid(decoded.session_id);
  } catch (_) {
    return "";
  }
}

function uuid(value: unknown) {
  const result = String(value ?? "").trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(result)
    ? result
    : "";
}
function text(value: unknown, max: number) {
  const result = String(value ?? "").trim();
  return result && result.length <= max ? result : "";
}
function nonNegativeInt(value: unknown) {
  const result = Number(value ?? 0);
  return Number.isInteger(result) && result >= 0 ? result : 0;
}
function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function errorDetails(error: unknown) {
  if (error instanceof Error) {
    return {
      message: error.message || "Cloud sync failed.",
      code: "",
      details: "",
      hint: "",
    };
  }
  if (error && typeof error === "object") {
    const record = error as Record<string, unknown>;
    return {
      message: textOrEmpty(record.message) ||
        textOrEmpty(record.error_description) ||
        textOrEmpty(record.error) ||
        "Cloud sync failed.",
      code: textOrEmpty(record.code),
      details: textOrEmpty(record.details),
      hint: textOrEmpty(record.hint),
    };
  }
  return {
    message: String(error || "Cloud sync failed."),
    code: "",
    details: "",
    hint: "",
  };
}
function textOrEmpty(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}
class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
