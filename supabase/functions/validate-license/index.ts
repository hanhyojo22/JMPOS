import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ValidateLicenseBody = {
  installationId?: string;
  activationToken?: string;
  licenseKey?: string;
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as ValidateLicenseBody;
    const installationId = sanitizeToken(body.installationId, 120);
    const activationToken = sanitizeToken(body.activationToken, 120);
    const licenseKey = sanitizeInviteCode(body.licenseKey);

    if (!installationId) {
      return jsonResponse({ error: "Installation id is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "License service is not configured" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const installationIdHash = await sha256Hex(installationId);
    if (licenseKey) {
      const response = await validateLicenseKeyForDevice(
        admin,
        licenseKey,
        installationIdHash,
      );
      return jsonResponse(response.body, response.status);
    }

    const { data: device, error: deviceError } = await admin
      .from("store_devices")
      .select("store_id, invite_id, activation_token_hash, revoked_at")
      .eq("installation_id_hash", installationIdHash)
      .maybeSingle();

    if (deviceError) throw deviceError;
    if (!device || device.revoked_at) {
      return jsonResponse({ error: "No activation found for this device" }, 404);
    }

    if (activationToken) {
      const activationTokenHash = await sha256Hex(activationToken);
      if (activationTokenHash !== device.activation_token_hash) {
        return jsonResponse({ error: "Activation token is invalid" }, 401);
      }
    }

    const { data: store, error: storeError } = await admin
      .from("stores")
      .select("id, name")
      .eq("id", device.store_id)
      .single();
    if (storeError) throw storeError;

    const { data: invite, error: inviteError } = await admin
      .from("store_invites")
      .select("code_hash, status")
      .eq("id", device.invite_id)
      .single();
    if (inviteError) throw inviteError;

    if (invite.status !== "used" && invite.status !== "active") {
      return jsonResponse({ error: "License is not active" }, 403);
    }

    const newActivationToken = crypto.randomUUID();
    const newActivationTokenHash = await sha256Hex(newActivationToken);
    const { error: updateError } = await admin
      .from("store_devices")
      .update({
        activation_token_hash: newActivationTokenHash,
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("installation_id_hash", installationIdHash);
    if (updateError) throw updateError;

    return jsonResponse({
      functionVersion: "validate-license-v1",
      storeId: store.id,
      storeName: store.name,
      licenseKey: "",
      activationToken: newActivationToken,
      restored: true,
      message: "Device activation is valid.",
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function sanitizeToken(value: unknown, maxLength: number) {
  const token = String(value ?? "").trim();
  if (token.length > maxLength) return "";
  return /^[a-zA-Z0-9_.:-]+$/.test(token) ? token : "";
}

function sanitizeInviteCode(value: unknown) {
  const code = String(value ?? "").trim().toUpperCase();
  return /^[A-Z0-9_-]{4,40}$/.test(code) ? code : "";
}

async function validateLicenseKeyForDevice(
  admin: ReturnType<typeof createClient>,
  licenseKey: string,
  installationIdHash: string,
) {
  const codeHash = await sha256Hex(licenseKey);
  const { data: invite, error: inviteError } = await admin
    .from("store_invites")
    .select("id, store_id, max_uses, used_count, expires_at, status")
    .eq("code_hash", codeHash)
    .maybeSingle();

  if (inviteError) throw inviteError;
  if (!invite || invite.status === "revoked") {
    return {
      status: 404,
      body: { error: "License code was not found" },
    };
  }
  if (invite.expires_at && new Date(invite.expires_at) <= new Date()) {
    return {
      status: 400,
      body: { error: "License code has expired" },
    };
  }

  const { data: device, error: deviceError } = await admin
    .from("store_devices")
    .select("store_id, revoked_at")
    .eq("installation_id_hash", installationIdHash)
    .eq("invite_id", invite.id)
    .maybeSingle();

  if (deviceError) throw deviceError;
  if (device && !device.revoked_at) {
    const { data: store, error: storeError } = await admin
      .from("stores")
      .select("id, name")
      .eq("id", device.store_id)
      .single();
    if (storeError) throw storeError;

    const activationToken = crypto.randomUUID();
    const activationTokenHash = await sha256Hex(activationToken);
    const { error: updateError } = await admin
      .from("store_devices")
      .update({
        activation_token_hash: activationTokenHash,
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("installation_id_hash", installationIdHash)
      .eq("invite_id", invite.id);
    if (updateError) throw updateError;

    return {
      status: 200,
      body: {
        functionVersion: "validate-license-v2",
        licenseExists: true,
        activated: true,
        restored: true,
        storeId: store.id,
        storeName: store.name,
        licenseKey,
        activationToken,
        message: "This license was restored for this device.",
      },
    };
  }

  const licenseAlreadyUsed =
    invite.store_id !== null ||
    (invite.used_count ?? 0) > 0 ||
    invite.status === "used" ||
    (invite.used_count ?? 0) >= invite.max_uses;

  if (licenseAlreadyUsed) {
    if (invite.store_id) {
      const { data: store, error: storeError } = await admin
        .from("stores")
        .select("id, name")
        .eq("id", invite.store_id)
        .single();
      if (storeError) throw storeError;

      return {
        status: 200,
        body: {
          functionVersion: "validate-license-v3",
          licenseExists: true,
          activated: false,
          restored: false,
          restoreAvailable: true,
          storeId: store.id,
          storeName: store.name,
          licenseKey,
          message:
            "License is already registered. Sign in with the original owner account to restore this store.",
        },
      };
    }

    return {
      status: 409,
      body: {
        error: "License is already activated on another device",
        licenseExists: true,
        activated: false,
      },
    };
  }

  return {
    status: 200,
    body: {
      functionVersion: "validate-license-v2",
      licenseExists: true,
      activated: false,
      restored: false,
      licenseKey,
      message: "License is valid and ready for owner setup.",
    },
  };
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
