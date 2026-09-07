-- ============================================================================
-- supabase-reminder-cron.sql — schedule the daily reminder-email Edge Function
--
-- Prerequisite: deploy the function first (from a machine with the Supabase
-- CLI and access to this project):
--   supabase functions deploy send-followup-reminders
--   supabase secrets set RESEND_API_KEY=re_xxx
--   supabase secrets set REMINDER_FROM_EMAIL="Built to Work <reminders@yourdomain.com>"
--
-- This session has no Supabase CLI access and no Resend account, so none of
-- the three commands above could be run for you — the function is written
-- and ready, but reminder emails will not actually send until you run them.
--
-- Run the SQL below in the Supabase SQL editor once the function is deployed.
-- It uses pg_cron + pg_net (both are Supabase extensions, enabled via
-- Database → Extensions if not already on) to call the function once a day.
-- Replace the two placeholders below with your actual project ref and the
-- service_role key from Project Settings → API — the service role key is a
-- secret; do not commit it into this file or anywhere else in the repo.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'send-followup-reminders-daily',
  '0 13 * * *', -- 1pm UTC ≈ 8am/9am US time depending on DST — adjust to taste
  $$
  select net.http_post(
    url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/send-followup-reminders',
    headers := jsonb_build_object(
      'Authorization', 'Bearer YOUR-SERVICE-ROLE-KEY',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- To check it ran: select * from cron.job_run_details order by start_time desc limit 5;
-- To remove it:    select cron.unschedule('send-followup-reminders-daily');
