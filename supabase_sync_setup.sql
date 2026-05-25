-- Run this once in Supabase SQL Editor.
-- It creates the sync event table and prepares your existing tables for automatic SQLite-to-Supabase sync.

create table if not exists public.pos_sync_events (
  event_id text primary key,
  local_queue_id bigint,
  table_name text not null,
  local_id text not null,
  operation text not null,
  payload text not null,
  created_at timestamptz,
  updated_at timestamptz,
  received_at timestamptz not null default now()
);

alter table public.products
add column if not exists local_id text unique,
add column if not exists source_table text not null default 'products',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

alter table public.products
drop constraint if exists products_barcode_key;

drop index if exists public.products_barcode_key;
drop index if exists public.products_barcode_unique_idx;

alter table public.sales
add column if not exists local_id text unique,
add column if not exists local_product_id text,
add column if not exists local_voided_by text,
add column if not exists receipt_number text,
add column if not exists source_table text not null default 'sales',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb, 
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

alter table public.users
add column if not exists local_id text unique,
add column if not exists local_role text,
add column if not exists source_table text not null default 'users',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

alter table public.audit_logs
add column if not exists local_id text unique,
add column if not exists local_user text,
add column if not exists source_table text not null default 'audit_logs',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

alter table public.pos_sync_events enable row level security;
alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.users enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "Allow POS sync event inserts" on public.pos_sync_events;
drop policy if exists "Allow POS sync event updates" on public.pos_sync_events;
drop policy if exists "Allow POS sync event reads" on public.pos_sync_events;

create policy "Allow POS sync event inserts"
on public.pos_sync_events
for insert
to authenticated
with check (true);

create policy "Allow POS sync event updates"
on public.pos_sync_events
for update
to authenticated
using (true)
with check (true);

create policy "Allow POS sync event reads"
on public.pos_sync_events
for select
to authenticated
using (true);

drop policy if exists "Allow POS product sync writes" on public.products;
drop policy if exists "Allow POS product sync reads" on public.products;

create policy "Allow POS product sync writes"
on public.products
for all
to authenticated
using (true)
with check (true);

create policy "Allow POS product sync reads"
on public.products
for select
to authenticated
using (true);

drop policy if exists "Allow POS sale sync writes" on public.sales;
drop policy if exists "Allow POS sale sync reads" on public.sales;

create policy "Allow POS sale sync writes"
on public.sales
for all
to authenticated
using (true)
with check (true);

create policy "Allow POS sale sync reads"
on public.sales
for select
to authenticated
using (true);

drop policy if exists "Allow POS user sync writes" on public.users;
drop policy if exists "Allow POS user sync reads" on public.users;

create policy "Allow POS user sync writes"
on public.users
for all
to authenticated
using (true)
with check (true);

create policy "Allow POS user sync reads"
on public.users
for select
to authenticated
using (true);

drop policy if exists "Allow POS audit sync writes" on public.audit_logs;
drop policy if exists "Allow POS audit sync reads" on public.audit_logs;

create policy "Allow POS audit sync writes"
on public.audit_logs
for all
to authenticated
using (true)
with check (true);

create policy "Allow POS audit sync reads"
on public.audit_logs
for select
to authenticated
using (true);
