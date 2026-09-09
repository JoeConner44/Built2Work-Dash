-- ============================================================================
-- supabase-backfill-granted.sql — one-time fix for pre-existing assignments
--
-- The app never creates a candidate_assignments row with a non-null
-- company_id and request_status = 'none' — saveAssignment() always sets
-- 'granted', and a customer's own request always sets 'requested'. So any
-- row matching that combination predates request_status existing at all:
-- a real assignment made under the old system that got left at the column's
-- default when it was added, instead of being treated as already granted.
--
-- This sets those rows to granted so the affected company doesn't lose
-- access to candidates they were already legitimately given.
-- ============================================================================

update candidate_assignments
set request_status = 'granted',
    granted_at     = coalesce(assigned_at, updated_at, now()),
    granted_by     = coalesce(nullif(assigned_by, ''), 'backfill')
where company_id is not null
  and request_status = 'none';
