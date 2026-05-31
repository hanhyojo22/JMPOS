-- Run once in Supabase SQL Editor after the license, sync, and storage setup SQL.
-- Cloud reads and writes require an approved, non-revoked POS device session.

alter table public.store_devices
add column if not exists cloud_session_id text;

alter table public.store_devices
add column if not exists cloud_session_user_id uuid references auth.users(id) on delete set null;

create or replace function public.has_active_pos_device(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_devices device
    join public.store_invites invite on invite.id = device.invite_id
    join public.store_members member on member.store_id = device.store_id
    where device.store_id = target_store_id
      and member.user_id = auth.uid()
      and device.cloud_session_user_id = auth.uid()
      and device.cloud_session_id = auth.jwt() ->> 'session_id'
      and device.revoked_at is null
      and invite.status in ('active', 'used')
      and (invite.license_expires_at is null or invite.license_expires_at > now())
  );
$$;

revoke all on function public.has_active_pos_device(uuid) from public;
grant execute on function public.has_active_pos_device(uuid) to authenticated;

create or replace function public.has_active_pos_device_storage_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when split_part(object_name, '/', 1)
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.has_active_pos_device(split_part(object_name, '/', 1)::uuid)
    else false
  end;
$$;

revoke all on function public.has_active_pos_device_storage_path(text) from public;
grant execute on function public.has_active_pos_device_storage_path(text) to authenticated;

drop policy if exists "Allow members to read their stores" on public.stores;
drop policy if exists "Allow active POS devices to read their stores" on public.stores;
create policy "Allow active POS devices to read their stores"
on public.stores for select to authenticated
using (public.has_active_pos_device(id));

drop policy if exists "Allow members to read memberships" on public.store_members;
drop policy if exists "Allow active POS devices to read memberships" on public.store_members;
create policy "Allow active POS devices to read memberships"
on public.store_members for select to authenticated
using (public.has_active_pos_device(store_id));

drop policy if exists "Allow members to read their store devices" on public.store_devices;
drop policy if exists "Allow active POS devices to read their store devices" on public.store_devices;
create policy "Allow active POS devices to read their store devices"
on public.store_devices for select to authenticated
using (public.has_active_pos_device(store_id));

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

drop policy if exists "Allow POS backup uploads" on storage.objects;
drop policy if exists "Allow POS store object reads" on storage.objects;
drop policy if exists "Allow POS store object inserts" on storage.objects;
drop policy if exists "Allow POS store object updates" on storage.objects;
drop policy if exists "Allow POS store object deletes" on storage.objects;
drop policy if exists "Allow active POS device storage objects" on storage.objects;
create policy "Allow active POS device storage objects"
on storage.objects for all to authenticated
using (
  bucket_id = 'backupfiles'
  and public.has_active_pos_device_storage_path(storage.objects.name)
)
with check (
  bucket_id = 'backupfiles'
  and public.has_active_pos_device_storage_path(storage.objects.name)
);
