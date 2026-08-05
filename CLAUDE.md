# Built2Work Dashboard — Notes for Claude Code

Single-page HTML dashboards (no build step). Each page is one large self-contained
`.html` file plus a shared `shared.js` for credentials/helpers:

- `index.html` — staff dashboard (participants, filters, pipeline, radius search)
- `operations.html` — operations dashboard
- `customer.html` — customer portal (assignments, radius search)
- `shared.js` — `SUPABASE_URL`, `SUPABASE_ANON`, the `sb` client, `MAPBOX_TOKEN`,
  `normalizePhone()`, `esc()/jsAttr()`, `validateUploadFile()`. Keep credentials here only.

## ⚠️ PROTECTED FEATURE: Radius / Geo Search — do not break it

This feature has regressed repeatedly. Treat it as load-bearing. Before pushing ANY
change to `index.html` or `customer.html`, verify it still works (checklist below).

**Where it lives**
- `index.html`: input `#geoAddressInput` (`oninput="onGeoInput()"`), floating results
  container `#geoFloatSugg` (a `position:fixed` div right before `</body>`),
  handlers `onGeoInput()` / `selectGeoSuggestion()` (~lines 2840–2895).
  Note: `#geoSuggestions` (line ~788) is a leftover, unused inline container — the
  live dropdown is `#geoFloatSugg`. Do not wire code back to `#geoSuggestions`.
- `customer.html`: input `#cGeoInput`, dropdown `#cGeoSugg`, handlers
  `cOnGeoInput()` / `cSelectGeo()` (~lines 538–620).

**Rules**
- Do NOT rename these element IDs or change the `oninput`/`onclick` wiring.
- Keep the Mapbox **Search Box API** flow: `searchbox/v1/suggest` (autocomplete) →
  `searchbox/v1/retrieve` (coordinates), with a rotating `session_token`. Do NOT
  revert to the legacy Geocoding `v5` endpoint — partial queries return nothing there,
  which is exactly the "box ignores what I type" bug.
- Batch/geocode-on-load uses `geocode/v6/forward` (v5 is retired). Keep v6.
- The suggestions dropdown must stay **visible on the light theme**: solid background
  and a drop-shadow so it doesn't blend into white content.
- Never let a failed/empty lookup fail silently — it must write a message to the
  status line (`#geoStatus` / `#cGeoStatus`) so a real problem is diagnosable.

**Verification checklist (run before every push touching these files)**
1. Load the page and sign in.
2. Type 3+ characters of an address into the radius box.
3. Confirm the suggestions dropdown appears AND is readable.
4. Click a suggestion, set a radius, click Apply.
5. Confirm the distance filter narrows the list (distance column populates).

## Theming

Colors come from CSS custom properties in `:root`. IMPORTANT: `index.html` has **two**
`:root` blocks — the base one near the top and a later `/* BTW BRAND OVERRIDES */`
block (~line 288). The override block wins, so edit it (or both) when changing the
palette. `operations.html` and `customer.html` each have a single `:root`.

The theme is light (white background, near-black text, red `#ce0e2d` brand accent).
The login screens (`#loginScreen` and `.login-*` on `index.html` and `customer.html`)
are also light/white to match the rest of the app.

## Logo

The Built to Work logo is a single shared file, `assets/logo.png`, referenced by every
page header and login screen via `<img src="assets/logo.png" alt="Built to Work">`. To
change the logo, replace that one file (see `assets/README.md`). Note: the PDF export in
`index.html` keeps its own base64 copy (the `LOGO` constant) that must be updated
separately.

## Git / branch conventions

Develop on the assigned `claude/*` branch. If its PR is already merged, restart the
branch from the latest default branch and open a NEW PR (never reuse a merged PR).
