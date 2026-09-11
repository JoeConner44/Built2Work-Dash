// supabase/functions/sync-internet-leads/index.ts
//
// Pulls the Internet Leads Google Sheet — via a Google Apps Script Web App
// deployed from inside the sheet itself, see
// google-apps-script/internet-leads-webapp.gs — and mirrors it into the
// "Internet Leads" Supabase table. Runs a few times a day (see
// supabase-internet-leads-sync-cron.sql for the schedule). No Google Cloud
// project, service account, or billing involved.
//
// This table has no staff-editable fields of its own (all Follow-Up
// tracking lives on candidate_assignments, keyed by phone — see
// supabase-internet-leads-followup.sql), so each run replaces the table's
// contents wholesale rather than upserting. That avoids needing a unique
// constraint on this table and matches "mirror of the sheet" semantics.
//
// Deploy: `supabase functions deploy sync-internet-leads`
// Secrets this function needs (set once, not committed anywhere — see
// google-apps-script/internet-leads-webapp.gs for how to get these values):
//   supabase secrets set INTERNET_LEADS_WEBAPP_URL='<the Apps Script Web app URL>'
//   supabase secrets set INTERNET_LEADS_SYNC_TOKEN='<the SECRET_TOKEN from that script>'
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically to
// every Edge Function — do not set those yourself.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WEBAPP_URL = Deno.env.get('INTERNET_LEADS_WEBAPP_URL');
const SYNC_TOKEN = Deno.env.get('INTERNET_LEADS_SYNC_TOKEN');

Deno.serve(async (_req) => {
  if (!WEBAPP_URL || !SYNC_TOKEN) {
    return new Response(
      JSON.stringify({
        error: 'INTERNET_LEADS_WEBAPP_URL / INTERNET_LEADS_SYNC_TOKEN not set — see the comment at the top of this file',
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const url = `${WEBAPP_URL}${WEBAPP_URL.includes('?') ? '&' : '?'}token=${encodeURIComponent(SYNC_TOKEN)}`;
    const res = await fetch(url, { redirect: 'follow' });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error('Sheet fetch failed: ' + JSON.stringify(data));

    const headers: string[] = data.headers || [];
    const rawRows: any[][] = data.rows || [];
    const records = rawRows
      .filter((r) => r.some((cell) => String(cell ?? '').trim() !== ''))
      .map((r) => {
        const obj: Record<string, string> = {};
        headers.forEach((h, i) => { if (h) obj[h] = String(r[i] ?? ''); });
        return obj;
      });

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Full mirror — see file header for why this is safe (no staff-editable
    // fields live on this table).
    const { error: delErr } = await sb.from('Internet Leads').delete().not('id', 'is', null);
    if (delErr) throw new Error('Clearing Internet Leads failed: ' + delErr.message);

    if (records.length) {
      const { error: insErr } = await sb.from('Internet Leads').insert(records);
      if (insErr) throw new Error('Inserting Internet Leads failed: ' + insErr.message);
    }

    return new Response(JSON.stringify({ synced: records.length }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
