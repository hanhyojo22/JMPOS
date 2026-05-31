import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AdminClient = SupabaseClient;
type Body = {
  action?: string;
  inviteId?: string;
  label?: string;
  durationMonths?: number;
  licenseExpiresAt?: string;
  slotLimit?: number;
  search?: string;
  status?: string;
  deviceId?: string;
};
type StoreJoin = {
  id: string;
  name: string | null;
  owner_user_id?: string | null;
};
type LicenseDevice = {
  id: string;
  device_name: string | null;
  activated_at: string | null;
  last_seen_at: string | null;
  revoked_at: string | null;
};
type LicenseRow = {
  id: string;
  label: string | null;
  status: string;
  store_id: string | null;
  device_slot_limit: number;
  used_count: number;
  created_at: string;
  used_at: string | null;
  license_expires_at: string | null;
  stores: StoreJoin | StoreJoin[] | null;
  store_devices: LicenseDevice[] | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = (await req.json()) as Body;
    const admin = serviceClient();
    const adminUserId = await authenticatedAdminId(admin, req);

    switch (body.action) {
      case "dashboard":
        return json(await dashboard(admin));
      case "list":
        return json(await listLicenses(admin, body));
      case "details":
        return json(await licenseDetails(admin, requiredUuid(body.inviteId)));
      case "create":
        return json(await createLicense(admin, adminUserId, body));
      case "renew":
        return json(await renewLicense(admin, adminUserId, body));
      case "set-expiry-date":
        return json(await setExpiryDate(admin, adminUserId, body));
      case "set-slot-limit":
        return json(await setSlotLimit(admin, adminUserId, body));
      case "suspend":
        return json(await setStatus(admin, adminUserId, body, "suspended"));
      case "reactivate":
        return json(await setStatus(admin, adminUserId, body, "active"));
      case "revoke-device":
        return json(await revokeDevice(admin, adminUserId, body));
      case "replace-unused-code":
        return json(await replaceUnusedCode(admin, adminUserId, body));
      case "remove-unused":
        return json(await removeUnusedLicense(admin, adminUserId, body));
      default:
        return json({ error: "Unsupported action" }, 400);
    }
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      error instanceof HttpError ? error.status : 500,
    );
  }
});

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new HttpError("Admin service is not configured", 500);
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function authenticatedAdminId(admin: AdminClient, req: Request) {
  const token = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) throw new HttpError("Missing authorization token", 401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError("Invalid authorization token", 401);
  const { data: allowed, error: allowedError } = await admin
    .from("license_admins")
    .select("user_id")
    .eq("user_id", data.user.id)
    .maybeSingle();
  if (allowedError) throw allowedError;
  if (!allowed) throw new HttpError("License administrator access is required", 403);
  return data.user.id;
}

async function dashboard(admin: AdminClient) {
  const rows = await licenseRows(admin);
  const ownerEmails = await ownerEmailMap(admin, rows);
  const now = Date.now();
  const soon = now + 30 * 86400000;
  return {
    total: rows.length,
    active: rows.filter((row) => licenseState(row) === "active").length,
    expiring: rows.filter((row) => {
      const expiry = dateMs(row.license_expires_at);
      return expiry !== null && expiry >= now && expiry <= soon;
    }).length,
    expired: rows.filter((row) => licenseState(row) === "expired").length,
    suspended: rows.filter((row) => licenseState(row) === "suspended").length,
    activeDevices: rows.reduce((sum, row) => sum + activeDevices(row), 0),
    recent: rows
      .sort((a, b) => lastActivity(b) - lastActivity(a))
      .slice(0, 8)
      .map((row) => toLicenseSummary(row, ownerEmails)),
  };
}

async function listLicenses(admin: AdminClient, body: Body) {
  const search = sanitizeText(body.search, 80).toLowerCase();
  const status = sanitizeText(body.status, 20).toLowerCase();
  const rows = await licenseRows(admin);
  const ownerEmails = await ownerEmailMap(admin, rows);
  return {
    licenses: rows
      .map((row) => toLicenseSummary(row, ownerEmails))
      .filter((row) => !status || row.state === status)
      .filter((row) =>
        !search ||
        row.label.toLowerCase().includes(search) ||
        row.storeName.toLowerCase().includes(search) ||
        row.ownerEmail.toLowerCase().includes(search)
      ),
  };
}

async function licenseDetails(admin: AdminClient, inviteId: string) {
  const { data: invite, error } = await admin
    .from("store_invites")
    .select("id, label, status, store_id, device_slot_limit, used_count, created_at, used_at, license_expires_at, stores(id, name, owner_user_id), store_devices(id, device_name, activated_at, last_seen_at, revoked_at)")
    .eq("id", inviteId)
    .single();
  if (error) throw error;
  const typedInvite = invite as LicenseRow;
  const ownerEmail = await emailForUser(admin, storeFor(typedInvite)?.owner_user_id);
  const { data: audit, error: auditError } = await admin
    .from("license_admin_audit_logs")
    .select("id, action, before_values, after_values, created_at")
    .eq("invite_id", inviteId)
    .order("created_at", { ascending: false })
    .limit(50);
  if (auditError) throw auditError;
  return { license: { ...toLicenseSummary(typedInvite, new Map([[storeFor(typedInvite)?.owner_user_id ?? "", ownerEmail]])), devices: typedInvite.store_devices ?? [] }, audit: audit ?? [] };
}

async function createLicense(admin: AdminClient, adminUserId: string, body: Body) {
  const label = sanitizeText(body.label, 100);
  if (!label) throw new HttpError("Customer or license label is required", 400);
  const slotLimit = positiveInt(body.slotLimit, 1, 100);
  const durationMonths = positiveInt(body.durationMonths, 12, 120);
  const code = licenseCode();
  const { data, error } = await admin
    .from("store_invites")
    .insert({
      code_hash: await sha256Hex(code),
      label,
      max_uses: 1,
      device_slot_limit: slotLimit,
      license_duration_months: durationMonths,
      status: "active",
    })
    .select("id, label, device_slot_limit, license_duration_months, status, created_at")
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, data.id, "create", null, { ...data, durationMonths });
  return { license: data, code, durationMonths };
}

async function renewLicense(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const durationMonths = positiveInt(body.durationMonths, 12, 120);
  const before = await inviteById(admin, inviteId);
  const base = Math.max(Date.now(), dateMs(before.license_expires_at) ?? Date.now());
  const expiry = addMonths(new Date(base), durationMonths).toISOString();
  const { data, error } = await admin
    .from("store_invites")
    .update({ license_expires_at: expiry, status: "active" })
    .eq("id", inviteId)
    .select()
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, "renew", before, data);
  return { licenseExpiresAt: expiry };
}

async function setExpiryDate(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const expiry = requiredIsoDate(body.licenseExpiresAt);
  const before = await inviteById(admin, inviteId);
  const { data, error } = await admin
    .from("store_invites")
    .update({ license_expires_at: expiry, status: "active" })
    .eq("id", inviteId)
    .select()
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, "set-expiry-date", before, data);
  return { licenseExpiresAt: expiry };
}

async function setSlotLimit(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const slotLimit = positiveInt(body.slotLimit, 1, 100);
  const before = await inviteById(admin, inviteId);
  const { data, error } = await admin
    .from("store_invites")
    .update({ device_slot_limit: slotLimit })
    .eq("id", inviteId)
    .select()
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, "set-slot-limit", before, data);
  return { slotLimit };
}

async function setStatus(admin: AdminClient, adminUserId: string, body: Body, status: string) {
  const inviteId = requiredUuid(body.inviteId);
  const before = await inviteById(admin, inviteId);
  const { data, error } = await admin
    .from("store_invites")
    .update({ status })
    .eq("id", inviteId)
    .select()
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, status, before, data);
  return { status };
}

async function revokeDevice(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const deviceId = requiredUuid(body.deviceId);
  const { data: before, error: beforeError } = await admin
    .from("store_devices")
    .select("id, invite_id, revoked_at")
    .eq("id", deviceId)
    .eq("invite_id", inviteId)
    .maybeSingle();
  if (beforeError) throw beforeError;
  if (!before) throw new HttpError("Device was not found for this license", 404);
  const revokedAt = new Date().toISOString();
  const { error } = await admin.from("store_devices").update({ revoked_at: revokedAt, cloud_session_id: null, cloud_session_user_id: null, updated_at: revokedAt }).eq("id", deviceId);
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, "revoke-device", before, { ...before, revoked_at: revokedAt });
  return { revoked: true };
}

async function replaceUnusedCode(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const before = await unusedInviteById(admin, inviteId);
  const code = licenseCode();
  const { data, error } = await admin
    .from("store_invites")
    .update({ code_hash: await sha256Hex(code) })
    .eq("id", inviteId)
    .select()
    .single();
  if (error) throw error;
  await audit(admin, adminUserId, inviteId, "replace-unused-code", before, data);
  return { code };
}

async function removeUnusedLicense(admin: AdminClient, adminUserId: string, body: Body) {
  const inviteId = requiredUuid(body.inviteId);
  const before = await unusedInviteById(admin, inviteId);
  await audit(admin, adminUserId, inviteId, "remove-unused", before, null);
  const { error } = await admin.from("store_invites").delete().eq("id", inviteId);
  if (error) throw error;
  return { removed: true };
}

async function licenseRows(admin: AdminClient) {
  const { data, error } = await admin
    .from("store_invites")
    .select("id, label, status, store_id, device_slot_limit, used_count, created_at, used_at, license_expires_at, stores(id, name, owner_user_id), store_devices(id, device_name, activated_at, last_seen_at, revoked_at)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as LicenseRow[];
}

function toLicenseSummary(row: LicenseRow, ownerEmails: Map<string, string>) {
  const store = storeFor(row);
  return {
    id: row.id,
    label: row.label ?? "Unlabeled license",
    state: licenseState(row),
    rawStatus: row.status,
    storeId: row.store_id,
    storeName: store?.name ?? "Not activated",
    ownerEmail: ownerEmails.get(store?.owner_user_id ?? "") ?? "",
    slotLimit: row.device_slot_limit ?? 1,
    activeDeviceCount: activeDevices(row),
    createdAt: row.created_at,
    activatedAt: row.used_at,
    licenseExpiresAt: row.license_expires_at,
    lastActivityAt: latestDeviceSeen(row),
  };
}

async function ownerEmailMap(admin: AdminClient, rows: LicenseRow[]) {
  const ownerIds = new Set(
    rows
      .map((row) => storeFor(row)?.owner_user_id)
      .filter((value): value is string => Boolean(value)),
  );
  const emails = new Map<string, string>();
  let page = 1;
  const perPage = 1000;
  while (ownerIds.size > emails.size) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    for (const user of data.users) {
      if (ownerIds.has(user.id)) emails.set(user.id, user.email ?? "");
    }
    if (data.users.length < perPage) break;
    page += 1;
  }
  return emails;
}

function licenseState(row: LicenseRow) {
  if (row.status === "suspended" || row.status === "revoked") return row.status;
  const expiry = dateMs(row.license_expires_at);
  if (expiry !== null && expiry < Date.now()) return "expired";
  return row.store_id ? "active" : "unused";
}
function activeDevices(row: LicenseRow) { return (row.store_devices ?? []).filter((device) => !device.revoked_at).length; }
function storeFor(row: LicenseRow) { return Array.isArray(row.stores) ? row.stores[0] : row.stores; }
function latestDeviceSeen(row: LicenseRow) {
  return (row.store_devices ?? [])
    .map((device) => device.last_seen_at)
    .filter((value): value is string => Boolean(value))
    .sort()
    .at(-1) ?? null;
}
function lastActivity(row: LicenseRow) { return dateMs(latestDeviceSeen(row)) ?? dateMs(row.created_at) ?? 0; }
function dateMs(value: unknown) { const ms = Date.parse(String(value ?? "")); return Number.isFinite(ms) ? ms : null; }
function addMonths(date: Date, months: number) { const copy = new Date(date); copy.setUTCMonth(copy.getUTCMonth() + months); return copy; }
function sanitizeText(value: unknown, max: number) { return replaceAsciiControlCharacters(String(value ?? "")).replace(/\s+/g, " ").trim().slice(0, max); }
function replaceAsciiControlCharacters(value: string) { return Array.from(value, (character) => { const code = character.charCodeAt(0); return code <= 31 || code === 127 ? " " : character; }).join(""); }
function positiveInt(value: unknown, fallback: number, max: number) { const n = Number(value ?? fallback); if (!Number.isInteger(n) || n < 1 || n > max) throw new HttpError("Invalid numeric value", 400); return n; }
function requiredUuid(value: unknown) { const id = String(value ?? "").trim(); if (!/^[0-9a-f-]{36}$/i.test(id)) throw new HttpError("Valid id is required", 400); return id; }
function requiredIsoDate(value: unknown) { const date = new Date(String(value ?? "")); if (!Number.isFinite(date.getTime())) throw new HttpError("Valid expiry date is required", 400); return date.toISOString(); }
function licenseCode() { const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; const part = () => Array.from(crypto.getRandomValues(new Uint8Array(5))).map((n) => alphabet[n % alphabet.length]).join(""); return `${part()}-${part()}-${part()}`; }
async function sha256Hex(value: string) { const bytes = new TextEncoder().encode(value); const digest = await crypto.subtle.digest("SHA-256", bytes); return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join(""); }
async function inviteById(admin: AdminClient, id: string) { const { data, error } = await admin.from("store_invites").select().eq("id", id).single(); if (error) throw error; return data; }
async function unusedInviteById(admin: AdminClient, id: string) { const invite = await inviteById(admin, id); if (invite.store_id || invite.used_count !== 0 || invite.used_at) throw new HttpError("Only unused licenses can be changed or removed", 409); return invite; }
async function emailForUser(admin: AdminClient, id?: string | null) { if (!id) return ""; const { data, error } = await admin.auth.admin.getUserById(id); if (error) throw error; return data.user?.email ?? ""; }
async function audit(admin: AdminClient, userId: string, inviteId: string, action: string, before: unknown, after: unknown) { const { error } = await admin.from("license_admin_audit_logs").insert({ admin_user_id: userId, invite_id: inviteId, action, before_values: before, after_values: after }); if (error) throw error; }
function json(body: Record<string, unknown>, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
class HttpError extends Error { constructor(message: string, readonly status: number) { super(message); } }
