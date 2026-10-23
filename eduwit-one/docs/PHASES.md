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
| `REHEARSAL PASSED` on staging | **blocked on owner** (D-031): 0001–0003 (core) applied to staging; the remaining steps contain DROP or DELETE, which the connector holds for a person to confirm. Needs `ONE_STAGING_DB_URL`, or approvals during the run |
| Full dump of production, path in `DECISIONS.md` | **blocked on owner: `ONE_PROD_DB_URL`** (D-010) |
| Applied to production; `select one.tick()` report has no `_error` key; `cron.job` shows both jobs | blocked by the dump |
| `one.events` count within 1% of the sources | pending |
| Least-privilege test passes | passes locally (`supabase/tests/local/20_events_secrets_privileges.sql` §5, and `supabase/tests/smoke.sql`, which runs the same catalogue checks on staging and production). Proven to fail on a bad grant |

## Phases 2–7

Not started.
