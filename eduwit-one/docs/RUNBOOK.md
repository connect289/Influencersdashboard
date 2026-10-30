# Eduwit One — runbook

How Eduwit One runs, what its alerts mean, and what to do. The database steps (rehearse, dump, apply, undo) are in
`RUNBOOK-database.md`; the checks are listed in `CHECKS.md` (generated). This file grows with each phase.

## What runs where

| Piece                  | Where                                                              | Every           | What it does                                                                                                                                                                                                                          |
| ---------------------- | ------------------------------------------------------------------ | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `one-tick`             | pg_cron, `call one.tick_job()`                                     | minute          | Heartbeat `one:tick`; records any check or copy killed last time as an error; due SQL checks (one commit each); escalation, digest; calls the app (the tick counts as finished here); event copy; checks killed earlier, last (D-056) |
| `one-nightly`          | pg_cron, `select one.nightly()`                                    | 02:30 IST       | Privilege audit, baselines, retention, proposal expiry, brief task                                                                                                                                                                    |
| `/api/internal/tick`   | the app, called by `one-tick`                                      | minute          | HTTP probes (app health, Vercel, Chatwoot, n8n, WhatsApp), heartbeat `one:app`, alert sender, the fix runs queued for the app (n8n retries, the Spark check), synthetic tests                                                         |
| fixes                  | in `one-tick`, after the app call, one commit per fix              | minute          | Verifies earlier runs, then tries each fix on each open incident of its checks (dry run while off, paused or in the window; a trial of one row until a run holds, D-084)                                                              |
| `/api/internal/ai/run` | the app, called by `one-tick` while an AI task is due              | minute          | Claims AI tasks for up to four minutes, calls the model of each task's tier, files the answers (D-075)                                                                                                                                |
| `/api/chat`            | the app, called by the Command centre page as the signed-in person | on each message | One turn of the chat (D-094): opens a `chat` task, calls Claude with the fixed tools, streams the answer, stores it; a confirmed action card runs one `one.ui_*` call as that person                                                  |
| `/api/watchdog`        | the app, called by UptimeRobot                                     | 5 min           | `{"ok":true}` while the last finished `one-tick` is under 5 minutes old and no alert email has waited 10 minutes                                                                                                                      |

## Alerts

- **Opening.** A check that fails (or cannot run: its SQL errors or its source is gone) opens an incident with the
  check's severity. The same check failing again touches it; a new failing subject (another job, partner or alert
  kind) alerts again. Three good runs in a row resolve it as recovered; failing again within 24 h reopens it.
- **P1:** an email to the P1 inbox at once. If nobody acknowledges it: again at 30 minutes; at 60 minutes to the P1
  inbox and the second contact; then every 60 minutes, up to the tenth reminder (the level `one.deliveries` allows; 0025,
  D-098). Acknowledge from the incident page to stop it.
- **P2:** listed in the morning brief, and in an 18:00 IST email digest when more than 5 opened that day.
- **P3:** the dashboard only.
- **Developer:** incidents tagged `code` also go to `alerts.developer_email` once it is set.
- **Storm (ONE-STORM).** More than 10 P1s within 5 minutes send one storm email naming the top three checks. The
  individual P1s are held under it for 15 minutes, then alert one by one if still open.
- **Mute or maintenance.** Mute a check or a whole app from the UI with a duration and a reason. Incidents still
  record; nothing is sent. When the mute ends, anything still failing alerts again.
- **A failing email.** An alert, escalation or storm email the provider refuses is tried again with a growing wait
  (2, 4, 8, 16, 32, 60, 60 minutes, eight tries in all) while its incident is open and unacknowledged; a brief or
  digest is tried twice. A delivery that failed for good counts for ONE-02 and the watchdog for 6 hours, so a revoked
  email key pages through UptimeRobot and cannot stay silent (D-085). Email is the only channel (owner, 23 Oct); no
  WhatsApp alert is sent.
- **Emails not going out (ONE-02, P1).** An alert email still waiting after 5 minutes, or one that failed in the last
  6 hours, means the database cannot reach the app (check `app.base_url` and the Vercel deployment) or the app cannot
  send (check the Resend key). Its own email waits in the same queue, so the watchdog pages through UptimeRobot after
  10 minutes.
- **Reopens and flapping.** A check that fails again within 24 h of recovering reopens its incident and pages again;
  reopens count for the storm guard like openings. On its third reopen the incident is damped: it goes to the evening
  digest with the tag `flapping` instead of a page, until it is resolved for good. Look at the check's threshold.
- **A killed check.** A check that runs past `checks.transaction_timeout` (30 s) is recorded as an error with
  "killed" in its result, which opens its incident; it then runs at the end of the tick, at most every 10 minutes per
  kill. Killed three times in a row it is parked: ONE-01 names it, and it is tried again every `checks.parked_retry_h`
  hours (6; 0 means until a person resets it) until a run finishes (0028, D-102). A check that stays parked has broken
  SQL (a lock or a slow plan): fix it, then as the database owner `update one.check_state set killed_count = 0 where
check_id = '<ID>'`. A platform stall (every app's jobs failing to start, PLAT-01B) parks healthy checks too; they come
  back on their own. An event copy that is killed halves its batch each time and stops at three
  (`one.event_watermarks.killed_count`). PLAT-01 does not page again for a one-tick run such a kill ended: the check's
  own incident carries it.

## Signing in

- **Who.** Only `@eduwit.in` Google accounts with an active row in Settings → Users. The owner adds an engineer
  there after the person has signed in once with Google (their Supabase user must exist). An engineer reads and
  operates; only the owner changes users, owner-only settings, recipients, Setup secrets and sensitive proposals.
- **The second step.** After Google, a 6-digit code goes to the person's email (valid 10 minutes, 5 tries, 5 codes an
  hour). Ticking "Trust this browser for 30 days" skips the code on that browser. Settings → Users → "Sign out
  everywhere" forgets the person's trusted browsers and signs out their other sessions (a lost laptop); setting the
  person inactive there stops every page and action at once, whatever session they hold.
- **Idle.** `access.idle_hours` (12) without a click or a key signs the person out; an open tab stops refreshing
  after that long, so it does not keep the session alive.
- **Locked out.** If no owner can sign in (lost mailbox, Google outage), sign in to Supabase and, as the owner,
  check `one.sign_in_log` (newest first) for the refusal; `one.users` holds the allow-list.
- **First deploy.** Supabase → Authentication → URL configuration: add `https://one.eduwit.in/auth/callback`; the
  Google provider is the one Spark already uses. Any Google account can complete the provider's flow and leave an
  `auth.users` row in the shared project (the callback signs it out, but the row stays and the CRMs' new-user
  trigger fires): keep Supabase's sign-ups disabled for the project, or the Google provider limited to the domain. Vercel env: `ONE_SUPABASE_URL`, `ONE_SUPABASE_ANON_KEY`,
  `ONE_SUPABASE_SERVICE_KEY`, `ONE_INTERNAL_KEY` (Setup item `one_app_env`). Use Supabase's asymmetric JWT signing keys
  (Project settings → JWT keys): the app then verifies a session on its own on every page instead of asking Supabase.

## Setup

Settings → Setup lists every credential and identity Eduwit One needs, who provides it and what it unblocks. A
secret pasted there goes straight to Vault under its `one_*` name; it is never shown again, and the audit records only
its name. "Validate" runs that item's probe; when it passes, the checks waiting for it (`setup:<item>`) switch on. To
rotate a key, paste the new one and validate; the app picks it up within a minute (an environment variable of the same
purpose overrides Vault, D-059).

## Who may change what

Engineers read everything, acknowledge, resolve, mute, ask, and change thresholds, the check runner, test schedules,
Witty's expectations and the analytics funnel. The owner also: every other setting (where credentials, alerts and codes
go, AI spend, retention, sign-in), users, Setup secrets, fix and config proposals and anything touching security,
and switching off or downgrading a P1, security, integrity, money or consent check (D-065).

## Proposals

Every finding that needs a person is a proposal: from a check, a test, the AI (phase 6), a person, or the builder.
Approve, reject with a note, or snooze (it comes back to the queue when the snooze ends). Every fix or config proposal,
and any that touches money, allocation, live switches, partner mappings, prompts, settings or security, needs the
owner.
Approving records the decision; the change itself is made in the app named under "where" (Eduwit One changes no app).
The one exception is a proposal a fix opened itself (source `check`): approving it runs that fix once, under your
session, on the rows it lists that still qualify, and the page shows the check 10 minutes later (see Fixes). The
builder's twelve proposals (D-063) and the six for the blocked tests (0017, D-071) wait for a decision and never
expire.

## Checks: what each one means

`docs/CHECKS.md` lists all 96 checks, generated from their sources in `supabase/checks/*.sql`: each one's id, app,
severity, cadence, what makes it fail and, where one exists, its fix. The same text is on every incident page
("The check"), with the rule's SQL. Ids read `<APP>-<n>`: WITTY, B2B, B2C, WEB, INF (influencer portal), CAT
(catalogue), CE (Eduwit Scout), INT (integrity across apps), PLAT (Supabase and pg_cron), ONE (Eduwit One
itself), HB (heartbeats: a component that stopped reporting).

When one fires:

1. Open the incident. "Evidence" is what the check saw on its last run (`status`, `value`, `error`). A status of
   `error` or `source_missing` means the check could not run (its SQL raised, or a table or function it reads is
   gone): look at the error, not at the app. Since D-042 that counts as failing, so a renamed table cannot go quiet.
2. Read the AI's summary and likely cause if the AI is on; they are advice. The check decides what is broken.
3. Look at the app's own screen (the Apps page links each app's admin) and its recent events on the incident page.
4. If a fix is listed for the check, its dry runs say what it would have done; switched on, it may already have acted
   (Actions page). An incident whose fix did not hold carries the tag `fix_failed` and went up a severity level.
5. Acknowledge to stop the reminders; resolve with a note once it is fixed (resolution `fixed`), or let three good
   runs resolve it as recovered. "False positive" and "accepted" are for a check that is wrong or a state you accept;
   say why, and consider changing the check (below).

Per app, the first place to look: Witty — the n8n workflow's executions and Witty's `w2_health_alerts()`; B2B — its
command centre and `b2b.health_check()`; Spark — its system health page and its inbox and outbox; website —
`/api/health` and `public.web_health()`; influencer portal — `/api/health` and `inf.health()`; catalogue — the
catalogue's change log; Eduwit Scout — its dashboard's queue and health pages, the messages in `ce.health`, its
GitHub Actions workers and its `ce-health` cron job (below); PLAT — Supabase's logs and `cron.job_run_details`; ONE —
this runbook's Alerts section.

## Eduwit Scout

Eduwit Scout (its own repository; schema `ce` in the shared database) turns partner websites, portals and
brochures into the per-partner programme catalogue. Eduwit One watches it like the other apps, by reading: app key
`catalogue_engine`, beside the older `catalogue` (the shared `catalog_*` tables, CAT-*), which stays as it is (D-096).

| Check | Severity, every | Fails when                                                                                                                                                 |
| ----- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CE-01 | P2, 15 min      | a `ce.heartbeat` component has no good report for `heartbeat_multiple` (3) × its `expected_interval_s`, or was read but never ok (one alert per component) |
| CE-02 | P2, 15 min      | a `ce.job` is dead (it failed `max_attempts` times)                                                                                                        |
| CE-03 | P2, 15 min      | the latest `ce.health` row of a metric in the last 24 h is an alert (one alert per metric, with the engine's message)                                      |
| CE-04 | P3, 15 min      | a job is queued 3 days past its `next_run_at`, or running with its lease expired an hour ago                                                               |
| CE-05 | P2, 15 min      | a `ce.run` is held: a crawl health gate stopped a publish and waits for a person (one alert per run)                                                       |

**Off until the engine is installed.** Schema `ce` reaches production after 1 Nov 2026, and a check whose table is
missing counts as failing (D-042), so all five ship off with `setup:catalogue_engine`. Once the engine's migrations are
in production: Settings → Setup → "Eduwit Scout installed in this database" → **Validate**. It checks that
`ce.heartbeat`, `ce.job`, `ce.health`, `ce.run` and `ce.events` exist with the columns Eduwit One reads and that the
database owner can read them (`one.setup_engine_facts()`, names only); when it passes, CE-01 to CE-05 switch on at
once. If it refuses, its detail names what is missing. To switch one off again, Settings → Checks, with a reason.

**Events.** `ce.events` is copied into the event timeline (app `catalogue_engine`, actor `engine`) by the minute tick as
soon as the table exists; before that the source is not listed, so its absence is not reported. After the Setup item
is validated it is always listed: a `ce.events` that goes missing then shows as a failing source in ONE-01, like any
app's.

**When one fires.** CE-01: the named component's worker (the engine's GitHub Actions workflows; `db:health_collect` is
the `ce-health` pg_cron job) stopped; its `last_error` in `ce.heartbeat` says why. CE-02: retry or cancel the dead
jobs in the engine's dashboard after reading their error there (Eduwit One keeps only ids). CE-03: the message says
what crossed its limit (database or storage size, dead jobs, stale workers). CE-04: a stage with no worker, or a worker
that died holding a job; the engine reclaims expired leases whenever a worker claims work, so a lasting one means no
worker is claiming. CE-05: approve or discard the held run in the engine's dashboard; the partner keeps its last good
catalogue meanwhile. Ask's `app_status` answers for `catalogue_engine` too (its checks and `ce-*` cron jobs). Eduwit
One has no fix for the engine and changes nothing in schema `ce`.

## Fixes

Eleven auto-fixes (spec §8, `one.fixes`; Settings → Fixes shows each one with its rights, history and switch). Each is
`one.fix_<id>(incident, dry_run)` over one shell (D-079, D-081): the switch in Settings → Fixes, the two-week
observation window, a cooldown, a rate limit, an action row before and after, and a check from 2 minutes later.

| Fix                | Tried on                             | What it does                                                                                                                                                                                                                                   | Rights it needs                | Rollback                                       |
| ------------------ | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------- |
| FIX-OUTBOX-W2      | WITTY-01 `outbox_failed`             | Lists failed Witty outbox rows that could be sent again and **proposes** a Witty change: Witty has no function that sends a failed row again (D-080)                                                                                           | none                           | none                                           |
| FIX-CACHE-W2       | WITTY-01 `cache_expired`             | Lists expired prompt caches and **proposes** a look at the Witty workflow: n8n's API cannot start its Cache Manager (D-080)                                                                                                                    | none                           | none                                           |
| FIX-N8N-RETRY      | WITTY-02 executions in error         | The app retries each failed execution once through the n8n API, after reading it: never one of another workflow, one no longer in error, or one that is itself a retry. An execution is retried at most once, whatever the answer              | n8n API key                    | none; Witty is idempotent by message id        |
| FIX-OUTBOX-B2B     | B2B-01 dead or waiting deliveries    | Lists dead deliveries, and failed ones older than an hour, of 7 days (not test ones, not ones sent again already) and opens a proposal; **your approval** runs B2B's `b2b.outbox_retry` for each, under your session (you must be a B2B admin) | EXECUTE on `b2b.outbox_retry`  | an admin sets them back to dead in the B2B CRM |
| FIX-CURSOR-B2C     | B2B-01 sync cursor over 600 s        | `b2b.b2c_sync_tick(200)` once                                                                                                                                                                                                                  | EXECUTE on `b2b.b2c_sync_tick` | none                                           |
| FIX-WEBHOOK-REKICK | B2B-06                               | The app checks that Spark's `/v1/handoffs` route answers (a 2xx, or 400, 401, 403, 405, 415 or 422; a redirect, 404 or 5xx is not an answer), then `b2b.outbox_kick()`; if not, nothing, and the P1 stays                                      | EXECUTE on `b2b.outbox_kick`   | none                                           |
| FIX-INBOX-RETRY    | B2C-02                               | `b2c.inbox_retry(50)`: up to 50 envelopes, test ones included (the function takes no filter)                                                                                                                                                   | EXECUTE on it                  | none                                           |
| FIX-OUTBOX-B2C     | B2C-03                               | `b2c.outbox_unstick()` (every row stuck sending, test ones included), then Spark's urgent sync                                                                                                                                                 | EXECUTE on both                | none                                           |
| FIX-OUTBOX-WEB     | WEB-01 dead or old outbox rows       | `public.web_outbox_retry` for dead rows with attempts left (not test ones), then the website's outbox worker                                                                                                                                   | EXECUTE on both                | none                                           |
| FIX-CATALOG-POLL   | WEB-01 poll older than 600 s, CAT-02 | `public.web_catalog_poll()`                                                                                                                                                                                                                    | EXECUTE on it                  | none                                           |
| FIX-CACHE-B2C      | CAT-01                               | `b2c.programme_cache_refresh(true)`                                                                                                                                                                                                            | EXECUTE on it                  | none                                           |

How they behave:

- **Who acts.** Every app call a fix makes runs as `eduwit_one_fixer`, which can execute exactly the functions in
  the table and nothing else: no table, no RLS bypass, no login. Postgres enforces it, and the migration guards refuse
  a grant to it on anything else (`student_leads`, allocations, money, switches, partners, mappings, prompts, settings).
- **Off and the window.** All ship off. For the first 14 days (`fixes.observation_days`) from the first tick that
  runs them (on production, the first after the apply; the banner on Settings → Fixes shows the dates), and whenever
  a fix is off, it only records a **dry run**: what it would have done, on which rows. A fix can be switched on only
  after the window and only once it has a dry run of its own; the owner does it on Settings → Fixes with a reason.
- **Limits.** One real run per fix per `cooldown_min`, whoever ran it (the tick, an approval, or a person calling
  `one.fix_<id>(incident, false)`); the tick's dry runs once per fix and incident per cooldown. More rows than
  `per_tick`: it does nothing and opens a (high-risk) proposal. Test rows (Witty's test phones, a test flag in a B2B
  or website payload) are never picked by the fixes that pick rows; the fixes that run an app's own job
  (`inbox_retry`, `outbox_unstick`, the polls, the sync) touch what that job would, test rows included, and count as
  one call each (D-081). A fix works only from what its check observed: none runs on an incident whose check could
  not run, and the propose-only fixes never go over their limit.
- **Held or not.** From 2 minutes after a real run (at most its cooldown), the first run of its check judges it:
  - passed, or the incident resolved: **held**;
  - failed while the fix's condition still holds on what that run saw: **did not hold**. The incident goes up one
    level (P3 to P2, P2 to P1; a P1 is alerted again) once per failing check run, however many fixes ran, and the tag
    `fix_failed` is added. That fix then **stops on that incident**: the tick never runs it there again, only your
    approval does, and "Dry run now" still works. Settings → Fixes marks the incident "stopped";
  - failed for another reason: held (the fix's part is done);
  - the check could not run (error, missing source), or did not run within the cooldown plus two of its cadences:
    **unverified**. Nothing is escalated; nothing counts as held.

  Actions shows "verified: held", "did not hold" or "unverified" with the check run that judged it.

- **App runs.** FIX-N8N-RETRY and FIX-WEBHOOK-REKICK are queued for the app, which claims each once within a minute
  and reports. A run claimed but never reported is closed as unknown at the next claim and never handed out again,
  and its executions count as retried; one whose fix was switched off before the app claimed it is closed as skipped.
- **Approvals.** A proposal a fix opened shows what approving does: FIX-OUTBOX-B2B runs B2B's own function under
  your session; an act fix runs once with the fixer's rights; an app fix is queued for the app. It runs only on rows
  that were proposed, are still in the change you submit, and still qualify then: remove rows from the change to
  narrow it, an edit cannot add any, and a tick refreshing the proposal while you read it cannot widen what you
  approve. If it ran, the rows' own state is read 10 minutes later (B2B delivered, website done, n8n retried) and
  shown on the proposal: done, still failing, or could not check. If nothing ran, the proposal says why and stays
  approved; the fix proposes again if its check still fails. Proposals from people or the AI record your decision and
  run nothing (the change is made in the app named).
- **Proof before power (D-084).** A fix applies itself only once it has shown it works, and stops itself when it
  stops working:
  - **Trial.** Until a real run of the fix has held within 30 days, each real run within `per_tick` acts on one row
    only (a fix that makes one call is its own trial). A proposal, whatever opens it (more rows than `per_tick`, a
    proposing or an approval fix), shows the whole plan, and an approved run is the owner's and runs whole. Settings → Fixes shows "trial" until a run holds,
    then "proven" with the date.
  - **One run per verdict.** No second real run on an incident before the verdict on the last one (held, did not
    hold, or unverified once the cooldown plus two check cadences have passed). The page shows "awaiting the verdict
    on incident #n".
  - **The breaker.** Two runs of a fix that did not hold within 7 days pause it: it records dry runs only (their rows
    say "paused: …"), ONE-FIXES opens an incident, and only the owner clears it on Settings → Fixes with a reason,
    after reading what went wrong. A further run that does not hold pauses it again at once.
  - Your approvals are not held by any of this: they are your consent for one run.
- **Dry run now.** Any engineer can press "Dry run now" on Settings → Fixes or on the incident page to see what a fix
  would do; it changes nothing and does not hold back the tick's own runs.
- **Turning one off** takes effect at the next tick. To stop all of them at once, switch each off (owner); a dry run
  still records what they would do.
- **Before switching on FIX-N8N-RETRY**, check the n8n version (n8n → Settings → About, or the Help menu): 2.25.7 or
  later, or 2.26.2 or later on 2.26.x. Older versions checked the wrong permission on the retry endpoint
  (CVE-2026-56778; D-080, D-082).
- **Reading the evidence before switching one on.** On Settings → Fixes, each fix's dry runs list the incident, the
  rows (ids only) and what it would have done. Switch on a fix whose dry runs you would have agreed with every time;
  leave off one that would have acted where a person should have looked first.

## Operating each app from Eduwit One

Each app has an Operate page (Apps → the app → "Operate: set up and run"; Eduwit One's own is `/apps/one/operate`):

- **What it needs**: the Setup items this app depends on, in the order to fill them, each with its state and a link to
  Settings → Setup. A check, test or fix waiting for an item shows as not configured, never as failing.
- **First time, in order**: what has to exist once (the app's own timers, its API key for Eduwit One, the test
  identities), with the "to fix" text of each open item.
- **Right now**: open incidents, heartbeats, checks on and failing, the app's own pg_cron jobs with their last run.
- **What Eduwit One can do for it**: the fixes of spec §8 that act on this app, their switch and counts, and "Dry run
  now" on each open incident.
- **When a check fires**: the first place to look for each of the app's checks, with its current status.
- **Synthetic tests**, **every day**, **its secrets** (present or not; rotation is in "Rotating a secret") and **what
  stays in the app**.
- **Ask the AI**: three questions with the text filled in; nothing is sent until you press Ask.

Everything on these pages is a read or a deep link: Eduwit One never changes an app's settings, deploys it or runs its
jobs outside the fix catalogue (D-079, D-083). The same content answers Ask's `operate` tool, and the runbook itself
answers its `runbook` tool (below).

## Eduwit One heals itself

What it does for itself, within schema `one`, its two roles and its two cron jobs (D-085); everything else is the
watchdog's or yours:

- **A wedged tick.** The minute tick takes a session lock. A session of Eduwit One's own role that has held it for
  over 10 minutes is ended by the next tick, which notes it in the `one:tick` heartbeat's error (HB-one:tick shows
  it). HB-one:tick itself judges the last _finished_ tick, as the watchdog does: over 3 minutes old is a P1.
- **Its cron jobs.** The tick re-creates `one-tick` or `one-nightly` when one is missing (and says `rescheduled` in
  its report). A job a person set inactive is left alone and ONE-03 reports it.
- **ONE-03 (P2, hourly).** The nightly has not finished in 26 hours, or its job is missing or inactive: retention,
  the privilege audit, baselines, proposal expiry and the brief are not running. Re-activate the job
  (`select cron.alter_job(jobid, active := true) from cron.job where jobname = 'one-nightly'`) or look at PLAT-01.
- **ONE-04 (P1, security).** No active owner can sign in. As the database owner, set the owner's row active in
  `one.users` (see "Locked out").
- **ONE-FIXES (P2).** A fix paused itself (see "Proof before power"); clear it on Settings → Fixes.
- **ONE-01** also counts fix acts that failed and AI tasks that failed in 24 hours (`fix_failed_acts_max`,
  `ai_failed_tasks_max`).
- **Poison checks and copies** stop after three kills (above). **Flapping** incidents are damped (Alerts).
- **Settings.** Every key the app parses has a shape check, so a typo is refused instead of taking the tick route
  down; the app parses each probe's settings on its own and a bad key shows as that probe's error. Any earlier version
  of a setting can be restored as a new version (Settings → the key → versions → Restore).
- **Histories are append-only** by trigger: the audit, settings versions, the sign-in log and check results refuse
  UPDATE and DELETE outside `one.retention()`. Retention keeps ok results 14 days (`retention.ok_results_days`),
  failures and errors 90 days, the app's own report audit rows 30 days, codes 7 days, the sign-in log a year.
- **Pages never silently lost**: see "A failing email" under Alerts.

## Rolling back a migration

Every migration in `supabase/migrations/` has a `.rollback.sql`. Roll back newest first: a migration's rollback
assumes every later one is already rolled back. Each rollback touches only schema `one`, its two roles, its two cron
jobs and the fixer's grants. Run it from a machine with database access (`RUNBOOK-database.md` §1), between the same
two catalogue fingerprints the apply uses, so a rollback that touched an app object is undone whole:

```sh
node scripts/db/with-db.ts ONE_PROD_DB_URL psql -X -q -1 -v ON_ERROR_STOP=1 \
  -f scripts/db/fp-before.sql -f supabase/migrations/<file>.rollback.sql -f scripts/db/fp-after.sql
```

Take a dump first (`scripts/db/dump.sh`). History (incidents, actions, proposals, runs, audit) is kept by every
rollback except 0002's, 0006's and 0023's (Eduwit Scout's), which say so.

| Migration                   | Its rollback                                                                                                                                                                                                                                                  | Before you run it                                                                                                                                                                           |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0024 Eduwit Scout panels    | Restores 0012's `one.embed_data` verbatim: the three engine panels on the Apps page go, every other panel stays                                                                                                                                               | —                                                                                                                                                                                           |
| 0023 Eduwit Scout checks    | Removes CE-01 to CE-05 with their state and results, and the `catalogue_engine` app row                                                                                                                                                                       | **Refuses** while the app has incidents, proposals or actions: export them, then run it with `PGOPTIONS="-c one.rollback_discards_history=on"`. AI tasks about its incidents stay, unlinked |
| 0022 Eduwit Scout           | Restores 0020's `ai_tool_data` and `events_sources` verbatim, drops `setup_engine_facts`, takes the Setup item out of the catalogue, forgets the `ce.events` watermark, puts back 0002's nine app keys                                                        | Roll back 0023 first. Events already copied stay                                                                                                                                            |
| 0019 fixes                  | Restores 0018's tick step and brief numbers and 0011's proposal decision verbatim; drops the fix functions, the fixer's functions and its grants on the apps, the action columns and the catalogue; revokes the migrating user's membership in the fixer role | Action rows and the fixes' proposals stay. The fixes stop at once                                                                                                                           |
| 0018 AI worker              | Restores the tick's app call, delivery claim and verdict, `proposal_sensitive`, Marketing and Analytics reads; drops the worker's API; suppresses brief emails still queued                                                                                   | Roll back 0019 first. Tasks, calls, briefs stay                                                                                                                                             |
| 0017 test proposals         | Removes the undecided ones                                                                                                                                                                                                                                    | —                                                                                                                                                                                           |
| 0016 test seams             | Drops the seams and the purge                                                                                                                                                                                                                                 | Test leads still in the apps are no longer purged: purge them first or note them                                                                                                            |
| 0015 tests                  | Removes tests (and their checks) that never ran                                                                                                                                                                                                               | A test that ran stays, with its runs                                                                                                                                                        |
| 0014 test runner            | Drops the runner and its columns; the Tests page read goes back to 0010's                                                                                                                                                                                     | —                                                                                                                                                                                           |
| 0013 builder proposals      | Removes the undecided ones                                                                                                                                                                                                                                    | —                                                                                                                                                                                           |
| 0012 app panels             | Drops the panels, Marketing and Analytics                                                                                                                                                                                                                     | —                                                                                                                                                                                           |
| 0011 page writes            | Drops the page writes                                                                                                                                                                                                                                         | Secrets saved in Vault stay (they are the owner's)                                                                                                                                          |
| 0010 page reads             | Drops the reads, pins and saved views                                                                                                                                                                                                                         | —                                                                                                                                                                                           |
| 0009 sign-in                | Drops sign-in functions and tables                                                                                                                                                                                                                            | Nobody can sign in afterwards                                                                                                                                                               |
| 0008 app API                | Drops the app's functions                                                                                                                                                                                                                                     | The app's tick and alert sender stop working                                                                                                                                                |
| 0007 settings seed          | Removes seeded settings; values a person changed stay                                                                                                                                                                                                         | —                                                                                                                                                                                           |
| 0006 checks seed            | Removes checks, their state and results, baselines                                                                                                                                                                                                            | **Refuses** while incidents, proposals, actions or deliveries exist: export schema one (`pg_dump -n one`), then run it with `PGOPTIONS="-c one.rollback_discards_history=on"`               |
| 0005 cron                   | Unschedules `one-tick` and `one-nightly`                                                                                                                                                                                                                      | Monitoring stops; the watchdog pages within 10 minutes                                                                                                                                      |
| 0004 event copy             | Drops the copy functions                                                                                                                                                                                                                                      | —                                                                                                                                                                                           |
| 0003 runner, then 0003 core | Drop the tick and core functions                                                                                                                                                                                                                              | Runner first                                                                                                                                                                                |
| 0002 core tables            | Drops every table of schema one                                                                                                                                                                                                                               | All of Eduwit One's data is lost: export first                                                                                                                                              |
| 0001 schema and roles       | Drops both roles (and their grants) and schema one                                                                                                                                                                                                            | Only when schema one is empty                                                                                                                                                               |

To remove Eduwit One completely, run them all newest first; `scripts/db/leftovers.sql` must then print 0.

## Rotating a secret

Paste a new value on Settings → Setup (owner) and press Validate; the app reads Vault every 60 seconds, so it is in use
within a minute. An environment variable of the same purpose overrides Vault (D-059). Then revoke the old value where
it was issued. Never paste a secret into a chat, a commit or a log; if one leaks, rotate it at once.

| Secret (Vault name / env)                           | Issued by                                         | To rotate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `one_internal_key` / `ONE_INTERNAL_KEY`             | Eduwit One (random, 32 bytes)                     | The database signs each call to the app with it (a token good for 90 seconds, `x-one-token`; the key itself never travels, D-086), the app checks it, and a key derived from it signs the idle cookie. Generate one (`openssl rand -hex 32`); from psql on the operator machine (`RUNBOOK-database.md` §1, not the dashboard's SQL editor, which keeps history) run `select vault.update_secret(id, '<new>') from vault.secrets where name = 'one_internal_key'`; set the same value in Vercel → eduwit-one → env `ONE_INTERNAL_KEY` and redeploy, within a minute of each other (between the two the tick's app call is refused). Everyone signs in again. A person's `curl` may still send `Authorization: Bearer <key>` |
| `ONE_SUPABASE_SERVICE_KEY`, `ONE_SUPABASE_ANON_KEY` | Supabase (shared project)                         | Prefer a secret key made for Eduwit One alone (Supabase → Project settings → API keys → new secret key): set it in Vercel, redeploy, then delete the old one. Never roll the project's JWT secret for this: it signs out and breaks all five apps                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `one_n8n_key` / `ONE_N8N_API_KEY`                   | n8n → Settings → n8n API                          | Create a new key, paste (`n8n_api`), validate, delete the old one in n8n                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `one_chatwoot_token`                                | Chatwoot → profile → access token                 | Reset the token of the user Eduwit One reads as, paste (`chatwoot`), validate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `one_vercel_token`                                  | Vercel → Account settings → Tokens                | New read token for the eduwit team, paste (`vercel`), validate, delete the old                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `one_b2b_read_key`                                  | B2B CRM → Settings → API keys                     | New referrals-only key, paste (`b2b_app`), validate, revoke the old                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `one_whatsapp_token`, `one_meta_token`              | Meta Business → System users                      | Generate a new token with the same scopes, paste (`whatsapp`, `meta`), validate, revoke the old                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `one_email_key`                                     | Resend → API keys                                 | New sending key for eduwit.in, paste (`email`), validate (sends a test email), delete the old                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `one_uptimerobot_key`                               | UptimeRobot → Integrations & API                  | Reset the read-only key, paste (`uptimerobot`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `one_anthropic_key` / `ONE_ANTHROPIC_API_KEY`       | Claude Console (the plan-linked organisation)     | New key, paste (`ai_key`), validate, disable the old in the Console                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `one_b2b_intake_key`                                | B2B CRM → Settings → API keys                     | New intake-only key, paste (`test_b2b_intake_key`), validate, revoke the old                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `one_test_runner_password`, `one_test_runner_totp`  | Supabase Auth; the B2B CRM's two-factor enrolment | Reset the test runner user's password; to change the factor, unenrol and enrol it again in B2B and paste the new base32 secret (`test_runner_user`); validate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `one_test_partner_secret`                           | B2B CRM → the test partner                        | Regenerate its inbound secret, paste (`test_partner`), validate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `one_test_wa_token`, `one_test_mailbox_key`         | Meta; the mailbox provider                        | New token or key, paste, validate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `ONE_PROD_DB_URL`, `ONE_STAGING_DB_URL`             | Supabase database password                        | Only in your shell (`RUNBOOK-database.md`). Resetting the database password also breaks n8n's and the apps' Postgres connections: coordinate it with them                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

`b2c_internal_key` and `web_internal_key` are Spark's and the website's; Eduwit One only reads that they exist.

## Adding a check or a test

**A check.**

1. Add a block to the app's file in `supabase/checks/` (`-- check: <ID>`, then `app`, `kind` (`sql` or `rpc` for SQL the database runs; `http` for a probe the app runs), `severity`, `cadence_s`, optional `open_after`, `resolve_after`, `fix`,
   `tags`, `disabled`, `search_path`, then `title` and `description`, then the SQL). The SQL is one read-only statement
   returning one row `(ok boolean, value jsonb)`, with counts and ids only, never a phone, email or name. Put a
   threshold in `config/settings.json` → `thresholds` and read it with `one.threshold('<key>')`.
2. `node scripts/db/gen-checks.ts` regenerates `0006_seed_checks.sql`, the seed of each app registered after 0002
   (`0023_seed_catalogue_engine_checks.sql` for `catalogue_engine`) and `docs/CHECKS.md` (`node scripts/db/gen-seed.ts`
   regenerates 0007 for a new threshold). Try it against production read-only: `node scripts/db/try-checks.ts --ids=<ID>`
   prints a statement to run in a read-only transaction.
3. `ONE_UPDATE_FINGERPRINT=1 scripts/db/local-test.sh` (commit the new `supabase/tests/fingerprint.expected`), then
   rehearse on staging and apply the check's seed file again (`RUNBOOK-database.md`): `0006_seed_checks.sql`, or
   `0023_seed_catalogue_engine_checks.sql` for a CE check. Re-applying it upserts every check by id and keeps a person's
   edits to switches, severity and cadence. 0007 cannot be applied to production again as it stands (its seed of
   `fixes` is refused once the observation window has started, D-096): a new threshold or Setup item on production
   needs a migration of its own, as 0022 did for the item `catalogue_engine`.
4. A new app: its key goes into a new migration that widens `one.apps`' key constraint (as 0022), and into
   `APPS` and `LATE_APPS` in `scripts/db/gen-checks.ts`, which then seeds its checks in a file of its own right after
   that migration (a fresh install runs 0006 before it, D-096); add it to `app_status` in `one.ai_tool_data`, and to
   `appNames` and `APPS` in the app.
5. An `http` check also needs a probe in `web/lib/checks/probes/` that reports its result; deploy the app.

**A test.**

1. Describe it in `config/tests.json` (id, app, seam, severity, Setup items it needs, steps with timeouts) and run
   `node scripts/db/gen-tests.ts` (regenerates `0015_seed_tests.sql` and `docs/TESTS.md`).
2. Write its journey in `web/lib/tests/journeys/<app>.ts`; it may act only through the kinds of `one.test_act` and
   read through `one.test_fact` its test is allowed (0016, D-069). A new kind is a migration.
3. Only test identities (phones `9100009…` handed out by the database): every row it creates must be a test row the
   app's own delete can remove, and the purge must know how (`web/lib/tests/purge.ts`).
4. Unit-test the journey (`web/lib/tests/journeys/journeys.test.ts`), run the local test and the click-through, then
   rehearse, apply and deploy. It switches on by itself when its Setup items are validated.

## Synthetic tests

The Tests page lists the eleven tests of spec §10 (`docs/TESTS.md`), each with its schedule, the Setup items it still
waits for, its last runs and its step timings. A test switches on by itself when every item it needs is validated;
"Run now" queues it for the next minute. A failing run opens the test's own incident (its id is the test's).

To bring the tests up, in this order (Settings → Setup):

1. `test_b2b_intake_key`: an intake-only B2B API key, saved as `one_b2b_intake_key`.
2. `test_runner_user` (owner): a Supabase user only for the tests, for example tests@eduwit.in. In the B2B CRM make it
   an admin with two-factor and enrol a TOTP factor; in Spark make it an admin with `is_test_user`. Put its email in
   Settings → test_identities.runner_email, save its password as `one_test_runner_password` and the TOTP secret
   (base32, from the enrolment) as `one_test_runner_totp`. Validate signs in with both and asks each CRM for its role
   (D-070). That switches on T-B2B-INTAKE and T-HANDOFF.
3. `test_partner`: a B2B partner used only for tests, the **only** partner with a `test_endpoint`, with an inbound
   secret saved as `one_test_partner_secret` (T-B2B-PUSH refuses to start while another partner has a test endpoint).
4. `test_spark_journey`: a Spark journey in test mode whose first step queues a WhatsApp message (T-B2C-NURTURE).
5. `test_whatsapp_number` and `chatwoot`: the test number in `w2_trusted` with `is_test`, its sender id and token, and
   Witty's number (T-WITTY-TURN). WhatsApp's 24-hour window applies: if the test has not run for a day, send one
   message to the test number from Witty's side first.
6. `n8n_api`: T-WITTY-QUALIFY switches Witty's harness workflow on for its run and off after it (D-072). If a run is cut
   short, check in n8n that the harness is off.

Every lead a test creates has a phone `9100009` + five digits that the database hands out, so every app marks it a
test lead. Two days after a run (`tests.purge_after_days`) the minute tick deletes its leads in Spark and B2B as the test
runner, through each CRM's own delete with reason "test" (nothing is hard-deleted); a purge that fails is retried and
ONE-PURGE reports it. Partner-routed test leads are kept until B2B accepts "test" for them (proposal
`p5-b2b-delete-sandbox-test-leads`); the rows the purge leaves are listed in D-071. The website and influencer tests
are blocked until the apps add what their proposals ask for (D-071).

## The AI layer

The AI writes advice; the checks' SQL decides what is broken (D-075). Each minute the tick queues AI tasks by fixed
rules (a classification for each new incident, an explanation for a P1 or P2 open 15 minutes, a fix proposal after an
hour, a weekly feature review on Mondays, a test idea when an incident is resolved as fixed, the nightly brief, every
Ask) and calls the worker when one is due. What the AI may write: an incident's summary and likely cause, briefs, its
answers, and open proposals a person decides. Synthetic test incidents are never analysed.

To switch it on (Settings → Setup → `ai_key`, owner). Claude only (D-078):

1. In the Claude Console, use the organisation linked to the Max or Team plan's API credits (claude.ai → Settings →
   the plan's API credits), create an API key for Eduwit One, and save it here as `one_anthropic_key` (or Vercel env
   `ONE_ANTHROPIC_API_KEY`). Calls then draw on the plan's monthly API credits, never on the plan itself. A
   subscription login cannot be used by a server (Anthropic's terms). Optionally set a spend limit on that workspace
   in the Console as a second guard.
2. The models and prices are seeded (Settings → AI → `models`, `prices`, `refusal_fallback`): Haiku 5.5, Sonnet 5.5,
   Opus 5.5, and Opus 4.8 for a refusal. **A model without a price is never called**: its tasks wait as deferred and
   say so.
3. Validate. It checks the key and every tier's model and the refusal fallback with a free model lookup.

Spend: `daily_cap_inr` (₹250, sized to fit the smallest plan's monthly API credits) and `per_task_cap_inr` (₹50). From `queue_non_triage_at_pct` (80%) of the day's cap only
classify and triage run; at the cap nothing runs, and ONE-01 fires at the cap or while work waits because of it. A call
is not made when its worst case (the whole output allowance) would pass the per-task cap, counted over the task's
attempts, or what is left today. Held-back tasks show "deferred" with the reason on the incident and Ask pages and are
offered again every 15 minutes; a failed call that can be retried waits 2, 4, then 8 minutes; tasks older than
`task_max_age_h` (48) are cancelled. To stop all AI work at once, set `daily_cap_inr` to 0 (ONE-01 then stays quiet).
Every call is in Audit → AI calls with its tokens, cost and prompt version, recorded as it ends; a call that got no
answer (a timeout) is counted at its worst case, because the provider may have billed it. When the plan's API credits
run out, tasks wait an hour at a time as "budget (credits exhausted)" and ONE-01 reports it: buy more credits or wait
for the next month's grant. When a model declines a task, the worker asks the refusal fallback once.

Contact data: the database redacts what it sends, and the worker masks it again (`web/lib/ai/pii.ts`: names under a
name key become initials, phones their last four digits wherever they appear, emails their domain; message texts, notes
and comments are left out). A name inside free text cannot be recognised, which is why those are left out; it is also
why the Ask form asks people not to type a student's name. Witty message excerpts reach the model only for an
explanation of a Witty incident, and only while `ai.allow_message_excerpts` is on (off): excerpts can carry names. Every
proposal the AI writes is the owner's to approve (D-077).

Ask uses fixed read-only tools, never SQL written by the model (D-076); each answer lists the tools it used. Besides
the incident, check, test, event, analytics, marketing, Witty, health, cron, spend, proposal and delivery tools, Ask
can read how Eduwit One and the apps are set up and run (D-083): `setup` (the Setup catalogue with each item's state and
the checks waiting for it), `app_status` (one app's heartbeats, checks, open incidents, cron jobs, fixes and tests),
`operate` (the Operate page's text), `fixes` and `actions` (the fix catalogue, counts and rows), `audit` (who changed
what, never the values) and `runbook` (the sections of this runbook, `RUNBOOK-database.md` and `WALKTHROUGH.md` that
match a question). So "how do I rotate the n8n key" or "what does Spark still need" are answered from the documents and
the live state, with the steps in order. The runbook the AI reads is generated from these files (`node
scripts/gen-docs.ts`; a unit test fails while it is stale): edit the documents, not the module. The morning brief
covers the day before, is built at 02:30 IST and mailed to the P1 inbox at `ai.schedule.brief_mail_at_ist` (08:00),
with links to the saved views marked "email it".

Cost controls (0026, D-099; lean by default since 0027, D-101). Settings → AI → `schedule` holds the switches, each
versioned and restorable: `classify_new_incidents` (false: no category for every new incident), `explain_severities`
(`["P1"]`: which severities get an explanation while unacknowledged), `explain_unacknowledged` (true: a P1 is explained
before anyone acknowledges it; an acknowledged P1 or P2 is always explained), `propose_fix_only_with_catalogue_fix`
(true: fix proposals only where some fix in the catalogue is tried on the check, or once a person acknowledged the
incident), `triage_min_gap_h` (24: one triage per incident per day unless its severity rose; 0 means one per routing),
`explain_after_min` (15: when an explanation is due, and a fix proposal for an acknowledged incident) and
`propose_fix_after_min` (1440: when a fix proposal is due otherwise). Explanations stay on the deep tier
(`routing.explain`); the open proposal "AI: explain incidents on the regular tier after 60 minutes" offers the cheaper
choice. To turn a use back on, set its switch on that page; the next tick follows it. A proposal on the Proposals page
that names Eduwit One's own settings (`change.settings_patch`) is applied by the owner's **Approve**: the patch is
merged into the current value and saved as a new version under the approver's name. The AI usage audit
(`docs/reviews/ai-usage-audit.md`) says what each use costs and why these are the defaults.

To run the worker by hand: `curl -X POST -H "Authorization: Bearer $ONE_INTERNAL_KEY" https://one.eduwit.in/api/internal/ai/run`.
The route's 300-second limit runs on Vercel Pro with Fluid compute (owner, 24 Oct).

The eval: `cd web && npm run ai:eval` runs the 30 incidents and 12 questions offline (it proves the harness and the
mask, and spends nothing). `npm run ai:eval -- --live` prints the regular tier's model and worst-case cost; add `--yes`
to run it, with `ONE_ANTHROPIC_API_KEY` set (`--tier quick|deep|all` for the others). It prints scores, leaks (must be
0), cost and latency.

## The command centre (chat)

The Command centre page (`/chat`, D-094) is Eduwit One operated by talking: set up, run and fix Witty, the website,
the two CRMs, the influencer portal and Eduwit One itself from one conversation. It is the same AI as Ask, with the same
rules, plus the ability to act, under these limits:

- **Reads** are the fixed read-only tools Ask has (incidents, checks, tests, events, analytics, marketing, Witty's panels,
  health, cron, spend, proposals, deliveries, n8n executions, the Setup state, each app's status, the fix catalogue, the
  audit, the Operate pages and this runbook). The model never writes SQL. Contact data is masked twice (the database's
  redaction, then `web/lib/ai/pii.ts`), the person's own message included.
- **Acts** are the console's own page functions (`one.ui_*`), run as the signed-in person with their role check and audit
  row, under the same request id. Four reversible, low-risk acts run at once: acknowledge an incident, a fix's dry run, a
  Setup item's validation, an explanation on the deep model, a brief re-built. Everything else (resolve, mute, run a
  test, switch a fix, decide a proposal, change a check, a test, a setting or a person) first shows an **action card**
  in the chat with the exact arguments; nothing runs until **Confirm and run** is pressed. A card not decided in two
  hours expires. An engineer is not offered the owner-only acts (fix switches, people); the database refuses them anyway.
- **Fixes on the apps** keep every rule of the fix catalogue (D-079, D-084): the chat can record a dry run and propose
  the owner's switch; it never runs a fix and never promises one will run.
- **Secrets** never pass through the model: the chat shows a Vault card (`request_secret`), the value goes to
  `one.ui_secret_put` as on Settings → Setup. A message that looks like a key, a token, a password or a connection string
  is refused before it is stored or sent, with a note to rotate it if it was real.
- **Budget**: each turn is one `chat` task in `one.ai_tasks`, its calls in Audit → AI calls with their cost, on the
  `regular` tier (`ai.routing.chat`). The day's cap and `queue_non_triage_at_pct` apply exactly as to Ask (at 80 % of the
  cap the chat says so and stops); a turn stops at the per-task cap, after 16 tool calls or 8 rounds. A turn the app
  did not finish in 10 minutes is failed, never re-queued, so it never counts as waiting work (ONE-01).
- **Storage**: conversations are the person's own (nobody else can read them, the owner included), kept
  `retention.chat_days` (90) and pruned by `one.retention()`; **Archive** hides one. Each conversation shows the tools
  each answer used and every action's outcome.

Good first messages: "What needs me right now?", "Walk me through setting up Witty", "What does Spark still need?",
"Why is the newest P1 open and what can we do?". For "set up X" the chat reads the Setup state and the Operate page and
gives the steps in order, validating items as they are filled and offering a Vault card for each key. The Ask page
remains for a single question with a full answer by email-style later; the chat answers at once.

## The external watchdog (UptimeRobot)

It is the only thing that notices Supabase, pg_cron or Vercel being down. Set it up once the app is deployed at
`https://one.eduwit.in` (Setup item `watchdog_monitor`):

1. UptimeRobot → **Add New Monitor** → type **Keyword**.
2. URL `https://one.eduwit.in/api/watchdog`; keyword `"ok":true`; alert when the keyword is **not** present.
3. Interval 5 minutes (the free plan's shortest).
4. Alert contact: `connect@eduwit.in`, and make sure the contact is **active** (on 23 Oct it was paused, D-018).
5. Test it: pause the `one-tick` job for 6 minutes on staging (`select cron.alter_job(jobid, active := false)` as the
   owner); the monitor must email within 10 minutes. Re-activate the job.

## Checking a change locally

Nothing here touches a Supabase project. `scripts/db/local-test.sh` builds a throwaway cluster, applies every migration
between catalogue fingerprints, runs every SQL test, rolls everything back and applies again (LOCAL TEST PASSED).
`e2e/run.sh` then clicks through every page as the owner and an engineer against the production build of the app and a
local Supabase stand-in, and checks the audit, the RPCs and the phone layout (CLICK-THROUGH PASSED; D-064). Its report
and screenshots land in `e2e/out/`.
