-- ============================================================================
-- supabase-internet-leads-followup.sql — bring Internet Leads (Google Sheet
-- import) into the Follow-Up tab as a staff-only-tracked source.
--
-- Internet Leads is a mostly separate pool from web_registration (people who
-- filled out the Google Form but never attended a BTW event), and sharing
-- with companies for this source stays direct-assign only (double-click in
-- the Leads tab, same as today) — NOT the masked browse/request flow. This
-- migration:
--   1. Adds lead_source to candidate_assignments so Follow-Up rows seeded
--      from Internet Leads can be told apart from web_registration ones.
--   2. Updates candidate_directory_followup (the customer portal's blinded
--      browse list) to keep excluding lead_source='internet_lead' rows —
--      they only ever reach a company via direct assignment.
--   3. Fixes get_granted_candidate(): it currently INNER joins
--      web_registration for name/phone/email/city/state, so directly
--      assigning an Internet-Leads-only candidate (no web_registration row)
--      to a company returns ZERO rows — the company sees nothing. This
--      switches to a left join with an Internet Leads fallback.
--   4. Same fallback for candidate_names_for_phones() (used by the
--      reminder-email Edge Function), so a Future-Contact reminder for an
--      Internet-Leads-only candidate emails a real name instead of falling
--      back to "Candidate (phone ...)".
--
-- Run in the Supabase SQL editor. Depends on supabase-followup.sql and the
-- two fix-* migrations already having been run.
-- ============================================================================

-- ── 1. Source tag ─────────────────────────────────────────────────────────
alter table candidate_assignments
  add column if not exists lead_source text default 'web';

alter table candidate_assignments
  drop constraint if exists candidate_assignments_lead_source_check;
alter table candidate_assignments
  add constraint candidate_assignments_lead_source_check
  check (lead_source in ('web','internet_lead'));

-- ── 2. Keep Internet Leads out of the customer-facing blinded list ─────────
create or replace view public.candidate_directory_followup as
select
  candidate_token(phone) as candidate_key,
  hopeful_job, pay_min, pay_max,
  further_vetted,
  (nullif(trim(coalesce(work_history,'')), '') is not null
   or nullif(trim(coalesce(file_url,'')), '') is not null) as has_work_history
from candidate_assignments
where company_id is null
  and coalesce(lead_source,'web') <> 'internet_lead';

grant select on public.candidate_directory_followup to authenticated;

-- ── 3. get_granted_candidate(): fall back to Internet Leads for contact info ─
create or replace function public.get_granted_candidate(p_candidate_key text)
returns table(
  assignment_id uuid,
  first_name text, last_name text, mobile_phone text, email_address text,
  street_address text, city text, state text,
  work_history text, resume_url text,
  status text, rejection_reason text
)
language plpgsql security definer as $$
declare
  v_company_id uuid;
  v_phone text;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'Not a customer account';
  end if;

  select ca.phone into v_phone
  from candidate_assignments ca
  where ca.company_id = v_company_id
    and ca.request_status = 'granted'
    and candidate_token(ca.phone) = p_candidate_key
  limit 1;
  if v_phone is null then
    raise exception 'Access has not been granted for this candidate';
  end if;

  return query
  select
    ca.id,
    coalesce(w."First Name", split_part(il."Name", ' ', 1))                    as first_name,
    coalesce(w."Last Name",
      case when il."Name" is not null and position(' ' in il."Name") > 0
           then substring(il."Name" from position(' ' in il."Name") + 1)
           else null end)                                                      as last_name,
    coalesce(w."Mobile Phone", il."Phone")                                     as mobile_phone,
    coalesce(w."Email Address", il."Email")                                    as email_address,
    w."Street Address"                                                        as street_address,
    coalesce(w."City", il."City")                                              as city,
    coalesce(w."State", il."State")                                            as state,
    fu.work_history, fu.file_url,
    ca.status, ca.rejection_reason
  from candidate_assignments ca
  left join candidate_assignments fu on fu.phone = v_phone and fu.company_id is null
  left join lateral (
    select *
    from web_registration wr
    where normalize_phone(wr."Mobile Phone") = v_phone
    order by
      (nullif(trim(coalesce(wr."First Name",'')), '') is not null) desc,
      wr."Date" desc nulls last
    limit 1
  ) w on true
  left join lateral (
    select *
    from "Internet Leads"
    where normalize_phone("Phone") = v_phone
    limit 1
  ) il on true
  where ca.company_id = v_company_id and ca.phone = v_phone
  limit 1;
end;
$$;
grant execute on function public.get_granted_candidate(text) to authenticated;

-- ── 4. candidate_names_for_phones(): same fallback for reminder emails ──────
create or replace function public.candidate_names_for_phones(p_phones text[])
returns table(phone text, full_name text)
language sql stable as $$
  with web_names as (
    select distinct on (normalize_phone(wr."Mobile Phone"))
      normalize_phone(wr."Mobile Phone") as phone,
      trim(coalesce(wr."First Name",'') || ' ' || coalesce(wr."Last Name",'')) as full_name
    from web_registration wr
    where normalize_phone(wr."Mobile Phone") = any(p_phones)
    order by
      normalize_phone(wr."Mobile Phone"),
      (nullif(trim(coalesce(wr."First Name",'')), '') is not null) desc,
      wr."Date" desc nulls last
  ),
  lead_names as (
    select distinct on (normalize_phone(il."Phone"))
      normalize_phone(il."Phone") as phone,
      trim(coalesce(il."Name",'')) as full_name
    from "Internet Leads" il
    where normalize_phone(il."Phone") = any(p_phones)
      and normalize_phone(il."Phone") not in (select phone from web_names)
  )
  select phone, full_name from web_names
  union all
  select phone, full_name from lead_names;
$$;
grant execute on function public.candidate_names_for_phones(text[]) to service_role;
