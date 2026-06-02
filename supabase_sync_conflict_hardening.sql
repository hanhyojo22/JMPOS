-- Run after supabase_sync_setup.sql.
-- Adds revision-based conflict checks and soft-delete tombstones for POS sync.

alter table public.pos_sync_events
add column if not exists device_id uuid references public.store_devices(id) on delete set null,
add column if not exists base_revision bigint not null default 0,
add column if not exists applied_revision bigint;

alter table public.products
add column if not exists revision bigint not null default 0,
add column if not exists deleted_at timestamptz,
add column if not exists deleted_by_device_id uuid references public.store_devices(id) on delete set null;

alter table public.sales
add column if not exists revision bigint not null default 0,
add column if not exists deleted_at timestamptz,
add column if not exists deleted_by_device_id uuid references public.store_devices(id) on delete set null;

alter table public.users
add column if not exists revision bigint not null default 0,
add column if not exists deleted_at timestamptz,
add column if not exists deleted_by_device_id uuid references public.store_devices(id) on delete set null;

alter table public.audit_logs
add column if not exists revision bigint not null default 0,
add column if not exists deleted_at timestamptz,
add column if not exists deleted_by_device_id uuid references public.store_devices(id) on delete set null;

create index if not exists products_store_deleted_idx
on public.products (store_id, deleted_at);

create index if not exists sales_store_deleted_idx
on public.sales (store_id, deleted_at);

create index if not exists users_store_deleted_idx
on public.users (store_id, deleted_at);

create index if not exists audit_logs_store_deleted_idx
on public.audit_logs (store_id, deleted_at);

create table if not exists public.pos_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  device_id uuid references public.store_devices(id) on delete set null,
  table_name text not null,
  local_id text not null,
  operation text not null,
  base_revision bigint not null,
  cloud_revision bigint not null,
  created_at timestamptz not null default now()
);

create index if not exists pos_sync_conflicts_store_created_idx
on public.pos_sync_conflicts (store_id, created_at desc);

alter table public.pos_sync_conflicts enable row level security;

drop policy if exists "Allow active POS device conflict reads" on public.pos_sync_conflicts;
create policy "Allow active POS device conflict reads"
on public.pos_sync_conflicts for select to authenticated
using (public.has_active_pos_device(store_id));

-- Mirror tables are read-only to POS clients. Conflict-safe writes go through
-- the pos-sync-apply Edge Function using its service-role client.
drop policy if exists "Allow POS product sync writes" on public.products;
drop policy if exists "Allow POS product sync reads" on public.products;
drop policy if exists "Allow active POS device products" on public.products;
drop policy if exists "Allow active POS device product reads" on public.products;
create policy "Allow active POS device product reads"
on public.products for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS sale sync writes" on public.sales;
drop policy if exists "Allow POS sale sync reads" on public.sales;
drop policy if exists "Allow active POS device sales" on public.sales;
drop policy if exists "Allow active POS device sale reads" on public.sales;
create policy "Allow active POS device sale reads"
on public.sales for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS user sync writes" on public.users;
drop policy if exists "Allow POS user sync reads" on public.users;
drop policy if exists "Allow active POS device users" on public.users;
drop policy if exists "Allow active POS device user reads" on public.users;
create policy "Allow active POS device user reads"
on public.users for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS audit sync writes" on public.audit_logs;
drop policy if exists "Allow POS audit sync reads" on public.audit_logs;
drop policy if exists "Allow active POS device audit logs" on public.audit_logs;
drop policy if exists "Allow active POS device audit reads" on public.audit_logs;
create policy "Allow active POS device audit reads"
on public.audit_logs for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow POS sync event inserts" on public.pos_sync_events;
drop policy if exists "Allow POS sync event updates" on public.pos_sync_events;
drop policy if exists "Allow POS sync event reads" on public.pos_sync_events;
drop policy if exists "Allow active POS device sync events" on public.pos_sync_events;
drop policy if exists "Allow active POS device sync event reads" on public.pos_sync_events;
create policy "Allow active POS device sync event reads"
on public.pos_sync_events for select to authenticated
using (public.has_active_pos_device(store_id));

create or replace function public.purge_pos_sync_tombstones(retain_for interval default interval '30 days')
returns table(table_name text, deleted_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_table text;
  affected bigint;
begin
  foreach target_table in array array['products', 'sales', 'users', 'audit_logs']
  loop
    execute format(
      'delete from public.%I where deleted_at is not null and deleted_at < now() - $1',
      target_table
    )
    using retain_for;
    get diagnostics affected = row_count;
    table_name := target_table;
    deleted_count := affected;
    return next;
  end loop;
end;
$$;

revoke all on function public.purge_pos_sync_tombstones(interval) from public;
