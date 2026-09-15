// google-apps-script/internet-leads-webapp.gs
//
// Google Apps Script Web App — serves the Internet Leads sheet as JSON so
// the Supabase sync-internet-leads Edge Function can pull it without any
// Google Cloud project or service account. 100% free, no billing involved.
//
// This file lives here for reference/version control only — Apps Script
// isn't deployed from git. You paste it directly into the sheet's own
// script editor (see SETUP below).
//
// SETUP (one-time, done entirely inside the Google Sheet):
//   1. Open the sheet → Extensions → Apps Script.
//   2. Delete the placeholder "function myFunction(){}" code and paste
//      this whole file in instead.
//   3. Replace SECRET_TOKEN below with a long random string of your own
//      (e.g. generate one at a password generator, 32+ characters). This
//      token is the only thing standing between "anyone with the URL" and
//      your candidates' names/phones/emails — don't reuse a token from
//      anywhere else, and don't share it outside this setup.
//   4. Deploy → New deployment → gear icon → type "Web app" →
//        Execute as: Me
//        Who has access: Anyone
//      → Deploy. The first deploy asks you to authorize the script to
//      read this spreadsheet — that's a one-time consent to your OWN
//      sheet, not a recurring cost or a third party gaining access.
//   5. Copy the "Web app URL" it gives you — looks like
//      https://script.google.com/macros/s/AKfycb.../exec
//   6. Store both values as Supabase Edge Function secrets (from a machine
//      with the Supabase CLI installed and logged into this project):
//        supabase secrets set INTERNET_LEADS_WEBAPP_URL='<the Web app URL from step 5>'
//        supabase secrets set INTERNET_LEADS_SYNC_TOKEN='<the SECRET_TOKEN you set in step 3>'
//
// If you ever edit this script again: Deploy → Manage deployments → edit
// the existing deployment (pencil icon) → Version: New version → Deploy.
// Otherwise the URL keeps serving the old code.

const SECRET_TOKEN = 'REPLACE_WITH_A_LONG_RANDOM_STRING';
const SHEET_GID = 59329832; // the "Internet Leads" tab this pulls from

function doGet(e) {
  if (!e || !e.parameter || e.parameter.token !== SECRET_TOKEN) {
    return ContentService.createTextOutput(JSON.stringify({ error: 'unauthorized' }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheets().filter(function (s) { return s.getSheetId() === SHEET_GID; })[0];
  if (!sheet) {
    return ContentService.createTextOutput(JSON.stringify({ error: 'sheet not found for gid ' + SHEET_GID }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  const values = sheet.getDataRange().getValues();
  if (values.length === 0) {
    return ContentService.createTextOutput(JSON.stringify({ headers: [], rows: [] }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  const headers = values[0];
  const rows = values.slice(1);
  return ContentService.createTextOutput(JSON.stringify({ headers: headers, rows: rows }))
    .setMimeType(ContentService.MimeType.JSON);
}
