-- Run this once in Supabase SQL Editor.
-- It creates the Storage bucket used by the POS online backup feature.

insert into storage.buckets (id, name, public)
values ('backupfiles', 'backupfiles', false)
on conflict (id) do nothing;

drop policy if exists "Allow POS backup uploads" on storage.objects;
drop policy if exists "Allow POS store object reads" on storage.objects;
drop policy if exists "Allow POS store object inserts" on storage.objects;
drop policy if exists "Allow POS store object updates" on storage.objects;
drop policy if exists "Allow POS store object deletes" on storage.objects;

create policy "Allow POS backup uploads"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'backupfiles'
  and storage.objects.name not like '%/sync_images/%'
);

create policy "Allow POS store object reads"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'backupfiles'
  and exists (
    select 1
    from public.store_members
    where store_members.store_id::text = split_part(storage.objects.name, '/', 1)
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS store object inserts"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'backupfiles'
  and exists (
    select 1
    from public.store_members
    where store_members.store_id::text = split_part(storage.objects.name, '/', 1)
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS store object updates"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'backupfiles'
  and exists (
    select 1
    from public.store_members
    where store_members.store_id::text = split_part(storage.objects.name, '/', 1)
      and store_members.user_id = auth.uid()
  )
)
with check (
  bucket_id = 'backupfiles'
  and exists (
    select 1
    from public.store_members
    where store_members.store_id::text = split_part(storage.objects.name, '/', 1)
      and store_members.user_id = auth.uid()
  )
);

create policy "Allow POS store object deletes"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'backupfiles'
  and exists (
    select 1
    from public.store_members
    where store_members.store_id::text = split_part(storage.objects.name, '/', 1)
      and store_members.user_id = auth.uid()
  )
);
