# Eduwit One — runbook

How Eduwit One runs, what its alerts mean, and what to do. The database steps (rehearse, dump, apply, undo) are in
`RUNBOOK-database.md`; the checks are listed in `CHECKS.md` (generated). This file grows with each phase.

## What runs where

| Piece | Where | Every | What it does |
| --- | --- | --- | --- |
| `one-tick` | pg_cron, `call one.tick_job()` | minute | Heartbeat `one:tick`; records any check or copy killed last time as an error; due SQL checks (one commit each); escalation, digest; calls the app (the tick counts as finished here); event copy; checks killed earlier, last (D-056) |
| `one-nightly` | pg_cron, `select one.nightly()` | 02:30 IST | Privilege audit, baselines, retention, proposal expiry, brief task |
| `/api/internal/tick` | the app, called by `one-tick` | minute | HTTP probes (app health, Vercel, Chatwoot, n8n, WhatsApp), heartbeat `one:app`, alert sender |
| `/api/watchdog` | the app, called by UptimeRobot | 5 min | `{"ok":true}` while the last finished `one-tick` is under 5 minutes old and no alert email has waited 10 minutes |

## Alerts

- **Opening.** A check that fails (or cannot run: its SQL errors or its source is gone) opens an incident with the
  check's severity. The same check failing again touches it; a new failing subject (another job, partner or alert
  kind) alerts again. Three good runs in a row resolve it as recovered; failing again within 24 h reopens it.
- **P1:** an email to the P1 inbox at once. If nobody acknowledges it: again at 30 minutes; at 60 minutes to the P1
  inbox and the second contact; then every 60 minutes. Acknowledge from the incident page to stop it.
- **P2:** listed in the morning brief, and in an 18:00 IST email digest when more than 5 opened that day.
- **P3:** the dashboard only.
- **Developer:** incidents tagged `code` also go to `alerts.developer_email` once it is set.
- **Storm (ONE-STORM).** More than 10 P1s within 5 minutes send one storm email naming the top three checks. The
  individual P1s are held under it for 15 minutes, then alert one by one if still open.
- **Mute or maintenance.** Mute a check or a whole app from the UI with a duration and a reason. Incidents still
  record; nothing is sent. When the mute ends, anything still failing alerts again.
- **A failing email.** Retried once after 2 minutes; a second failure is final and ONE-01 reports it, so a dead
  email key cannot stay silent. Email is the only channel (owner, 23 Oct); no WhatsApp alert is sent.
- **Emails not going out (ONE-02, P1).** An alert email still waiting after 5 minutes means the database cannot reach
  the app (check `app.base_url` and the Vercel deployment) or the app cannot send (check the Resend key). Its own
  email waits in the same queue, so the watchdog pages through UptimeRobot after 10 minutes.
- **A killed check.** A check that runs past `checks.transaction_timeout` (30 s) is recorded as an error with
  "killed" in its result, which opens its incident; it then runs at the end of the tick, at most every 10 minutes per
  kill. Look at the check's SQL and the table it reads (a lock or a slow plan).

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
  Google provider is the one Spark already uses. Vercel env: `ONE_SUPABASE_URL`, `ONE_SUPABASE_ANON_KEY`,
  `ONE_SUPABASE_SERVICE_KEY`, `ONE_INTERNAL_KEY` (Setup item `one_app_env`).

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
Approving records the decision; the change itself is made in the app named under "where" (Eduwit One changes no app),
or, from phase 7, by a catalogued fix. The builder's twelve proposals (D-063) wait for a decision and never expire.

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
