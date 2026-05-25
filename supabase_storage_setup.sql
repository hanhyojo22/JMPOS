-- Run this once in Supabase SQL Editor.
-- It creates the Storage bucket used by the POS online backup feature.

insert into storage.buckets (id, name, public)
values ('backupfiles', 'backupfiles', false)
on conflict (id) do nothing;

drop policy if exists "Allow POS backup uploads" on storage.objects;

create policy "Allow POS backup uploads"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'backupfiles');
