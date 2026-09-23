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
// supabase-internet-leads-followup.sql), so it's safe to mirror the sheet's
// contents wholesale on each run. That's done as an upsert-then-prune
// rather than delete-then-insert: a blanket delete followed by a separate
// insert isn't atomic across two HTTP requests, so two overlapping runs
// (the cron firing while someone manually invokes it, say) can have one
// run's insert land on rows another run just re-inserted, hitting
// "Entry ID"'s primary key. Upsert is safe against that since it just
// updates the row instead of colliding.
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

    // Trim header text — the sheet's "Skills & Experience " column has a
    // trailing space that the real Supabase column ("Skills & Experience")
    // doesn't, and a mismatched key in the insert payload fails the whole
    // batch, not just that field.
    const headers: string[] = (data.headers || []).map((h: string) => (h || '').trim());
    const rawRows: any[][] = data.rows || [];
    const entryIdCol = headers.indexOf('Entry ID');
    const records = rawRows
      .filter((r) => r.some((cell) => String(cell ?? '').trim() !== ''))
      .filter((r) => entryIdCol < 0 || String(r[entryIdCol] ?? '').trim() !== '')
      .map((r) => {
        const obj: Record<string, string> = {};
        headers.forEach((h, i) => { if (h) obj[h] = String(r[i] ?? ''); });
        return obj;
      });

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // "Entry ID" (the Google Form's own submission id) is this table's
    // primary key — unlike exc_truck_loading, there's no separate
    // auto-generated "id" column here.
    let pruned = 0;
    if (records.length) {
      const { error: upErr } = await sb.from('Internet Leads').upsert(records, { onConflict: 'Entry ID' });
      if (upErr) throw new Error('Upserting Internet Leads failed: ' + upErr.message);

      // Remove rows for leads no longer present in the sheet (e.g. deleted
      // there) — scoped to just the current Entry IDs, not a blanket clear.
      const entryIds = records.map((r) => r['Entry ID']).filter((v) => v !== '' && v != null);
      const { data: staleRows, error: delErr } = await sb
        .from('Internet Leads')
        .delete()
        .not('Entry ID', 'in', `(${entryIds.join(',')})`)
        .select('Entry ID');
      if (delErr) throw new Error('Removing stale Internet Leads failed: ' + delErr.message);
      pruned = staleRows?.length || 0;
    }

    return new Response(JSON.stringify({ synced: records.length, pruned }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
