-- Run once in Supabase SQL Editor before deploying admin-license-management.
-- Existing activated licenses receive one year from the migration date.

alter table public.store_invites
add column if not exists license_expires_at timestamptz;

alter table public.store_invites
add column if not exists license_duration_months integer not null default 12;

alter table public.store_invites
drop constraint if exists store_invites_license_duration_months_positive;

alter table public.store_invites
add constraint store_invites_license_duration_months_positive
check (license_duration_months > 0);

update public.store_invites
set license_expires_at = now() + interval '1 year'
where store_id is not null
  and license_expires_at is null;

create table if not exists public.license_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.license_admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete restrict,
  invite_id uuid references public.store_invites(id) on delete set null,
  action text not null,
  before_values jsonb,
  after_values jsonb,
  created_at timestamptz not null default now()
);

create index if not exists store_invites_license_expires_idx
on public.store_invites (license_expires_at);

create index if not exists license_admin_audit_logs_invite_created_idx
on public.license_admin_audit_logs (invite_id, created_at desc);

alter table public.license_admins enable row level security;
alter table public.license_admin_audit_logs enable row level security;

drop policy if exists "Allow license admins to read own membership" on public.license_admins;
create policy "Allow license admins to read own membership"
on public.license_admins
for select
to authenticated
using (user_id = auth.uid());

-- License administration writes are intentionally performed only by the
-- JWT-protected admin-license-management Edge Function using its service role.

-- After creating your developer account in Supabase Authentication, grant it
-- portal access by running this once with your own email address:
-- insert into public.license_admins (user_id)
-- select id from auth.users where email = 'YOUR_ADMIN_EMAIL'
-- on conflict do nothing;
