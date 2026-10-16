-- ============================================================================
-- supabase-culture-index.sql — adds a staff-only Culture Index PDF slot to each
-- Follow-Up candidate (separate from the resume in file_url).
--
-- Additive and nullable: existing rows are untouched. The file itself is
-- uploaded by the dashboard to the existing 'candidate-files' storage bucket
-- under the culture-index/ folder. This column is NOT added to any customer
-- view (candidate_directory_followup etc.), so it is never exposed on the
-- customer portal.
-- ============================================================================

alter table candidate_assignments
  add column if not exists culture_index_url text;
