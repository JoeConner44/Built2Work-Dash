-- ============================================================================
-- supabase-followup.sql — Candidate follow-up, request/grant workflow, and
-- masked candidate directory for the customer portal.
--
-- IMPORTANT — READ BEFORE RUNNING:
--   This file was written without access to your live Supabase project (this
--   session has no DB credentials and could not inspect your actual schema or
--   existing RLS policies — only the columns referenced by index.html /
--   customer.html / operations.html could be inferred). Run this in the
--   Supabase SQL editor on a staging copy first if you have one, and read the
--   "MANUAL VERIFICATION REQUIRED" section at the bottom before trusting the
--   masking in production — it calls out one specific thing this script
--   cannot check for you.
--
-- What this adds:
--   1. New columns on candidate_assignments for the request/grant workflow
--      and for the Follow-Up page (contact outcome, interest disposition,
--      reminder, structured pay range).
--   2. candidate_token() — a one-way, non-reversible per-candidate id, so the
--      customer portal can reference a candidate without ever receiving their
--      real phone number.
--   3. Four "masked directory" views (web / exc / trivia / hopeful+pay) that
--      expose ONLY non-identifying columns, keyed by candidate_token instead
--      of phone, for every Yes/Maybe candidate — this is what the customer
--      portal's "browse candidates" screen reads.
--   4. request_candidate_access() and get_granted_candidate() — the two
--      SECURITY DEFINER functions that let a customer request access, and
--      read full PII ONLY once a staff member has granted it.
--   5. RLS policies scoping candidate_assignments so customers can see/update
--      only their own company's rows, through the my_candidate_requests view
--      rather than the raw table (the raw table's `phone` column IS a phone
--      number, so customers must never SELECT it directly).
-- ============================================================================

-- ── 1. New columns on candidate_assignments ──────────────────────────────────
alter table candidate_assignments
  add column if not exists contact_outcome      text,       -- null | 'Contacted' | 'Wrong Number' | 'No Response'
  add column if not exists interest_disposition text,       -- null | 'Interested' | 'Future Contact' | 'Not Interested'
  add column if not exists reminder_date        date,
  add column if not exists reminder_set_by      text,       -- staff email, used to route the reminder email
  add column if not exists reminder_sent_at     timestamptz,
  add column if not exists pay_min              numeric,
  add column if not exists pay_max              numeric,
  add column if not exists request_status       text default 'none', -- 'none' | 'requested' | 'granted' | 'denied'
  add column if not exists requested_at         timestamptz,
  add column if not exists granted_at           timestamptz,
  add column if not exists granted_by           text,
  add column if not exists denied_at            timestamptz,
  add column if not exists denial_reason        text;

alter table candidate_assignments
  drop constraint if exists candidate_assignments_contact_outcome_check;
alter table candidate_assignments
  add constraint candidate_assignments_contact_outcome_check
  check (contact_outcome is null or contact_outcome in ('Contacted','Wrong Number','No Response'));

alter table candidate_assignments
  drop constraint if exists candidate_assignments_interest_disposition_check;
alter table candidate_assignments
  add constraint candidate_assignments_interest_disposition_check
  check (interest_disposition is null or interest_disposition in ('Interested','Future Contact','Not Interested'));

alter table candidate_assignments
  drop constraint if exists candidate_assignments_request_status_check;
alter table candidate_assignments
  add constraint candidate_assignments_request_status_check
  check (request_status in ('none','requested','granted','denied'));

-- One master (follow-up) row per candidate. The app's existing
-- .upsert(payload, {onConflict:'phone,company_id'}) calls (see
-- saveAssignment() in index.html) only work today because a plain unique
-- constraint on (phone, company_id) already exists — but a plain unique
-- constraint treats every NULL company_id as distinct, so it does NOT stop
-- duplicate master rows for the same phone. This partial index closes that
-- gap without touching the existing (phone, company_id) constraint.
create unique index if not exists candidate_assignments_master_uniq
  on candidate_assignments(phone) where company_id is null;

-- ── 2. Non-reversible candidate id ───────────────────────────────────────────
-- CHANGE THE SALT BELOW before running this in production — pick any long
-- random string and keep it out of the client-side code (it only ever runs
-- server-side inside this function). Anyone who can read this file can see
-- the salt, but that only matters if they can also run SQL against your
-- database directly — the whole point is that the browser/client never sees
-- it or the phone numbers it's hashed with.
create or replace function public.candidate_token(p_phone text)
returns text
language sql immutable
as $$
  select substring(encode(digest(coalesce(p_phone,'') || 'sjfkjdsfkjsakfjdsalfjskdjfksjfsajfitiehdghdjsajgdsjajsjfshlgdsjl', 'sha256'), 'hex') from 1 for 24)
$$;

-- ── 3. Masked directory views (no name / phone / email / street address) ────
-- These are what the customer portal's "browse candidates" screen queries.
-- A view's SELECT list — not the querying role's RLS on the base table —
-- decides what columns come back, which is exactly what we want here: every
-- Yes/Maybe candidate is visible for browsing, but only through these
-- non-identifying columns.

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
where trim("Interested in Construction Jobs") in ('Yes','Maybe');

create or replace view public.candidate_directory_exc as
select
  candidate_token(normalize_phone("Login Code")) as candidate_key,
  "Total Score", "Safety Score", "Productivity Score"
from exc_truck_loading
where normalize_phone("Login Code") in (
  select normalize_phone("Mobile Phone") from web_registration
  where trim("Interested in Construction Jobs") in ('Yes','Maybe')
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
);

-- hopeful_job / pay range live on the master (company_id IS NULL) row that
-- the Follow-Up page maintains — this is the canonical, shared-across-every-
-- company copy referenced in the plan; work_history/resume are deliberately
-- NOT exposed here (they only ever reach a customer through
-- get_granted_candidate(), once access has been granted).
create or replace view public.candidate_directory_followup as
select candidate_token(phone) as candidate_key, hopeful_job, pay_min, pay_max
from candidate_assignments
where company_id is null;

grant select on public.candidate_directory_web,
                 public.candidate_directory_exc,
                 public.candidate_directory_trivia,
                 public.candidate_directory_followup
  to authenticated;

-- ── 4. Customer-only helper + request/reveal functions ───────────────────────
create or replace function public.is_customer()
returns boolean language sql stable as $$
  select exists(select 1 from companies where email ilike (auth.jwt()->>'email'));
$$;

create or replace function public.current_company_id()
returns uuid language sql stable as $$
  select id from companies where email ilike (auth.jwt()->>'email') limit 1;
$$;

-- Customer clicks "Request Contact Info" on a masked card → looks the phone
-- up server-side from the token (never returning it to the client) and
-- creates/reopens a request row for their company.
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

-- Reads full PII for one candidate, but only for a company whose request was
-- granted — this is the ONLY path by which a customer's session ever
-- receives a name, phone, email, or street address.
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
  select ca.id, w."First Name", w."Last Name", w."Mobile Phone", w."Email Address",
         w."Street Address", w."City", w."State",
         fu.work_history, fu.file_url,
         ca.status, ca.rejection_reason
  from candidate_assignments ca
  join web_registration w on normalize_phone(w."Mobile Phone") = v_phone
  left join candidate_assignments fu on fu.phone = v_phone and fu.company_id is null
  where ca.company_id = v_company_id and ca.phone = v_phone
  limit 1;
end;
$$;
grant execute on function public.get_granted_candidate(text) to authenticated;

-- Customer's own view of every request they've made, keyed by candidate_key
-- (never phone) so it's safe to expose directly.
create or replace view public.my_candidate_requests as
select
  ca.id as assignment_id,
  candidate_token(ca.phone) as candidate_key,
  ca.request_status, ca.requested_at, ca.granted_at, ca.denied_at, ca.denial_reason,
  ca.status, ca.rejection_reason
from candidate_assignments ca
where ca.company_id = public.current_company_id();

grant select on public.my_candidate_requests to authenticated;

-- ── 5. RLS: customers update only their own granted row's hiring status ─────
-- (SELECT on the base table is intentionally NOT granted to customers — they
-- read through my_candidate_requests / get_granted_candidate instead, since
-- candidate_assignments.phone is a real phone number.)
alter table candidate_assignments enable row level security;

drop policy if exists "customers update own granted assignment" on candidate_assignments;
create policy "customers update own granted assignment" on candidate_assignments
  for update
  using (company_id = public.current_company_id() and request_status = 'granted')
  with check (company_id = public.current_company_id());

grant update on candidate_assignments to authenticated;

-- ── 6. Helper for the reminder-email Edge Function ───────────────────────────
-- "Mobile Phone" in web_registration is stored in whatever format the CSV
-- import gave it (may include punctuation/country code), while
-- candidate_assignments.phone is always normalize_phone()'d — a raw `IN`
-- match between them misses rows, the exact bug normalize_phone() exists to
-- avoid elsewhere in this app. This does the matching in SQL instead.
create or replace function public.candidate_names_for_phones(p_phones text[])
returns table(phone text, full_name text)
language sql stable as $$
  select normalize_phone("Mobile Phone"), trim(coalesce("First Name",'') || ' ' || coalesce("Last Name",''))
  from web_registration
  where normalize_phone("Mobile Phone") = any(p_phones);
$$;
grant execute on function public.candidate_names_for_phones(text[]) to service_role;

-- ============================================================================
-- MANUAL VERIFICATION REQUIRED (this script cannot do this part for you):
--
-- This session has no credentials for your Supabase project, so it could not
-- inspect supabase-rls.sql or whatever policies already exist. Before you
-- trust the masking above, go to Supabase Dashboard → Authentication →
-- Policies and check web_registration, exc_truck_loading, windows_trivia,
-- and candidate_assignments for any EXISTING policy that grants a customer
-- (i.e. any authenticated user, or specifically one whose email is in
-- `companies`) a broad `SELECT` on the base table. If one exists, a customer
-- can bypass all of the masking above by calling that table directly from
-- the browser console with their own logged-in session. Narrow or remove
-- that policy so customers only reach candidate data through the
-- candidate_directory_* views and the two functions added here.
-- ============================================================================
