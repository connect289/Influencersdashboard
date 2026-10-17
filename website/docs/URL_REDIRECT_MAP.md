# URL redirect map (old Hostinger site → new site)

**Status: partial.** The current site could not be crawled from the build environment (D-006, S-01). This map holds
every URL known from the spec; it is completed automatically from `content/legacy/urls.txt` once
`web/scripts/crawl-legacy-site.mjs` runs. The machine-readable source of truth is `web/content/redirects.ts`, which
`next.config.ts` turns into 301 redirects and which CI tests entry by entry (`e2e/content.spec.ts`; spec 13.1 / 16.7). Admin-managed
redirects (`web_redirects`, Phase 10) are applied after these.

## Rules
- `/about` and every `/legal/*` path stay **identical** (spec 13.1). No redirect needed; CI asserts they return 200.
- Old URLs that have a direct equivalent → 301 to it. Old URLs with no equivalent → 301 to the closest hub
  (`/programmes`, `/universities`, `/resources`, `/`), never to a 404.
- Query strings on old URLs are dropped except UTM/click-ID parameters, which are preserved so attribution survives.
- Trailing slashes are normalised to no trailing slash; uppercase paths → lowercase.
- `www.eduwit.in/*` → `https://eduwit.in/*` (domain-level, Vercel).

## Known URLs (from the spec)
| Old URL | New URL | Type | Source |
|---|---|---|---|
| `/` | `/` | same | spec §1 |
| `/about` | `/about` | same (must not change) | spec §1, §13.1 |
| `/contact` | `/contact` | same (assumed path) | spec §1 (contact details, contact form) |
| `/legal/terms-and-conditions` | same | same | spec §1 |
| `/legal/privacy-policy` | same | same | spec §1 |
| `/legal/disclaimer` | same | same | spec §1 |
| `/legal/refund-policy` | same | same | spec §1 |
| `/legal/cookie-policy` | same | same | spec §1 |
| `/legal/data-privacy-opt-out` | same | same | spec §1 |

## Likely URLs to confirm with the crawl
Hostinger Horizons sites commonly use paths such as `/courses`, `/services`, `/universities`, `/blog`,
`/testimonials`, `/privacy`, `/terms`. Provisional mappings, applied only if the crawl finds them:

| Old URL (if found) | New URL |
|---|---|
| `/courses`, `/programs`, `/programmes-offered` | `/programmes` |
| `/courses/*`, `/course/*` | `/programmes?q=<derived>` (or the curated view if one exists) |
| `/services` | `/how-it-works` |
| `/universities/*` (old slug) | `/universities/<new slug>` |
| `/blog`, `/blog/*` | `/resources`, `/resources/<slug>` |
| `/testimonials` | `/about#student-stories` |
| `/privacy`, `/privacy-policy` | `/legal/privacy-policy` |
| `/terms` | `/legal/terms-and-conditions` |
