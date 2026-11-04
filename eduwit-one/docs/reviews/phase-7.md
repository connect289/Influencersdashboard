# Phase 7 (fixes) review

A separate agent reviewed Eduwit One phase 7 on 24 Oct 2026. It worked read-only and adversarially, at commits
`48c9890` and `03bb742` (`52208f1..03bb742`) on `claude/festive-babbage-7yhhx8`, and ran its probes on its own
throwaway cluster.

**Scope.**
- Migration 0019 and its rollback, and the code 0019 calls: 0003's `evaluate` and `settings_check`, 0005's
  `tick_job`, 0010, 0011, 0018, `apply_grants`.
- The guards, the fingerprint and the smoke test.
- `web/lib/fixes`, the n8n and reachability clients, the proposal and Fixes pages.
- D-079 and D-080.
- The B2B and B2C function sources the fixes call (`b2b-crm/`, `b2c-crm/`, read only).

**Method.**
- Ran `scripts/db/local-test.sh` (passed), the tooling tests (19 passed), `tsc` and `npm run check` (186 passed).
- Ran a guard probe and SQL probes A to H, each migration applied inside the fingerprint wrapper.
- Read the code.

**Verdict.** Not ready: 1 blocker, 12 majors and 12 minors.

**Sound:**
- **Rollback.** Its copies of earlier functions are byte-identical to their sources. It leaves nothing behind and
  revokes the fixer's membership and grants.
- **The fixer's rights.** The fixer cannot log in, does not bypass RLS and holds no table privilege. Only the fixer
  can execute its functions. `fix_run`, `fix_act`, `proposal_execute` and `fix_<id>` are executable by postgres only.
- **The API.** Only the five intended functions reach it.
- **Proposals.** Person and AI proposals never run, and fix proposals are the owner's to approve.
- **Dry runs and disabled fixes** call nothing.
- **Over-limit runs** do nothing and open a proposal.
- **Test rows** are left out of the row-picking plans and out of approvals.
- **PII.** Action rows and proposals hold ids and counts only, and results are redacted.
- **App reports.** `app_fix_report` accepts only its two fixes and reports once.
- **The n8n retry** is never retried by the HTTP layer.
- **Claims** use SKIP LOCKED.

## Findings and what was done

| # | Finding | Resolution |
| --- | --- | --- |
| B1 | A forbidden grant passed all three nets. `do $$ begin execute('grant select (id), update (id) on public.student_leads to eduwit_one_fixer'); end $$` gave the guards nothing to see. The fingerprint dropped every `eduwit_one_*` ACL entry and had no column ACLs. Smoke and `99_fixes` looked only at table ACLs. The same shape granted anon the contact columns of `student_leads` | `execute(...)` and concatenated templates count as dynamic SQL and are refused unless they are a reviewed template. The fingerprint includes `attacl` and compares Eduwit One's roles' grants with an allow-list of what the migrations grant. Smoke and `99_fixes` check column privileges for both roles. `local-test.sh` runs 10 bad statements through the wrapper, and each is refused. `guards.test.ts` covers the bypass forms, and `rehearse.sh` refuses five bad migrations |
| M1 | Any `alter default privileges … in schema one` passed, whatever other schemas or grantees it named. One giving the fixer every future table in `public` applied unseen | Default privileges are allowed only in the reader's exact form; anything else is refused (tested) |
| M2 | Approval did not run what the owner saw. A narrowing edit was ignored, and a tick refreshing the open proposal between view and click widened the run | Rows run = proposed ∩ submitted ∩ still qualifying. `approved_rows` and `approved_change` are kept. Tested: shown [5, 6], refreshed by the tick to [5, 6, 7, 8], approved with 6 removed and 2 and 3 added: only 5 ran |
| M3 | Over-limit FIX-OUTBOX-W2 and FIX-CACHE-W2 got an `execute` part and the "approving runs it" text. Approving ran nothing and left the proposal approved for good. CACHE-W2 with two expired caches lost its Witty advice | Propose-only fixes never go over their limit and carry no execute part; their own rationale is always shown |
| M4 | `check_result.ok` was true with nothing shown: n8n's plan hid retried ids, a check error read as ok, and B2B counted pending as ok | `one.fix_rows_state` reads each row's own state: B2B delivered, website done, n8n retried with none failed or skipped. `ok` is null when nothing can be read, and `{ran: false, why}` when nothing ran. Tested: refused, still sending, then delivered |
| M5 | "Held" was recorded with no evidence: no check run was needed, and a skipped or erroring check gave held | Only the first check run at or after `verify_at` judges. Ok means held. Error or missing source, or no run by the cooldown plus two cadences, means unverified (D-081 (3)). Tested |
| M6 | One failing result escalated once per pending run: two fixes on one check took a P3 to a P1 | Escalation happens once per failing check run (keyed by the judging result). Tested |
| M7 | One verification error stopped every verification and proposal check, every tick | Each run is judged in its own block, and an error writes an unverified row. Proposal checks run in their own block. Tested with bad evidence |
| M8 | The fixes ran inside the app call's transaction with no lock timeout. A fix waiting on an app row lost that minute's app call and repeated every minute | The fix step runs after the app call in `one.tick_job()`, one commit per fix, with `checks.lock_timeout` before each act. `query_canceled` is caught per fix. Tested: the act sees `lock_timeout` 2 s |
| M9 | A claimed run without a report was handed out again after 5 minutes, so n8n executions could be retried twice | A run is claimed once. One unreported is closed as unknown at the next claim, and its ids count as sent. Tested |
| M10 | Retrying never stopped: after a failed verification the next cooldown ran the fix again (only FIX-CURSOR-B2C stopped). FIX-N8N-RETRY retried its own failed retries | Stop rule: after a run did not hold, the fix stays off that incident, and only an approval runs it again. The probe reports `retries_15m`, which the plan leaves out, and the runner never POSTs a retry. Rows and ids an earlier run sent are left out. Tested |
| M11 | Cooldown holes: approved and hand-called runs were not counted | Every real run counts, whoever made it. It stays per fix, not per incident, because each act is app-wide (D-081 (1)). Tested |
| M12 | Spec §8: approving "everything else" executes the RPC with a `check_due_at`. Only fix proposals ran, while person and AI proposals got a `check_due_at` nobody ever verified | **Owner's call.** Interim: only fix proposals execute. Others record the decision and get no `check_due_at`; a fix proposal that ran nothing says why in `check_result` (D-081 (4)) |
| m1 | A partial B2B approval read "Approved and run". Its result was not redacted, and the website logged a system actor | `partial` is in the result, and the message names refused rows. The result is redacted. The approver's id is passed to `web_outbox_retry` |
| m2 | The rate limit means nothing for count-one fixes that touch many rows (`inbox_retry(50)`, `outbox_unstick()`), and they include test rows | **Owner's call**, default accept: they do what the app's own retry would. Documented in the catalogue, the runbook and D-081 (9) |
| m3 | "Real runs" counted proposals and timeouts | Only acted runs count. Proposals, held and escalated are counted separately (page and brief) |
| m4 | The proposal banner was wrong for app fixes and showed "0 rows" for CACHE-W2 | Worded by mode (B2B's function under your session, the fixer's rights, or queued for the app), with the narrowing rule. Propose-only fixes have no banner |
| m5 | A fix switched off still had its queued app runs carried out | The claim closes a tick's run of a fix switched off since then as skipped |
| m6 | Ids out of time or not configured were never retried. The app did not check an execution's workflow, and it claimed after its deadline | Every id not POSTed is reported as `skipped` with a reason and planned again. The runner reads each execution (workflow, status, retry) before POSTing and claims nothing after its deadline. Tested |
| m7 | "Answers" counted 3xx, 401 and 404 | A 2xx, or 400, 401, 403, 405, 415 or 422, shows the route is there. A redirect, 404 or 5xx does not. Tested |
| m8 | The owner could end the window in one write | `observation_days` 14–90; `observation_started_at` write-once |
| m9 | Guard gaps: CREATE inside DO, any overload, `alter schema one owner`, `reassign owned`, forbidden tables as a word list | CREATE must be taken back in the same file; EXECUTE matches exact signatures; the two statements are refused; the bodies of functions handed to the fixer may call only catalogue functions |
| m10 | Least privilege overstated: the fixer holds PUBLIC's grants, and two granted functions take any path | Documented (D-081 (8)). PUBLIC's grants are reachable only through the fixer's own bodies, which the guards restrict. Its functions pass fixed paths |
| m11 | postgres stays a member of the fixer; the comment said otherwise and no test asserted it | Comment corrected. Smoke asserts no membership of or in the fixer except the migrating user's |
| m12 | B2B-01's new SQL was not re-run on production. FIX-OUTBOX-B2B picked failed rows still inside B2B's backoff | Re-run read-only on 24 Oct: ok (`CHECK-TRIAL.md`). The plan picks dead deliveries, and failed ones older than an hour |
| Tests | Column grants, edits that remove rows, refreshes, unhappy `check_result`, double escalation, held without a run, a failing verification row, re-claim, lock waits; `rehearse.sh` with plain forms only; smoke blind to nested errors | All added in `99_fixes.sql`, `guards.test.ts`, `run.test.ts` and `labels.test.ts`. The tick's report has a top-level `fixes_error` |

## After the fixes

- `scripts/db/local-test.sh`: LOCAL TEST PASSED, both passes, including "the fingerprint wrapper refuses grants the
  migrations do not make" and "rollback left nothing behind".
- Tooling: 22 tests passed, typecheck clean, guards passed (40 files), generators current.
- Web: `npm run check` passed (190 tests).
- `e2e/run.sh`: CLICK-THROUGH PASSED (138 pages, 20/20 writes).
