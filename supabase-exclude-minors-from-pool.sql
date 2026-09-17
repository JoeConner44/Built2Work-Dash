-- ============================================================================
-- supabase-exclude-minors-from-pool.sql — Keep candidates under 18 out of the
-- customer-facing candidate pool entirely.
--
-- IMPORTANT — READ BEFORE RUNNING:
--   This session has no credentials for your live Supabase project and could
--   not inspect it — this was written against what supabase-followup.sql
--   (already in this repo) defines. Run supabase-followup.sql first if you
--   haven't, then run this. Test on a staging copy first if you have one.
--
-- What this adds:
--   1. is_adult(dob text) — a safe DOB parser: returns true (i.e. "don't
--      exclude") whenever DOB is missing or unparseable, since we only want
--      to act when the data actually SHOWS someone is under 18, not guess
--      about incomplete data. Only returns false for a DOB that parses to an
--      age under 18.
--   2. Re-defines candidate_directory_web, candidate_directory_exc, and
--      candidate_directory_trivia (from supabase-followup.sql) to also
--      require is_adult("DOB") — this is the actual gate the customer
--      portal's "browse candidates" screen reads, so a minor's card can
--      never appear there.
--   3. Re-defines request_candidate_access() with the same check, so a
--      customer can't request a minor's contact info even by calling the
--      RPC directly with a guessed/brute-forced candidate key.
--
-- Deliberately NOT touched: get_granted_candidate() and
-- candidate_directory_followup. A minor can never reach 'granted' status
-- since request_candidate_access() now refuses them at the request step, so
-- gating the reveal step too would be redundant. The staff dashboard
-- (index.html) is unaffected by this file — staff can still see and filter
-- to minors there (see the new "<18" age filter chip); this file only
-- narrows what customers can browse/request.
-- ============================================================================

create or replace function public.is_adult(p_dob text)
returns boolean
language plpgsql stable as $$
declare
  v_dob date;
begin
  begin
    v_dob := p_dob::date;
  exception when others then
    return true; -- unparseable DOB: no evidence of age, don't exclude
  end;
  if v_dob is null then
    return true;
  end if;
  return age(current_date, v_dob) >= interval '18 years';
end;
$$;

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
from web_registration
where trim("Interested in Construction Jobs") in ('Yes','Maybe')
  and public.is_adult("DOB");

create or replace view public.candidate_directory_exc as
select
  candidate_token(normalize_phone("Login Code")) as candidate_key,
  "Total Score", "Safety Score", "Productivity Score"
from exc_truck_loading
where normalize_phone("Login Code") in (
  select normalize_phone("Mobile Phone") from web_registration
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
    and public.is_adult("DOB")
);

create or replace view public.candidate_directory_trivia as
select
  candidate_token(normalize_phone(coalesce("Mobile Phone","QR Code Scan"))) as candidate_key,
  "Trivia Auto Mechanic Score", "Trivia Civil Construction Score", "Trivia Electrical Score",
  "Trivia Plumbing Score", "Trivia Welding Score", "Trivia Construction Labor Score",
  "Trivia HVAC Score", "Trivia Warehouse Score", "Trivia Heavy Equipment Technician Score"
from windows_trivia
where normalize_phone(coalesce("Mobile Phone","QR Code Scan")) in (
  select normalize_phone("Mobile Phone") from web_registration
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
    and public.is_adult("DOB")
);

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
  from web_registration
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
