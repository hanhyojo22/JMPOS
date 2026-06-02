-- Run once in Supabase SQL Editor before deploying the lost-phone recovery Edge Functions.
-- Recovery codes are temporary, hashed, single-use credentials for existing activated stores.

create table if not exists public.license_recovery_codes (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid not null references public.store_invites(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  code_hash text not null unique,
  revoked_device_id uuid not null references public.store_devices(id) on delete restrict,
  issued_by_admin_user_id uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  invalidated_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists license_recovery_codes_invite_created_idx
on public.license_recovery_codes (invite_id, created_at desc);

create index if not exists license_recovery_codes_store_created_idx
on public.license_recovery_codes (store_id, created_at desc);

create unique index if not exists license_recovery_codes_one_active_per_invite_idx
on public.license_recovery_codes (invite_id)
where consumed_at is null and invalidated_at is null;

alter table public.license_recovery_codes enable row level security;

-- Recovery-code reads and writes are intentionally limited to service-role Edge Functions.
