-- ============================================================================
-- supabase-internet-leads-sync-cron.sql — schedule the Internet Leads Google
-- Sheet sync a few times a day
--
-- Prerequisite: deploy the function and set its secret first (from a machine
-- with the Supabase CLI and access to this project):
--   supabase functions deploy sync-internet-leads
--   supabase secrets set GOOGLE_SERVICE_ACCOUNT_KEY='<paste the full service-account JSON key, as one line>'
--
-- This session has no Supabase CLI access and no Google Cloud credentials, so
-- neither of the two commands above could be run for you — the function is
-- written and ready, but the sheet will not actually sync until you run them.
--
-- Run the SQL below in the Supabase SQL editor once the function is deployed.
-- Uses pg_cron + pg_net (same pattern as supabase-reminder-cron.sql). Replace
-- the two placeholders with your actual project ref and the service_role key
-- from Project Settings → API — the service role key is a secret; do not
-- commit it into this file or anywhere else in the repo.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'sync-internet-leads-4x-daily',
  '0 6,12,16,20 * * *', -- 4x/day UTC (~2am/8am/12pm/4pm ET) — adjust to taste
  $$
  select net.http_post(
    url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/sync-internet-leads',
    headers := jsonb_build_object(
      'Authorization', 'Bearer YOUR-SERVICE-ROLE-KEY',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- To check it ran: select * from cron.job_run_details order by start_time desc limit 5;
-- To remove it:    select cron.unschedule('sync-internet-leads-4x-daily');
