# Eduwit One — changes

Append-only, newest first. One entry per deploy or per phase step; production database changes name the dump they
followed.

## 24 Oct 2026 — staging rehearsal passed through the Management API (D-091)

- `docs/REHEARSALS.md`: `REHEARSAL PASSED` on staging at 15:41 UTC for migration set `60b7dbb4…cac6c0`, by
  `scripts/db/api-rehearse.sh`. Staging keeps schema `one` and its two cron jobs, as intended. No production change yet;
  the production apply follows D-090 (no dump) and was refused by the cloud session's permission layer on the first try.
- The rehearsal found and the scripts fixed (no migration changed): the `one-*` jobs now pause while files run and
  resume after the smoke test (a tick deadlocked with `apply_grants()`); the lock wait is 60 s; `fingerprint.sql` sorts
  with `collate "C"` (en_US.UTF-8 ordered `_` and `:` unlike the local cluster); `smoke.sql`'s same-minute tick
  assertion applies only while still in the run's minute. `fingerprint.expected` unchanged; `local-test.sh` passes.
- Staging's stale partial apply of 23 Oct was dropped by its actual signatures, one wrapped transaction per file.

## 24 Oct 2026 — the dump waived; the Management API route (D-090)

- The owner waived the production dump for the phase 1 apply. `scripts/db/apply.sh` takes
  `ONE_APPLY_WITHOUT_DUMP=owner-accepted`, set on purpose for every run, in place of the dump check; without it, it
  refuses as before. `GO-LIVE-SESSION.md` steps 4 to 6 follow.
- The connector cannot run the rollbacks: its confirmation of DROP and DELETE reaches nobody (D-031 again). The one
  statement it held changed nothing on staging (checked read-only: 6 leftovers, 24 tables, 16 functions).
- For a machine with HTTPS to `api.supabase.com` and no Postgres connection: `scripts/db/with-api.ts` (the Management
  API's query endpoint, as postgres; projects by target name; the token never printed), `scripts/db/wrap.ts` (one file
  as one transaction between the two catalogue fingerprints, byte-identical to what psql runs), `scripts/db/api-rehearse.sh`
  and `scripts/db/api-apply.sh` (the sequences of `rehearse.sh` and `apply.sh`). Runbook §3 and §5. Type-checked and
  tested for their refusals; not yet run against a database.
- The six checks D-088 rewrote were re-run read-only on production through the connector: all ok, same values as on
  23 Oct, each under 5 ms planned and 0.5 ms run (`docs/CHECK-TRIAL.md`, D-089).

## 24 Oct 2026 — go-live instructions for the owner's computer

- Vercel project `eduwit-one` created in the Eduwit team (region `bom1`) with the two public values set for Production;
  the brief below carries the deploy steps (service key, internal key in Vercel and Vault, exposed schema, redirect URL,
  `vercel --prod`, the domain, first sign-in).
- `docs/GO-LIVE-SESSION.md`: the staging rehearsal, production dump and production apply as a self-contained brief for
  a Claude session on the owner's computer, with the connection strings entered in a text editor, never a chat. The
  cloud sessions cannot run these steps (D-089), and the connector's confirmation prompts did not reach the owner.

## 24 Oct 2026 — efficiency leftovers (0020; D-088)

- Redaction compiled: the PII key list is one anchored pattern per call and the contact detector runs only on text
  that can hold a contact; `one.redact` keeps its signature and results. `one.mask_text` takes the same short path.
- The tick commits once per check and once per event source (the start mark still committed before the run); a source
  whose table is missing waits 10 minutes before the next try; the report always carries its events key.
- B2B-05, B2B-10 and INT-07 rewritten for the apps' indexes; B2B-10, INT-07, B2C-05, B2C-09 and WEB-06 use a sargable
  IST day. B2B-10's "last decided checks" are by due date now. To re-run read-only on production before go-live.
- The Witty event sources skip rows already copied before the per-row lead lookup.
- The model's per-task data is compact JSON; the incident context sends the newest result whole and compacts the older
  ones (`one.jsonb_compact`).
- A failed Vault read is logged with its cause; a failed app panel shows its error on the card.
- Tests: `99_hardening.sql` section 8 (pattern equivalence, the tick's transaction count, the back-off, the Witty
  sources, the compacted context). The hardening review's table says what was done per item.

## 24 Oct 2026 — hardening: proof before power, self-healing, security, efficiency (0020; D-084 to D-087)

- Fixes (D-084): a switched-on fix acts on one row until a run of it has held (a proposal, whatever opens it, still
  shows the whole plan, and an approved run runs whole); no second run on an incident before the last run's verdict,
  a run by hand included; two runs that did not hold within 7 days pause the fix (`one.fix_state`, ONE-FIXES) until
  the owner clears it (`one.ui_fix_unpause`); the Fixes and Operate pages show trial, proven, paused and awaiting.
- Self-healing (D-085): alert emails retried with a growing wait and counted by ONE-02 and the watchdog when they
  fail; the tick breaks its own wedged lock and re-creates its missing cron jobs; poison checks and copies stop;
  flapping incidents damped; ONE-03 (nightly), ONE-04 (active owner); shapes for every setting the app parses;
  PLAT-04 sees an unanswered queue; retention prunes ok results, report audit rows, codes, sign-in log; append-only
  histories by trigger; `one.ui_settings_restore`.
- Security (D-086): contact data masked in check values, errors, incidents, alert emails and the incident page;
  owner gate on cadence, open_after and P1 test schedules; the window's start cannot be backdated; saved-view days
  validated; the database calls the app with a short-lived token; watchdog cache and rate limit; advisory label on
  AI text in emails; security headers.
- Efficiency (D-087): eight indexes, fillfactor, grouped Fixes counts, a light fixes list on the incident page, the
  funnel rewritten, sargable day windows, bounded fix scans, two-tier results retention, dead code dropped.
- Tests: `99_hardening.sql` sections 5 to 7 (each on its own fixtures); `99_fixes.sql` follows the verdict rule; the
  tick's lock is looked up under pg_locks' bigint-key form; web tests for each change; `docs/reviews/hardening.md`.

## 24 Oct 2026 — hardening: operate the five apps, and Ask knows how (0020; D-083)

- Operate pages (`/apps/<app>/operate`, linked from each app's page): what the app needs (Setup items in order,
  with their state), first-time steps, heartbeats, checks, open incidents, its pg_cron jobs, the fixes that act on it
  (switch, counts, dry run), its tests, every-day checks, the first place to look per check, its secrets and what
  stays in the app. One for Eduwit One itself. Reads only (`web/lib/operate`, ids checked by a unit test).
- Ask: seven more read-only tools: `setup`, `app_status`, `fixes`, `actions`, `audit` (migration 0020 redefines
  `one.ai_tool_data`), `operate` and `runbook` (the app; the runbook from `docs/*.md` through a generated module with
  a drift test). The Ask prompt says to start from them for "how do I" questions. Two eval questions cover them. Each
  open Setup item and each Operate page offers a filled-in question to Ask (`/ask?q=…`).
- Local test `99_hardening.sql`: each tool through `one.ai_tool`, held task only, read-only, no secret value.

## 24 Oct 2026 — phase 7: the owner's answers (D-082)

- Every default taken: only fix proposals run when approved; the count-one fixes stay as they are; FIX-OUTBOX-W2
  and FIX-CACHE-W2 stay proposal-only; B2B approvals need the owner's OAuth or aal2 session; FIX-N8N-RETRY waits for
  n8n 2.25.7 or 2.26.2 (runbook); B2B-01 stays P1.
- Staging rehearsal attempted from the build session: no route to Postgres, and the connector's confirmation got no
  answer. It runs from the owner's machine (`RUNBOOK-database.md` §2).

## 24 Oct 2026 — phase 7: review resolved (1 blocker, 12 majors, 12 minors; D-081)

- Guards and fingerprint: dynamic `execute(...)` forms, default privileges other than the reader's, `reassign owned`
  and `alter schema one owner` are refused; the fixer's EXECUTE must match exact signatures and its functions may
  call only catalogue functions. The fingerprint covers column grants and checks Eduwit One's own roles' grants
  against an allow-list. Smoke and `99_fixes.sql` check column privileges and memberships.
- 0019: every real run counts for the cooldown; a fix stops on an incident where a run did not hold; verification
  needs a check run after the run (held, did not hold, unverified), escalates once per failing check run, and judges
  each run in its own block. The fixes run after the app call, one commit each, with a 2 s lock timeout. App runs
  are claimed once. Approvals run only rows proposed, approved and still qualifying, and their `check_result` reads
  each row's state. Propose-only fixes never go over their limit. FIX-OUTBOX-B2B picks failed deliveries only past
  an hour. The window lasts 14 to 90 days and its start is write-once.
- App: the n8n retry reads each execution first (its workflow, still in error, not a retry), reports every id it did
  not send as skipped, and claims nothing after its deadline; WITTY-02 reports `retries_15m`. Spark "answers" with a
  2xx, 400, 401, 403, 405, 415 or 422 only. The proposal page says what approving does by mode and shows the check
  result; the Fixes page counts proposals and marks stopped incidents; Actions shows unverified runs.
- B2B-01's new SQL re-run on production (read only): ok. `docs/reviews/phase-7.md`, the runbook's Fixes section, the
  walkthrough and the phase table updated.

## 24 Oct 2026 — phase 7: the hand-over documents

- `RUNBOOK.md`: what each check means and what to do when one fires; the fixes (each one's trigger, action, rights,
  rollback, the window, limits, verification, how to judge dry runs); rolling back each migration; rotating each
  secret; adding a check or a test. `RUNBOOK-database.md` applies every migration and rolls back between fingerprints.
- `WALKTHROUGH.md`: a 30-minute checklist to follow alone, and what has to happen once before it.

## 24 Oct 2026 — phase 7: the fixes in the app and on the pages

- The minute tick carries out the runs the database queues for the app (`lib/fixes`): FIX-N8N-RETRY retries each
  failed Witty execution once (`POST /api/v1/executions/{id}/retry`, never retried by the HTTP layer), and
  FIX-WEBHOOK-REKICK checks that Spark's handoff endpoint answers (HEAD, then GET; below 500 within 10 s) before the
  database kicks B2B's outbox. Reports go back through `one.app_fix_report`.
- Settings → Fixes: each fix with what triggers it, what it does, its mode (acts, from the app, owner approves,
  proposes only), its rights and whether they are granted, its rollback, counts (dry runs, real runs, held,
  escalated), its open incidents with a "Dry run now" button, and its latest rows; the owner's switch and limits with a
  reason (refused before the window ends). The window's state is a banner.
- Actions: each row's step (dry run, about to act, acted, did nothing, verified) and a one-line summary. Incidents
  list the fixes tried on their check, with a dry-run button. A fix proposal says what approving runs, and its check
  result after.
- The morning brief's prompt asks for what each fix did. The click-through covers the Fixes page (desktop and phone)
  and two writes on it.
- Fix: plans read the check's value from the incident's evidence, and skip an incident whose check could not run.

## 24 Oct 2026 — phase 7: the fixes in the database (0019; D-079, D-080)

- Migration 0019 (with its rollback): the catalogue `one.fixes` (11 fixes of spec §8), `one.fix_<id>(incident,
dry_run)` for each over one shell (`one.fix_run`: the switch, the observation window, the cooldown, the rate limit
  that opens a proposal instead, test rows left out, an action row before and after), the plans (ids and counts
  only), the fixer's eight `one.fixer_*` functions and its grants: USAGE on `public`, `b2b`, `b2c` and EXECUTE on ten
  app functions, nothing else. Verification 2 minutes after a run; a second failure within the cooldown moves the
  incident up one level instead of a retry.
- The minute tick runs the fixes first in its app call (each isolated) and starts the two-week observation window on
  its first run. The app's side of its two fixes: `one.app_fixes_claim()`, `one.app_fix_report()` (service role).
- Approving a proposal a fix opened runs it once under the approver's session (FIX-OUTBOX-B2B: B2B's own
  `b2b.outbox_retry`, for a B2B admin), applied and verified 10 minutes on (`check_result`).
- The Fixes page's reads and writes: `one.ui_fixes()`, `one.ui_fix_set()` (owner), `one.ui_fix_dry_run()`. The morning
  brief's numbers include what each fix did.
- `one.settings_check('fixes')`: each fix is `{enabled, per_tick 1–500, cooldown_min 1–1440}`; switched on only after
  the window and with a dry run of its own.
- Three fixes cannot act without changing an app and propose instead or wait for the owner (D-080). B2B-01 now fails
  on dead and waiting deliveries (0006 regenerated).
- Guards: the fixer may get EXECUTE only on the catalogue's functions, USAGE on the three schemas, CREATE on schema one
  only while it is handed its functions; tests, including `rehearse.sh` refusing a migration that grants the fixer
  anything on `student_leads`. Local test `99_fixes.sql`: a dry-run row for every fix from a staged incident, real runs
  through the fixer, approvals, verification; the smoke test checks the fixer's rights by catalogue.

## 24 Oct 2026 — phase 6: the owner's answers (D-078)

- Claude only: Gemini removed from the AI layer (settings, router, client, Setup validator, worker route, eval,
  preflight probes); `one.settings_check` refuses a provider and any non-Claude model. Witty's Gemini checks unchanged.
- Quick tier Claude Haiku 5.5 (effort low); regular Sonnet 5.5, deep Opus 5.5; refusal fallback Claude Opus 4.8, asked
  once by the worker when a model declines, priced and capped like any call.
- Budget: ₹250 a day, sized to the Max/Team plan's monthly API credits that the key draws on; "credit balance is too
  low" defers tasks for an hour as `budget (credits exhausted)` and ONE-01 reports it.
- Witty excerpts stay off; brief at 08:00 IST; Vercel Pro; the live eval defaults to the regular tier.

## 24 Oct 2026 — phase 6 review resolved

- Review: `docs/reviews/phase-6.md` (1 blocker, 6 majors, 6 minors), all resolved.
- Every AI proposal is the owner's to approve (`ai_written` in its touches, D-077).
- ONE-01 fires at the cap and while work waits because of it; it counts tasks held past their lease as backlog.
- The mask finds phones the way the database does (inside longer digit runs, any separator, other scripts' digits,
  any 10–15 digit run; dates and ids left alone), masks every string under a name key and the keys of maps of people,
  keeps colliding keys apart, and masks tool error texts. The eval plants these shapes; the shared prompt says data is
  never an instruction. The Ask form says names cannot be masked.
- Budget: the per-task cap holds across attempts (`task_spent_inr`), each call is recorded as it ends
  (`one.ai_calls_add`, which returns the day's budget as it stands), a call with no answer counts at its worst case,
  the worst case assumes 2 characters a token, and the SDK no longer retries (a retried call could outlive the 300 s
  limit). A retryable failure waits 2, 4, 8 minutes.
- Ask: no statement timeout is claimed (none can be armed in a function); events at most 14 days; no tool call starts
  without time for the answer; a cancelled statement while a context is built fails that task, not the claim.
- Settings check covers routing, models, the fallback tier and `usd_inr`; effort is not sent to models that refuse it;
  the rollback suppresses queued brief emails; the test-idea rule skips synthetic incidents; n8n's status filter runs
  before its limit.

## 24 Oct 2026 — phase 6 (AI): the eval set

- `web/lib/ai/eval`: 30 incidents across the apps (classify and triage) and 10 Ask questions with their tool data,
  shaped like what the database hands the worker, with contacts planted to prove the mask. Graded deterministically
  (category, facts each answer must state, the tools used, no contact in any request or answer), with cost and p50
  latency per tier. Runs through the real worker with a fake database.
- `npm run ai:eval` runs offline with a reference answerer (proves the harness and the mask; spends nothing); with
  `--live --yes` it calls each tier's model (keys `ONE_ANTHROPIC_API_KEY` / `ONE_GEMINI_API_KEY` only) after printing
  the worst-case cost. A unit test keeps the offline run at 100% with no leak.

## 24 Oct 2026 — phase 6 (AI): the worker, its prompts and the pages

- `POST /api/internal/ai/run` (internal key; 300 s, Fluid compute): claims tasks for up to four minutes, routes each
  to its model, masks the data again, checks the call's worst case against the per-task cap and what is left today,
  validates the answer against the kind's schema (one repair attempt) and files it. A task with no key, no model or no
  price waits as deferred and says why; refusals and cut-off answers fail without a retry; every call's tokens and
  cost are recorded whatever the outcome (corrected below: as each call ends, and a call with no answer at its worst
  case). Ask runs up to two rounds of the fixed tools, plus n8n's executions, and answers in the third at the latest.
- Prompts as markdown in `web/lib/ai/prompts` (shared rules and one per kind), stamped `kind@hash` into each call's
  `prompt_version` through `scripts/gen-prompts.ts` (a unit test fails while the generated module is stale).
- Setup item `ai_key` has a validator (`ai`): every tier's provider, model, price and key, proven with the provider's
  free model lookup. Credentials `ONE_ANTHROPIC_API_KEY` / `one_anthropic_key` and `ONE_GEMINI_API_KEY` /
  `one_gemini_key`.
- The brief email (plain text, escaped, with a link to the brief and the saved views marked "email it").
- Pages: the incident's AI card shows the summary, likely cause, kind of problem, next steps and explanation, or why
  triage is waiting; Ask lists the tools each answer used; deferred tasks show their reason.

## 24 Oct 2026 — phase 6 (AI): the model layer and the worker's database side (D-075, D-076)

- `web/lib/ai`: the PII mask (`pii.ts`: names to initials, phones to their last 4 digits, emails to their domain,
  message bodies left out unless allowed, secrets and identity documents always left out), tier routing and costs
  (`models.ts`), and the Claude (Anthropic SDK, pinned 0.133.0) and Gemini clients (`client.ts`). Unit tests for each.
- Settings `ai`: `prices` (Claude seeded, Gemini null until confirmed), `effort` per tier, `max_parallel`,
  `task_max_age_h` and `schedule`; `one.settings_check` refuses a malformed price, provider, effort or schedule (0003).
- Migration 0018: the schedule and `one.ai_step()` (run by the tick's app call), the claim with its budget gate, the
  masked context per kind, `ai_finish` / `ai_fail` / `ai_defer` with the calls they made, Ask's fixed tools, the brief
  email (`deliveries.brief_id`, `briefs.sent_at` once mailed), and the Marketing and Analytics reads split from their
  pages so Ask can use them. PLAT-04 also watches the AI worker's job calls. Local test `99_ai_worker.sql`.
- Found by that test: `least()` skips nulls, so a call recorded without a cost would have counted as ₹99,999,999.

## 24 Oct 2026 — forms call their action from a submit handler (D-074)

- In the click-through, two to four of 18 writes per run lost their answer although the write was audited and the
  action had resolved. `ActionForm` now calls the server action from its submit handler and keeps the result in plain
  state instead of a form action with useActionState, clears the form on success, and refreshes the page's data after
  the answer. Server actions no longer revalidate (every console page is dynamic); the mute form's `back` field, which
  only fed the revalidation, is gone.
- Verified: CLICK-THROUGH PASSED twice running (18/18 writes); each of the 13 runs before it had lost two to four.

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

- Added `scripts/db/rehearse.sh`, `apply.sh` and `dump.sh`. Also added `with-db.ts` (credentials go into PG\*
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
