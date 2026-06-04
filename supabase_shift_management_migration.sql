-- Run after supabase_sync_setup.sql and supabase_sync_conflict_hardening.sql.
-- Adds cloud-synced POS shift management mirror tables.

create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  local_id text not null,
  status text not null default 'open',
  opened_by text not null,
  opened_at timestamptz not null,
  opening_cash numeric not null default 0,
  closed_by text,
  closed_at timestamptz,
  closing_cash numeric,
  expected_cash numeric,
  over_short numeric,
  z_reading_number text,
  source_table text not null default 'shifts',
  sync_event_id text,
  operation text not null default 'upsert',
  payload jsonb not null default '{}'::jsonb,
  local_updated_at timestamptz,
  cloud_updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  deleted_at timestamptz,
  deleted_by_device_id uuid references public.store_devices(id) on delete set null
);

create table if not exists public.shift_readings (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  local_id text not null,
  shift_id bigint not null,
  type text not null,
  created_by text not null,
  created_at timestamptz not null,
  opening_cash numeric not null default 0,
  sales_total numeric not null default 0,
  void_total numeric not null default 0,
  receipt_count integer not null default 0,
  item_count integer not null default 0,
  expected_cash numeric not null default 0,
  counted_cash numeric,
  over_short numeric,
  source_table text not null default 'shift_readings',
  sync_event_id text,
  operation text not null default 'upsert',
  payload jsonb not null default '{}'::jsonb,
  local_updated_at timestamptz,
  cloud_updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  deleted_at timestamptz,
  deleted_by_device_id uuid references public.store_devices(id) on delete set null
);

alter table public.sales
add column if not exists shift_id bigint;

create unique index if not exists shifts_store_local_id_unique_idx
on public.shifts (store_id, local_id);

create unique index if not exists shift_readings_store_local_id_unique_idx
on public.shift_readings (store_id, local_id);

create index if not exists shifts_store_deleted_idx
on public.shifts (store_id, deleted_at);

create index if not exists shift_readings_store_deleted_idx
on public.shift_readings (store_id, deleted_at);

create index if not exists sales_store_shift_id_idx
on public.sales (store_id, shift_id);

alter table public.shifts enable row level security;
alter table public.shift_readings enable row level security;

drop policy if exists "Allow active POS device shift reads" on public.shifts;
create policy "Allow active POS device shift reads"
on public.shifts for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow active POS device shift reading reads" on public.shift_readings;
create policy "Allow active POS device shift reading reads"
on public.shift_readings for select to authenticated
using (public.has_active_pos_device(store_id));
