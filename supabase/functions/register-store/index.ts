import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type RegisterStoreBody = {
  storeName?: string;
  ownerName?: string;
  email?: string;
  password?: string;
  inviteCode?: string;
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as RegisterStoreBody;
    const storeName = sanitizeText(body.storeName, 80);
    const ownerName = sanitizeText(body.ownerName, 80);
    const email = sanitizeEmail(body.email);
    const password = body.password ?? "";
    const inviteCode = sanitizeInviteCode(body.inviteCode);

    if (!storeName) return jsonResponse({ error: "Store name is required" }, 400);
    if (!ownerName) return jsonResponse({ error: "Owner name is required" }, 400);
    if (!email) return jsonResponse({ error: "Valid owner email is required" }, 400);
    if (password.length < 6) {
      return jsonResponse({ error: "Password must be at least 6 characters" }, 400);
    }
    if (!inviteCode) {
      return jsonResponse({ error: "Valid invite/license code is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Registration service is not configured" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const codeHash = await sha256Hex(inviteCode);
    const { data: invite, error: inviteError } = await admin
      .from("store_invites")
      .select("id, store_id, max_uses, used_count, expires_at, status")
      .eq("code_hash", codeHash)
      .maybeSingle();

    if (inviteError) throw inviteError;
    if (!invite || invite.status !== "active") {
      return jsonResponse({ error: "Invite/license code is invalid" }, 400);
    }
    if (invite.expires_at && new Date(invite.expires_at) <= new Date()) {
      return jsonResponse({ error: "Invite/license code has expired" }, 400);
    }
    if ((invite.used_count ?? 0) >= invite.max_uses) {
      return jsonResponse({ error: "Invite/license code has already been used" }, 400);
    }

    const { data: authData, error: authError } =
      await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: ownerName,
          store_name: storeName,
        },
      });

    if (authError) {
      return jsonResponse(
        {
          error: authError.message.includes("already")
            ? "This email already has a cloud account. Use a new email or delete the existing Supabase Auth user first."
            : authError.message,
        },
        400,
      );
    }

    const userId = authData.user?.id;
    if (!userId) {
      return jsonResponse({ error: "Could not create cloud user" }, 500);
    }

    let storeId = invite.store_id as string | null;
    if (storeId) {
      const { error: updateStoreError } = await admin
        .from("stores")
        .update({
          name: storeName,
          owner_user_id: userId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", storeId);
      if (updateStoreError) throw updateStoreError;
    } else {
      const { data: store, error: storeError } = await admin
        .from("stores")
        .insert({ name: storeName, owner_user_id: userId })
        .select("id")
        .single();
      if (storeError) throw storeError;
      storeId = store.id;
    }

    const { error: memberError } = await admin.from("store_members").upsert(
      {
        store_id: storeId,
        user_id: userId,
        role: "owner",
      },
      { onConflict: "store_id,user_id" },
    );
    if (memberError) throw memberError;

    const nextUsedCount = (invite.used_count ?? 0) + 1;
    const { error: inviteUpdateError } = await admin
      .from("store_invites")
      .update({
        store_id: storeId,
        used_count: nextUsedCount,
        used_at: new Date().toISOString(),
        used_by_user_id: userId,
        status: nextUsedCount >= invite.max_uses ? "used" : "active",
      })
      .eq("id", invite.id)
      .eq("used_count", invite.used_count);

    if (inviteUpdateError) throw inviteUpdateError;

    return jsonResponse({
      functionVersion: "register-store-admin-v2",
      userId,
      storeId,
      email,
      storeName,
      session: null,
      sessionCreated: false,
      message:
        "Cloud account and store were registered. Sign in to Cloud Sync with the owner email and password.",
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

function sanitizeText(value: unknown, maxLength: number) {
  return String(value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function sanitizeEmail(value: unknown) {
  const email = String(value ?? "").trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) ? email : "";
}

function sanitizeInviteCode(value: unknown) {
  const code = String(value ?? "").trim().toUpperCase();
  return /^[A-Z0-9_-]{4,40}$/.test(code) ? code : "";
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
