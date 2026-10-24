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

## Phase 4 — UI (built and reviewed; the production run waits on phase 1 and the deploy)

| Criterion | Status |
| --- | --- |
| All pages in §12 for owner and engineer | done: Overview, Incidents, Proposals, Actions, Tests, Brief, Ask, Audit, Apps (7), Marketing, Analytics, Settings (every key, Setup, Checks and the runner, Maintenance, Users, Privileges, Fixes). Roles enforced in the database (`80_ui_api.sql`, `95_review4.sql`; D-065). Deferred to their phases: run a fix now and revert an action (7), test step timings (5), emailing a saved view (6) |
| Sign-in flow | done: Google, then code or trusted device (D-058), idle and revocation enforced (D-066); `70_auth.sql`. The live run waits on the redirect URL (Setup item `one_app_env`) |
| Realtime | met by polling (D-060) |
| Settings versioning | done: every settings key is versioned with who, when and why, and any version can be restored; checks, tests, mutes and users are audited with before and after (D-065) |
| Every page renders against production data read-only | **blocked on owner**: needs the phase 1 apply and the deploy. Locally, `e2e/run.sh` renders every page as both roles with no page error (D-064) |
| Every embed RPC call is listed with its latency | done: the Apps page shows each panel's time, Marketing and Analytics each section's; the click-through lists every RPC with its latency |
| No page writes outside `one.*` | done locally: the click-through sends every write a page offers; each left an audit row with a request id, every RPC was a `one.*` function, and no row outside schema one changed except `vault.secrets` from the Setup secret form (by design, D-059) |
| Phone layout for Incidents and Proposals | done: 390 px, no sideways scroll (checked by the click-through); screenshots in `docs/reviews/phase-4-screens/` |
| Phase and security reviews | done: `docs/reviews/phase-4-ui.md`, `docs/reviews/phase-4-security.md`, all resolved |

## Phase 5 — Synthetic tests (built and reviewed; live runs wait on phase 1 and the test identities)

| Criterion | Status |
| --- | --- |
| All tests in §10 implemented and scheduled | 7 of 11 have journeys and schedules (D-068 to D-072); T-WEB-ENQUIRY, T-WEB-ADVISOR, T-WEB-CATALOG and T-INFLUENCER are blocked on app changes, each with a proposal (0017) |
| Each test passes once end to end on the test identities | not yet: no run has happened against the real apps. The seams pass on the local cluster and each journey passes against a simulated app in unit tests; a real run waits for the phase 1 apply and the Setup items (test identities, test runner login); T-ALERT needs only the email key |
| Purge removes every artefact after the window | partly, by design: each run's test leads are soft-deleted through Spark's recycle bin and B2B's deletion with reason "test" (D-071). Nothing is hard-deleted, because B2B's and Spark's rows have no foreign key to the lead; partner-routed test leads are kept until B2B accepts "test" for them; what stays is listed in D-071. A failed purge is retried and ONE-PURGE reports it |
| Phase review | done: `docs/reviews/phase-5.md` (1 blocker, 5 majors, 9 minors), all resolved |
| Click-through still passes (phase 4's criterion) | CLICK-THROUGH PASSED twice running (133 pages, 18/18 writes, only `vault.secrets` changed outside schema one), after `ActionForm` moved off form actions (D-074); the 13 runs before it each lost two to four answers |
| No test row leaks into any app's analytics | each lead test checks B2B's command centre or Spark's analytics against a direct count of real rows; Witty's harness leads are checked as is_test; Eduwit One's own metrics leave test rows out (D-073). Witty has no lead count of its own to check; the website's waits with its tests |

## Phase 6 — AI (built and reviewed; Claude only; live runs wait on phase 1, the deploy and the Anthropic key)

| Criterion | Status |
| --- | --- |
| Worker claims `one.ai_tasks`, routes by settings (Claude only, D-078), validates outputs against schemas, writes only to `one.*` | done: `/api/internal/ai/run`, called by the tick's app call while a task is due (no new cron job); routing per tier from `ai.models` with the fallback tier; zod schemas per kind sent as Claude's structured output and checked again by the worker; `one.ai_finish` files by kind into schema one only (D-075) |
| Task kinds | all eight: classify, triage, explain, propose_fix, propose_feature, test_author, brief, ask; queued by fixed rules (`one.ai_schedule`), never by the AI |
| Budgets | done: from 80% of `daily_cap_inr` only classify and triage run, at the cap nothing, and ONE-01 fires; a call whose worst case passes the per-task cap (over all attempts) or what is left today is not made; calls are recorded as they end; at most `max_parallel` (2) tasks at once (`99_ai_worker.sql`, `worker.test.ts`) |
| PII mask, unit-tested | done: `pii.test.ts` (14 cases), the worker's tests, and the eval's leak check over 70 items on each tier: no planted contact reaches a request or an answer. Ask runs fixed tools, never model-written SQL (D-076) |
| Prompts as markdown, stamped into `prompt_version` | done: `web/lib/ai/prompts/*.md`, `kind@hash`, a unit test fails while the generated module is stale |
| Eval: 30 incidents, 10 questions, `npm run ai:eval` prints scores and cost per tier | harness done and passing offline (100% with the reference answerer, 0 leaks); a scored run waits for the Anthropic key (`--live --yes`, regular tier first, D-078) |
| First brief delivered | not yet: built, filed and mailed on the local cluster (`99_ai_worker.sql`, `alerts.test.ts`); the first real one waits for the phase 1 apply, the key and the prices |
| A proposal of each kind from real data | not yet: each kind is filed on the local cluster from the worker's answers; real ones need production data and the key |
| Spend under cap for 3 days | not yet: needs three days of live runs |
| Phase review | done: `docs/reviews/phase-6.md` (1 blocker, 6 majors, 6 minors), all resolved; every AI proposal is the owner's (D-077) |
| Click-through still passes (phase 4's criterion) | CLICK-THROUGH PASSED after the review's fixes (133 pages, 18/18 writes, only `vault.secrets` changed outside schema one) |

## Phase 7 — Fixes and hand-over (built and reviewed; every fix off; the window starts with the first production tick)

| Criterion | Status |
| --- | --- |
| All fix functions with dry-run | done: the 11 fixes of spec §8 as `one.fix_<id>(incident, dry_run)` over one shell (`one.fix_run`): switch, window, cooldown, rate limit, stop rule, test rows left out, action rows before and after, verification (D-079, D-081). Three cannot act without an app change and propose or wait for the owner (D-080) |
| Fixer grants per fix | done: USAGE on `public`, `b2b`, `b2c` and EXECUTE on the ten catalogue functions, nothing else; the fixer owns only `one.fixer_*`. Settings → Fixes shows each fix's rights and whether the database holds them |
| Fixes settings page with dry-run history | done: Settings → Fixes (each fix's trigger, action, mode, rights, rollback, counts, open incidents with "Dry run now" and "stopped", latest rows, the owner's switch and limits) and Actions with each row's step and verdict |
| Every fix has a dry-run action row from a real or staged incident | done on staged incidents: `99_fixes.sql` records a dry-run row for each of the 11 from incidents with the evidence their checks write. On production, every fix's plan compiles and found nothing to do on 24 Oct; real rows come after the apply |
| The grant guard in `rehearse.sh` blocks a test migration that grants on `student_leads` | done: `guards.test.ts` runs `rehearse.sh` on five bad migrations (a column grant and a table grant on `student_leads`, an EXECUTE grant inside a DO block, a dynamic `execute(...)` column grant, default privileges into `public`), and each is refused before it connects. The fingerprint wrapper refuses the same grants at apply time (`local-test.sh`) |
| All fixes disabled in production at hand-over | done in the seed: every fix ships `enabled: false`, and `one.settings_check` refuses switching one on during the window or without a dry run of its own. The production apply is the owner's (phase 1) |
| `RUNBOOK.md` complete | done: what each check means, what each fix does, how to roll back each migration, how to rotate each secret, how to add a check or a test |
| Two-week observation window started | **waits on the phase 1 apply**: it starts itself on the first tick that runs the fixes, on production the first after the apply, and cannot be backdated or shortened below 14 days |
| 30-minute walkthrough as a checklist | done: `docs/WALKTHROUGH.md` |
| Phase review | done: `docs/reviews/phase-7.md` (1 blocker, 12 majors, 12 minors), resolved; M12 and m2 are the owner's calls, with interim defaults (D-081) |
| Click-through still passes (phase 4's criterion) | CLICK-THROUGH PASSED after the review's fixes (138 pages, 20/20 writes, including a dry run and a fix setting) |
