/* ============================================================================
 * shared.js — common config + helpers for the Built to Work dashboards
 * Loaded by index.html, customer.html and operations.html AFTER the Supabase
 * CDN script and BEFORE each page's own inline script.
 *
 * SECURITY: the Supabase value below is the *anon* key and is public by design.
 * It is safe to ship ONLY because Row-Level Security is enforced server-side
 * (see supabase-rls.sql). Do NOT put a service_role key here.
 * ==========================================================================*/

const SUPABASE_URL  = 'https://uqesgpnnqalpdhbfglbg.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxZXNncG5ucWFscGRoYmZnbGJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNTM3ODMsImV4cCI6MjA5MDYyOTc4M30.1y0wSE7lhNVVPamC-1WEVF0qpFhO9mUN2FVGbNSifMI';
const MAPBOX_TOKEN  = 'pk.eyJ1Ijoiam9lLWNvbm5lciIsImEiOiJjbXFmYnViNGUxa3VnMnhxMGFxYTl3cmduIn0.Dk4qRQ9eQx1DtBcnPgDtdg';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_ANON);

/* Phone normalizer: strip non-digits, drop a leading country-code "1", keep the
 * last 9 digits. Handles float-formatted CSV values like "1234567890.0". This
 * mirrors public.normalize_phone() in supabase-rls.sql — keep them in sync. */
function normalizePhone(p){
  const s = String(p||'').split('.')[0];
  const d = s.replace(/[^0-9]/g,'').replace(/^1/,'');
  return d.slice(-9);
}

/* Single source of truth for "is this email a customer account?", used to
 * route logins between the staff dashboards (index.html/operations.html) and
 * the customer portal (customer.html). Uses ilike (case/whitespace-insensitive)
 * so a stray casing difference between Supabase Auth and the companies table
 * can't silently misroute someone. Errors are logged and treated as "not a
 * customer" (fail toward the staff-only side) rather than throwing. */
async function isCustomerEmail(email){
  const clean = String(email||'').trim();
  if(!clean) return false;
  const {data,error} = await sb.from('companies').select('id').ilike('email',clean).limit(1);
  if(error){ console.error('companies lookup failed', error); return false; }
  return !!(data && data.length);
}

/* HTML-escape a value for safe insertion as element text OR inside a
 * double-quoted attribute. Use this for EVERY DB/API/user-supplied value that
 * goes into innerHTML. */
function esc(v){
  return String(v==null?'':v)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;');
}

/* Escape a value that is interpolated into a JS string literal which itself
 * sits inside a double-quoted HTML attribute, e.g.:
 *     `<div onclick="pick('${jsAttr(name)}')">`
 * It JS-escapes backslash and single-quote, then HTML-escapes the characters
 * that would break out of the attribute. */
function jsAttr(v){
  return String(v==null?'':v)
    .replace(/\\/g,'\\\\')
    .replace(/'/g,"\\'")
    .replace(/&/g,'&amp;')
    .replace(/"/g,'&quot;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;');
}

/* Relative timestamp: "just now", "5m ago", "2h ago", "3d ago", then a date. */
function timeAgo(iso){
  if(!iso) return '';
  const s = Math.floor((Date.now() - new Date(iso).getTime())/1000);
  if(isNaN(s) || s < 0) return '';
  if(s < 60) return 'just now';
  const m = Math.floor(s/60);  if(m < 60) return m+'m ago';
  const h = Math.floor(m/60);  if(h < 24) return h+'h ago';
  const d = Math.floor(h/24);  if(d < 30) return d+'d ago';
  return new Date(iso).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'});
}

/* Validate a user-selected upload before sending it to Supabase Storage.
 * Returns { ok:true, ext } or { ok:false, error }. The accept= attribute is
 * client-side only and bypassable, so this is a real (still client-side) gate;
 * the authoritative limit lives in the storage bucket policy. */
const UPLOAD_MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const UPLOAD_ALLOWED_EXT = ['pdf','doc','docx','rtf','odt','txt','png','jpg','jpeg','webp','heic','xlsx','xls','csv'];
const UPLOAD_ALLOWED_MIME = [
  'application/pdf','application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/rtf','text/rtf','application/vnd.oasis.opendocument.text',
  'text/plain','image/png','image/jpeg','image/webp','image/heic',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/csv'
];
function validateUploadFile(file){
  if(!file) return {ok:false, error:'No file selected.'};
  if(file.size > UPLOAD_MAX_BYTES) return {ok:false, error:'File is larger than 10 MB.'};
  const parts = file.name.split('.');
  const ext = parts.length > 1 ? parts.pop().toLowerCase() : '';
  if(!ext || !UPLOAD_ALLOWED_EXT.includes(ext)) return {ok:false, error:'File type ".'+ext+'" is not allowed.'};
  // file.type can be empty for some types; if present it must be on the allow-list.
  if(file.type && !UPLOAD_ALLOWED_MIME.includes(file.type)) return {ok:false, error:'File content type is not allowed.'};
  return {ok:true, ext};
}
