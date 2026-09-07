-- ============================================================================
-- supabase-further-vetting.sql — "Further Vetted by BTW Staff" + "Has Work
-- History" as filterable signals on the customer portal's Search tab.
--
-- Neither exposes any actual content pre-grant — just a yes/no a customer can
-- filter on to spot candidates BTW has done extra homework on, same privacy
-- posture as everything else in supabase-followup.sql. The underlying work
-- history text and resume file stay hidden until access is granted, exactly
-- as before; this only adds a boolean saying whether either exists.
-- ============================================================================

alter table candidate_assignments
  add column if not exists further_vetted boolean not null default false;

create or replace view public.candidate_directory_followup as
select
  candidate_token(phone) as candidate_key,
  hopeful_job, pay_min, pay_max,
  further_vetted,
  (nullif(trim(coalesce(work_history,'')), '') is not null or file_url is not null) as has_work_history
from candidate_assignments
where company_id is null;

grant select on public.candidate_directory_followup to authenticated;
