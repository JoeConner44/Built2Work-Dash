-- ============================================================================
-- supabase-fix-duplicate-registrations.sql — candidate names showing as
-- generic "Candidate" instead of their real name
--
-- Some candidates registered more than once (multiple events), so
-- web_registration can have more than one row for the same phone number.
-- get_granted_candidate() joined to web_registration with no preference for
-- which of those rows to use, so Postgres could just as easily pick a
-- blank/partial registration over the one with a real name on it. This picks
-- the row that actually has a name, tie-broken by most recent.
--
-- candidate_names_for_phones() (used by the reminder-email Edge Function)
-- had the same issue — fixed the same way.
-- ============================================================================

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
  left join candidate_assignments fu on fu.phone = v_phone and fu.company_id is null
  cross join lateral (
    select *
    from web_registration wr
    where normalize_phone(wr."Mobile Phone") = v_phone
    order by
      (nullif(trim(coalesce(wr."First Name",'')), '') is not null) desc,
      wr."Date" desc nulls last
    limit 1
  ) w
  where ca.company_id = v_company_id and ca.phone = v_phone
  limit 1;
end;
$$;
grant execute on function public.get_granted_candidate(text) to authenticated;

create or replace function public.candidate_names_for_phones(p_phones text[])
returns table(phone text, full_name text)
language sql stable as $$
  select distinct on (normalize_phone(wr."Mobile Phone"))
    normalize_phone(wr."Mobile Phone"),
    trim(coalesce(wr."First Name",'') || ' ' || coalesce(wr."Last Name",''))
  from web_registration wr
  where normalize_phone(wr."Mobile Phone") = any(p_phones)
  order by
    normalize_phone(wr."Mobile Phone"),
    (nullif(trim(coalesce(wr."First Name",'')), '') is not null) desc,
    wr."Date" desc nulls last;
$$;
grant execute on function public.candidate_names_for_phones(text[]) to service_role;
