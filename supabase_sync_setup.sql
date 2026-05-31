-- Run this once in Supabase SQL Editor after supabase_license_setup.sql.
-- It creates the sync event table and prepares your existing tables for per-store SQLite-to-Supabase sync.

create extension if not exists pgcrypto;

create table if not exists public.pos_sync_events (
  event_id text primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  local_queue_id bigint,
  table_name text not null,
  local_id text not null,
  operation text not null,
  payload text not null,
  created_at timestamptz,
  updated_at timestamptz,
  received_at timestamptz not null default now()
);

alter table public.pos_sync_events
add column if not exists store_id uuid references public.stores(id) on delete cascade;

alter table public.products
add column if not exists store_id uuid references public.stores(id) on delete cascade,
add column if not exists local_id text unique,
add column if not exists source_table text not null default 'products',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists pending_delete boolean not null default false,
add column if not exists pending_delete_at timestamptz,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

create table if not exists public.product_image_deletions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  local_product_id text not null,
  bucket_id text not null,
  object_path text not null,
  image_reference text,
  sync_event_id text,
  reason text not null default 'product_delete',
  status text not null default 'pending',
  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  last_error text,
  constraint product_image_deletions_status_check
    check (status in ('pending', 'completed', 'failed'))
);

alter table public.products
drop constraint if exists products_barcode_key;

drop index if exists public.products_barcode_key;
drop index if exists public.products_barcode_unique_idx;

alter table public.sales
add column if not exists store_id uuid references public.stores(id) on delete cascade,
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
add column if not exists store_id uuid references public.stores(id) on delete cascade,
add column if not exists local_id text unique,
add column if not exists local_role text,
add column if not exists source_table text not null default 'users',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

alter table public.audit_logs
add column if not exists store_id uuid references public.stores(id) on delete cascade,
add column if not exists local_id text unique,
add column if not exists local_user text,
add column if not exists source_table text not null default 'audit_logs',
add column if not exists sync_event_id text,
add column if not exists operation text not null default 'upsert',
add column if not exists payload jsonb not null default '{}'::jsonb,
add column if not exists local_updated_at timestamptz,
add column if not exists cloud_updated_at timestamptz not null default now();

do $$
declare
  missing_count integer;
  store_count integer;
  only_store_id uuid;
  table_name text;
  archive_table_name text;
begin
  select count(*) into store_count
  from public.stores;

  select id into only_store_id
  from public.stores
  order by created_at, id::text
  limit 1;

  foreach table_name in array array[
    'pos_sync_events',
    'products',
    'product_image_deletions',
    'sales',
    'users',
    'audit_logs'
  ]
  loop
    execute format('select count(*) from public.%I where store_id is null', table_name)
    into missing_count;

    if missing_count = 0 then
      continue;
    elsif store_count = 1 then
      execute format('update public.%I set store_id = $1 where store_id is null', table_name)
      using only_store_id;
    else
      archive_table_name := table_name || '_unassigned_store_archive';

      execute format(
        'create table if not exists public.%I (like public.%I including defaults including generated including identity)',
        archive_table_name,
        table_name
      );

      execute format(
        'alter table public.%I add column if not exists archived_at timestamptz not null default now()',
        archive_table_name
      );

      execute format(
        'insert into public.%I select *, now() from public.%I where store_id is null',
        archive_table_name,
        table_name
      );

      execute format('delete from public.%I where store_id is null', table_name);
    end if;
  end loop;
end $$;

alter table public.pos_sync_events
alter column store_id set not null;

alter table public.products
alter column store_id set not null;

alter table public.product_image_deletions
alter column store_id set not null;

alter table public.sales
alter column store_id set not null;

alter table public.users
alter column store_id set not null;

alter table public.audit_logs
alter column store_id set not null;

alter table public.products drop constraint if exists products_local_id_key;
alter table public.sales drop constraint if exists sales_local_id_key;
alter table public.users drop constraint if exists users_local_id_key;
alter table public.audit_logs drop constraint if exists audit_logs_local_id_key;

create unique index if not exists products_store_local_id_unique_idx
on public.products (store_id, local_id);

create unique index if not exists product_image_deletions_unique_idx
on public.product_image_deletions (store_id, bucket_id, object_path);

create index if not exists product_image_deletions_pending_idx
on public.product_image_deletions (store_id, status, requested_at);

create unique index if not exists sales_store_local_id_unique_idx
on public.sales (store_id, local_id);

create unique index if not exists users_store_local_id_unique_idx
on public.users (store_id, local_id);

create unique index if not exists audit_logs_store_local_id_unique_idx
on public.audit_logs (store_id, local_id);

alter table public.pos_sync_events enable row level security;
alter table public.products enable row level security;
alter table public.product_image_deletions enable row level security;
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
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = pos_sync_events.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS sync event updates"
on public.pos_sync_events
for update
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = pos_sync_events.store_id
      and store_members.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = pos_sync_events.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS sync event reads"
on public.pos_sync_events
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = pos_sync_events.store_id
      and store_members.user_id = auth.uid()
  )
);

drop policy if exists "Allow POS product sync writes" on public.products;
drop policy if exists "Allow POS product sync reads" on public.products;
drop policy if exists "Allow POS product image deletion reads" on public.product_image_deletions;
drop policy if exists "Allow POS product image deletion inserts" on public.product_image_deletions;

create policy "Allow POS product sync writes"
on public.products
for all
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = products.store_id
      and store_members.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = products.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS product sync reads"
on public.products
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = products.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS product image deletion reads"
on public.product_image_deletions
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = product_image_deletions.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS product image deletion inserts"
on public.product_image_deletions
for insert
to authenticated
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = product_image_deletions.store_id
      and store_members.user_id = auth.uid()
  )
);

drop policy if exists "Allow POS sale sync writes" on public.sales;
drop policy if exists "Allow POS sale sync reads" on public.sales;

create policy "Allow POS sale sync writes"
on public.sales
for all
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = sales.store_id
      and store_members.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = sales.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS sale sync reads"
on public.sales
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = sales.store_id
      and store_members.user_id = auth.uid()
  )
);

drop policy if exists "Allow POS user sync writes" on public.users;
drop policy if exists "Allow POS user sync reads" on public.users;

create policy "Allow POS user sync writes"
on public.users
for all
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = users.store_id
      and store_members.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = users.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS user sync reads"
on public.users
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = users.store_id
      and store_members.user_id = auth.uid()
  )
);

drop policy if exists "Allow POS audit sync writes" on public.audit_logs;
drop policy if exists "Allow POS audit sync reads" on public.audit_logs;

create policy "Allow POS audit sync writes"
on public.audit_logs
for all
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = audit_logs.store_id
      and store_members.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = audit_logs.store_id
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS audit sync reads"
on public.audit_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.store_members
    where store_members.store_id = audit_logs.store_id
      and store_members.user_id = auth.uid()
  )
);

-- Final production override: sync access requires a cloud session that was
-- authorized by an active, non-revoked POS device.
drop policy if exists "Allow POS sync event inserts" on public.pos_sync_events;
drop policy if exists "Allow POS sync event updates" on public.pos_sync_events;
drop policy if exists "Allow POS sync event reads" on public.pos_sync_events;
drop policy if exists "Allow active POS device sync events" on public.pos_sync_events;
create policy "Allow active POS device sync events"
on public.pos_sync_events for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS product sync writes" on public.products;
drop policy if exists "Allow POS product sync reads" on public.products;
drop policy if exists "Allow active POS device products" on public.products;
create policy "Allow active POS device products"
on public.products for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS product image deletion reads" on public.product_image_deletions;
drop policy if exists "Allow POS product image deletion inserts" on public.product_image_deletions;
drop policy if exists "Allow active POS device image deletions" on public.product_image_deletions;
create policy "Allow active POS device image deletions"
on public.product_image_deletions for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS sale sync writes" on public.sales;
drop policy if exists "Allow POS sale sync reads" on public.sales;
drop policy if exists "Allow active POS device sales" on public.sales;
create policy "Allow active POS device sales"
on public.sales for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS user sync writes" on public.users;
drop policy if exists "Allow POS user sync reads" on public.users;
drop policy if exists "Allow active POS device users" on public.users;
create policy "Allow active POS device users"
on public.users for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS audit sync writes" on public.audit_logs;
drop policy if exists "Allow POS audit sync reads" on public.audit_logs;
drop policy if exists "Allow active POS device audit logs" on public.audit_logs;
create policy "Allow active POS device audit logs"
on public.audit_logs for all to authenticated
using (public.has_active_pos_device(store_id))
with check (public.has_active_pos_device(store_id));
