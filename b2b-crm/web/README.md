# Eduwit Partner CRM: web app

Next.js 16 (App Router, Turbopack), React 19, Tailwind CSS 4, Supabase Auth. Design: `../../docs/b2b-design.md`.

## What it does today (app shell)

- Sign-in for the single Admin (`connect@eduwit.in`): Google, or email + password; then a 6-digit authenticator code
  (TOTP). Password reset by email. Any other account is refused, signed out and logged.
- Five failed password or code attempts lock sign-in for 15 minutes. Sessions end after 12 hours idle.
- The shell: sidebar, ⌘K command palette, `g` + letter shortcuts, light/dark/system theme, Security page (sessions,
  sign out other devices, sign-in history). Planned screens describe what is coming.
- Command Center (`/`): today's leads, leads to partners and accepted (each against the same hours yesterday), the
  7-day duplicate rate, first-contact SLA compliance and this month's expected commission; partner health cards
  (today against the daily cap, accepted and duplicates this week, pushes retrying or failed); where leads went in
  the last 7 days by destination and source; the lead stream; alerts; the pool size; every live switch; and, until a
  partner is live and routing is on, the road to the first routed lead. Test leads are left out. `b2b.command_center`.
- Pre-routing pool (`/pool`): leads with no destination yet, grouped by why they wait (still chatting with Witty,
  ready but routing is off, ready and due, opted out, older than 90 days, test leads) with counts by age, where each
  would go once decided, and what keeps leads from a partner. `b2b.pool_overview`.
- Leads (`/leads`): search (name, phone, email, ID), status/stage/source/routing filters with counts, keyset paging,
  a drawer with the lead's details, Witty chat and activity, bulk soft delete with a reason, the recycle bin with
  restore, and CSV export (full or masked; every export is logged). State lives in the URL, so every view is a link.
  The export streams page by page (up to 50,000 rows, with partner, reference and both status layers), so a large file
  keeps downloading while the Admin works; its filters are fixed when it starts (`b2b.leads_export_start` / `_page`).
- Lead corrections: the drawer's Edit tab corrects contact, interest, profile, classification and notes, with a reason.
  Changes go through `lead_intake()` (as `crm`) via `b2b.lead_edit`, which checks every field and keeps the old and new
  value in `b2b.lead_edits`; the tab lists that history and flags a correction Witty has since written over. Fields
  cannot be emptied (lead_intake cannot clear), and routing, consent, source and money fields are not editable.
- Partners (`/partners`): cards with status, live state, today's and this month's leads and go-live progress; add and
  edit (identity and student-facing brand, CRM type, duplicate handling and hold window, caps, working hours and
  holidays, SLAs, lead criteria, notification switch); mark active, pause, resume, close (with reasons); the live
  switch, which stays locked until the go-live checklist is complete.
- Programme Repository (`/programmes`): per partner, upload the partner's Excel or CSV file (kept as uploaded in a
  private bucket), map its columns once (the template is saved), and every row is normalised (amounts like "1.5 L",
  modes, levels, dates, commission) and matched to the catalogue. Review the rows that need it, preview what changes
  against the live offers (removals that leave a programme with no partner are flagged), publish, and roll back to any
  earlier version. Catalogue coverage by course across partners.
  Or connect the partner's Google Sheet (shared as "anyone with the link can view"): Sync now downloads it as Excel,
  reads the chosen tab, and creates a draft only when its content changed (same template, matching and review as a
  file). The page marks a sheet as due after its check interval; reading it on a schedule without a click needs a
  Vercel Cron secret and is not built yet.
- Routing (`/routing`): the automatic-routing switch (off until turned on; it warns when no partner is live or consent
  is missing), today's numbers, partner readiness and the decision log; a simulator that runs the engine on any lead
  without writing anything and can then route it by hand with a note; rules (always send to, only consider, never send
  to); commission rates (confirm the file's proposals, or set a partner-wide rate; versioned, never edited); engine
  settings saved as a new version with a reason. Each decision has its own page explaining why, and the lead drawer
  has a Routing tab. The engine itself is `b2b.route_core` (`supabase/migrations/*_m6b_route_lead.sql`); pg_cron calls
  `b2b.route_ready_leads` every minute, which does nothing while the switch is off.
- Hand-off rules (Addenda 1 and 2, `docs/B2B_CRM_ADDENDUM_*.md`): every lead is passed to a CRM except junk and
  programme mismatch, which stay in the master table under Leads → Not passed (single or bulk "Pass to CRM", with a
  reason). Paid-campaign, B2C-created and B2C-held leads go to the B2C CRM's sales lane; unqualified leads to its
  nurture lane; rules may also send leads to B2C. From the lead drawer: send a B2C lead to partners by hand, or record
  that a partner marked a lead lost (B2C nurture). Passed leads that Witty later reclassifies wait in the review queue.
  The engine is `b2b.route_decide` (`supabase/migrations/*_m7b1_route_decide.sql`).
- Pushes to partners (`supabase/migrations/*_m8*.sql`, contract in `docs/partner-api.md`): pg_cron runs
  `b2b.push_tick` every 10 seconds, which sends queued leads with pg_net (signed, idempotent), reads the partner's
  answer (created, duplicate, rejected, error), retries after 10 s, 1 min, 5 min, 15 min and 1 h, waits out the
  partner's hold window and then accepts. Duplicates and rejections move the lead to the next partner; late duplicate
  claims become commission disputes. Partners report back to `POST /v1/partners/{slug}/events` (HMAC-signed). The
  partner page's Connection tab holds the API credential, the signing secret (shown once), pushes, events and disputes.
- Notifications (`/notifications`, `supabase/migrations/*_m9*.sql`): once a partner accepts a lead, the student gets
  one WhatsApp message (an approved template sent through Meta's Cloud API from Eduwit's number) and one email
  (Resend or Brevo), inside quiet hours, in Hindi or English, naming the partner and when it will call. Never to test
  leads, opted-out students or partners with notifications off. pg_cron runs `b2b.notify_tick` every 30 seconds; a
  failed message is retried once, then marked failed with an alert. Each channel has its own live switch (both off),
  and a message due while its switch is off is cancelled, not sent late. The screen holds the switches with what is
  still missing, the templates with a preview per partner, the provider settings (keys go to Vault) and the masked
  send log with "Send again". The lead drawer's Routing tab lists the student's messages.
- System health (`/system`, `supabase/migrations/*_m14*.sql`, contract in `docs/b2c-contract.md`): the background
  jobs with their last run and failures, events received from the B2C CRM, open erasure requests, webhook endpoints
  (signing secret shown once, test ping, switch on or pause with a reason), the delivery log with "Send now", and API
  keys (shown once, revocable). Machine endpoints for the B2C CRM: `GET /v1/handoffs` (reconciliation feed),
  `POST /v1/leads/{id}/route-to-partners` (both with an API key, `Authorization: Bearer`) and
  `POST /v1/events/b2ccrm` (HMAC-signed). pg_cron runs `b2b.outbox_tick` every 15 seconds to deliver webhooks.
- Mapping studio (`/mapping`, `supabase/migrations/*_m15*.sql`): per partner, rules from its stages, sub-stages,
  pipelines, fields (with direction and transform chains such as `trim | amount`), picklist values and activities to
  Eduwit's model, edited on a draft and published as numbered versions (golden files must pass; any version can be
  restored). Suggestions come from other partners on the same CRM, synonyms and similar names. Tabs: Stages, Fields,
  Values, Activities, Test (a payload in, a lead out and back, golden files), Queue (everything unmapped, with counts
  and leads), Schema (uploaded field lists, what the events show, drift, stage corrections) and Versions. The partner
  page's go-live checklist links here.
- Sync & SLAs (partner page tab, `supabase/migrations/*_m16*.sql`): sync health (last event, lag, failures, dead
  letters, pushes, a 7-day chart and one traffic light), the SLA scorecard in the partner's working hours with recent
  breaches, dead letters with Retry and Discard (with a reason), and reconciliation items, which are re-checked every
  night and on demand, or against the partner's own export (CSV or JSON). The lead drawer's Partner sync tab shows
  the lead's SLA clocks, the partner's calls, messages and stage changes, and every raw event with its mapping.
  pg_cron runs `b2b.sla_tick` every 5 minutes and `b2b.reconcile_all` nightly.
- Intake (`/intake`, `supabase/migrations/*_m17*.sql`): sources by volume, failed requests with Retry and Discard,
  and the latest requests with where each lead is heading. The import wizard reads .xlsx or CSV in the browser (up
  to 50,000 rows), maps columns (mappings can be saved), matches courses to the catalogue, previews duplicates (with
  CSV downloads), then records the consent basis and the routing choice (route, hold, B2C); history with release
  and a 24-hour rollback. Ad forms (Meta and Google question mapping, fixed values, consent), New lead (typed in by
  hand) and Connections (webhook URLs; secrets go to Vault). Machine routes: `POST /v1/leads` (Intake API, contract
  in `docs/intake-api.md`), `GET/POST /v1/webhooks/meta/leadgen`, `POST /v1/webhooks/google/leadform`. pg_cron runs
  `b2b.intake_tick` every 10 seconds (Meta fetches) and `b2b.import_tick` every minute.
- Conversions (`/capi`, `supabase/migrations/*_m18*.sql`): lead milestones reported to Meta (Conversions API) and
  Google Ads (offline and enhanced conversions for leads). It shows each platform's live switch and what blocks it,
  totals and match-key coverage, per-milestone counts and value, an event log with Retry, Setup (consent rule, accounts,
  credentials in Vault, stage-to-event maps) and Check a lead (the exact payloads, hashed). pg_cron runs `b2b.capi_tick`
  every minute. Setup guide: `docs/capi-setup.md`.
- Partner CRM adapters (partner page → Connection, `supabase/migrations/*_m19*.sql`): LeadSquared, Zoho CRM,
  Salesforce, HubSpot and Meritto, per environment (live and sandbox): settings, keys (to Vault), reference and status
  fields, polling, fixed values, sign-in state, last poll, field fetch and a masked push preview. pg_cron runs
  `b2b.partner_sync_tick` every minute. Guide: `docs/partner-adapters.md`.

## How access is enforced

| Layer | Check |
| --- | --- |
| `proxy.ts` | Refreshes the session, signs out after 12 h idle, redirects signed-out visitors, sets a nonce CSP |
| `app/(app)/layout.tsx` → `requireAdmin()` | On every request: `b2b.me()` must say allowlisted and `is_admin` (TOTP-verified) |
| Server actions → `assertAdmin()` | Same check; throws |
| Database | RLS `(select b2b.is_admin())` on every `b2b` table; Admin functions re-check `b2b.is_admin()` |

The service-role key is used only for the signed-out steps: logging attempts, the lockout check and the reset-link
allowlist check (`lib/auth.ts`).

## Run locally

```bash
cp .env.example .env.local   # fill in the four values
npm install
npm run dev                  # http://localhost:3000
npm test && npm run typecheck && npm run build
```

## Deploy on Vercel (one time)

1. Vercel → Add New → Project → import `connect289/Influencersdashboard`. **Root Directory: `b2b-crm/web`.**
   `vercel.json` pins the Mumbai region (`bom1`).
2. Environment variables (Production and Preview):
   - `NEXT_PUBLIC_SUPABASE_URL` = `https://xlseqwgyjuqhktrguhyc.supabase.co`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` = Supabase → Project Settings → API Keys → publishable key
   - `SUPABASE_SERVICE_ROLE_KEY` = same page → secret key (mark it Sensitive)
   - `NEXT_PUBLIC_SITE_URL` = the app's URL, e.g. `https://eduwit-b2b-crm.vercel.app` (no trailing slash)
3. Supabase (production project):
   - Project Settings → Data API → **Exposed schemas: add `b2b`** (the app shows a setup notice until this is done).
   - Authentication → URL Configuration → Redirect URLs: add `https://<your app URL>/auth/callback`.
     Keep the old CRM's URLs; do not change the Site URL.
   - Authentication → Providers → Email: turn on **leaked password protection**.
   - Authentication → Multi-Factor: TOTP **enabled** (the default).
4. Deploy. Every push then builds automatically; merging to `main` updates production.
