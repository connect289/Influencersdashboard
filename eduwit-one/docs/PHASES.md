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
| Least-privilege test passes | passes locally (`supabase/tests/local/20_events_secrets_privileges.sql` §5, and `supabase/tests/smoke.sql`, which runs the same catalogue checks on staging and production). Proven to fail on a bad grant |

## Phase 2 — Checks and heartbeats (in progress; phase 1 blocked on owner, rule 4)

| Criterion | Status |
| --- | --- |
| All checks in §6 seeded | done: 83 checks in `docs/CHECKS.md` (generated); a unit test lists every §6 id |
| Every check has at least one result row | SQL checks: proven read-only on production (`docs/CHECK-TRIAL.md`) and locally; on production after the phase 1 apply. App-run checks: with the probe runner |
| Known live findings produce the expected incident | b2c-capacity (B2C-10) and base URLs or keys (PLAT-05): incidents in the local test, failing on production in the trial. Nurture Worker inactive (WITTY-08): off until `setup:n8n_api` |
| HTTP probes for n8n, Chatwoot, Vercel, website, Spark, WhatsApp; heartbeats written | pending (probe runner) |
| A broken probe produces an HB incident within 3 minutes | stale-heartbeat path proven locally (`30_checks.sql`); the end-to-end probe test comes with the probe runner |

## Phases 3–7

Not started.
