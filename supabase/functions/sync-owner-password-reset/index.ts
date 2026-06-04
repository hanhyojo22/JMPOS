import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AdminClient = SupabaseClient;
type ResetBody = {
  password?: string;
};
type StoreRow = {
  id: string | null;
};
type AuthenticatedUser = {
  id: string;
  email: string;
};
const RESET_ATTEMPT_LIMIT = 5;
const RESET_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = (await req.json()) as ResetBody;
    const password = body.password ?? "";
    if (password.length < 6 || password.length > 128) {
      return json({ error: "Password must be 6 to 128 characters." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Password reset sync is not configured." }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const user = await authenticatedUser(admin, req);
    const attemptId = await recordPasswordResetAttempt(admin, user.id);
    try {
      const passwordHash = await sha256Hex(password);

      const { data: stores, error: storesError } = await admin
        .from("stores")
        .select("id")
        .eq("owner_user_id", user.id);
      if (storesError) throw storesError;

      const storeIds = ((stores ?? []) as StoreRow[])
        .map((store: StoreRow) => String(store.id ?? ""))
        .filter((id: string) => id.length > 0);

      let updated = 0;
      for (const storeId of storeIds) {
        updated += await updateOwnerRows(admin, storeId, passwordHash);
      }
      if (updated === 0 && user.email) {
        updated += await updateOwnerRowsByEmail(admin, user.email, passwordHash);
      }

      await markPasswordResetAttemptSucceeded(admin, attemptId);
      return json({ updated });
    } catch (error) {
      await markPasswordResetAttemptFailed(admin, attemptId, error);
      throw error;
    }
  } catch (error) {
    const message = error instanceof HttpError
      ? error.message
      : "Could not sync the POS owner password.";
    const status = error instanceof HttpError ? error.status : 500;
    return json({ error: message }, status);
  }
});

async function recordPasswordResetAttempt(admin: AdminClient, userId: string) {
  const windowStart = new Date(Date.now() - RESET_ATTEMPT_WINDOW_MS)
    .toISOString();
  const { count, error: countError } = await admin
    .from("password_reset_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("attempted_at", windowStart);
  if (countError) throw countError;
  if ((count ?? 0) >= RESET_ATTEMPT_LIMIT) {
    throw new HttpError(
      "Too many password reset attempts. Please wait 1 hour before trying again.",
      429,
    );
  }

  const { data, error: insertError } = await admin
    .from("password_reset_attempts")
    .insert({ user_id: userId })
    .select("id")
    .single();
  if (insertError) throw insertError;
  const attemptId = String(data?.id ?? "");
  if (!attemptId) {
    throw new HttpError("Could not record password reset attempt.", 500);
  }
  return attemptId;
}

async function markPasswordResetAttemptSucceeded(
  admin: AdminClient,
  attemptId: string,
) {
  const { error } = await admin
    .from("password_reset_attempts")
    .update({
      succeeded_at: new Date().toISOString(),
      failure_reason: null,
    })
    .eq("id", attemptId);
  if (error) throw error;
}

async function markPasswordResetAttemptFailed(
  admin: AdminClient,
  attemptId: string,
  error: unknown,
) {
  const { error: updateError } = await admin
    .from("password_reset_attempts")
    .update({
      failure_reason: failureReason(error),
    })
    .eq("id", attemptId);
  if (updateError) console.error("Could not mark reset attempt failed", updateError);
}

function failureReason(error: unknown) {
  const text = error instanceof Error ? error.message : String(error);
  return text.slice(0, 500);
}

async function authenticatedUser(
  admin: AdminClient,
  req: Request,
): Promise<AuthenticatedUser> {
  const token = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) throw new HttpError("Missing authorization token.", 401);

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError("Invalid or expired password reset session.", 401);
  }
  return {
    id: data.user.id,
    email: data.user.email?.trim().toLowerCase() ?? "",
  };
}

async function updateOwnerRows(
  admin: AdminClient,
  storeId: string,
  passwordHash: string,
) {
  const { data: rows, error } = await admin
    .from("users")
    .select("id, revision, payload")
    .eq("store_id", storeId)
    .or("role.eq.admin,local_role.eq.admin,role.eq.owner,local_role.eq.owner")
    .is("deleted_at", null);
  if (error) throw error;

  return await updateRows(admin, rows ?? [], passwordHash);
}

async function updateOwnerRowsByEmail(
  admin: AdminClient,
  email: string,
  passwordHash: string,
) {
  const { data: rows, error } = await admin
    .from("users")
    .select("id, revision, payload")
    .or("role.eq.admin,local_role.eq.admin,role.eq.owner,local_role.eq.owner")
    .or(`email.eq.${email},username.eq.${email}`)
    .is("deleted_at", null);
  if (error) throw error;

  return await updateRows(admin, rows ?? [], passwordHash);
}

async function updateRows(
  admin: AdminClient,
  rows: Record<string, unknown>[],
  passwordHash: string,
) {
  let updated = 0;
  for (const row of rows) {
    const payload = isRecord(row.payload) ? row.payload : {};
    const revision = Number(row.revision ?? 0) + 1;
    const { error: updateError } = await admin
      .from("users")
      .update({
        password_hash: passwordHash,
        payload: { ...payload, password_hash: passwordHash },
        revision,
        operation: "upsert",
        sync_event_id: `password-reset:${crypto.randomUUID()}`,
        cloud_updated_at: new Date().toISOString(),
      })
      .eq("id", row.id);
    if (updateError) throw updateError;
    updated += 1;
  }
  return updated;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
