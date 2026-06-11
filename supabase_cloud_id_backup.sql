-- Optional but recommended before running the cloud_id migration on Supabase Free.
-- Creates data-only copy tables so the migration can be manually rolled back.

create table if not exists public.backup_products_before_cloud_id as
select * from public.products;

create table if not exists public.backup_sales_before_cloud_id as
select * from public.sales;

create table if not exists public.backup_shifts_before_cloud_id as
select * from public.shifts;

create table if not exists public.backup_shift_readings_before_cloud_id as
select * from public.shift_readings;

create table if not exists public.backup_users_before_cloud_id as
select * from public.users;

create table if not exists public.backup_audit_logs_before_cloud_id as
select * from public.audit_logs;

do $$
begin
  if to_regclass('public.pos_sync_events') is not null then
    create table if not exists public.backup_pos_sync_events_before_cloud_id as
    select * from public.pos_sync_events;
  end if;

  if to_regclass('public.pos_sync_conflicts') is not null then
    create table if not exists public.backup_pos_sync_conflicts_before_cloud_id as
    select * from public.pos_sync_conflicts;
  end if;
end $$;

select 'products' as table_name, count(*) as row_count
from public.products
union all
select 'backup_products_before_cloud_id', count(*)
from public.backup_products_before_cloud_id
union all
select 'sales', count(*)
from public.sales
union all
select 'backup_sales_before_cloud_id', count(*)
from public.backup_sales_before_cloud_id
union all
select 'shifts', count(*)
from public.shifts
union all
select 'backup_shifts_before_cloud_id', count(*)
from public.backup_shifts_before_cloud_id
union all
select 'shift_readings', count(*)
from public.shift_readings
union all
select 'backup_shift_readings_before_cloud_id', count(*)
from public.backup_shift_readings_before_cloud_id;
