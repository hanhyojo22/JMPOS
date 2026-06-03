import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string;
const passwordResetRedirectUrl = import.meta.env
  .VITE_SUPABASE_PASSWORD_RESET_REDIRECT_URL as string | undefined;
export const supabase = createClient(url, key);
export const resetRedirectUrl =
  passwordResetRedirectUrl?.trim() ||
  `${globalThis.location.origin}/reset-password`;

export type LicenseSummary = {
  id: string;
  label: string;
  state: string;
  storeName: string;
  ownerEmail: string;
  slotLimit: number;
  activeDeviceCount: number;
  licenseExpiresAt: string | null;
  lastActivityAt: string | null;
};

export async function adminApi<T>(body: Record<string, unknown>): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Your admin session has expired.");
  const response = await fetch(
    `${url}/functions/v1/admin-license-management`,
    {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error ?? "Admin request failed.");
  return payload as T;
}

export async function syncOwnerPasswordAfterRecovery(password: string) {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Your password reset session has expired.");
  const response = await fetch(`${url}/functions/v1/sync-owner-password-reset`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ password }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error ?? "Could not sync the POS owner password.");
  }
  return payload as { updated: number };
}
