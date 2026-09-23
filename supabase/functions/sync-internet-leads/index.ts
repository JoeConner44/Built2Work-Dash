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
// run's insert land on rows another run just re-inserted, hitting the
// table's primary key ("Phone" — see below). Upsert is safe against that
// since it just updates the row instead of colliding.
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
    // Read as text first — res.json() throws (or, in some runtimes,
    // silently resolves to undefined) on an empty/non-JSON body, e.g. if
    // Apps Script rate-limits the request or returns an HTML error page
    // instead of the expected JSON. Parsing text ourselves means a bad
    // response surfaces as a clear error instead of an opaque crash.
    const raw = await res.text();
    let data: any;
    try {
      data = raw ? JSON.parse(raw) : null;
    } catch {
      throw new Error(`Sheet fetch returned non-JSON (status ${res.status}): ${raw.slice(0, 300)}`);
    }
    if (!res.ok || !data || data.error) {
      throw new Error(`Sheet fetch failed (status ${res.status}): ${JSON.stringify(data ?? raw.slice(0, 300))}`);
    }

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

    // The table's actual primary key is "Phone" (confirmed via
    // pg_constraint) — not "Entry ID" as assumed earlier, which is just a
    // plain unconstrained column. Dedupe by Phone before upserting:
    // Postgres errors ("ON CONFLICT DO UPDATE command cannot affect row a
    // second time") if two rows in the same upsert share a conflict key,
    // which happens whenever someone submits the Google Form more than
    // once. Keep the highest Entry ID (most recent submission) per phone.
    const byPhone = new Map<string, Record<string, string>>();
    for (const r of records) {
      const phone = r['Phone'];
      if (!phone) continue;
      const existing = byPhone.get(phone);
      if (!existing || Number(r['Entry ID'] || 0) > Number(existing['Entry ID'] || 0)) {
        byPhone.set(phone, r);
      }
    }
    const dedupedRecords = [...byPhone.values()];

    let pruned = 0;
    if (dedupedRecords.length) {
      const { error: upErr } = await sb.from('Internet Leads').upsert(dedupedRecords, { onConflict: '"Phone"' });
      if (upErr) throw new Error('Upserting Internet Leads failed: ' + upErr.message);

      // Remove rows for phones no longer present in the sheet (e.g.
      // deleted there) — scoped to just the current phones, not a blanket
      // clear.
      const phones = dedupedRecords.map((r) => r['Phone']);
      const { data: staleRows, error: delErr } = await sb
        .from('Internet Leads')
        .delete()
        .not('Phone', 'in', `(${phones.join(',')})`)
        .select('"Phone"');
      if (delErr) throw new Error('Removing stale Internet Leads failed: ' + delErr.message);
      pruned = staleRows?.length || 0;
    }

    return new Response(
      JSON.stringify({ synced: dedupedRecords.length, sheetRows: records.length, pruned }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
