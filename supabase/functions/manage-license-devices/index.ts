import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ManageDevicesBody = {
  action?: "list" | "revoke";
  storeId?: string;
  installationId?: string;
  deviceId?: string;
};

type AdminClient = SupabaseClient;
type DeviceRow = {
  id: string;
  device_name: string | null;
  installation_id_hash: string;
  activated_at: string;
  last_seen_at: string;
  revoked_at: string | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as ManageDevicesBody;
    const action = body.action;
    const storeId = sanitizeUuid(body.storeId);
    const installationId = sanitizeToken(body.installationId, 120);

    if (action !== "list" && action !== "revoke") {
      return jsonResponse({ error: "Unsupported action" }, 400);
    }
    if (!storeId) return jsonResponse({ error: "Valid store id is required" }, 400);
    if (!installationId) {
      return jsonResponse({ error: "Installation id is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Device management service is not configured" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const userId = await authenticatedUserId(admin, req);
    await assertStoreOwner(admin, storeId, userId);

    const installationIdHash = await sha256Hex(installationId);
    if (action === "list") {
      return jsonResponse(await listDevices(admin, storeId, installationIdHash));
    }

    const deviceId = sanitizeUuid(body.deviceId);
    if (!deviceId) return jsonResponse({ error: "Valid device id is required" }, 400);
    return jsonResponse(
      await revokeDevice(admin, storeId, deviceId, installationIdHash),
    );
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      error instanceof AuthError ? error.status : 500,
    );
  }
});

async function listDevices(
  admin: AdminClient,
  storeId: string,
  installationIdHash: string,
) {
  const { data: devices, error: devicesError } = await admin
    .from("store_devices")
    .select("id, device_name, installation_id_hash, activated_at, last_seen_at, revoked_at")
    .eq("store_id", storeId)
    .order("activated_at", { ascending: true });
  if (devicesError) throw devicesError;

  const { data: invite, error: inviteError } = await admin
    .from("store_invites")
    .select("device_slot_limit")
    .eq("store_id", storeId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (inviteError) throw inviteError;

  const rows = (devices ?? []) as DeviceRow[];
  const activeDeviceCount = rows.filter((device) => !device.revoked_at).length;
  return {
    slotLimit: invite?.device_slot_limit ?? 1,
    activeDeviceCount,
    devices: rows.map((device) => ({
      id: device.id,
      name: device.device_name || "POS Device",
      isCurrent: device.installation_id_hash === installationIdHash,
      activatedAt: device.activated_at,
      lastSeenAt: device.last_seen_at,
      revokedAt: device.revoked_at,
    })),
  };
}

async function revokeDevice(
  admin: AdminClient,
  storeId: string,
  deviceId: string,
  installationIdHash: string,
) {
  const { data: device, error: deviceError } = await admin
    .from("store_devices")
    .select("id, installation_id_hash, revoked_at")
    .eq("id", deviceId)
    .eq("store_id", storeId)
    .maybeSingle();
  if (deviceError) throw deviceError;
  if (!device) throw new AuthError("Device was not found for this store", 404);
  if (device.installation_id_hash === installationIdHash) {
    throw new AuthError("The current device cannot revoke itself", 400);
  }
  if (device.revoked_at) return { revoked: true };

  const { error: updateError } = await admin
    .from("store_devices")
    .update({
      revoked_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", deviceId)
    .eq("store_id", storeId);
  if (updateError) throw updateError;

  return { revoked: true };
}

async function authenticatedUserId(admin: AdminClient, req: Request) {
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new AuthError("Missing authorization token", 401);

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new AuthError("Invalid authorization token", 401);
  return data.user.id;
}

async function assertStoreOwner(
  admin: AdminClient,
  storeId: string,
  userId: string,
) {
  const { data, error } = await admin
    .from("store_members")
    .select("role")
    .eq("store_id", storeId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new AuthError("Store access denied", 403);
  if (data.role !== "owner") throw new AuthError("Owner access is required", 403);
}

function sanitizeUuid(value: unknown) {
  const text = String(value ?? "").trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(text)
    ? text
    : "";
}

function sanitizeToken(value: unknown, maxLength: number) {
  const token = String(value ?? "").trim();
  if (token.length > maxLength) return "";
  return /^[a-zA-Z0-9_.:-]+$/.test(token) ? token : "";
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

class AuthError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
