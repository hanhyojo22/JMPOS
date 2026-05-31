-- Run this once in Supabase SQL Editor before deploying the device-slot Edge Functions.
-- Existing licenses keep their current behavior with one active device slot.

alter table public.store_invites
add column if not exists device_slot_limit integer not null default 1;

alter table public.store_invites
drop constraint if exists store_invites_device_slot_limit_positive;

alter table public.store_invites
add constraint store_invites_device_slot_limit_positive
check (device_slot_limit > 0);
