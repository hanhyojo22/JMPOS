-- Run this once in Supabase SQL Editor before deploying the register-store Edge Function.
-- It creates the store/license tables used to control first-install registration.

create extension if not exists pgcrypto;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_members (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner',
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

create table if not exists public.store_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  label text,
  store_id uuid references public.stores(id) on delete set null,
  max_uses integer not null default 1,
  device_slot_limit integer not null default 1,
  used_count integer not null default 0,
  expires_at timestamptz,
  used_at timestamptz,
  used_by_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  constraint store_invites_max_uses_positive check (max_uses > 0),
  constraint store_invites_device_slot_limit_positive check (device_slot_limit > 0),
  constraint store_invites_used_count_valid check (used_count >= 0)
);

alter table public.store_invites
add column if not exists device_slot_limit integer not null default 1;

alter table public.store_invites
drop constraint if exists store_invites_device_slot_limit_positive;

alter table public.store_invites
add constraint store_invites_device_slot_limit_positive
check (device_slot_limit > 0);

create table if not exists public.store_devices (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  invite_id uuid references public.store_invites(id) on delete set null,
  installation_id_hash text not null unique,
  activation_token_hash text not null,
  device_name text,
  activated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists store_invites_status_expires_idx
on public.store_invites (status, expires_at);

create index if not exists store_devices_store_id_idx
on public.store_devices (store_id);

alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.store_invites enable row level security;
alter table public.store_devices enable row level security;

drop policy if exists "Allow members to read their stores" on public.stores;
drop policy if exists "Allow members to read memberships" on public.store_members;
drop policy if exists "Allow members to read their store devices" on public.store_devices;

create policy "Allow members to read their stores"
on public.stores
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = stores.id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow members to read memberships"
on public.store_members
for select
to authenticated
using (user_id = auth.uid());

create policy "Allow members to read their store devices"
on public.store_devices
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = store_devices.store_id
      and store_members.user_id = auth.uid()
  )
);

-- Store invites are intentionally not readable by client apps.
-- Store devices are written by Edge Functions using the service role key.
-- Client apps use anon/publishable keys only and never receive service-role access.

-- Example one-time invite/license code:
-- 3TQGL-TZ74G-C585F
insert into public.store_invites (code_hash, label, max_uses)
values (
  encode(digest('3TQGL-TZ74G-C585F', 'sha256'), 'hex'),
  'Initial POS install invite',
  1
)
on conflict (code_hash) do nothing;

-- Additional one-time invite/license code:
-- V46QC-SBH9E-JHDLS
insert into public.store_invites (code_hash, label, max_uses)
values (
  encode(digest('V46QC-SBH9E-JHDLS', 'sha256'), 'hex'),
  'Additional POS install invite',
  1
)
on conflict (code_hash) do nothing;

-- Additional one-time invite/license code:
-- PRERP-GLYDF-28EWX
insert into public.store_invites (code_hash, label, max_uses)
values (
  encode(digest('PRERP-GLYDF-28EWX', 'sha256'), 'hex'),
  'Additional POS install invite',
  1
)
on conflict (code_hash) do nothing;

-- Additional one-time invite/license code:
-- 5ZNB3-5F23Q-C9RZM
insert into public.store_invites (code_hash, label, max_uses)
values (
  encode(digest('5ZNB3-5F23Q-C9RZM', 'sha256'), 'hex'),
  'Additional POS install invite',
  1
)
on conflict (code_hash) do nothing;

-- Additional one-time invite/license code:
-- ZZAM6-LABGF-7298B
insert into public.store_invites (code_hash, label, max_uses)
values (
  encode(digest('ZZAM6-LABGF-7298B', 'sha256'), 'hex'),
  'Additional POS install invite',
  1
)
on conflict (code_hash) do nothing;
