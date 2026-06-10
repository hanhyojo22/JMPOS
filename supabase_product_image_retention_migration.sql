alter table public.product_image_deletions
add column if not exists purge_after_at timestamptz;

alter table public.product_image_deletions
drop constraint if exists product_image_deletions_status_check;

alter table public.product_image_deletions
add constraint product_image_deletions_status_check
check (status in ('pending', 'soft_deleted', 'completed', 'failed'));

create index if not exists product_image_deletions_purge_idx
on public.product_image_deletions (store_id, status, purge_after_at)
where status = 'soft_deleted';
