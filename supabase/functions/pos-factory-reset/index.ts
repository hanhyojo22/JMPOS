import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const cloudImagePrefix = "supabase-storage://";
const productImagePrefix = "sync_images/products";
const imageRetentionDays = 30;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const resetTables = [
  "shift_readings",
  "sales",
  "shifts",
  "products",
  "audit_logs",
] as const;

type AdminClient = SupabaseClient;
type FactoryResetBody = {
  storeId?: string;
  bucket?: string;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as FactoryResetBody;
    const storeId = uuid(body.storeId);
    const bucket = bucketName(body.bucket) || "backupfiles";
    if (!storeId) return json({ error: "Valid store id is required" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Factory reset service is not configured" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { token, userId } = await authenticatedUser(admin, req);
    await assertStoreOwner(admin, storeId, userId);
    const device = await activeDevice(admin, storeId, userId, token);

    const now = new Date().toISOString();
    const images = await markProductImagesForRetention({
      admin,
      storeId,
      bucket,
      userId,
      now,
    });
    const tableCounts = await softDeleteBusinessRows({
      admin,
      storeId,
      deviceId: device.id,
      now,
    });
    const conflictsCleared = await clearSyncConflicts(admin, storeId);

    return json({
      reset: true,
      storeId,
      tableCounts,
      images,
      conflictsCleared,
    });
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

async function softDeleteBusinessRows(args: {
  admin: AdminClient;
  storeId: string;
  deviceId: string;
  now: string;
}) {
  const counts: Record<string, number> = {};
  for (const table of resetTables) {
    const { data, error } = await args.admin
      .from(table)
      .update({
        deleted_at: args.now,
        deleted_by_device_id: args.deviceId,
        operation: "delete",
        cloud_updated_at: args.now,
      })
      .eq("store_id", args.storeId)
      .is("deleted_at", null)
      .select("id");
    if (error) throw error;
    counts[table] = data?.length ?? 0;
  }
  return counts;
}

async function markProductImagesForRetention(args: {
  admin: AdminClient;
  storeId: string;
  bucket: string;
  userId: string;
  now: string;
}) {
  const { data, error } = await args.admin
    .from("products")
    .select("local_id, image_url, payload")
    .eq("store_id", args.storeId)
    .is("deleted_at", null);
  if (error) throw error;

  const purgeAfterAt = purgeAfterDate();
  let softDeleted = 0;
  for (const row of data ?? []) {
    const localId = text(row.local_id, 120) || "unknown";
    const imageReference = imageReferenceFromProduct(row);
    const objectPath = objectPathForProductImage(
      args.storeId,
      localId,
      args.bucket,
      imageReference,
    );
    if (!objectPath) continue;

    await upsertDeletion(args.admin, {
      storeId: args.storeId,
      localId,
      bucket: args.bucket,
      objectPath,
      imageReference,
      syncEventId: `${args.storeId}:factory-reset:${args.now}`,
      reason: "factory_reset",
      status: "soft_deleted",
      userId: args.userId,
      purgeAfterAt,
    });
    softDeleted += 1;
  }

  const purged = await purgeExpiredImageDeletions({
    admin: args.admin,
    storeId: args.storeId,
    bucket: args.bucket,
  });

  return {
    softDeleted,
    purged,
    purgeAfterAt: purgeAfterAt.toISOString(),
  };
}

function imageReferenceFromProduct(row: Record<string, unknown>) {
  const imageUrl = text(row.image_url, 2000);
  if (imageUrl) return imageUrl;
  const payload = row.payload;
  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    return text((payload as Record<string, unknown>).image_url, 2000);
  }
  if (typeof payload === "string" && payload.trim()) {
    try {
      const decoded = JSON.parse(payload) as Record<string, unknown>;
      return text(decoded.image_url, 2000);
    } catch (_) {
      return "";
    }
  }
  return "";
}

async function upsertDeletion(
  admin: AdminClient,
  row: {
    storeId: string;
    localId: string;
    bucket: string;
    objectPath: string;
    imageReference: string | null;
    syncEventId: string;
    reason: string;
    status: "soft_deleted" | "completed" | "failed";
    userId: string;
    purgeAfterAt?: Date;
  },
) {
  const now = new Date().toISOString();
  const { error } = await admin.from("product_image_deletions").upsert(
    {
      store_id: row.storeId,
      local_product_id: row.localId,
      bucket_id: row.bucket,
      object_path: row.objectPath,
      image_reference: row.imageReference,
      sync_event_id: row.syncEventId,
      reason: row.reason,
      status: row.status,
      requested_by: row.userId,
      requested_at: now,
      purge_after_at: row.purgeAfterAt?.toISOString() ?? null,
      completed_at: row.status === "completed" ? now : null,
      last_error: null,
    },
    { onConflict: "store_id,bucket_id,object_path" },
  );
  if (error) throw error;
}

async function purgeExpiredImageDeletions(args: {
  admin: AdminClient;
  storeId: string;
  bucket: string;
}) {
  const { data, error } = await args.admin
    .from("product_image_deletions")
    .select("object_path")
    .eq("store_id", args.storeId)
    .eq("bucket_id", args.bucket)
    .eq("status", "soft_deleted")
    .lte("purge_after_at", new Date().toISOString())
    .limit(1000);
  if (error) throw error;

  const paths = ((data ?? []) as Array<{ object_path?: string }>)
    .map((row) => text(row.object_path, 2000))
    .filter((path) => path && belongsToStore(args.storeId, path));
  if (paths.length === 0) return 0;

  const { error: removeError } = await args.admin.storage
    .from(args.bucket)
    .remove(paths);
  if (removeError) {
    for (const path of paths) {
      await setDeletionStatus(args.admin, args.storeId, args.bucket, path, {
        status: "failed",
        last_error: removeError.message,
      });
    }
    throw removeError;
  }

  for (const path of paths) {
    await setDeletionStatus(args.admin, args.storeId, args.bucket, path, {
      status: "completed",
      completed_at: new Date().toISOString(),
      last_error: null,
    });
  }
  return paths.length;
}

async function setDeletionStatus(
  admin: AdminClient,
  storeId: string,
  bucket: string,
  objectPath: string,
  values: Record<string, unknown>,
) {
  const { error } = await admin
    .from("product_image_deletions")
    .update(values)
    .eq("store_id", storeId)
    .eq("bucket_id", bucket)
    .eq("object_path", objectPath);
  if (error) throw error;
}

async function clearSyncConflicts(admin: AdminClient, storeId: string) {
  const { count, error } = await admin
    .from("pos_sync_conflicts")
    .delete({ count: "exact" })
    .eq("store_id", storeId);
  if (error) throw error;
  return count ?? 0;
}

function objectPathForProductImage(
  storeId: string,
  localId: string,
  bucket: string,
  imagePath?: string | null,
) {
  const parsed = parseStorageReference(imagePath);
  if (parsed) {
    if (parsed.bucket !== bucket) {
      throw new Error("Image bucket does not match");
    }
    if (!belongsToStore(storeId, parsed.objectPath)) {
      throw new Error("Image path does not belong to this store");
    }
    return parsed.objectPath;
  }

  const path = text(imagePath, 2000);
  if (!path || path.startsWith("http")) return "";
  return `${storeId}/${productImagePrefix}/${localId}${imageExtension(path)}`;
}

function parseStorageReference(value: unknown) {
  const valueText = text(value, 2000);
  if (!valueText.startsWith(cloudImagePrefix)) return null;
  const reference = valueText.slice(cloudImagePrefix.length);
  const separator = reference.indexOf("/");
  if (separator <= 0 || separator === reference.length - 1) return null;
  return {
    bucket: reference.slice(0, separator),
    objectPath: reference.slice(separator + 1),
  };
}

function belongsToStore(storeId: string, objectPath: string) {
  return objectPath.startsWith(`${storeId}/${productImagePrefix}/`);
}

function purgeAfterDate() {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + imageRetentionDays);
  return date;
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

async function assertStoreOwner(
  admin: AdminClient,
  storeId: string,
  userId: string,
) {
  const { data, error } = await admin
    .from("stores")
    .select("owner_user_id")
    .eq("id", storeId)
    .maybeSingle();
  if (error) throw error;
  if (!data || data.owner_user_id !== userId) {
    throw new HttpError(
      "Only the store owner can factory reset cloud data",
      403,
    );
  }
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
    throw new HttpError("This device is not authorized for cloud reset", 403);
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

function bucketName(value: unknown) {
  const result = text(value, 120);
  return /^[a-zA-Z0-9._-]+$/.test(result) ? result : "";
}

function text(value: unknown, max: number) {
  const result = String(value ?? "").trim();
  return result && result.length <= max ? result : "";
}

function imageExtension(path: string) {
  const match = path.toLowerCase().match(/\.(png|jpe?g|webp|gif)$/);
  return match ? match[0].replace(".jpeg", ".jpg") : ".jpg";
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
      message: error.message || "Factory reset failed.",
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
        "Factory reset failed.",
      code: textOrEmpty(record.code),
      details: textOrEmpty(record.details),
      hint: textOrEmpty(record.hint),
    };
  }
  return {
    message: String(error || "Factory reset failed."),
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
