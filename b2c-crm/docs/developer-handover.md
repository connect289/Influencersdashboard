# Eduwit Spark: handover to the developer (taking it live)

Version 16 October 2026. Spark is the B2C CRM: code in `b2c-crm/web` (Next.js 16), database schema `b2c` in Supabase,
migrations `b2c-crm/supabase/migrations/b1…b43` (apply in order; all idempotent), checks in `b2c-crm/supabase/tests`.
This guide is the whole path from where things stand to a working, live CRM. Do the steps in order; each says how to
check it and how to undo it. `docs/go-live-plan.md` keeps the history; this file supersedes it for what is left.

**Never:** run `student_leads_v2_rename.sql`; change Witty's `w2_*` tables, `lead_intake()`, the n8n workflows or the
B2B CRM's code; put a secret in git or in chat. `LIVE_MODE` stays `off` until step 12.

## Where things stand

| Piece | State |
| --- | --- |
| Production database `xlseqwgyjuqhktrguhyc` ("EDUWIT LEAD TRACK", Mumbai) | **Done 16 Oct 2026**: `b1`–`b45` (`b39`–`b43` and `staging_b4_pool_calendar.sql` through the SQL editor, `b44`–`b45` through the connector); 510 `b2c` functions, the same set as staging and the tested local build; 16 `b2c-*` timers; anon executes nothing; programme cache filled (715 programmes, 29 universities). `b2c` exposed in the Data API. First Admin: connect@eduwit.in |
| Staging database `mplbspysxmtohnlwpbti` ("eduwit-b2b-staging") | **Done 16 Oct 2026**: `b1`–`b45`; 510 functions; test people and 30 test leads seeded for the browser tests |
| Local proof | `b1`–`b43` on a clean Postgres: every suite passes (`test_completion` 209 checks, `test_phase1` 99, `test_phase2` 45, `test_phase3` 91, `test_phase4` 47, `test_features` 26, `test_support_phones` 28, `test_walkthrough_fixes` 10) |
| Production site | Vercel project `eduwit-spark` (team `eduwit`), root `b2c-crm/web`, `https://spark.eduwit.in` (DNS done) and `https://eduwit-spark.vercel.app`. **Deployed 16 Oct 2026 from branch commit `cfe6131`** (every screen of `b39`–`b45`). Set: Supabase URL and publishable key, **service role key** (Vikas, 16 Oct), site URL `https://spark.eduwit.in`, SMTP, VAPID, `LINK_SECRET`, `B2C_INTERNAL_KEY`, `LIVE_MODE=off`. Google sign-in and the emailed code work (Vikas signed in on 16 Oct). **Not yet**: the timers' key in Vault (step 5.2) and the optional services (step 5.3) |
| Staging site | `https://eduwit-b2c-crm.vercel.app` (Vercel project `eduwit-b2c-crm`), deployed 16 Oct from the same branch; the browser tests ran against it |
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
- `b2c-crm/supabase/manual/staging_b4_pool_calendar.sql`: saving a pool's members and a person's weekly hours
  (production only; staging has it).

**Staging** (`mplbspysxmtohnlwpbti`) → SQL editor → paste `apply_b39_b45.sql` → Run. Then run each file in
`b2c-crm/supabase/manual/sql-editor-tests/` (one at a time). Each ends on purpose with an **error** that reads
`TESTRESULT pass=N fail=0 …`: `fail=0` is a pass; any failure is listed by name. The error is what guarantees nothing a
test writes is kept. Expected on a clean copy: `test_completion` 209, `test_phase1` 99, `test_phase2` 45,
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
   Until this runs, queued messages, the B2B sync and the other background jobs wait).
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

## 12. Live

`LIVE_MODE=on` in Vercel (Redeploy), then Workspace → Settings → live mode on. Un-pause journeys one by one.
**Check:** the first real lead reaches a counsellor and the first real WhatsApp leaves from the B2C number.
**Undo:** `LIVE_MODE=off` stops every message at once.

## 13. Clean up

Delete the test leads and test users from production (Leads → filter "test" → bulk delete; Teams → deactivate test users).
Keep staging as it is for future changes: every new migration goes to staging first, every suite must pass there, then
production.

## Where to read more

`web/README.md` (setup, jobs, every route), `docs/B2C_CRM_PROMPT.md` (the spec), `docs/completion-gaps.md` (what was
built for each part of the spec), `docs/b2b-developer-notes.md`, `docs/breach-runbook.md`. Questions: vikas@eduwit.in.
