-- ============================================================================
-- supabase-event-participants.sql — consolidate registration/EXC/trivia CSVs
-- into one table going forward, without touching or losing any historical
-- data in web_registration / exc_truck_loading / windows_trivia.
--
-- Starting with White Plains, the vendor provides one combined CSV per event
-- (registration + many simulator modules + trivia + a new Duck Hunter game)
-- instead of three separate ones. This migration:
--   1. Creates event_participants — a 1:1 landing table for the new CSV's
--      columns, verbatim, no transformation. Every new-CSV-only field
--      (ConsentToTerms, the 12 TopIndustry* columns, Duck Hunter, the extra
--      simulator modules, etc.) is captured so nothing is lost, even though
--      nothing new is surfaced in the dashboards yet (per plan).
--   2. Creates three compatibility views — web_registration_all,
--      exc_truck_loading_all, windows_trivia_all — each a UNION ALL of the
--      matching old table and event_participants, translated to expose the
--      OLD column names/shape. This is the only translation layer; nothing
--      downstream needs to know the new table exists.
--   3. Repoints every SQL view/function that reads the three old tables
--      (candidate_directory_web/exc/trivia, get_granted_candidate,
--      request_candidate_access, candidate_names_for_phones) at the new
--      compatibility views instead — their logic and column names are
--      otherwise unchanged.
--
-- IMPORTANT — RLS on event_participants is NOT set up by this file. RLS is
-- enabled with zero policies (fails closed: nobody can read it, including
-- through the _all views, until policies are added) because the live
-- policies on web_registration/exc_truck_loading/windows_trivia
-- ("web_read"/"exc_read"/"win_read") aren't committed anywhere in this repo
-- to copy from. Run this first:
--     select tablename, policyname, cmd, qual
--     from pg_policies
--     where tablename in ('web_registration','exc_truck_loading','windows_trivia');
-- and get matching policies added to event_participants before relying on
-- this for real event data — see supabase-event-participants-rls.sql once
-- that's ready.
--
-- The three _all views are created WITH (security_invoker = true) — this is
-- required, not optional: a plain view runs with its owner's privileges by
-- default, which would bypass RLS on the underlying tables entirely and
-- expose raw PII to any role the view is granted to. security_invoker makes
-- the view re-check RLS as the querying role instead, same protection the
-- raw tables already have.
-- ============================================================================

-- ── 1. New table — one row per participant per event, columns verbatim ──────
create table if not exists public.event_participants (
  id bigint generated always as identity primary key,
  "DateCaptured" text,
  "EventName" text,
  "FName" text,
  "LName" text,
  "Phone" text,
  "Email" text,
  "Address" text,
  "Address2" text,
  "City" text,
  "State" text,
  "Zip" text,
  "Language" text,
  "DOB" text,
  "ConsentToTerms" text,
  "Gender" text,
  "StudentOther" text,
  "WorkIndustry" text,
  "WorkIndustryOther" text,
  "JobStatus" text,
  "JobStatusOther" text,
  "InterestedInAutoMechanic" text,
  "InterestedInJobOpportunities" text,
  "TopIndustryHeavyEquipmentOperator" text,
  "TopIndustryGeneralLaborer" text,
  "TopIndustryElectrician" text,
  "TopIndustryWelder" text,
  "TopIndustryCarpenter" text,
  "TopIndustryPlumber" text,
  "TopIndustryConcreteWorkerFinisher" text,
  "TopIndustrySupervisor" text,
  "TopIndustryOffice" text,
  "TopIndustryNone" text,
  "TopIndustryOther" text,
  "TopIndustryOtherFreeText" text,
  "ConstructionExperience" text,
  "YearsConstructionExperience" text,
  "TradeCertifications" text,
  "TradeCertificationsCDL" text,
  "TradeCertificationsHeavyEquipmentOperator" text,
  "TradeCertificationsJourneymanElectrician" text,
  "TradeCertificationsMasterElectrician" text,
  "TradeCertificationsNEC" text,
  "TradeCertificationsCCM" text,
  "TradeCertificationsPMP" text,
  "TradeCertificationsCCO" text,
  "TradeCertificationsEPA608" text,
  "TradeCertificationsHVACE" text,
  "TradeCertificationsJourneymanPlumber" text,
  "TradeCertificationsMasterPlumber" text,
  "TradeCertificationsCW" text,
  "TradeCertificationsCWI" text,
  "TradeCertificationsCLC" text,
  "TradeCertificationsMCAA" text,
  "AEXCBenchLoadingTotalScore" text,
  "AEXCClearDebrisPilesTotalScore" text,
  "AEXCControlFamiliarizationTotalScore" text,
  "AEXCDigFootingsTotalScore" text,
  "AEXCLoadingandUnloadingfromaTrailerTotalScore" text,
  "AEXCManeuverHoistedObjectTotalScore" text,
  "AEXCTrenchingandPipeInstallationTotalScore" text,
  "AEXCWalkaroundTotalScore" text,
  "EXCBackfillingTotalScore" text,
  "EXCControlFamiliarizationTotalScore" text,
  "EXCManeuveringMachineTotalScore" text,
  "EXCOvertheMoonTotalScore" text,
  "EXCQuickCouplerTotalScore" text,
  "EXCRakingtheGreenTotalScore" text,
  "EXCTrenchingTotalScore" text,
  "EXCTruckLoadingTotalScore" text,
  "EXCWalkaroundTotalScore" text,
  "SLDBackfillingTotalScore" text,
  "SLDSlotDozingTotalScore" text,
  "SLDSteeringTotalScore" text,
  "SLDStraightandLevelDozingTotalScore" text,
  "SLDWalkaroundTotalScore" text,
  "TriviaAutoMechanicScore" text,
  "TriviaCivilConstructionScore" text,
  "TriviaElectricalScore" text,
  "TriviaPlumbingScore" text,
  "TriviaWeldingScore" text,
  "TriviaMechanicalScore" text,
  "TriviaConstructionLaborScore" text,
  "TriviaHVACScore" text,
  "TriviaWarehouseScore" text,
  "TriviaTotalScore" text,
  "TriviaHeavyEquipmentTechnicianScore" text,
  "DuckHunterKills" text,
  "DuckHunterAccuracy" text,
  "DuckHunterScore" text,
  lat double precision,
  lng double precision
);

alter table public.event_participants enable row level security;
-- No policies yet — see the file header. This fails closed (unreadable)
-- rather than open until matching policies are added.

-- ── 2. Compatibility views — old column names, old + new data unioned ───────

create or replace view public.web_registration_all
with (security_invoker = true) as
select
  'web_registration'::text as _source,
  "First Name", "Last Name", "Mobile Phone", "Email Address", "Street Address",
  "City", "State", "Zip Code", "Event Name", "Date", "DOB", "Gender", "Job Status",
  "Student",
  "Interested in Construction Jobs",
  "What industry do you work in?", "What industry do you work in",
  "Trade Certifications or Licenses",
  "Trade Certifications or Licenses_1", "Trade Certifications or Licenses_2",
  "Trade Certifications or Licenses_3", "Trade Certifications or Licenses_4",
  "Trade Certifications or Licenses_5", "Trade Certifications or Licenses_6",
  "Trade Certifications or Licenses_7", "Trade Certifications or Licenses_8",
  "Trade Certifications or Licenses_9", "Trade Certifications or Licenses_10",
  "Trade Certifications or Licenses_11", "Trade Certifications or Licenses_12",
  "Trade Certifications or Licenses_13", "Trade Certifications or Licenses_14",
  "Trade Certifications or Licenses_15",
  lat, lng
from web_registration
union all
select
  'event_participants'::text as _source,
  "FName" as "First Name", "LName" as "Last Name", "Phone" as "Mobile Phone",
  "Email" as "Email Address", "Address" as "Street Address",
  "City", "State", "Zip" as "Zip Code", "EventName" as "Event Name",
  "DateCaptured" as "Date", "DOB", "Gender", "JobStatus" as "Job Status",
  null as "Student",
  "InterestedInJobOpportunities" as "Interested in Construction Jobs",
  "WorkIndustry" as "What industry do you work in?", null as "What industry do you work in",
  "TradeCertificationsCDL" as "Trade Certifications or Licenses",
  "TradeCertificationsHeavyEquipmentOperator" as "Trade Certifications or Licenses_1",
  "TradeCertificationsJourneymanElectrician" as "Trade Certifications or Licenses_2",
  "TradeCertificationsMasterElectrician" as "Trade Certifications or Licenses_3",
  "TradeCertificationsNEC" as "Trade Certifications or Licenses_4",
  "TradeCertificationsCCM" as "Trade Certifications or Licenses_5",
  "TradeCertificationsPMP" as "Trade Certifications or Licenses_6",
  "TradeCertificationsCCO" as "Trade Certifications or Licenses_7",
  "TradeCertificationsEPA608" as "Trade Certifications or Licenses_8",
  "TradeCertificationsHVACE" as "Trade Certifications or Licenses_9",
  "TradeCertificationsJourneymanPlumber" as "Trade Certifications or Licenses_10",
  "TradeCertificationsMasterPlumber" as "Trade Certifications or Licenses_11",
  "TradeCertificationsCW" as "Trade Certifications or Licenses_12",
  "TradeCertificationsCWI" as "Trade Certifications or Licenses_13",
  "TradeCertificationsCLC" as "Trade Certifications or Licenses_14",
  "TradeCertificationsMCAA" as "Trade Certifications or Licenses_15",
  lat, lng
from event_participants;

grant select on public.web_registration_all to authenticated;

create or replace view public.exc_truck_loading_all
with (security_invoker = true) as
select "Date", "Event Name", "Login Code", "Total Score", "Safety Score", "Productivity Score"
from exc_truck_loading
union all
select
  "DateCaptured" as "Date", "EventName" as "Event Name", "Phone" as "Login Code",
  "EXCTruckLoadingTotalScore" as "Total Score",
  null as "Safety Score", null as "Productivity Score"
from event_participants;

grant select on public.exc_truck_loading_all to authenticated;

create or replace view public.windows_trivia_all
with (security_invoker = true) as
select
  "Date", "Event Name", "QR Code Scan", "Mobile Phone",
  "Trivia Auto Mechanic Score", "Trivia Civil Construction Score", "Trivia Electrical Score",
  "Trivia Plumbing Score", "Trivia Welding Score", "Trivia Construction Labor Score",
  "Trivia HVAC Score", "Trivia Warehouse Score", "Trivia Heavy Equipment Technician Score"
from windows_trivia
union all
select
  "DateCaptured" as "Date", "EventName" as "Event Name", null as "QR Code Scan", "Phone" as "Mobile Phone",
  "TriviaAutoMechanicScore" as "Trivia Auto Mechanic Score",
  "TriviaCivilConstructionScore" as "Trivia Civil Construction Score",
  "TriviaElectricalScore" as "Trivia Electrical Score",
  "TriviaPlumbingScore" as "Trivia Plumbing Score",
  "TriviaWeldingScore" as "Trivia Welding Score",
  "TriviaConstructionLaborScore" as "Trivia Construction Labor Score",
  "TriviaHVACScore" as "Trivia HVAC Score",
  "TriviaWarehouseScore" as "Trivia Warehouse Score",
  "TriviaHeavyEquipmentTechnicianScore" as "Trivia Heavy Equipment Technician Score"
from event_participants;

grant select on public.windows_trivia_all to authenticated;

-- ── 3. Repoint every reader at the compatibility views ───────────────────────
-- Same bodies as currently live (supabase-exclude-minors-from-pool.sql /
-- supabase-internet-leads-followup.sql), with every `from web_registration`
-- / `from exc_truck_loading` / `from windows_trivia` swapped for the _all
-- views — no other logic changes.

create or replace view public.candidate_directory_web as
select
  candidate_token(normalize_phone("Mobile Phone"))          as candidate_key,
  "City"                                                     as city,
  "State"                                                    as state,
  lat, lng,
  "Interested in Construction Jobs"                          as job_interest,
  "Trade Certifications or Licenses",
  "Trade Certifications or Licenses_1",
  "Trade Certifications or Licenses_2",
  "Trade Certifications or Licenses_3",
  "Trade Certifications or Licenses_4",
  "Trade Certifications or Licenses_5",
  "Trade Certifications or Licenses_6",
  "Trade Certifications or Licenses_7",
  "Trade Certifications or Licenses_8",
  "Trade Certifications or Licenses_9",
  "Trade Certifications or Licenses_10",
  "Trade Certifications or Licenses_11",
  "Trade Certifications or Licenses_12",
  "Trade Certifications or Licenses_13",
  "Trade Certifications or Licenses_14",
  "Trade Certifications or Licenses_15"
from web_registration_all
where trim("Interested in Construction Jobs") in ('Yes','Maybe')
  and public.is_adult("DOB");

create or replace view public.candidate_directory_exc as
select
  candidate_token(normalize_phone("Login Code")) as candidate_key,
  "Total Score", "Safety Score", "Productivity Score"
from exc_truck_loading_all
where normalize_phone("Login Code") in (
  select normalize_phone("Mobile Phone") from web_registration_all
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
    and public.is_adult("DOB")
);

create or replace view public.candidate_directory_trivia as
select
  candidate_token(normalize_phone(coalesce("Mobile Phone","QR Code Scan"))) as candidate_key,
  "Trivia Auto Mechanic Score", "Trivia Civil Construction Score", "Trivia Electrical Score",
  "Trivia Plumbing Score", "Trivia Welding Score", "Trivia Construction Labor Score",
  "Trivia HVAC Score", "Trivia Warehouse Score", "Trivia Heavy Equipment Technician Score"
from windows_trivia_all
where normalize_phone(coalesce("Mobile Phone","QR Code Scan")) in (
  select normalize_phone("Mobile Phone") from web_registration_all
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
    and public.is_adult("DOB")
);

grant select on public.candidate_directory_web,
                 public.candidate_directory_exc,
                 public.candidate_directory_trivia
  to authenticated;

create or replace function public.request_candidate_access(p_candidate_key text)
returns text
language plpgsql security definer as $$
declare
  v_company_id uuid;
  v_phone text;
  v_status text;
begin
  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'Not a customer account';
  end if;

  select normalize_phone("Mobile Phone") into v_phone
  from web_registration_all
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
    and public.is_adult("DOB")
    and candidate_token(normalize_phone("Mobile Phone")) = p_candidate_key
  limit 1;
  if v_phone is null then
    raise exception 'Candidate not found';
  end if;

  insert into candidate_assignments(phone, company_id, request_status, requested_at)
  values (v_phone, v_company_id, 'requested', now())
  on conflict (phone, company_id)
  do update set
    request_status = 'requested',
    requested_at   = now(),
    denied_at      = null,
    denial_reason  = null
  where candidate_assignments.request_status in ('none','denied');

  select request_status into v_status
  from candidate_assignments where phone = v_phone and company_id = v_company_id;
  return v_status;
end;
$$;
grant execute on function public.request_candidate_access(text) to authenticated;

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
    from web_registration_all wr
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

create or replace function public.candidate_names_for_phones(p_phones text[])
returns table(phone text, full_name text)
language sql stable as $$
  with web_names as (
    select distinct on (normalize_phone(wr."Mobile Phone"))
      normalize_phone(wr."Mobile Phone") as phone,
      trim(coalesce(wr."First Name",'') || ' ' || coalesce(wr."Last Name",'')) as full_name
    from web_registration_all wr
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
