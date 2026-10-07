-- ============================================================================
-- supabase-event-participants-rls.sql — RLS for event_participants, mirroring
-- the live policies on web_registration/exc_truck_loading/windows_trivia:
--
--   web_registration  "web_read"  SELECT: is_admin() OR normalize_phone("Mobile Phone") IN (SELECT my_assigned_phones())
--   exc_truck_loading "exc_read"  SELECT: is_admin() OR normalize_phone("Login Code")   IN (SELECT my_assigned_phones())
--   windows_trivia    "win_read"  SELECT: is_admin() OR normalize_phone(COALESCE("Mobile Phone","QR Code Scan")) IN (SELECT my_assigned_phones())
--   web_registration  "Staff can update web_registration" UPDATE: is_admin()
--
-- event_participants plays all three old tables' role for a given person in
-- one row, with a single "Phone" column, so one SELECT policy (checked
-- against "Phone") covers what web_read/exc_read/win_read did combined.
-- Run this after supabase-event-participants.sql.
-- ============================================================================

create policy "event_participants_read" on public.event_participants
  for select
  using (is_admin() OR (normalize_phone("Phone") IN (select my_assigned_phones())));

create policy "Staff can update event_participants" on public.event_participants
  for update
  using (is_admin())
  with check (is_admin());
