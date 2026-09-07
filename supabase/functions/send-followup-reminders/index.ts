// supabase/functions/send-followup-reminders/index.ts
//
// Runs once a day (see supabase-reminder-cron.sql for the schedule). Finds
// every Follow-Up candidate whose reminder date has arrived and emails the
// staff member who set it, then marks the reminder sent so it isn't emailed
// again tomorrow. The in-app "due" banner on the Follow-Up tab in index.html
// is separate from this and keeps showing the reminder until staff change
// its disposition — this function is purely the email side.
//
// Deploy: `supabase functions deploy send-followup-reminders`
// Secrets this function needs (set once, not committed anywhere):
//   supabase secrets set RESEND_API_KEY=re_xxx
//   supabase secrets set REMINDER_FROM_EMAIL="Built to Work <reminders@yourdomain.com>"
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically to
// every Edge Function — do not set those yourself.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const FROM_EMAIL = Deno.env.get('REMINDER_FROM_EMAIL') || 'Built to Work <onboarding@resend.dev>';

Deno.serve(async (req) => {
  if (RESEND_API_KEY == null) {
    return new Response(
      JSON.stringify({ error: 'RESEND_API_KEY is not set — run: supabase secrets set RESEND_API_KEY=re_xxx' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const today = new Date().toISOString().slice(0, 10);

  const { data: due, error } = await sb
    .from('candidate_assignments')
    .select('id, phone, reminder_date, reminder_set_by')
    .is('company_id', null)
    .eq('interest_disposition', 'Future Contact')
    .lte('reminder_date', today)
    .is('reminder_sent_at', null);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  if (!due || due.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), { headers: { 'Content-Type': 'application/json' } });
  }

  const phones = due.map((r: any) => r.phone);
  // web_registration."Mobile Phone" isn't normalized the way
  // candidate_assignments.phone is, so this matches through the same
  // normalize_phone() the rest of the app uses (see supabase-followup.sql)
  // rather than an `.in()` against the raw column.
  const { data: candidates } = await sb.rpc('candidate_names_for_phones', { p_phones: phones });
  const nameByPhone: Record<string, string> = {};
  (candidates || []).forEach((c: any) => {
    if (c.phone && c.full_name) nameByPhone[c.phone] = c.full_name;
  });

  let sent = 0;
  const failures: any[] = [];
  const sentIds: string[] = [];

  for (const row of due as any[]) {
    if (!row.reminder_set_by) continue; // no staff email to send to — skip, stays due
    const name = nameByPhone[row.phone] || `Candidate (phone ${row.phone})`;
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: FROM_EMAIL,
          to: row.reminder_set_by,
          subject: `Follow-up reminder: ${name}`,
          text: `You asked to be reminded to follow up with ${name} today (${row.reminder_date}).\n\nOpen the Follow-Up tab in the Built to Work dashboard to update their status.`,
        }),
      });
      if (!res.ok) {
        failures.push({ id: row.id, error: await res.text() });
        continue;
      }
      sentIds.push(row.id);
      sent++;
    } catch (e) {
      failures.push({ id: row.id, error: String(e) });
    }
  }

  if (sentIds.length) {
    await sb
      .from('candidate_assignments')
      .update({ reminder_sent_at: new Date().toISOString() })
      .in('id', sentIds);
  }

  return new Response(JSON.stringify({ sent, failed: failures.length, failures }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
