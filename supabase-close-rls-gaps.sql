-- ============================================================================
-- supabase-close-rls-gaps.sql — remove blanket `true` RLS policies that
-- override the properly-scoped ones already sitting next to them.
--
-- Found by inspecting pg_policies on 2026-09-07: web_registration,
-- exc_truck_loading, windows_trivia, and candidate_assignments each carry a
-- policy with qual = true for `authenticated` (web_registration also has one
-- for `anon` — no login required at all). Postgres OR's every permissive
-- policy on a table together, so a single `true` policy silences every
-- stricter policy alongside it — including the masking added in
-- supabase-followup.sql. This predates that file; it isn't something the
-- candidate-portal change introduced.
-- ============================================================================

-- exc_truck_loading — "exc_read" already does is_admin() OR assigned-phone.
drop policy if exists "Authenticated read" on exc_truck_loading;

-- windows_trivia — "win_read" already does is_admin() OR assigned-phone.
drop policy if exists "Authenticated read" on windows_trivia;

-- web_registration — "web_read" already does is_admin() OR assigned-phone.
drop policy if exists "Authenticated read" on web_registration;
drop policy if exists "Staff can read web_registration" on web_registration;

-- Staff still need to update web_registration (e.g. batch geocoding writes
-- lat/lng back to it) — replace the blanket true/true with an is_admin() gate
-- instead of just dropping it.
drop policy if exists "Staff can update web_registration" on web_registration;
create policy "Staff can update web_registration" on web_registration
  for update using (is_admin()) with check (is_admin());

-- candidate_assignments — the other four (ca_select/ca_insert/ca_update/
-- ca_delete) already check (company_id = my_company_id() OR is_admin()); this
-- one's name says "Staff full access" but actually matched any authenticated
-- user, customers included, for every command including UPDATE and DELETE.
drop policy if exists "Staff full access - assignments" on candidate_assignments;
create policy "Staff full access - assignments" on candidate_assignments
  for all using (is_admin()) with check (is_admin());

-- Confirmed 2026-09-07: nothing outside this dashboard reads web_registration
-- as an unauthenticated user, so the most severe policy of the bunch — full
-- table read with no login at all — comes out too.
drop policy if exists "Anon can read web_registration" on web_registration;
