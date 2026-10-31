# Runbook — eduwit.in website

For whoever operates the site: what runs where, routine checks, flags, the go-live procedure (with the DNS cut-over and
rollback), and what to do when something breaks. Companion docs: `GO_LIVE_CHECKLIST.md` (tick list),
`GO_LIVE_DRY_RUN.md` (rehearsal results), `SECURITY_REVIEW.md`, `LOAD_TESTS.md`, `APPROVALS_NEEDED.md`,
`SETUP_CHECKLIST.md`, `DECISIONS.md`.

## 1. What runs where

| Piece | Where | Notes |
|---|---|---|
| Next.js app (`website/web`) | Vercel, region `bom1` (Mumbai) | Static/ISR pages and cached API responses from Vercel's edge; functions for everything else |
| Database | the shared production Supabase project `xlseqwgyjuqhktrguhyc` | website objects are `public.web_*`; shared catalogue read-only; leads only through `lead_intake` |
| Scheduled jobs | Supabase pg_cron only (D-082; Vercel stays on Hobby, no Vercel crons) | `web_catalog_poll` every minute (inside the database, 30 s statement timeout, D-088); `web_outbox_worker` every minute → `web_outbox_tick()`, which POSTs `/api/internal/outbox` only when a job is due (D-088); `web_seo_daily` 21:30 UTC / 03:00 IST → POST `/api/internal/seo-daily`. The two HTTP jobs use `web_settings.internal_base_url` and Vault secret `web_internal_key`; until both exist they send nothing |
| Email | the provider in S-12 | verification codes, confirmations (through the outbox, retried) |
| Rate limits, breaker | Upstash Redis (S-15) | without it: Postgres limiter for rate limits (D-077); the AI breaker is then per instance |
| Errors | Sentry (S-19) + Vercel logs | logs are JSON with `requestId`; no personal data (scrubbed) |
| Witty on the website | `/api/witty` (internal name `web_advisor`) | model: Gemini `gemini-3.6-flash` via `GEMINI_API_KEY` (D-083); flag `web_advisor_enabled`; students verify their email first (needs the email provider) |

### Programme list sync (D-081)
Witty, the CRMs and the website all use the same shared catalogue tables. The website keeps a fast copy that the
`web_catalog_poll` job rebuilds within a minute of any catalogue change (by any route), and the outbox worker then
refreshes cached pages: changes show on the website within about 2 minutes. New catalogue programmes with a course the
website has never seen stay hidden until a super admin maps them in Admin → Taxonomy mapping (they get an email).
Admin → Dashboard → "Programme list sync" and `/api/health` (detail, `checks.catalog`) show when it last ran; more than
10 minutes means the poll has stopped (check the pg_cron job `web_catalog_poll`: `select * from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'web_catalog_poll') order by start_time desc limit 5`).

## 2. Secrets and settings

Set in Vercel → Project → Settings → Environment Variables, for **Production and Preview** (preview refuses the dev
fallbacks, L1). Full list with meanings: `web/.env.example`; required in production: `SUPABASE_SECRET_KEY`,
`WEB_SESSION_SECRET`, `WEB_INTERNAL_KEY`, `NEXT_PUBLIC_SITE_URL=https://eduwit.in`,
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `APP_ENV=production`, email provider keys,
Turnstile keys.

**Rotating a secret:** set the new value in Vercel and redeploy. `WEB_SESSION_SECRET` rotation signs everyone out
(students and admin second factor) — do it off-peak. `WEB_INTERNAL_KEY`: set the new value in Vercel and, at the same
time, in the Vault secret the database jobs use: `select vault.update_secret((select id from vault.secrets where name =
'web_internal_key'), '<new key>')` (D-082). (`CRON_SECRET` is not needed: there are no Vercel crons.)

## 3. Routine checks

- **Daily (2 min):** Admin → Dashboard (leads today, outbox dead letters, Witty status); Admin → Outbox (dead letters:
  retry once the cause is fixed); Sentry new issues.
- **Weekly:** Admin → Data quality (unmapped programmes, missing fees, zero-result searches → add synonyms or
  curated views); Admin → SEO toolkit (falling pages, on-page scores, 404s → one-click redirects); Admin → Privacy
  requests (complete within 30 days through the CRM process, then mark done).
- **Health:** `GET /api/health` → `{ ok: true }` (uptime monitor, every minute). Detail (database, outbox, providers):
  same URL with `Authorization: Bearer $WEB_INTERNAL_KEY`. `GET /api/metrics` (bearer) for the oversight system.

## 4. Flags (Admin → Flags and settings; no redeploy)

| Flag | Default | Effect |
|---|---|---|
| `web_advisor_enabled` | off | Witty on the website. Off → the hero shows the guided finder and "Get free counselling" |
| `push_unverified_gate_leads` / `_after_minutes` | off / 60 | push gate attempts that never verified as unverified leads |
| `require_phone_otp` | off | phone OTP after email (needs S-25) |
| `document_upload_enabled` | off | document upload in the application form |
| `announcement` | none | site-wide announcement bar |
| `design_concept` | `a` | Concept A (owner-confirmed, D-023); `b` switches to Concept B |
| `default_theme` | `system` | dark / light / follow the device |
| `application_form` | — | hide or make optional non-core form fields (D-069) |
| `business_hours` | none | opening hours in structured data (S-51) |
| `code_send_hourly_cap` | 200 | verification codes per hour for the whole site; above it forms ask people to try again later and `gate.code_ceiling_reached` is logged; 0 stops all sends (super admin, D-086) |
| `web_advisor_daily_cap` | `{"turns": 2000, "cost_usd": 25}` | Witty turns and model spend per India day for the whole site; above either Witty pauses until midnight IST (super admin, D-089) |

## 5. Go-live procedure (only after the owner's written approval)

Owner approvals needed first: go-live itself, and the 🔴 items A-B2B-1 and A-CONSENT-1 (plus S-44 lawyer review).
Everything below is rehearsed by `scripts/db/go-live-dry-run.sh`.

**T-7 days**
1. Supply the go-live setup items (`GO_LIVE_CHECKLIST.md` §Before go-live). Paste the current legal texts into Admin →
   Legal pages (they are empty placeholders until the old site is crawled, S-01) and get S-44 approved.
2. Export the full DNS zone from Hostinger (every record: A, AAAA, CNAME, MX, TXT/SPF/DKIM/DMARC, SRV, CAA,
   verification records) and save it with the date. Lower the TTL of the `@` and `www` records to 300 s.
3. Create the Vercel project (S-10), set the environment variables (§2), add `eduwit.in` and `www.eduwit.in` as domains
   (Vercel shows the exact records; do not change DNS yet).

**T-1 day**
4. Refresh `scripts/db/fingerprint.prod.txt` from production (read-only `fingerprint.sql`), rebuild the replica and run
   `scripts/db/go-live-dry-run.sh`. It must print `DRY RUN PASSED`.
5. Compare `select md5(prosrc) from pg_proc where proname = 'lead_intake'` on production with the snapshot used for s01
   (`s01_lead_intake_email_verified.rollback.sql`); if it differs, regenerate s01 (§8) before applying it.

**Go-live day (quiet hour, e.g. 07:00 IST)**
6. **Backup:** the Supabase organisation is on the Free plan (no point-in-time recovery or automatic backups), so take a
   full dump first: `pg_dump "$PROD_DB_URL" -Fc --no-owner -f eduwit-prod-before-website-<date>.dump` and keep it safe
   (it contains personal data).
7. **Apply website migrations** to production in order (`supabase/migrations/20261017100000_…` to `…20261031100000_web14…`;
   never `00000000000000_prod_snapshot.sql`), each in its own transaction with `set lock_timeout = '5s'`. Expected
   ≈ 1–5 s in total plus the first read-model build (≈ 3 s). Then `scripts/db/check-shared-unchanged.sh <prod-url>`
   (read-only) must say "shared objects unchanged".
8. **Apply approved shared changes** in this order (each file, then its smoke test where one exists, in a
   transaction): s07 (or the B2B admin flips the routing setting in the CRM), s05 (then record the lawyer's approval
   date in the CRM), s01, s04, s06 (optional). **Not at go-live:** s02 (only together with the CRM reader changes,
   A-AGENT-2/3) and s03 (later, A-TAX-1).
8a. **Connect the database jobs** (D-082): create the Vault secret with the same value as Vercel's `WEB_INTERNAL_KEY`,
   `select vault.create_secret('<WEB_INTERNAL_KEY>', 'web_internal_key');` (run in the SQL editor; never commit it).
   `internal_base_url` is set in step 10 once the site is deployed. Check the jobs exist:
   `select jobname, schedule, active from cron.job where jobname like 'web\_%';` → `web_catalog_poll`,
   `web_outbox_worker`, `web_seo_daily`.
9. **First admin:** `connect@eduwit.in` is seeded as super admin; sign in at `/admin` with Google (S-21) or email +
   password, then the emailed code; add other staff in Admin → Content → Staff with their roles.
10. **Deploy** the production build on Vercel (from the approved commit). Point the jobs at it:
    `update public.web_settings set value = '"https://<project>.vercel.app"' where key = 'internal_base_url';`
    (Admin → Flags and settings shows it too). Within a minute Admin → Outbox shows the worker running. Smoke test on the `*.vercel.app` URL against
    production data: home, finder search, a university page, a curated view, the enquiry form end to end with a test
    phone (`is_test`), admin sign-in, `/api/health` = ok, outbox worker running (Admin → Outbox).
11. **DNS cut-over (§6).** Then switch the jobs to the real address:
    `update public.web_settings set value = '"https://eduwit.in"' where key = 'internal_base_url';`
12. **After cut-over (first 2 hours):** old URLs → 301 (`docs/URL_REDIRECT_MAP.md`; spot-check 10), `robots.txt` and
    `sitemap.xml` live, submit the sitemap in Search Console, a real enquiry reaches the CRM as a lead with source
    `website_form`, Sentry quiet, Lighthouse on `/` and `/programmes/online-mba`.
13. **First 24 hours:** watch leads per hour against the old site's normal, outbox dead letters (should stay 0), error
    rate, Search Console coverage. Keep the Hostinger site untouched for 14 days (rollback target).

## 6. DNS cut-over: Hostinger → Vercel

Only the website records change. **Never touch MX, SPF/DKIM/DMARC TXT, or any other record** — email
(`connect@eduwit.in`) and verifications must keep working (risk R-12).

| Step | Record | From (Hostinger) | To (Vercel) |
|---|---|---|---|
| 1 | `@` (eduwit.in) A / ALIAS | Hostinger's address | the A record Vercel shows for the domain (currently `76.76.21.21`; use what Vercel displays) |
| 2 | `www` CNAME | Hostinger | `cname.vercel-dns.com` (or the value Vercel displays) |
| 3 | CAA (only if one exists) | — | add `0 issue "letsencrypt.org"` so Vercel can issue the certificate |

Keep nameservers at Hostinger (simplest rollback). Vercel issues the TLS certificate within minutes of the records
resolving. In Vercel's domain settings set `www.eduwit.in` to redirect (308) to `eduwit.in`, the canonical host. Propagation with a 300 s TTL: typically under 30 minutes. Verify with
`dig +short eduwit.in`, `dig +short www.eduwit.in CNAME` and a browser in a private window from mobile data.

**Rollback (any time in the first 14 days):** restore the two records to the exported Hostinger values (§5 step 2). With
TTL 300 s visitors are back on the old site within minutes. Then, if the problem is in the database layer, run the
database rollback (§7). Leads created by the new site stay in the CRM (they are real enquiries).

After 14 stable days: raise the TTL back to 3600 s and retire the Hostinger site.

## 7. Rollback of the database changes

- **Shared proposals:** each `supabase/migrations-shared/sNN_*.rollback.sql`, in reverse order of application.
  s05's rollback refuses once leads reference the website consent versions (deactivate instead, as it says).
- **web14 alone** (limits of 31 Oct 2026): `supabase/rollbacks/20261031100000_web14_audit_limits.rollback.sql` (one
  transaction) restores the earlier function definitions and job commands and removes what web14 added.
- **Website objects:** first `pg_dump --schema=public --table='web_*'` (keep the consent ledger, applications and
  privacy requests for DPDP), then `scripts/db/rollback-web.sql`. It refuses if any shared object depends on a website
  object, removes the website's pg_cron jobs and every `web_*` object, and leaves leads and touchpoints in the shared
  tables untouched.
- **Last resort:** restore the full dump taken in §5 step 6 (the Free plan has no point-in-time recovery) — this also rewinds Witty and the
  CRMs, so only with every product owner's agreement.

## 8. Incidents

| Symptom | Likely cause | What to do |
|---|---|---|
| `/api/health` 503 | database unreachable | Supabase status/dashboard; pages keep serving from the edge cache; forms show "try again"; no action in the app |
| Searches return "temporarily unavailable" (503) | database busy (per-instance cap, D-080) or slow | check Supabase CPU; short spikes clear by themselves; for ad spikes enable the read replica (S-54) or raise compute; `WEB_DB_MAX_CONCURRENCY` only if the database has headroom |
| No verification emails | email provider down or quota | provider dashboard; sends are retried by the outbox; meanwhile students can reach a counsellor through the WhatsApp and phone links shown with the forms and on the contact page |
| Outbox dead letters growing | a downstream (email, CAPI, CRM write) failing | Admin → Outbox shows the error; fix the cause, then retry; leads themselves are written synchronously through `lead_intake` and are not lost |
| Gate/forms refuse everyone ("verification failed") | Turnstile keys wrong or Turnstile down (fails closed in production) | check the keys and the site's hostnames in the Turnstile dashboard (S-13); Cloudflare status |
| Witty answers "couldn't answer just now" / hero shows the finder | AI provider errors → breaker open (5 failures in 2 min → 60 s) | provider status; it recovers automatically; to stop it entirely turn `web_advisor_enabled` off |
| Confirmation emails late, dashboard says "Background jobs are not running" | the pg_cron job `web_outbox_worker` is not reaching the site | `select * from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'web_outbox_worker') order by start_time desc limit 5`; then `select * from net._http_response order by created desc limit 5` (401 → Vault key differs from Vercel's `WEB_INTERNAL_KEY`; connection errors → wrong `internal_base_url`). Run once by hand: `POST /api/internal/outbox` with the bearer key |
| Wrong fees or programmes | catalogue data (owned by Witty/catalogue) or the sync stopped | Admin → Dashboard "Programme list sync": if it says the check has not run, fix the pg_cron job `web_catalog_poll`; force a sync with `POST /api/internal/catalog-poll` then `POST /api/internal/outbox` (bearer). If the catalogue itself is wrong, fix it at the source (Witty's catalogue) — the website follows within ~2 minutes |
| A new programme is in Witty/CRM but not on the website | a course the website taxonomy has never seen (hidden until mapped, spec 5.3) | Admin → Taxonomy mapping: map it to a programme and specialisation (super admins got an email); it appears within ~2 minutes |
| Lead missing in the CRM | `lead_intake` error, or routing held (A-B2B-1 not applied) | Admin → Outbox / logs (`lead.*` events, request id); B2B "unqualified: phone_not_verified" means A-B2B-1 is not live |
| A shared function changed under the website (after another product's release) | another product's migration | rebuild the replica and run `npm run db:gate`; `check-shared-unchanged.sh` names what changed |
| Suspected abuse (floods of enquiries) | bots | rate limits and Turnstile hold; Admin → Insights shows junk scores; lower limits in `web/lib/server/rate-limit.ts` and redeploy if needed |
| Forms say "We're getting a lot of requests right now" | the site-wide code ceiling is reached (log `gate.code_ceiling_reached`, D-086) | Admin → Insights and the gate attempts show whether it is real demand (a campaign) or a flood; raise `code_send_hourly_cap` for real demand; it clears by itself within the hour |
| Witty shows the finder all day; log `web_advisor.daily_cap_reached` | the daily Witty ceiling is reached (D-089) | check Admin → Insights for one visitor or many; raise `web_advisor_daily_cap` if it is real use; it resets at midnight IST |

**Regenerating s01** (if production's `lead_intake` changed): `scripts/db/make-s01.py` (instructions inside; it reads
production's current body read-only, re-inserts the s01 lines and rewrites the rollback file), then
`check-shared-proposals.sh`, and get the change re-reviewed.

## 9. Staff access

Admin roles (D-067): **Viewer** reads everything except student emails; **Content editor** edits content, SEO,
redirects, taxonomy mapping; **Super admin** also flags, legal pages, consent texts, outbox retries and privacy
requests. Sign-in: Google or email + password, then an emailed 6-digit code (a trusted device skips the code for 30
days on that browser; signing out keeps that trust — clearing the browser's cookies removes it; deactivating the staff
member in Admin → Staff blocks them everywhere).
Every change is in Admin → Audit log.
