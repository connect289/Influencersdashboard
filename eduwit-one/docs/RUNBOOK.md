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

## The external watchdog (UptimeRobot)

It is the only thing that notices Supabase, pg_cron or Vercel being down. Set it up once the app is deployed at
`https://one.eduwit.in` (Setup item `watchdog_monitor`):

1. UptimeRobot → **Add New Monitor** → type **Keyword**.
2. URL `https://one.eduwit.in/api/watchdog`; keyword `"ok":true`; alert when the keyword is **not** present.
3. Interval 5 minutes (the free plan's shortest).
4. Alert contact: `connect@eduwit.in`, and make sure the contact is **active** (on 23 Oct it was paused, D-018).
5. Test it: pause the `one-tick` job for 6 minutes on staging (`select cron.alter_job(jobid, active := false)` as the
   owner); the monitor must email within 10 minutes. Re-activate the job.
