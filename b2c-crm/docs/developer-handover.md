# Eduwit Spark: handover to the developer (taking it live)

Version 16 October 2026. Spark is the B2C CRM: code in `b2c-crm/web` (Next.js 16), database schema `b2c` in Supabase,
migrations `b2c-crm/supabase/migrations/b1…b56` (apply in order; all idempotent), checks in `b2c-crm/supabase/tests`.
This guide is the whole path from where things stand to a working, live CRM. Do the steps in order; each says how to
check it and how to undo it. `docs/go-live-plan.md` keeps the history; this file supersedes it for what is left.

**Never:** run `student_leads_v2_rename.sql`; change Witty's `w2_*` tables, `lead_intake()`, the n8n workflows or the
B2B CRM's code; put a secret in git or in chat. `LIVE_MODE` stays `off` until step 12.

## Where things stand

| Piece | State |
| --- | --- |
| Production database `xlseqwgyjuqhktrguhyc` ("EDUWIT LEAD TRACK", Mumbai) | **Done 16 Oct 2026**: `b1`–`b46` (`b39`–`b43` and `staging_b4_pool_calendar.sql` through the SQL editor, `b44`–`b46` through the connector); 510 `b2c` functions, the same set as staging and the tested local build; 16 `b2c-*` timers; anon executes nothing; programme cache filled (715 programmes, 29 universities). `b2c` exposed in the Data API. First Admin: connect@eduwit.in |
| Staging database `mplbspysxmtohnlwpbti` ("eduwit-b2b-staging") | **Done 16 Oct 2026**: `b1`–`b46`; 510 functions; test people and 30 test leads seeded for the browser tests |
| Local proof | `b1`–`b43` on a clean Postgres: every suite passes (`test_completion` 209 checks, `test_phase1` 99, `test_phase2` 45, `test_phase3` 91, `test_phase4` 47, `test_features` 26, `test_support_phones` 28, `test_walkthrough_fixes` 10) |
| Production site | Vercel project `eduwit-spark` (team `eduwit`), root `b2c-crm/web`, `https://spark.eduwit.in` (DNS done) and `https://eduwit-spark.vercel.app`. **Deployed 16 Oct 2026 from branch commit `ab1d219`** (every screen of `b39`–`b45`). Set: Supabase URL and publishable key, **service role key** (Vikas, 16 Oct), site URL `https://spark.eduwit.in`, SMTP, VAPID, `LINK_SECRET`, `B2C_INTERNAL_KEY`, `LIVE_MODE=off`. Google sign-in and the emailed code work (Vikas signed in on 16 Oct). **Not yet**: the timers' key in Vault (step 5.2) and the optional services (step 5.3) |
| Staging site | `https://eduwit-b2c-crm.vercel.app` (Vercel project `eduwit-b2c-crm`), deployed 16 Oct from the same commit; the browser tests ran against it |
| Programme page (16 Oct) | Grouped by university; filters in the address (`?q=&university=&course=&specialization=&level=&mode=`, more under "More filters"). **Each card leads with the full fee for the whole programme**: the catalogue's total; if that is missing, the yearly fee times the duration; if only a yearly fee is known it says "Fee per year". The per-semester instalment sits under it; the yearly figure is only in Details and the compare table. 86 of the 715 programmes have no fee in the catalogue and show "—" until the B2B CRM's Programme Repository fills them in. Commission column and the university's rate chip: Admin and Marketing only |
| Checks on 16 Oct | Local database: every suite passes (`test_completion` 210, `test_phase1` 99, `test_phase2` 45, `test_phase3` 91, `test_phase4` 47, `test_features` 26, `test_support_phones` 28, `test_walkthrough_fixes` 10). App: typecheck, 174 unit tests, production build. Browser: `walkthrough.spec.ts` opened every screen as every role (laptop and phone) against staging and locally with no error page, server error or console error; `flows.spec.ts` 14 of 14 (call log, note, stage, support ticket, work-mobile change, password link and code). Note: the Vercel projects' production branch is `main`, which has no `b2c-crm` folder, so a push to `main` makes them log a failed build that changes nothing; merge this branch into `main` (or set the production branch to it) so pushes deploy |
| Staging site | Vercel project for `https://eduwit-b2c-crm.vercel.app` on the staging database |
| Branch | `claude/exciting-heisenberg-fse6ik` in `connect289/Influencersdashboard` |

## 1. Backup production (Vikas)

Steps 2 and 3 are done (16 October). Keep this step for every future migration.

### Backup

Supabase → production project → Database → Backups: confirm today's backup (or take one). **Check:** a backup listed
for today. **Undo for everything below:** restore it.

## 2. The database: staging first, then production (SQL editor) — done 16 Oct 2026; repeat for future migrations

Two files, both idempotent (safe to run again, and safe where part is already applied):

- `b2c-crm/supabase/manual/apply_b39_b45.sql`: migrations `b39`–`b45` in one file (generated from `supabase/migrations`).
  `b46_health_timer_calls.sql` came after the bundle: run it on its own, after the bundle (both databases already have it).
- `b2c-crm/supabase/manual/staging_b4_pool_calendar.sql`: saving a pool's members and a person's weekly hours
  (production only; staging has it).

**Staging** (`mplbspysxmtohnlwpbti`) → SQL editor → paste `apply_b39_b45.sql` → Run. Then run each file in
`b2c-crm/supabase/manual/sql-editor-tests/` (one at a time). Each ends on purpose with an **error** that reads
`TESTRESULT pass=N fail=0 …`: `fail=0` is a pass; any failure is listed by name. The error is what guarantees nothing a
test writes is kept. Expected on a clean copy: `test_completion` 215, `test_phase1` 99, `test_phase2` 45,
`test_features` 26, `test_support_phones` 28, `test_walkthrough_fixes` 10 (real staging data can change a count; every
check must still pass). `test_phase3` and `test_phase4` write catalogue and partner fixtures, so they refuse to run
anywhere but a local Postgres database named `b2c_fresh` (load `supabase/tests/local_stubs.sql`, then every migration in
order; see `b2c-crm/README.md` → tests).

**Production** (`xlseqwgyjuqhktrguhyc`), only after staging passes: backup (step 1) → SQL editor → run
`staging_b4_pool_calendar.sql` (first time only), then `apply_b39_b45.sql` (or the next migration file). Do **not** run
the test suites on production: it is the database Witty, the B2B CRM and the Influencer Dashboard share. The read-only
check below is enough there, because the migrations are the same files that passed on staging and locally.

**Check (production and staging; every row must say `true`):**

```sql
select 'b2c functions' what, count(*) >= 470 ok from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c'
union all select 'pool_save', to_regproc('b2c.pool_save') is not null
union all select 'calendar_save', to_regproc('b2c.calendar_save') is not null
union all select 'b40 erase', to_regproc('b2c.lead_erase') is not null
union all select 'b41 programme cache', to_regclass('b2c.programme_cache') is not null
union all select 'b42 queues', to_regproc('b2c.queues') is not null
union all select 'b43 connectors', to_regclass('b2c.connector_status') is not null
union all select 'test users gone', not exists (select 1 from b2c.users where email like '%.cp@eduwit.in')
union all select 'no anon execute', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                                 where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute'));
```

**Undo:** restore the backup from step 1 (everything Spark adds lives in schema `b2c`; Witty's tables, `student_leads`
and the B2B CRM's objects are not touched by these files).

## 3. Supabase production settings — done 16 Oct 2026 (kept for reference)

1. **Expose the schema.** Project Settings → API (Data API) → Exposed schemas: add `b2c` (keep `public`). Save.
2. **Sign-in addresses.** Authentication → URL Configuration:
   - **Site URL: do not change it.** The B2B CRM shares this project and its emails use it.
   - Redirect URLs: add `https://spark.eduwit.in/**` and `https://eduwit-spark.vercel.app/**`.
3. **Google sign-in.** Authentication → Sign In / Providers → Google: enabled, with the Client ID and secret of the OAuth
   client from step 4.1. If the B2B CRM already uses Google sign-in here, keep its client and only add Spark's addresses
   to that client in step 4.1.
4. **Email.** Authentication → Emails → SMTP: the same Google Workspace SMTP as Spark (password resets and invitations
   come from Supabase).

**Check:** `https://spark.eduwit.in/login` → Continue with Google → back on Spark.

Two errors seen on 15–16 October and what they mean:

- Google's **"Error 400: redirect_uri_mismatch"**: the Google client set in step 3.3 does not list
  `https://xlseqwgyjuqhktrguhyc.supabase.co/auth/v1/callback` (step 4.1).
- **"Unable to exchange external code"**, and landing on `https://dashboard-eduwit.vercel.app/login` (this project's Site
  URL, the Influencer Dashboard): the Client ID and Client secret in step 3.3 do not belong to the same Google client
  (Google no longer shows old secrets: on the client, **Add secret**, paste the new one with that client's exact ID), and
  `https://spark.eduwit.in/**` is missing from Redirect URLs (step 3.2), so Supabase fell back to the Site URL.
  The Influencer Dashboard, the B2B CRM and Spark share this project's callback, so one Google client serves all three.

## 4. Google Cloud (project `even-crossing-499410-j3`, as vikas@eduwit.in)

1. **Sign-in client** (Google Auth Platform → Clients → the client set in step 3.3, type Web application):
   - Authorised JavaScript origins: `https://spark.eduwit.in`, `https://eduwit-spark.vercel.app`
   - Authorised redirect URIs: `https://xlseqwgyjuqhktrguhyc.supabase.co/auth/v1/callback`
   - This is the fix for the "Error 400: redirect_uri_mismatch" seen on 15 October: the staging client only lists the
     staging callback (`mplbspysxmtohnlwpbti…`). Save; it can take a few minutes.
2. **Each person's own Gmail** (Me → My Gmail). A second Web application client (or the same one):
   - Authorised redirect URI: `https://spark.eduwit.in/auth/google/gmail/callback`
   - Audience: Internal (only @eduwit.in). Data access: scopes `gmail.send`, `gmail.readonly`, `gmail.metadata`.
   - APIs & Services: enable the **Gmail API**.
   - Put its ID and secret in Vercel as `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` (step 5).
3. **Service account with domain-wide delegation** (optional but recommended: then nobody has to connect Gmail, and
   Teams syncs from Workspace). Create a service account and key; in Google Workspace Admin → Security → API controls →
   Domain-wide delegation, add its client ID with the scopes:
   `https://www.googleapis.com/auth/gmail.send`, `https://www.googleapis.com/auth/gmail.readonly`,
   `https://www.googleapis.com/auth/admin.directory.user.readonly`, `https://www.googleapis.com/auth/calendar.events`.
   Vercel: `GOOGLE_SA_EMAIL`, `GOOGLE_SA_PRIVATE_KEY`, `GOOGLE_ADMIN_EMAIL=connect@eduwit.in`.

## 5. Vercel `eduwit-spark`: the service role key, then the services

1. Domain: Settings → Domains → `spark.eduwit.in` must show "Valid configuration" (done).
2. **Still to do: run the deploy script once** (the service role key is already in Vercel; the script needs it in your
   shell too, to call `app_deploy_set`, which stores `B2C_INTERNAL_KEY` in Vault so the 16 timers can call the site.
   Until this runs, queued messages, the B2B sync and the other background jobs wait, and the Home page's health row
   "The app answering the timers" stays yellow with "not pointed at the site yet").
   Run it with the production service role key (Supabase → production → Project Settings → API
   keys → service_role). It sets the key, rotates `B2C_INTERNAL_KEY` into Vault, redeploys and points the database
   timers at the site (`app_deploy_set`). It refuses a staging key.
   ```bash
   cd b2c-crm/web
   VERCEL_TOKEN=… PRODUCTION_SERVICE_ROLE_KEY=… SMTP_HOST=smtp.gmail.com SMTP_USER=… SMTP_PASSWORD=… node scripts/deploy-production.mjs
   ```
   **Check:** it prints `state READY` and the timers' calls return 200
   (`select status_code, count(*) from net._http_response where created > now() - interval '10 minutes' group by 1`).
3. Add the remaining variables in Vercel → Settings → Environment Variables (Production), then Redeploy. Every name is
   explained in `web/.env.example`:

| Service | Variables | Without it |
| --- | --- | --- |
| B2B CRM link (step 8) | `B2B_API_URL`, `B2B_API_KEY`, `B2B_SIGNING_SECRET` | no hand-offs; `/v1/handoffs` answers 503 |
| WhatsApp, the B2C number (step 7) | `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_WABA_ID`, `WHATSAPP_TOKEN`, `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_API_VERSION` | WhatsApp is dry-run only |
| Own Gmail (step 4.2) | `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GMAIL_TOKEN_KEY` (`openssl rand -base64 32`; changing it makes everyone reconnect) | the Connect button refuses |
| Service account (step 4.3) | `GOOGLE_SA_EMAIL`, `GOOGLE_SA_PRIVATE_KEY`, `GOOGLE_ADMIN_EMAIL` | counsellors connect Gmail themselves; no Teams sync |
| Claude (briefs, reply classification, insights) | `ANTHROPIC_API_KEY` | features wait or fall back to rules |
| Exotel (optional; Settings → telephony) | `EXOTEL_SID`, `EXOTEL_API_KEY`, `EXOTEL_API_TOKEN`, `EXOTEL_SUBDOMAIN`, `EXOTEL_CALLER_ID`, `EXOTEL_WEBHOOK_KEY` | counsellors call from their own phones and log calls |

**Check:** Workspace → Connectors shows each connected service with a recent "last success".

## 6. People (Vikas)

1. Sign in at `https://spark.eduwit.in` as connect@eduwit.in (the first Admin; check
   `select email, role, is_active from b2c.users where role = 'admin'`; if missing, add it as described in
   `web/README.md` → "First Admin").
2. Teams: add each person (the "Not yet added" list shows every Workspace account), with role, team, work mobile
   (needed for WhatsApp alerts to their own number), languages, caps and hours. Invitations expire after 7 days.
3. Allocation: rules, pools, working hours, breaks/lunch, holidays (import), on-call person.

**Check:** every person signs in once (Teams → last sign-in).

## 7. WhatsApp on the B2C number

1. Meta → WhatsApp → Configuration: webhook URL `https://spark.eduwit.in/v1/webhooks/whatsapp`, verify token =
   `WHATSAPP_VERIFY_TOKEN`, subscribe to `messages`.
2. Templates (Workspace → Templates). Either import the ones already on the account (Connectors → "Import templates from
   WhatsApp") or create and submit them. Needed:
   - `assignment_hours` and `assignment_after_hours` purposes (the counsellor's first message; email is the fallback);
   - sales templates marked usable by Sales (openers, follow-up, brochure, fees);
   - `staff_alert` (utility, 3 variables: title, details, link): reminders and alerts to staff's own numbers;
   - marketing templates for journeys and campaigns.

**Check:** a test lead (phone `9190000000NN`) gets the dry-run message in its timeline; Connectors shows WhatsApp
"last success".

## 8. The B2B CRM link (B2B developer)

Give the B2B developer `docs/b2b-developer-notes.md` (new events, `GET /v1/events`, `public.b2c_lead_status_v`, the
optional team/revenue fields, the catalogue keys) and the contract. They register Spark's endpoint
`https://spark.eduwit.in/v1/handoffs`, issue the API key and signing secret (→ step 5.3), and deploy Addendum 4.
Test from `b2c-crm/web`: `npm run mock-b2b` against production with test leads.

**Check:** a test hand-off is allocated within seconds and the assignment shows in the B2B CRM.
Settings → `b2b_writes.team_and_revenue` stays off until the B2B developer confirms the write API accepts `team_id`,
`expected_net_revenue_inr` and `realised_net_revenue_inr`.

## 9. Settings to confirm (Workspace → Settings)

Money (commission rates, `ca_confirmed`), SLA minutes (by temperature and by source), custom profile fields, document
checklists per university, stages and sub-stages, messaging quiet hours and the Gmail daily allowance, staff alert kinds,
qualification questions, partner-lost sub-stage map. Every change is versioned with a reason.

## 10. End-to-end with test leads (Vikas and one counsellor)

Hand-off → allocation → first WhatsApp (dry run) → call and log → follow-up → programme fit and share → application and
documents → enrolment → Admin verifies → commission line → run → statement. Also: a not-qualified lead re-engaging gets
the qualification form; a flagged lead appears for review; bulk delete and undo; export to Excel; erasure on a test lead.
The browser tests in `web/e2e` cover the screens (`npm run e2e` against a URL with test users, see `web/README.md`).

## 11. Continuous checks

GitHub Actions `.github/workflows/b2c-crm-ci.yml` runs typecheck, unit tests, `npm audit` and dependency review on
every change under `b2c-crm/web`; Dependabot proposes updates weekly. Keep both green. Security incidents:
`docs/breach-runbook.md`.

**Production timers registered (4 Nov 2026, on the owner's word).** The deploy script's step 5 was done by hand, in the
order that never refuses a timer call: a new `B2C_INTERNAL_KEY` (64 hex characters, sensitive) set on Vercel
`eduwit-spark`, production redeployed (03:21 UTC), then `b2c.app_deploy_set('https://spark.eduwit.in', <the same key>)`
on production. The key was never printed; it lives only in Vercel and Vault. The timers' calls answer 200 from 03:24
UTC; `LIVE_MODE` stays off, so messages are still dry runs until go-live (step 12).

**Health (4 Nov 2026, migration `b53`).** `GET /api/health` answers 200 when Spark can work (its configuration, the
database and file storage within 3 seconds each, the timers and the app answering them) and 503 when it cannot; the
body gives each part a level (`ok`, `warn`, `bad`), and the counts behind them with the `x-internal-key` header (the
timers' key). It never names a student, reads at most a few thousand timer runs, and answers from a 15-second cache.
Eduwit One calls it every 5 minutes (check B2C-11, heartbeat `spark`). The parts: `config`, `database`, `storage`,
`timers`, `app`, `outbox`, `inbox`, `sending`, `connectors`, `programmes`, `ai`, `jobs` (`lib/health.ts`,
`b2c.health()`); a queue or connector that needs a look makes the status `degraded` and leaves it 200.

**Calls that never hang (11 Nov 2026, migration `b54`).** Every server-side Supabase client gives a Data API call 15
seconds (`db: { timeout }` in `web/lib/supabase`); the database itself ends a statement at 8, so this only cuts a call
whose answer never arrives, and the person sees "The database did not answer in time. Please try again." The mailer
gives a mail server 10 seconds to connect and 20 on a silent socket (nodemailer's defaults are 2 and 10 minutes, longer
than the every-minute job's 60 seconds). `b54` adds seven indexes for the every-minute timers and the navigation
counts (`outbox_unstick`, `reminder_tick`, `brief_due_take`, `sla_tick`, `recordings_expired`, the commission sum per
lead, unread conversations and unread alerts), each checked with EXPLAIN on 60,000 to 100,000 local rows. One tried
and left out: `journey_runs (lead_id, entered_at)` made `journey_enroll_tick` slower; that tick's cost is
`may_message` per pooled lead, which is the next thing to rework when the pool grows.

**Messages that stop mid-send (b53).** The app records sending outcomes ten at a time, starts no send later than 40
seconds into its run and hands the rest back (`b2c.send_release`), so a run cut short loses at most ten outcomes. A
message still `sending` 15 minutes after it was taken (`send_queue.taken_at`) is marked failed by `b2c.send_unstick(15)`,
never sent again (it may have gone out): an assignment WhatsApp falls back to email and the admins get one notice.
Eduwit One's FIX-SENDQ-B2C runs it on B2C-07 once the owner switches it on (it ships off, with two weeks of dry runs).
System health (Admin) shows them as "stopped mid-send". Checks: `supabase/tests/test_health.sql` (25).

**Hardening (13 Nov 2026, migration `b55`).** Fixes from the November audit. Erasing a student also removes the files
they sent or were sent on WhatsApp and the number on those messages, and a WhatsApp file that finishes downloading after
the erasure is deleted, not kept. An expired export's file is deleted from storage (bucket `b2c-exports`, through the same
removal job as erased files), not only forgotten. WhatsApp STOP is checked first and understood with punctuation, emoji
and a few words around it ("Stop.", "STOP!!", "please stop", "stop messaging me"), in Hindi too (बंद करो, मत भेजो,
रोको) and as "unsub"; a STOP from a number Spark does not know is put on the suppression list and is no longer sent to
the B2B CRM as a new lead; a STOP from a lead in active sales is recorded and the counsellor is told. At send time a
message is cancelled, not sent, when its student can no longer be messaged or (for marketing) the address is
suppressed, so nothing handed back or retried after a STOP or an erasure goes out; suppressing an address cancels the
marketing queued to it. When Meta does not answer in time or answers with a server error, the message may have gone
out: it is marked failed and never sent again (as with "stopped mid-send"). An enrolment can be recorded only once per
lead and only on an active lead. A server action called after the session ended answers "You were signed out. Sign in
again." instead of failing, so the form keeps what was typed. A refused template list from Meta makes the WhatsApp
connector show the error. In the Inbox the Admin can read a conversation from a new number that has no lead yet
(read-only, "waiting for the CRM to route this lead"). Webhook events for other numbers on the same Meta account are
ignored (`WHATSAPP_PHONE_NUMBER_ID`). Checks: `supabase/tests/test_hardening_2026_11.sql` (25).

**One deadline per job; a refusal from Meta is final (13 Nov 2026, migration `b56`).** Two more fixes from the November
audit. *Jobs.* The every-minute call ran its jobs one after another inside the platform's 60 seconds, so a slow job
early in the list left the later ones cut off part-way. Each job now has its own deadline (`web/lib/job-budget.ts`),
worked out when it starts from the time really left: the 60 seconds, less 10 kept free at the end (the timer listens
for 55), less a share kept for every job still to come. The order is by urgency (`web/lib/sync-jobs.ts`): messages,
what must reach the B2B CRM at once, phone alerts, replies waiting for their class, files students sent, files of
erased students, support mail, recordings and calendars, large exports, analytics. A job with no time left is not
started and is reported as skipped; a job that runs out of time between two items stops there, records what it did and
hands back what it had taken but not started, with no attempt spent (`b2c.send_release` for messages,
`b2c.job_release(kind, ids)` for the other queues), so it is due again a minute later. A brief or the daily insights
start only with time for Claude to answer (10 and 20 seconds). Messages may start until 36 seconds into the minute run
(35 in the 15-minute run; it was 40), which leaves the B2B sync its share; the B2B sync now also stops at its deadline
instead of running on. The call's answer lists every job under `jobs`: `ran`, `skipped`, `stopped_early` or `failed`,
its milliseconds and the parts that stopped; the fields it had before are unchanged. *Refusals.* When Meta answers a
WhatsApp send with a refusal that cannot succeed on a second try (the number is not on WhatsApp, the template is not
approved, paused or wrongly filled, the 24-hour window has closed, the person stopped marketing messages), the message
is failed at once with the reason in words and Meta's code, shown where failed messages already show (the
conversation, the queue, the admins' notice); before, it was sent again up to five times. Rate limits are tried again
as before. A refusal of Spark's connection itself (an expired token, a missing permission, a locked or restricted
account or number) is reported on the WhatsApp connector, the message is tried again as before, and the WhatsApp
messages left in that run are handed back uncounted, so one broken connection does not cost a whole batch an attempt.
The codes and what each means are listed in `web/lib/whatsapp.ts` (`classifyWaError`); a code that is not listed is
tried again. This part needed no database change: `b2c.send_done` already fails a result marked `"retry": false`
(`b55`). Apply `b56` before deploying this version of the app: a job that runs out of time calls `b2c.job_release`.
Checks: `supabase/tests/test_job_budget_2026_11.sql` (29); the same checks for an HTTP SQL API, to send with
the migration in one transaction that is rolled back: `supabase/tests/b56.http.sql` (ends with
`TESTRESULT total=29 failed=0`).

**The SQL suites run in CI (13 Nov 2026).** `b2c-crm/supabase/local-test.sh` starts a throwaway local PostgreSQL, applies
`tests/local_stubs.sql` and every migration twice, then runs every `tests/test_*.sql`; a failed check fails the run. It
never connects to staging or production. The Spark CI workflow runs it on every push to `main` and every pull request
that touches `b2c-crm/supabase` (it used to run for `b2c-crm/web` only, with no database checks).

**Server errors are logged and counted (14 Nov 2026, audit finding M11; web only, no Spark migration).** Spark had no
`instrumentation.ts`, so an error a page, route or server action threw left no line of Spark's own. `web/instrumentation.ts`
now writes one JSON line per failed request (`event: "request_error"`: the error's name, digest and code, the method,
the route pattern and the kind of render; never the message, the path, the query string, headers or cookies:
`web/lib/request-error.ts`, the B2B CRM's module) and counts it. `web/lib/error-report.ts` (the same file as in the
other Eduwit apps) sends the counts to Eduwit One with `one.app_error_report`, through the existing service-role
client pointed at schema `one` (no new key or environment variable): the route pattern, the error's name, the digest
and the kind, at most one call a minute per server instance, in the background with a 3-second limit. A failed call
is dropped, logged once as `error_report_failed` and not retried for 5 minutes; a request is never delayed or failed
by it. It runs only on a deployment (production build, hosted Supabase address, service key present), never locally,
in tests or in CI. Eduwit One's check `B2C-ERR` (P2) fires above 20 errors in 15 minutes (the owner's threshold) and
its Spark page shows the last 24 hours. It needs Eduwit One's migration `0041` in the same database; deployed before
it, the calls fail quietly. Checks: `web/lib/error-report.test.ts`, `web/lib/request-error.test.ts`,
`web/instrumentation.test.ts`.

## 12. Live

`LIVE_MODE=on` in Vercel (Redeploy), then Workspace → Settings → live mode on. Un-pause journeys one by one.
**Check:** the first real lead reaches a counsellor and the first real WhatsApp leaves from the B2C number.
**Undo:** `LIVE_MODE=off` stops every message at once.

## 13. Clean up

Delete the test leads and test users from production (Leads → filter "test" → bulk delete; Teams → deactivate test users).
Keep staging as it is for future changes: every new migration goes to staging first, every suite must pass there, then
production.

## Small things left as they are (not blockers)

- `b2c.today()` lists "To qualify" tasks only through the Today card the app builds itself, because the task sits on a
  pooled lead; the database view of overdue tasks assumes an active lead.
- `nurture_overview` reports partner-lost sub-stage names in lower case.
- `qualify_assign(request, null)` with no task yet creates a task without an owner (the Admin assigns it from the queue).
- Spark's background jobs run inside the every-minute `/api/internal/sync` call, each to its own deadline inside a Vercel
  function's 60 seconds (`b56`). An export that cannot be read within one run is recorded as not finished and tried
  again, three times at most; `export_take` also retries a run that died part-way.
- The health row "The app answering the timers" counts only Spark's own timer calls (`b46`); the production database is
  shared, so the B2B CRM's test ping to Spark (one 503 before its signing secret matched, on 16 Oct) no longer turns it red.
- Playwright from a network that proxies outbound traffic can report `502` on static files; run the browser tests locally
  (`npm run e2e`, the app on your machine against the staging database) for a clean result.

## Where to read more

`web/README.md` (setup, jobs, every route), `docs/B2C_CRM_PROMPT.md` (the spec), `docs/completion-gaps.md` (what was
built for each part of the spec), `docs/b2b-developer-notes.md`, `docs/breach-runbook.md`. Questions: vikas@eduwit.in.
