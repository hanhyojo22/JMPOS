create table if not exists public.password_reset_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index if not exists password_reset_attempts_user_time_idx
  on public.password_reset_attempts (user_id, attempted_at desc);

alter table public.password_reset_attempts enable row level security;

drop policy if exists "Service role manages password reset attempts" on public.password_reset_attempts;
create policy "Service role manages password reset attempts"
  on public.password_reset_attempts
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');
