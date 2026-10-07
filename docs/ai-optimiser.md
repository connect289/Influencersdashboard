# AI Optimiser (Claude, Advisory mode)

Claude watches outcomes, partner effort and money, and recommends bounded changes to the routing engine (spec B7.8.2).
In Advisory mode nothing changes until an Admin approves. Screen: **AI Optimiser** (`/ai`).

## 1. What it does

| Run | When | Model (configurable) |
| --- | --- | --- |
| Light check | Every 15 minutes, **only if new alerts arrived** | `claude-haiku-4-5-20251001` |
| Optimisation | Hourly, **only if decisions or outcomes changed** | `claude-sonnet-5-5` |
| Deep review | Nightly after 01:00 IST | `claude-opus-5-5` |
| Weekly report | Monday after 09:00 IST | `claude-opus-5-5` |
| Event run | A partner auto-paused, an NCPL drop, a model change, a rate or partner change (at most hourly) | regular |
| Run now | By the Admin | per kind |

Each run reads data through tools, then files a report: a summary, findings and up to 5 recommendations.

## 2. What it can see and change

**Reads (aggregated and pseudonymised only):** segment and partner scorecards, conversion cohorts, commission rates,
engine settings and their history, model metrics, recent decisions (leads appear as `L-xxxxxxxx`), alerts, the uplift
against the holdout, and `run_simulation`. No names, phones or e-mails ever reach Claude.

**Can propose:**

| Lever | Bounds |
| --- | --- |
| Exploration share for a segment | 0–50% |
| Maturity window | 30–90 days |
| Recency half-life | 14–60 days |
| Prior strength | 5–50 leads |
| Segment mode pin | Expires within 30 days |
| Speed and reliability factors | On or off |
| Temporary partner weight | ±10%, up to 14 days |
| Share cap for a segment | 50–100% |
| Routing rule, partner pause | Drafts: a rule is created **inactive**; a pause happens only on approval |

**Can never touch:** consent, duplicate and attempt rules, the B2C fallback, capacity and contracts, commission rates,
live switches, students or partners. The database refuses anything else, whatever the model writes.

## 3. How a recommendation is checked

1. **Every number comes from a tool.** The worker compares each number in the report with the tool results of that run
   (rounding and percentages allowed). If any number cannot be traced, the whole run is filed as *rejected* and nothing
   reaches the inbox.
2. **Bounds** are checked in the database (`ai_validate_change`); out-of-bounds changes are refused and listed on the run.
3. **Simulation.** Each setting change is replayed on logged, matured decisions (inverse propensity, using the
   selection probabilities every decision records): NCPL now and with the change, the difference with a 95% interval,
   and how many decisions it rests on. Until leads mature (60 days) there is little to replay and the inbox says so.

In the inbox the Admin approves (optionally editing the value), or rejects with a reason. An approved change is written
to the engine policy as an **AI change**, versioned with the run and the approver; the change log keeps the previous
value for one-click rollback. Recommendations expire after 7 days.

## 4. Measuring it honestly

10% of eligible leads (setting `engine_policy.holdout_share`) are a **holdout**: they always use the Admin's settings,
never an AI change, and never the per-lead model. The **AI vs holdout** tab compares realised net commission per matured
lead between the two groups, by month, with a z-score. Until both groups have 30 matured leads, the AI's value is
unproven and the screen says so.

## 5. Setting it up (one time)

1. **Anthropic API key.** In the Vercel project of the B2B CRM, add the environment variable `ANTHROPIC_API_KEY`
   (from console.anthropic.com, an organisation key with zero data retention if available). It is never stored in the
   database or shown in the CRM.
2. **Worker key.** In the CRM, System → API keys: create a key with the scope *AI optimiser worker*. Add it to Vercel as
   `AI_WORKER_KEY`. Redeploy.
3. **Worker address.** AI Optimiser → Settings: enter the CRM's address (e.g. `https://b2b.eduwit.in`). The database
   wakes `/v1/ai/tick` there when a run is queued.
4. **Budget.** Set the daily budget (default $5). Runs stop for the day once it is spent, with an alert.
5. **Switch it on** (AI Optimiser → Settings). The Set up card on the Inbox tab shows what is still missing.

## 6. Cost

Runs are priced from the token counts in the run log, using the per-model prices in the `ai` setting (check them against
Anthropic's current price list; they are for the log, not billing). The system prompt and tool list are cached between
turns. Quiet periods cost nothing: light checks run only on new alerts, and the hourly pass only when something changed.
Typical spend with the defaults is a few dollars a day at most; the daily budget is a hard stop.

## 7. Where it is

Database: `b2b.ai_runs`, `ai_tool_outputs`, `ai_recommendations`, `ai_state`; `ai_tool`, `ai_simulate`, `ai_uplift`
(M26a); the worker API `api_ai_claim / api_ai_tool / api_ai_finish / api_ai_fail`, `ai_schedule_tick` (every 5 minutes),
`ai_recommendation_decide`, `ai_recommendation_rollback`, `ai_settings_save` (M26b). Web: `lib/ai/` (prompts, worker,
validator), `app/v1/ai/tick`, `app/(app)/ai`.

Autopilot (changes inside the bounds applied automatically when the simulation shows at least a 3% gain, at most 3 a
day, re-checked after 7 days and rolled back if worse) is Phase 4.
