-- ============================================================================
-- supabase-white-plains-cleanup.sql — remove the bad prior White Plains
-- upload from the three old tables before loading the clean version through
-- event_participants.
--
-- STEP 1 — run this first and confirm the exact "Event Name" string(s)
-- shown below before running anything else. Destructive operations get the
-- exact matched string, never a guess.
-- ============================================================================

select "Event Name", count(*) from web_registration where "Event Name" ilike '%white plains%' group by 1;
select "Event Name", count(*) from exc_truck_loading where "Event Name" ilike '%white plains%' group by 1;
select "Event Name", count(*) from windows_trivia    where "Event Name" ilike '%white plains%' group by 1;

-- ============================================================================
-- STEP 2 — once the exact string(s) above are confirmed, replace
-- 'REPLACE_WITH_EXACT_EVENT_NAME' below with each one (one delete block per
-- distinct string, if there's more than one) and run this.
-- ============================================================================

-- delete from web_registration where "Event Name" = 'REPLACE_WITH_EXACT_EVENT_NAME';
-- delete from exc_truck_loading where "Event Name" = 'REPLACE_WITH_EXACT_EVENT_NAME';
-- delete from windows_trivia    where "Event Name" = 'REPLACE_WITH_EXACT_EVENT_NAME';
