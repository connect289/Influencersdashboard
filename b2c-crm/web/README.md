# Eduwit Spark (B2C CRM): web app (Phases 1–4: Sell, Nurture, Money and analytics, Telephony and depth)

Next.js 16 (App Router, Turbopack), React 19, `@supabase/ssr`, zod, sonner, lucide, Geist. The styles are the approved
design's stylesheet (`app/globals.css`, from `../design`), not Tailwind. The database is the `b2c` schema
(`../supabase/migrations`, b1–b29); every action calls a `b2c.*` function that checks the person's permission itself.

```
npm install
cp .env.example .env.local   # fill in
npm run dev                  # http://localhost:3000
npm run typecheck && npm test && npm run build
```

## What is in it

| Area | Routes |
| --- | --- |
| Sign-in | `/login` (Google limited to eduwit.in, or email and password), `/verify` (6-digit code to the company inbox; trust the device for 30 days), `/pending` |
| Sales app (counsellors, sales head, Admin) | `/s` Today, `/s/leads`, `/s/leads/[id]`, `/s/pipeline`, `/s/followups`, `/s/inbox`, `/s/programmes`, `/s/me` |
| Workspace (Admin; Marketing reads) | `/w` Home, `/w/leads` (bulk tools, Recycle bin), `/w/leads/[id]`, `/w/pipeline`, `/w/allocation` (rules, pools, hours and leave, simulation, queues, decisions), `/w/teams`, `/w/enrollments`, `/w/connectors`, `/w/settings`, `/w/guide` |
| Marketing (Admin and Marketing) | `/w/nurture` (Overview, Pool, Journeys, Campaigns, Segments, Replies, Scoring and rules, suppressions), `/w/nurture/journeys/[id]` (steps, trigger, draft and publish, versions, test on a test lead), `/w/templates` (sales and marketing WhatsApp, counsellor and marketing email; submit to Meta). On the lead screen: nurture history, journey, one-off message, consent, hand to a counsellor |
| Money (Admin; Marketing reads) | `/w/money`: Overview (universities and counsellors side by side, tiers this month), Enrolments (link to the catalogue, refund, book again, adjust), Universities (rates by date, billing, period close, invoices, receipts), Receivables (ageing), Statements (CSV upload, four piles), Counsellor commission (needs a rate, fallbacks, overrides, partner rates), Runs (prepare, hold back a line, approve). `GET /w/money/invoice/[id]` the GST invoice or credit note as PDF; `GET /w/money/run/[id]/csv` the finance sheet |
| Money (counsellors) | `/s/money`: this month, provisional and due, 12 months, every line with the partners considered and the rate; `GET /s/money/statement/[run]` the statement PDF |
| Team | `/w/team` (Admin sets targets; Marketing reads), `/s/team` (the sales head sets counsellors' targets): month against target with a pace marker, activity monitor, capacity. On Today: the month's progress and the leaderboard (names only for those who opt in) |
| Analytics (every role, in its scope) | `/w/analytics`, `/s/analytics`: standard and personal dashboards, filters for every widget, the widget editor, **Ask** (Claude writes a query spec from the catalogue; the database runs it as the person), **Explain** on any chart, CSV, schedules (PDF or CSV by email), alerts, the morning insights. Every number opens its leads on `/w/leads?drill=…` or `/s/leads?drill=…` |
| Telephony (Phase 4) | The Call button calls `b2c.call_start`: with Settings → telephony → provider `none` (today) it is the manual flow (dialler, log sheet); with `exotel` the call is bridged (counsellor's mobile first), recorded, and logged by itself; test leads always use the mock, played from the call sheet. `GET/POST /v1/webhooks/telephony/exotel?key=…` (status callbacks and the Passthru applet for incoming calls). Recordings play on the timeline through a 5-minute signed link (logged) |
| Ad spend (Admin and Marketing) | `/w/money` → Ad spend: import the Meta Ads Manager and Google Ads CSV exports (by day, INR), match campaigns to leads, spend, leads, cost per lead and ROAS per campaign; the Ad spend dashboard in Analytics |
| Support (everyone) | `/s/support`, `/w/support`: raise a ticket (what it is about, subject, description, links, up to 4 screenshots), follow it by number (SUP-0001) through Open, In progress (in progress, waiting for you, fixed) and Closed; reply, close, reopen. The Admin sees everyone's tickets and can set any status. Every message from the CRM side is emailed to Settings → support → `developer_emails` with the screenshots; the developer answers by replying (read from Settings → support → `mailbox` every 5 minutes; a `Status: fixed` line sets the status) or through `/support/r/<signed link>` in each email. Fixed tickets close by themselves after 7 days |
| Phone numbers (Admin) | `/w/teams` → Phone numbers: each person's work mobile and own caller ID, changed or moved with a reason and kept in a history; Me shows a person their numbers with "Ask for a change" |
| Calendar (everyone, personal) | Connectors and Me → Availability: "Show my follow-ups in my Google Calendar" |
| Brief before you call | On the lead screen: 3–5 lines, each with its source; written by Claude from scrubbed input, refreshed when a key fact changes, and by the job for calls due within the hour |
| Public (signed links in marketing email) | `/u/[token]` unsubscribe per channel, `POST /e/u/[token]` one-click (List-Unsubscribe), `/e/o/[token]` open pixel, `/e/c/[token]` tracked click and "I'm interested", `/thanks` |
| From the B2B CRM | `POST /v1/handoffs`: signed webhooks (HMAC over the raw body, 5-minute window), stored and applied once per envelope id |
| From Meta | `GET/POST /v1/webhooks/whatsapp`: signed with the app secret; messages to `b2c.wa_inbound`, statuses to `b2c.wa_status` |
| Jobs (pg_cron → here, `x-internal-key`) | `POST /api/internal/sync?mode=urgent` (every minute, also sends phone alerts, classifies replies with Claude, writes briefs for calls due within the hour, emails alerts and scheduled dashboards, and once a day after Settings → ai → `insights_hour_ist` writes the insights; Phase 4: fetches call recordings into the private bucket, removes them after the retention period, and pushes follow-ups to Google Calendar), `?mode=batch` (every 15 minutes), `POST /api/internal/reconcile` (every 5 minutes, also reads the marketing mailbox's replies and bounces and, hourly, Meta template status and quality), `POST /api/internal/directory` (daily, 02:10 IST) |
| Export (Admin) | `GET /w/leads/export?v=<view>&q=<search>`: the view or search as CSV, up to 10,000 rows, logged in the audit log |

**Sync with the B2B CRM** (decisions K2 and K14): the B2B CRM sends hand-offs and lead changes in real time. The B2C CRM
sends its activity back in one batch every 15 minutes (merged to one update per lead), except what must go at once:
consent request sent, consent answer, opt-out, erasure, route-to-partners, new students (Intake API) and **every
counsellor assignment and its end**, so the B2B CRM records each hand-off to the internal sales team like a hand-off to a
partner (Addendum 4 §4a). A lead reaches a partner only through the B2B engine.

**Messages**: WhatsApp from the Eduwit B2C number (template first outside the 24-hour window) and counsellors' email from
their own mailbox. Nothing is sent unless `LIVE_MODE=on` **and** Settings → live mode is on; test leads (phones `910000…`,
`9190000000…`) never get a real message. In test mode a message is recorded as "test mode, not sent".

## Setup (Vikas), staging first

1. **Supabase → Project Settings → Data API → Exposed schemas: add `b2c`** and save. Until then sign-in says the app
   cannot reach its data.
2. **Vercel** (staging is live at https://eduwit-b2c-crm.vercel.app, project `eduwit-b2c-crm` in the Eduwit team):
   `NODE_USE_ENV_PROXY=1 node scripts/deploy-staging.mjs` with `VERCEL_TOKEN`, the staging `SUPABASE_SERVICE_ROLE_KEY`
   and `SMTP_*` in the environment creates the project if needed (root `b2c-crm/web`, region Mumbai), sets its
   variables straight from the environment, deploys the current branch and points the database timers at it (it also
   does step 5). By hand instead: new project from this repo with root `b2c-crm/web` and the variables in `.env.example`.
3. **Supabase → Authentication**: enable Google (OAuth client from Google Cloud, authorised redirect
   `https://mplbspysxmtohnlwpbti.supabase.co/auth/v1/callback`); under URL Configuration add the site URL and
   `https://<site>/auth/callback`. Turn off public sign-ups: the Admin adds people under Teams.
4. **First Admin**: connect@eduwit.in is the Admin on staging. Without Google: on the sign-in page, "First time, or
   forgot your password?" emails a one-time link (1 hour) to set a password; the 6-digit code follows as usual.
   After that, add everyone else from Teams; each person sets a password the same way (or uses Google).
5. **Timers**: in the SQL editor, `select vault.create_secret('<B2C_INTERNAL_KEY>', 'b2c_internal_key');` and
   `update b2c.settings set value = '{"base_url": "https://<site>"}', updated_at = now() where key = 'app';`
   The four `b2c-*` cron jobs then start calling the app (until both exist they do nothing).
6. **B2B CRM → System health → Webhooks and API keys**: register `https://<site>/v1/handoffs`, subscribe to `b2c.*` and
   `b2b.*`, issue the signing secret (`B2B_SIGNING_SECRET`) and an API key with scopes `b2c`, `events`, `intake`
   (`B2B_API_KEY`). Send the test ping; then switch the endpoint on. Run `npm run mock-b2b` against the deployment to
   play the signature checks (test leads only; delete them afterwards).
7. **Email codes**: SMTP settings (Google Workspace SMTP relay, or a mailbox with an app password).
8. **Phone alerts**: `npx web-push generate-vapid-keys`; set `NEXT_PUBLIC_VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`.
   Each person turns alerts on per device under Me → Availability and alerts.
9. **Teams sync**: add the scope `https://www.googleapis.com/auth/admin.directory.user.readonly` to the service account's
   domain-wide delegation and set `GOOGLE_ADMIN_EMAIL` (a Workspace admin it acts as).
9a. **Nurture (Phase 2)**: set `LINK_SECRET` (`openssl rand -hex 32`), `ANTHROPIC_API_KEY` (reply classification; the
   model is Settings → nurture → `classify_model`, `claude-haiku-4-5` by default) and `WHATSAPP_WABA_ID`; add
   `https://www.googleapis.com/auth/gmail.readonly` to the delegation and set Settings → `marketing_email` to the
   marketing mailbox. Then in `/w/templates` submit the marketing templates to Meta, and in `/w/nurture` read each
   starter journey (they start paused) before you **Run** it.
9b. **Money and analytics (Phase 3)**: run `../supabase/manual/staging_phase3_ledger_guards.sql` in the SQL editor.
   Under Settings → money enter Eduwit's GSTIN, legal name, address and state code, and have the CA confirm the GST rate,
   SAC, refund windows and the tier denominator (then set `ca_confirmed` to true). In `/w/money` → Universities enter
   each university's billing details and rate (with its start date), and a counsellor fallback for universities no
   partner covers. Per-programme partner rates come from the B2B CRM (`b2b.partner_programmes`, `b2b.rates`); until
   they exist the partner-wide rate is used. Claude: `ANTHROPIC_API_KEY`; model, daily cap (₹500) and prices are
   Settings → ai (default `claude-sonnet-5-5`, with the server-side refusal fallback on). Schedules and alert emails
   use the SMTP settings of step 7.
9d. **Support tickets**: Settings → support → `developer_emails` starts as `["vikas@eduwit.in"]` (a stand-in); replace it
   with the developer's address. For answers by plain
   email reply, set `mailbox` to a Workspace mailbox (e.g. support@eduwit.in) covered by the service account's
   delegation (gmail.send and gmail.readonly); without it the developer answers through the link in each email, and
   tickets go out by SMTP.
9c. **Phase 4**: nothing is needed to keep today's way of calling. To switch Exotel on: set the `EXOTEL_*` variables
   (`.env.example`), give every counsellor a mobile number in Teams, set Settings → telephony (`provider: "exotel"`,
   `caller_id`, `retention_days`), add the recording announcement in Exotel's call flow, point the Passthru applet of
   the incoming-call flow at the webhook, and turn LIVE_MODE on. Calendar: add the scope
   `https://www.googleapis.com/auth/calendar.events` to the service account's delegation. Ad spend needs no setup.
10. **Later, for live channels**: WhatsApp Cloud API number and templates (audit §9), Gmail delegation (audit §8). Keep
   `LIVE_MODE=off` until the end-to-end test with test leads passes.

## Checks

- **Browser tests against staging** (`e2e/`, Playwright with the Chromium already on the machine):
  1. `SUPABASE_SERVICE_ROLE_KEY` must be the **staging** service role key; every script checks the key's project first and
     stops for any other (production above all).
  2. `npm run e2e:seed` creates five test people (`e2e.admin`, `e2e.manager`, `e2e.asha`, `e2e.ravi`, `e2e.marketing`
     @eduwit.in, all test users) with fresh passwords in `e2e/.auth/passwords.json` (never committed), and 30 test leads
     (phones `9100009901NN`, lead ids 990101–990130) through the B2B hand-off route; 22 are allocated, 8 go to the pool.
  3. `npm run e2e` starts the app locally (LIVE_MODE off, nothing is sent), signs each person in through the password and
     emailed-code screens (the code comes from `b2c.mfa_issue`, as the app would email it), opens every screen per role
     at laptop and phone sizes (screenshots in `e2e/screens/`), and runs the main flows on test leads: logging a call,
     a note, the Admin changing a work mobile, Marketing unable to call, a counsellor unable to open another's lead.
  Behind the cloud proxy, run both with `NODE_USE_ENV_PROXY=1`.
- `npm test`: signing (contract reference code), batch and answer mapping, Intake API body, WhatsApp body and webhook
  parsing, Meta signatures, Gmail JWT and header injection, IST dates, the internal key, email and share text (HTML
  escaping, placeholders), CSV (formula injection), the guides' Markdown, directory mapping; Phase 2: signed email
  links, marketing email (tracked links, footer, List-Unsubscribe), the marketing inbox reader, Meta template mapping;
  Phase 3: the PII scrubber, analytics specs, ranges and number formats, every chart type, commission lines (partners
  and rate shown), money words and tiers, invoice, statement and dashboard PDFs, statement CSV reading; Phase 4: Exotel
  callbacks (outbound, the counsellor's leg not answering, inbound Passthru), the mock's recording, calendar events
  (no phone or email), Meta and Google ad CSVs; support emails, status lines in answers, the developer's signed link,
  screenshot limits, Gmail attachments; dates are not phone numbers in the brief's check. 96 tests.
- `../supabase/tests/test_phase1.sql` (99) and `test_phase2.sql` (45): rolled-back database checks (run in the SQL editor).
  `test_phase3.sql` (91) and `test_phase4.sql` (47), the Phase 3 and 4 exit tests, run on a local database built from
  the migrations.
- `npm run mock-b2b`: the B2B webhook checks against a running deployment.

Not yet verified end to end: sign-in with real accounts, the B2B link (needs Addendum 4 deployed and the keys), live
WhatsApp and Gmail, Meta template approval, Claude classification, Ask, Explain, insights and briefs with a real key, scheduled and alert
emails, the money screens with real rates, a real Exotel call, Calendar against a real Workspace account, a real ad
export. Those are the staging steps above.
