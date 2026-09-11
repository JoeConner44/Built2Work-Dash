// supabase/functions/sync-internet-leads/index.ts
//
// Pulls the Internet Leads Google Sheet and mirrors it into the
// "Internet Leads" Supabase table. Runs a few times a day (see
// supabase-internet-leads-sync-cron.sql for the schedule).
//
// Authenticates as a Google service account (JWT Bearer flow) — a personal
// Google login can't be used for an unattended cron job. The sheet must be
// shared with the service account's client_email as a Viewer.
//
// This table has no staff-editable fields of its own (all Follow-Up
// tracking lives on candidate_assignments, keyed by phone — see
// supabase-internet-leads-followup.sql), so each run replaces the table's
// contents wholesale rather than upserting. That avoids needing a unique
// constraint on this table and matches "mirror of the sheet" semantics.
//
// Deploy: `supabase functions deploy sync-internet-leads`
// Secrets this function needs (set once, not committed anywhere):
//   supabase secrets set GOOGLE_SERVICE_ACCOUNT_KEY='<the full service-account JSON key, as one line>'
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically to
// every Edge Function — do not set those yourself.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GOOGLE_KEY_RAW = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_KEY');

const SPREADSHEET_ID = '1Kjamq-PizJEWT74_ai614tROfJFhrAiRuqszFkfrnrI';
const SHEET_GID = 59329832; // stable even if the tab is renamed later

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = '';
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const raw = atob(clean);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(): Promise<string> {
  const key = JSON.parse(GOOGLE_KEY_RAW!);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/spreadsheets.readonly',
    aud: key.token_uri || 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const encHeader = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const encClaims = base64UrlEncode(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${encHeader}.${encClaims}`;

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(key.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(signature)}`;

  const res = await fetch(key.token_uri || 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error('Google token exchange failed: ' + JSON.stringify(data));
  return data.access_token;
}

Deno.serve(async (_req) => {
  if (!GOOGLE_KEY_RAW) {
    return new Response(
      JSON.stringify({ error: 'GOOGLE_SERVICE_ACCOUNT_KEY is not set — see the comment at the top of this file' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const accessToken = await getAccessToken();
    const authHeaders = { Authorization: `Bearer ${accessToken}` };

    // Resolve the gid to the tab's current title — the gid in the sheet URL
    // stays stable even if someone renames the tab later.
    const metaRes = await fetch(
      `https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}?fields=sheets.properties`,
      { headers: authHeaders },
    );
    const meta = await metaRes.json();
    if (!metaRes.ok) throw new Error('Sheet metadata fetch failed: ' + JSON.stringify(meta));
    const sheet = (meta.sheets || []).find((s: any) => s.properties.sheetId === SHEET_GID);
    if (!sheet) throw new Error(`No tab with gid ${SHEET_GID} found in the spreadsheet`);
    const tabTitle = sheet.properties.title;

    const valuesRes = await fetch(
      `https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${encodeURIComponent(tabTitle)}`,
      { headers: authHeaders },
    );
    const values = await valuesRes.json();
    if (!valuesRes.ok) throw new Error('Sheet values fetch failed: ' + JSON.stringify(values));

    const rows: string[][] = values.values || [];
    if (rows.length < 1) {
      return new Response(JSON.stringify({ synced: 0, note: 'Sheet is empty' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    const headers = rows[0];
    const records = rows.slice(1)
      .filter((r) => r.some((cell) => (cell || '').trim() !== ''))
      .map((r) => {
        const obj: Record<string, string> = {};
        headers.forEach((h, i) => { if (h) obj[h] = r[i] ?? ''; });
        return obj;
      });

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { error: delErr } = await sb.from('Internet Leads').delete().not('id', 'is', null);
    if (delErr) throw new Error('Clearing Internet Leads failed: ' + delErr.message);

    if (records.length) {
      const { error: insErr } = await sb.from('Internet Leads').insert(records);
      if (insErr) throw new Error('Inserting Internet Leads failed: ' + insErr.message);
    }

    return new Response(JSON.stringify({ synced: records.length, tab: tabTitle }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
