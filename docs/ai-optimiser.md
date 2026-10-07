# AI Optimiser (Claude: Advisory, Autopilot, Ask the CRM)

Claude watches outcomes, partner effort and money, and recommends bounded changes to the routing engine (spec B7.8.2).
In Advisory mode nothing changes until an Admin approves. Screen: **AI Optimiser** (`/ai`).

## 1. What it does

| Run | When | Model (configurable) |
| --- | --- | --- |
| Light check | Every 15 minutes, **only if new alerts arrived** | `claude-haiku-4-5-20251001` |
| Optimisation | Hourly, **only if decisions or outcomes changed** | `claude-sonnet-5-5` |
| Deep review | Nightly after 01:00 IST | `claude-opus-5-5` |
| Weekly report | Monday after 09:00 IST | `claude-opus-5-5` |
| Event run | See below (at most hourly) | regular |
| Run now | By the Admin | per kind |

Each run reads data through tools, then files a report: a summary, findings and up to 5 recommendations.

- **Nightly and weekly runs keep their schedule.** The deep review runs once per IST day and the weekly report once per
  week; only scheduled runs count, so a deep review or weekly report started with *Run now* does not move or replace
  them. If a run of the same kind is still waiting or running, the scheduler tries again 5 minutes later.
- **Event runs** are queued when, since the last event run, a partner was auto-paused or its status changed, an NCPL
  drop or a model fallback was alerted, a model's status changed (promotion, retirement), a commission rate was created
  or ended or changed from a programme file, or a partner was switched live. A draft programme upload, a live switch
  turned off and switches other than a partner's do not count.
- **Daily budget.** Once today's spend (IST) reaches the daily budget, the scheduler queues nothing more that day, and
  anything already queued (including *Run now*) is skipped, by the worker's next claim or by the next scheduler tick
  (within 5 minutes), so nothing left waiting runs after midnight on the next day's budget. One budget alert is raised
  per day, however often it is hit.

## 2. What it can see and change

**Reads (aggregated and pseudonymised only):** segment and partner scorecards, conversion cohorts, commission rates,
engine settings and their history, model metrics, recent decisions (leads appear as `L-xxxxxxxx`, a hash salted with a
secret kept in the `ai` setting and never shown, so it cannot be traced back to a lead ID), alerts, the uplift against
the holdout, and `run_simulation`. No names, phones or e-mails ever reach Claude.

A tool call with a malformed input (text where a number belongs, a fractional day count, a bad date) gets an error
back as its result, and Claude can correct it; it no longer ends the run. A run may make 40 tool calls; after that every
call answers "tool call limit (40) reached for this run; call submit_report now", so the run can still file its report.

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
2. **Bounds** are checked in the database (`ai_validate_change`); out-of-bounds changes, and changes with a value of the
   wrong type, are refused and listed on the run with the reason. The other recommendations of the run are still filed.
3. **Simulation.** Each setting change is replayed on logged, matured decisions (inverse propensity, using the
   selection probabilities every decision records): NCPL now and with the change, the difference with a 95% interval,
   and how many decisions it rests on. Until leads mature (60 days) there is little to replay and the inbox says so.

In the inbox the Admin approves (optionally editing the value), or rejects with a reason. An approved change is written
to the engine policy as an **AI change**, versioned with the run and the approver; the change log keeps the previous
value for one-click rollback. Recommendations expire after 7 days. A new recommendation on the same lever and target
(segment, partner) supersedes an older open one; a rule draft supersedes only an open draft of the same rule (same
name, ignoring case), so drafts of different rules stay side by side.

## 4. Measuring it honestly

10% of eligible leads (setting `engine_policy.holdout_share`) are a **holdout**: they always use the Admin's settings,
never an AI change, and never the per-lead model. The **AI vs holdout** tab compares realised net commission per matured
lead between the two groups, by month, with a z-score. Until both groups have 30 matured leads, the AI's value is
unproven and the screen says so.

## 5. Setting it up (one time)

1. **Anthropic API key.** In the Vercel project of the B2B CRM, add the environment variable `ANTHROPIC_API_KEY`
   (from console.anthropic.com, an organisation key with zero data retention if available). It is never stored in the
   database or shown in the CRM. A worker without it only reports in (the AI screen shows the key as not seen) and
   claims no run, so queued runs wait instead of failing.
2. **Worker key.** In the CRM, System → API keys: create a key with the scope *AI optimiser worker*. Add it to Vercel as
   `AI_WORKER_KEY`. Redeploy.
3. **Worker address.** AI Optimiser → Settings: enter the CRM's address (e.g. `https://b2b.eduwit.in`). The database
   wakes `/v1/ai/tick` there when a run is queued.
4. **Budget.** Set the daily budget (default $5). Runs stop for the day once it is spent, with one alert a day.
5. **Switch it on** (AI Optimiser → Settings). The Set up card on the Inbox tab shows what is still missing.

## 6. Cost

Runs are priced from the token counts in the run log (input, output, cache reads and cache writes, for failed runs too),
using the per-model prices in US$ per million tokens in the `ai` setting. They are for the log and the daily budget, not
billing; check them against Anthropic's current price list. Defaults:

| Model | Input | Output | Cache read | Cache write (5 min) |
| --- | --- | --- | --- | --- |
| `claude-sonnet-5-5`, `claude-sonnet-5` | $2 | $10 | $0.20 | $2.50 |
| `claude-opus-5-5` | $4 | $20 | $0.20 | $5 |
| `claude-haiku-4-5-20251001` | $1 | $5 | $0.10 | $1.25 |

The prices are edited in AI Optimiser → Settings (0–1,000 per million tokens). Every model chosen for regular, deep and
quick runs needs a price: the save refuses a model without one ("add a price for … first"). A model that is not listed
(for example one changed outside the screen) is priced at the dearest listed rates, so the budget is never
under-counted. Each turn may use up to `max_tokens` (default 12,000, room for adaptive thinking on Opus and Sonnet 5.5).
The system prompt and tool list are cached between turns. Quiet periods cost nothing: light checks run only on new
alerts, and the hourly pass only when something changed. Typical spend with the defaults is a few dollars a day at
most; the daily budget is a hard stop.

## 7. Where it is

Database: `b2b.ai_runs`, `ai_tool_outputs`, `ai_recommendations`, `ai_state`; `ai_tool`, `ai_simulate`, `ai_uplift`
(M26a); the worker API `api_ai_claim / api_ai_tool / api_ai_finish / api_ai_fail`, `ai_price` (a model's price),
`ai_schedule_tick` (every 5 minutes) with `ai_is_trigger_event` (which events queue an event run),
`ai_recommendation_decide`, `ai_recommendation_rollback`, `ai_autopilot_gate`, `ai_overview` (M26b); Autopilot,
`ai_settings_save` and Ask the CRM (M30a). Web: `lib/ai/` (prompts, worker, validator), `app/v1/ai/tick`, `app/(app)/ai`.

## 8. Autopilot (Phase 4)

AI Optimiser → Settings → Mode: **Advisory** (default) or **Autopilot**.

- **When it can be switched on.** Autopilot stays locked until AI-steered leads have beaten the holdout on *realised*
  net commission per matured lead (the same measure as the AI vs holdout tab) over the last 4 weeks of matured leads:
  partner allocations between 60 and 88 days old (`maturity_days` to `maturity_days` + 28), every one of those 4 weeks
  present in both groups, and at least 30 leads in each group. The settings form shows it locked with the current
  figures, and the database refuses the switch ("Autopilot unlocks once AI-steered leads beat the holdout over 4 weeks
  of matured leads"). The check applies only to switching on: other settings can still be saved while in Autopilot, and
  switching back to Advisory is always allowed.

- **What it applies.** Only a *setting* change inside the bounds of section 2, and only when its simulation rests on at
  least 30 decisions, shows at least 3% more net commission per lead (setting `ai.autopilot.min_gain_pct`, 1–50) and
  the lower end of its 95% interval is above zero. At most 3 a day (`max_per_day`, 1–10). Drafts (a rule, a pause) and
  anything below the bar stay in the inbox for the Admin. Qualifying changes are taken oldest first, and those from one
  run in the order the run listed them. `ai_autopilot_tick` runs every 5 minutes.
- **Recorded.** Each change is versioned "by autopilot" with the run, the simulation and the reason, and appears in the
  change log with one-click rollback.
- **7-day review (every applied change, Advisory or Autopilot).** Realised commission cannot exist 7 days after a change
  (leads mature after 60), so the review compares, inside the change's scope, the AI-steered leads routed since the
  change with the holdout leads routed in the same days, on *expected* net commission per lead from the stage each lead
  has reached (the same leading indicators as P̂).
  - Steered clearly worse (z ≤ −1): an autopilot change is **rolled back automatically**; an approved one raises an alert
    and the change log suggests rolling it back.
  - Too few leads: checked again a week later, three times at most, then kept as inconclusive.
- **Kill switch.** Switching the mode back to Advisory stops new automatic changes at once; applied ones stay until
  rolled back.

## 9. Ask the CRM (Phase 4)

AI Optimiser → **Ask the CRM**: a question in plain words ("Which partner had the best SLA compliance last month?").
Claude answers only through the metric layer (`list_metrics`, `query_metric`: the same definitions as the dashboards),
never free SQL and never personal data. Every number in the answer must appear in a tool result; otherwise the answer is
not shown, and the screen lists the numbers that could not be traced. Each answer lists the queries behind it, each a
link to the matching drill-down. Questions are logged as AI runs (kind `ask`), priced and counted against the daily
budget; the last 20 are kept on the tab.
