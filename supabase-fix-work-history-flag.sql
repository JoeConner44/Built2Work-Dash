-- ============================================================================
-- supabase-fix-work-history-flag.sql — has_work_history was true for every
-- candidate
--
-- candidate_directory_followup computed has_work_history as
-- (... or file_url is not null). That's only correct if an empty resume is
-- stored as NULL. If file_url actually defaults to '' instead, every row —
-- including candidates who never had anything uploaded — satisfies
-- "is not null" even though there's nothing there. work_history already
-- guarded against this with nullif(trim(...), ''); file_url didn't. This
-- applies the same guard to file_url.
-- ============================================================================

create or replace view public.candidate_directory_followup as
select
  candidate_token(phone) as candidate_key,
  hopeful_job, pay_min, pay_max,
  further_vetted,
  (nullif(trim(coalesce(work_history,'')), '') is not null
   or nullif(trim(coalesce(file_url,'')), '') is not null) as has_work_history
from candidate_assignments
where company_id is null;

grant select on public.candidate_directory_followup to authenticated;
