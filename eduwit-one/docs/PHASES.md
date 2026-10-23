# Eduwit One — phase tracker

The acceptance criteria of specification §14, ticked as they pass. With `DECISIONS.md` this is the resumable state.
"Blocked on owner" names the missing item; the build continues with the parts that do not depend on it (spec §17.4).

## Phase 0 — Preflight: done 23 Oct 2026

| Criterion | Status |
| --- | --- |
| `scripts/preflight.ts` exercises every access row with a real read, list or ping | done: 31 items, 13 verified, 12 not provided, 1 refused, 5 unfilled. Supabase, staging, advisors and n8n are exercised through the build session's connectors and recorded with their date in `docs/preflight-connector.json`; that evidence ages out after 7 days |
| Every row marked verified / refused / not provided / unfilled with what was run | done: `docs/PREFLIGHT-table.md` |
| Verified items written for `one.settings.setup` as validated | done: `supabase/seed/setup.json`, loaded by migration 0007 |
| Refused rows get a one-line fix note | done |
| Companion documents read (System Map, prerequisites, website docs) | done; database survey and changes recorded in `DECISIONS.md` |
| `DECISIONS.md` started | done: D-001 to D-027 |
| Fresh-agent review | done: `docs/reviews/phase-0.md`, every finding resolved |

## Phase 1 — Database

| Criterion | Status |
| --- | --- |
| Migrations 0001–0007 with rollbacks | done locally: `scripts/db/local-test.sh` prints LOCAL TEST PASSED (D-029) |
| `REHEARSAL PASSED` on staging | **blocked on owner** (D-031, D-041): 0001–0003 (core) applied to staging through the connector; the rest needs `scripts/db/rehearse.sh` run from a machine with database access (`docs/RUNBOOK-database.md` step 2) |
| Full dump of production, path in `DECISIONS.md` | **blocked on owner**: `scripts/db/dump.sh` from a machine with database access (runbook step 3; D-010, D-041) |
| Applied to production; `select one.tick()` report has no `_error` key; `cron.job` shows both jobs | blocked by the dump |
| `one.events` count within 1% of the sources | pending |
| Second database review (security rubric) | done: `docs/reviews/phase-1-2-db.md`, 1 blocker, 10 majors, 18 minors; all resolved (D-054), tests in `supabase/tests/local/60_review2.sql` |
| Least-privilege test passes | passes locally (`supabase/tests/local/20_events_secrets_privileges.sql` §5, and `supabase/tests/smoke.sql`, which runs the same catalogue checks on staging and production). Proven to fail on a bad grant |

## Phase 2 — Checks and heartbeats (built; production run waits on phase 1, rule 4)

| Criterion | Status |
| --- | --- |
| All checks in §6 seeded and running | done: 83 checks (`docs/CHECKS.md`, generated); a unit test lists every §6 id. SQL checks run in `one.tick_job()`; app-run checks run in `web/lib/checks` |
| HTTP probes for n8n, Chatwoot, Vercel, website, Spark, WhatsApp; heartbeats written | done in code (`web/lib/checks/probes/*`, migration 0008). App health, Vercel and Chatwoot proven against the real vendors (contract tests, recorded fixtures 23 Oct); n8n and WhatsApp on documented-shape fixtures until their credentials are filled (D-049) |
| Every check has at least one result row | SQL checks: read-only trial on production (`docs/CHECK-TRIAL.md`) and locally. On production after the phase 1 apply and the app deploy (Setup items `supabase_api_schema`, `one_app_env`) |
| Known live findings produce the expected incident | b2c-capacity (B2C-10) and base URLs or keys (PLAT-05): incidents in the local test and failing on production in the trial. Nurture Worker inactive (WITTY-08): off until `setup:n8n_api` |
| A broken probe produces an HB incident within 3 minutes | stubbed path: a failing website probe writes a failed heartbeat (web unit test), and HB-website opens at 3 × 60 s (`30_checks.sql`). Staging end to end waits on the app deploy |

## Phase 3 — Alerts (built; live run waits on phase 1 and the app deploy)

| Criterion | Status |
| --- | --- |
| Deliveries by email | done: `one.claim_deliveries` / `one.finish_delivery` (0008), Resend client and sender (`web/lib/alerts`), retry once then final (ONE-01) |
| WhatsApp template submitted | not applicable: email only, the owner's choice (D-052) |
| Escalation | done: re-send at 30 min, second contact at 60, every 60 after; stops on acknowledge (`50_alerts.sql` §2) |
| Mute | done: `one.mute` / `one.unmute`, maintenance by app; held deliveries; re-route when the mute ends (§4) |
| Storm handling | done: ONE-STORM check, one alert, P1s suppressed under it for 15 min, deep-model triage (§5) |
| The external watchdog configured | **blocked on owner**: after the first deploy (D-053, `docs/RUNBOOK.md`) |
| T-ALERT passes | phase 5 (synthetic tests) |
| An unacknowledged synthetic P1 re-sends at 30 and 60 minutes | proven locally on the stubbed path (§2); on staging after the deploy |
| The watchdog emails when one-tick is paused for 5 minutes on staging | after the deploy and the monitor (D-053) |

## Phases 4–7

Not started.
