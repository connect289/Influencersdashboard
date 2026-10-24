# Eduwit One — changes

Append-only, newest first. One entry per deploy or per phase step; production database changes name the dump they
followed.

## 24 Oct 2026 — correction: the live refresh was not why answers went missing

- The earlier entry blamed the 15 s live refresh for the click-through's lost answers. A run with the live refresh
  switched off still lost two: the action's request answers 200, its write is audited, and the form never shows the
  result. The guard stays (a refresh during an action is still pointless); the cause is being traced. The click-through
  now records, for a failed write, every request during the wait and whether each response body completed.

## 24 Oct 2026 — phase 5 review resolved

- Review: `docs/reviews/phase-5.md` (1 blocker, 5 majors, 9 minors), all resolved.
- Setup validators `b2b_intake`, `test_partner` and `test_whatsapp` (none writes anything), and a unit test that every
  validator a Setup item names exists. T-WITTY-TURN checks WhatsApp's own numbers for the sender and Witty before each run.
- Runner: rounds over every run, leases released when a run waits, the end of the budget kept for the purge, poll
  errors retried until the step's timeout (`Failed` and `Unsafe` end a run), an `acting` mark so no action repeats.
- Purge: only the CRMs' own soft deletes (nothing hard-deleted: B2B's and Spark's rows have no foreign key to the lead);
  a run whose deletes failed stays due with backoff (`one.test_runs.purge_attempts`, `purge_next_at`); new check
  ONE-PURGE. Phone allocation refuses a phone that already holds a lead and no longer resets it.
- Journeys: the command centre read once per run; the harness switched off after a failed start; Spark's mock call
  accepted; the Chatwoot conversation read in its own step; nurture facts scoped to the test's journey run; T-B2B-PUSH
  needs the partner secret; one sign-in per pass and a sign-out at its end.
- e2e: each write's answer is timed, and a failed write reports what the browser saw (errors, the action's answer).

## 24 Oct 2026 — phase 5, test rows out of Eduwit One's own metrics

- 0012: Witty's replies panel and the Marketing page's leads by campaign and touchpoints leave out harness phones,
  Witty's trusted test numbers and test leads (spec §10). Asserted in `98_tests_journeys.sql`; the local stubs gain
  `public.w2_trusted`.
- D-073 records where each journey differs from spec §10's steps and why.

## 24 Oct 2026 — live refresh no longer cuts into a form's action

- The 15 s live refresh skips its tick while a form's action is pending or within 5 s of a click or key. The
  click-through twice saw a write recorded in the audit whose answer never reached the form (a refresh landing during
  the server action); `components/shell/live-refresh.tsx`.

## 24 Oct 2026 — phase 5, the journeys, the test runner login and the purge

- 0014: a run's artefacts are only added to, and `phones` is written only by the database.
- 0016: the seams of every journey (Witty's turn and harness run, the B2B lead, its routing, push and partner activity,
  the hand-off to Spark, Spark's record, write-back and journey sends, and both leak counts), each answering only for a
  test lead on the run's own phones and returning no contact field; phone allocation from `9100009` after Witty's own
  reset; the purge (`one.test_purge_due`, `one.test_run_purge`); `one.setup_test_facts` for the Setup page (D-071).
- 0017: six proposals for what the blocked tests need from the website, the catalogue, Witty and B2B (D-071).
- Web: the test runner login with two-factor (`lib/tests/totp.ts`, `lib/tests/apps.ts`, D-070); B2B's intake and
  signed partner events, n8n's harness (D-072), the test WhatsApp sender and Chatwoot's message list; journeys for
  T-WITTY-TURN, T-WITTY-QUALIFY, T-B2B-INTAKE, T-B2B-PUSH, T-HANDOFF and T-B2C-NURTURE; the purge pass after the
  tests in each tick; Setup validators `test_runner` and `spark_journey`. New Setup items `test_runner_user` and
  `test_spark_journey`; T-WEB-ENQUIRY, T-WEB-ADVISOR and T-INFLUENCER are blocked with their reasons.
- Tests: `supabase/tests/local/98_tests_journeys.sql`; unit tests for every journey's path and refusals, the purge, the
  sign-in and the signature.

## 23 Oct 2026 — phase 5, the seams and T-ALERT end to end

- 0016: `one.test_fact` and `one.test_act`, each kind allowed only for a run in flight of a test that may use it,
  every action recorded on the run (D-069). T-ALERT's kinds: a synthetic P2 incident on the new check ONE-SYNTH with a
  test delivery, its status, and closing it. Synthetic incidents are left out of the P2 digest.
- Web: the runner runs after the probes and alerts in each minute tick, and on its own at `/api/internal/tests/run`;
  the T-ALERT journey; Resend's delivery status in the email client; unit tests that keep every journey equal to
  `config/tests.json`.
- Tests: `supabase/tests/local/97_tests_seams.sql`.

## 23 Oct 2026 — phase 5, the test runner's database side and the catalogue

- 0014: runs keep their steps, timings, artefacts and state; a lease per runner; `one.tests_state`,
  `one.test_run_start`, `one.test_run_save`, `one.test_run_finish` (reports to the test's own check), and a reaper
  for runs nobody reached. Tests switch on when their Setup items are validated, and their checks follow them. The
  Tests page shows step timings against each step's timeout and what a test still waits for (D-068).
- 0015 (generated from `config/tests.json` by `scripts/db/gen-tests.ts`): the eleven tests of spec §10 and their
  checks; `docs/TESTS.md`. T-ALERT is on; T-WEB-CATALOG is blocked (no safe catalogue write); the rest wait for
  their test identities.
- Web: `lib/tests/cron.ts` (schedules) and `lib/tests/runner.ts` (the state machine), with unit tests.
- Tests: `supabase/tests/local/96_tests_runner.sql`; `scripts/db/gen-tests.test.ts`.

## 23 Oct 2026 — phase 4 reviews resolved, and the click-through

- Phase review (`docs/reviews/phase-4-ui.md`: 1 blocker, 6 majors, 14 minors) and security review
  (`docs/reviews/phase-4-security.md`: 2 high, 5 medium): every finding fixed or accepted with a reason, in the
  resolution tables; tests in `supabase/tests/local/95_review4.sql`.
- Phone layout: cards and grids shrink to the screen, JSON wraps, and the Act and Decide cards come first on a phone.
- Roles (D-065): engineers change thresholds, checks, tests, witty and analytics settings only; fix and config proposals
  and anything touching security are the owner's; P1, security and integrity checks stay on unless the owner says.
- Sign-in (D-066): a signed, per-session idle cookie; the idle limit from `access.idle_hours`; "Sign out everywhere"
  ends other sessions; the live refresh stops when nobody uses the page.
- Redaction (D-067): phones in any grouping and long numbers; more name keys.
- Panels: Witty replies and learnings fixed; section times on Marketing and Analytics; STABLE reads; heavy pages refresh
  every 5 minutes. Snoozed proposals come back. Setup validation recorded only by the app. HB-gemini and WITTY-09
  blocked until built (D-049). Settings shapes checked for analytics, ai and fixes; an unchanged save is refused.
- Settings index lists every key; the check runner's settings are on the Checks page; acknowledge from the Overview;
  a banner while mutes are in force.
- `e2e/run.sh`: the click-through on a local cluster with a Supabase stand-in (D-064).

## 23 Oct 2026 — phase 4, the UI (built; production run waits on phase 1 and the deploy)

- Sign-in (0009): Google restricted to `@eduwit.in`, then an emailed 6-digit code or a trusted device; every UI
  function checks the caller with `one.ui_require()` from the signed JWT; sign-in log; idle sign-out (D-058).
- Page reads (0010) and writes (0011): Overview, Incidents, Proposals, Actions, Tests, Brief, Ask, Audit (with CSV
  export), Settings (versioned JSON editor, Checks, Maintenance, Users, Privileges, Fixes) and Setup (secrets to
  Vault, validation, D-059). Each write is audited with its request id; owner-only keys and sensitive proposals need
  the owner.
- Apps, Marketing and Analytics (0012): app panels run the apps' own reads as the signed-in person, redacted and
  timed (D-062); the funnel from `settings.analytics.funnel` with medians between steps; partner and counsellor
  tables; saved views; aggregate-only CSV.
- The builder's proposals (0013): twelve open findings with evidence measured on production (D-063).
- Web: Tailwind v4 kit with generated brand tokens (D-061), strict CSP with a nonce, polling every 15 s instead of
  Realtime (D-060), phone layouts, empty, loading and error states on every page.
- Tests: `supabase/tests/local/70_auth.sql`, `80_ui_api.sql`, `90_ui_apps.sql`; smoke asserts every
  `authenticated`-executable function calls `one.ui_require(`; web unit tests for security helpers, CSV, tokens and
  the code email. Decisions D-058 to D-063.

## 23 Oct 2026 — second database review resolved

- Cron procedure: start marks committed before each check and event copy; killed runs reaped as errors and moved
  after the alert step and the app call; a tick lock; the run counts as finished after the app call (D-056).
- New checks ONE-02 (alert email pending 5 min) and PLAT-01W (a less-than-daily job's failure); PLAT-01 and B2C-01
  read finished runs through the runid key; B2B-02 looks back 15 minutes; PLAT-04 counts calls with no status;
  PLAT-06 adds the security-definer-view lint; INT-06 allows added columns; WITTY-03 counts from 09:00 IST (86 checks).
- Heartbeat checks through `one.heartbeat_state()`: a never-seen component is down once expected.
- Redaction finds contacts anywhere in text, in keys and in JSON kept as text; more name and comment keys.
- Settings are validated on write (`one.settings_check()`); `app.base_url` must be https.
- Grants: the API roles execute only the functions in `one.api_grants` and hold no table privilege (D-055).
- `/api/watchdog` reads the last finished tick and the oldest pending alert email.
- Migration guards rewritten as a statement reader; every apply wrapped in a catalogue fingerprint of everything
  outside schema one (D-057). `0006`'s rollback refuses to discard history unless told to.
- Tests: `supabase/tests/local/60_review2.sql`, new guard cases, local-test steps for both refusals, the watchdog
  verdict in `web/lib/core.test.ts`. Decisions D-054 to D-057.

## 23 Oct 2026 — phase 3, alerts

- Escalation, the P2 digest, storm suppression, developer copies and mute re-routing, in SQL each minute
  (`one.alerts_step()` in both tick paths); new columns `incidents.routed_at`, `deliveries.claimed_at` and
  `provider_id`.
- App API: `one.claim_deliveries`, `one.finish_delivery`, `one.mute`, `one.unmute` (0008). New check ONE-STORM (84
  checks).
- Web: Resend email client, alert composition and the sender, run by `/api/internal/tick` after the probes.
- `docs/RUNBOOK.md` started (what runs where, alerts, the watchdog set-up); new Setup item `watchdog_monitor`.
- Tests: `supabase/tests/local/50_alerts.sql` and `web/lib/alerts/alerts.test.ts`.
- Decisions D-051 to D-053.

## 23 Oct 2026 — phase 2, probe runner

- Added `web/`, the Next.js 15 app (D-012). Routes: `/api/health`, `/api/watchdog` (D-018), `/api/internal/heartbeat`
  and `/api/internal/tick`, which runs the HTTP probes and writes heartbeats and results in one call.
- Clients for app health, Vercel, Chatwoot, n8n and WhatsApp, each with a Real and a Mock implementation. The app
  health, Vercel and Chatwoot fixtures were recorded from real responses (D-049).
- Migration 0008 `app_api`: `one.app_tick_state()`, `one.app_report()`, `one.witty_escalations()`, `one.watchdog()`
  (D-047). The seed now includes `vendors` and `health_paths`.
- Two new Setup items: `supabase_api_schema` and `one_app_env`. The preflight was re-run (unchanged otherwise: 13
  verified).
- Heartbeat checks now fail for a component read but never once ok (D-050).
- Added `.github/workflows/eduwit-one-ci.yml`: guards, drift, the local migration test, and the web app's checks and
  build.
- Real finding from the recording: the Eduwit One Vercel project does not exist yet (404), as expected before phase 4.

## 23 Oct 2026 — phase 1 review fixes

- Fixed the phase 1 review's blocker and eight majors (`docs/reviews/phase-1.md`, D-042 to D-046): recursive PII
  redaction of event payloads; failing-to-run checks open incidents; per-check search path; re-alerting on reopen,
  escalation and new subjects; a committing cron procedure with lock and transaction timeouts; event overlap and
  state windows.
- New objects in schema `one` only: columns `checks.search_path`, `check_state.last_started_at`,
  `incidents.subjects`, `incidents.alert_seq`; functions `due_checks`, `run_check_safe`, `report_add`,
  `tick_app_call`, `public_schema_writers`, `redact`, `events_copy_safe`; procedure `tick_job`. `one-tick` now runs
  `call one.tick_job()`.
- Local test passes; the changed checks were re-run read-only on production. Staging is unchanged (0001 to 0003 core
  from before; the connector still holds DROP and DELETE).

## 23 Oct 2026 — database runbook

- Added `docs/RUNBOOK-database.md`: rehearse, dump and apply from a machine with direct database access (D-041).
  A retry of the staging rehearsal through the connector timed out again on the 0003 runner (no approval prompt
  reached the owner); nothing new was applied to staging.

## 23 Oct 2026 — phase 2, check catalogue

- The full specification catalogue (83 checks: 73 on, 10 off until configured) is now in `supabase/checks/*.sql`.
  `scripts/db/gen-checks.ts` generates migration 0006 and `docs/CHECKS.md` from it, with a drift test.
- New thresholds in `config/settings.json` (D-039); migration 0007 regenerated.
- Every SQL check was run read-only on production (`scripts/db/try-checks.ts`, `docs/CHECK-TRIAL.md`). Nothing was
  written.
- Local test extended with `supabase/tests/local/30_checks.sql`: the known findings open the expected incidents, a
  stale heartbeat opens and recovers, and setup-gated checks are skipped.
- Decisions D-033 to D-040.

## 23 Oct 2026 — phase 1, rehearsal tooling and partial staging apply

- Added `scripts/db/rehearse.sh`, `apply.sh` and `dump.sh`. Also added `with-db.ts` (credentials go into PG*
  variables, never argv; a URL that reaches the wrong project is refused), `guards.ts` with its tests, `fingerprint.sql`,
  `leftovers.sql`, `supabase/tests/smoke.sql` and `docs/REHEARSALS.md`.
- The local fixture tests moved to `supabase/tests/local/` and now refuse to run on any database but the local test
  cluster.
- Staging (`mplbspysxmtohnlwpbti`), through the connector as postgres: applied 0001, 0002 and 0003 (core), each in
  its own transaction. 0003 (runner) did not reach the database: the connector holds statements containing DELETE for
  a person to confirm (D-031). No cron job is scheduled on staging, and nothing of the apps changed.
- Read-only queries on production: RLS coverage of the app tables (D-030), postgres's read reach for the dump
  (D-032), and pg_cron's RLS policies.

## 23 Oct 2026 — phase 1, database (local)

- Added migrations 0001–0007, each with a rollback: schema `one` and its two roles; the core tables; settings,
  secrets, heartbeats, incidents and alert routing; the check runner, `one.tick()` and `one.nightly()`; the event copy
  from 17 sources; the two cron jobs; the first 9 checks; the settings seed (generated by `scripts/db/gen-seed.ts`).
- Added the local test: `scripts/db/local-test.sh` with stubs in `supabase/tests/local/` and tests in
  `supabase/tests/10_core.sql` and `20_events_secrets_privileges.sql`. Result: LOCAL TEST PASSED (apply, test,
  rollback leaving nothing behind, apply again, test again).
- Fixed what the local test found: JSON literals in the check seeds were stored as strings, a text-array append in
  `one.capture_baselines()`, a heartbeat interval limit too low for the nightly job, and an ungrantable reader grant on
  `net` (D-028).
- One read-only query against production (schema owners and grant options), no write. Nothing applied to staging or
  production yet.

## 23 Oct 2026 — phase 0, preflight

- Added `eduwit-one/` with `config/defaults.json` (non-secret hosts and ids) and `config/setup-items.json` (the Setup
  checklist, 31 items).
- Added `scripts/preflight.ts`, a re-runnable access preflight. It made real reads against GitHub, Vercel, Chatwoot,
  n8n, Lightsail, UptimeRobot, Resend, the B2B API, WhatsApp, the model APIs and the app health endpoints. Optionally it
  runs a read-only survey of production through `psql`.
- First run: 13 verified, 12 not provided, 1 refused (Lightsail), 5 unfilled. Results are in `docs/PREFLIGHT.md`, and
  the seed for `one.settings.setup` is in `supabase/seed/setup.json`.
- Logo saved as `web/public/brand/eduwit-logo-source.jpg`; palette navy `#072E59`, amber `#F2A505`.
- No database, Vault, Vercel or n8n object was created or changed. One probe's call is counted by the B2B CRM's own
  key-usage audit (`b2b.api_key_usage`, D-021); every other call was a read.
- Fresh review fixes (`docs/reviews/phase-0.md`): no psql output or URL credentials can reach a report, presence-only
  identities are "unfilled", dated connector evidence, refused rows always carry a fix, a Meta probe.
