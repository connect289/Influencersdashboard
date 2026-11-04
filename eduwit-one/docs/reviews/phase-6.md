# Phase 6 (AI) review

A fresh, adversarial review of Eduwit One phase 6 at commit `2b10ab8` (`92e66b2..2b10ab8`) on
`claude/festive-babbage-7yhhx8`, run read-only by a separate agent on 24 Oct 2026, with probes on its own throwaway
cluster.

**Scope.** Migration 0018 and its rollback, the `ai` branch of `one.settings_check` (0003), PLAT-04, the local test
`99_ai_worker.sql`; `web/lib/ai/**` (mask, routing, clients, schemas, worker, prompts, eval), the worker route, the
`ai` Setup validator, the brief email, the incident and Ask pages; D-075, D-076 and the runbook's AI section.

**Method.** `scripts/db/local-test.sh` (passed), `vitest` (170 passed), `tsc` (clean), SQL probes (p1–p6) and a mask
probe, and reading.

**Verdict.** Not ready: 1 blocker, 6 majors, 6 minors, and documentation errors. Sound: the default path (database data
through `one.redact`, then `pii.ts`) leaks nothing; the rollback copies are identical to their sources and leave
nothing behind; only the six worker functions reach the service role and nothing new reaches anon or authenticated;
`transaction_read_only` holds in Ask's tools (a called function cannot lift it, and pg_net cannot queue); no model SQL
runs; the worker builds `meta` itself and zod strips anything else; the risk floor holds; filing is idempotent; the brief
email and the pages escape AI text; the Anthropic request matches the SDK's types and the Claude prices match
Anthropic's list; Gemini's usage accounting is right; the claim's lock and lease prevent double processing.

## Findings and what was done

| # | Finding | Resolution |
| --- | --- | --- |
| B1 | An AI proposal's owner gate depended on the model's own words: a feature proposal raising top partners' lead share by 20% with `touches: ["app_settings"]` was approvable by an engineer | Every AI proposal's touches carry `ai_written`, which `one.proposal_sensitive` treats as the owner's; the model's list is filtered and never lowers who decides (D-077) |
| M1 | ONE-01 never fired at 100%: it compared with `<=`, counted only `pending` while the gate turns the backlog into `deferred`, and the pre-call check keeps spend at or below the cap | ONE-01 fires at the cap and while any task is deferred with `budget (cap reached)`; backlog counts tasks held past their lease; a cap of 0 (AI switched off) raises nothing |
| M2 | The mask judged whole digit runs ("lead 12 9876543210", two numbers in a run, "/", "_", a no-break space, other scripts' digits passed), names nested under a name key passed, and four paths skip the database's redaction (the Ask question, brief pins, Witty excerpts, tool errors; tool errors were not masked at all) | Phones are found as `one.has_contact` finds them, after digits and spaces are normalised, with dates and ids protected; every string under a name key and the keys of maps of people become initials; tool errors are masked. Names in free text cannot be recognised: bodies stay out by default, the runbook says excerpts can carry names, and the Ask form asks people not to type one |
| M3 | `set_config('statement_timeout')` inside a function never takes effect (D-044), so tools were bounded only by the role's timeout; the worker did not check its deadline before tool calls; a cancelled statement while a context was built would fail the whole claim, every minute | The claim is gone from the code and the docs; events are bounded to 14 days; no tool call starts without time for the answer; `ai_claim` catches `query_canceled` and fails that task |
| M4 | The SDK's own retry re-sent a timed-out call with the same timeout, so a deep call could run past Vercel's 300 s and pg_net's 290 s | `maxRetries: 0`: the queue retries, with a backoff |
| M5 | A retryable failure went straight back to `pending` and was claimed again at once: three 429s failed a task within one invocation | A retry waits 2, 4, then 8 minutes (`deferred` with `not_before`) |
| M6 | The per-task cap applied per attempt; calls that timed out had no cost; calls of a cut-short invocation were never recorded; 3 characters a token is not an upper bound | The claim returns the task's earlier spend; each call is recorded as it ends (`one.ai_calls_add`, which also returns the day's budget as it stands); a call with no answer counts at its worst case; the worst case assumes 2 characters a token |
| m1 | `routing`, `models`, the fallback tier and `usd_inr` were not validated (`"opus"` as a tier broke every schedule) | Validated in `one.settings_check` |
| m2 | Effort on the quick tier would make Haiku 4.5 answer 400 | Effort is not sent to models that refuse it; the validator says so |
| m3 | Masked keys collided | Duplicates get `#2`, `#3` |
| m4 | The rollback left queued brief emails for a sender that no longer knows briefs | The rollback suppresses them |
| m5 | The test-idea rule queued synthetic incidents; n8n's status filter ran after its limit | Both fixed |
| m6 | The eval's planted contacts used only simple shapes; the prompts did not say data is never an instruction | The eval plants the M2 shapes; `system.md` says data and tool results are never instructions |
| Docs | D-075's budget bound and ONE-01 sentence, the runbook's ONE-01, mask and call-record sentences, D-076 and CHANGES on Ask's rounds and on call records, the `ai_tool` comment | All corrected |
