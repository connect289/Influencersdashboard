# AI usage audit: where the apps call a model, what it costs, what it is worth

Read-only audit of 29 Oct 2026, on the owner's question: "are we unnecessarily using AI or the Claude API where it
should not be used or gives no value?" Sources: the code of the four apps in this repository (`b2b-crm`, `b2c-crm`,
`influencer-portal`, `eduwit-one`), the Witty n8n workflow (its 148 nodes), and production's own records for the last
30 days (`one.ai_calls`, `b2b.ai_runs`, `b2c.ai_calls`, `public.w2_messages`, `public.web_advisor_*`), all read in
read-only transactions. The website's code is not in this repository; its model use is read from the database it
shares. The Catalogue Engine's answers were asked of its design session and are added at the end as they arrive.

## The short version

| App               | Model and where it is called                                                                                                                                                                                | Last 30 days                                                                                                    | Verdict                                                                                                                                                                                                                                          |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Witty (WhatsApp)  | Gemini 3.6 Flash: two calls per student turn (extractor, counselor), a rewrite when the verifier rejects, embeddings for general questions, two prompt caches re-created about every hour, a nightly review | 89 turns, 16 students; ~1.1 M input tokens, 97 % from cache; 4 nightly reviews, 4 proposals nobody has approved | **The caches cost more than they save** at this traffic (roughly 60 to 80 times more). Everything else is used well, with deterministic code around every call.                                                                                  |
| Website advisor   | Gemini 3.6 Flash, same prompts as Witty, per chat turn                                                                                                                                                      | 0 sessions ever                                                                                                 | Nothing spent. Keep; it already has per-session caps.                                                                                                                                                                                            |
| Spark (B2C CRM)   | Claude: reply classification (after keyword rules), per-lead briefs, Ask, Explain, a daily insights feed                                                                                                    | 0 calls ever (no key set)                                                                                       | Nothing spent. Two settings to tighten before the key goes in.                                                                                                                                                                                   |
| B2B partner CRM   | Claude as the allocation optimiser: light checks, hourly optimisation, nightly deep review (Opus), weekly report, Ask the CRM, autopilot                                                                    | 0 runs ever (`ai.enabled = false`)                                                                              | Nothing spent. Two cron jobs still run every 5 minutes for it; harmless.                                                                                                                                                                         |
| Influencer portal | none                                                                                                                                                                                                        | none                                                                                                            | Nothing to do.                                                                                                                                                                                                                                   |
| Eduwit One        | Claude: classify every incident, triage every routing, explain P1/P2 after 15 min (Opus), propose a fix after 60 min, nightly brief, weekly feature review, Ask, the command centre                         | 0 calls (no key yet); 262 tasks queued and cancelled in 6 days                                                  | **This is where the money would go** once the key is saved: about ₹150 a day at today's incident rate, most of it on Opus explanations of set-up gaps nobody has acknowledged. Four changes cut it to about ₹55 a day and keep the useful parts. |
| Catalogue Engine  | unknown to this session                                                                                                                                                                                     | not in production                                                                                               | Asked its design session (answers below when they arrive).                                                                                                                                                                                       |

Today the whole estate spends on one thing: Witty's Gemini calls, and within those, the prompt caches. Everything on
Claude is either switched off or waiting for a key. The audit's value is therefore mostly **before the money starts**:
Spark, the B2B CRM and Eduwit One each have a daily cap, but caps bound the damage, they do not buy value.

## 1. Witty (n8n workflow "Eduwit Witty", Gemini)

**Where the model is called.** Section 2 of the workflow, "Process Turn": for every student message that reaches it,
the **extractor** (Gemini 3.6 Flash, a 21,000-character prompt) reads the message and returns facts with the exact
evidence words; code validates them and decides the next step (the "Plan Reply" node, a 1,000-line deterministic
engine with fixed texts for greetings, consent, stop, hand-off and most questions); the **counselor** (Gemini 3.6 Flash,
an 18,000-character prompt) writes the reply with placeholders that code fills from the programme catalogue; the
"Verify Reply" node rejects unverified numbers and falls back to a fixed reply, with one **rewrite** call allowed. A
general question also costs one **embedding** call (gemini-embedding-001) to search the knowledge base. Section 7
re-creates two **prompt caches** every 15 minutes if they would expire within 40 minutes (TTL 90 minutes). Section 9
runs a **nightly review** (one Gemini call) over yesterday's weak turns and files proposals in `w2_learnings`.

**What production shows (30 days).**

| Measure                                                          | Value                                                                                                 |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Student messages in / replies out                                | 92 / 92 (16 phone numbers; 8 messages in the last 7 days)                                             |
| Turns that called the models                                     | 89, of which 73 counselor replies, 7 fixed replies (greeting, hand-off, gate), 4 nurture, 3 fallbacks |
| Input tokens for those turns                                     | 1,080,000, of which 1,047,000 (97 %) read from the caches; 10,500 per turn                            |
| Output tokens                                                    | 11,000 in total (150 per turn)                                                                        |
| Replies in "ACK" mode (an acknowledgement, no programme content) | 18 of 73 counselor calls                                                                              |
| Prompt caches                                                    | two, re-created about once an hour, around the clock, 10,500 tokens held                              |
| Nightly reviews                                                  | 4 in 30 days (it skips a night with nothing to review); 4 proposals, all still "proposed"             |
| Knowledge base                                                   | 1 document, 1 chunk                                                                                   |

**Findings.**

1. **The prompt caches cost more than they save (high confidence; small money).** A cache saves input tokens on every
   turn, but it is paid for by the hour whether or not a turn happens. Witty held 10,500 cached tokens for 24 hours a
   day and re-created them about 24 times a day, to serve about 3 turns a day. At Gemini Flash-class list prices
   (assumptions to check on the Google bill: about $0.30 per million input tokens, about $1 per million cached tokens
   per hour), the caches cost in the order of $0.30 a day and the turns they served would have cost about $0.03 a day
   uncached. Break-even is roughly 100 turns a day. **Recommendation:** switch the Cache Manager off (disable the
   "Every 15 Minutes · Cache" trigger) until Witty passes about 100 turns a day; `w2_turn_prompts()` already falls back
   to the plain prompt when no live cache exists, so nothing else changes. A later refinement is to create a cache only
   when a conversation is active (first turn of the hour) instead of on a timer.
2. **The counselor is called for acknowledgements (medium confidence).** 18 of 73 counselor calls were "ACK" turns,
   where the reply carries no programme content; "Plan Reply" already has fixed texts for many cases. Letting it answer
   ACK turns from templates would cut counselor calls by about a quarter. Worth doing only once traffic grows; today it
   is cents.
3. **The nightly review produces proposals nobody looks at (value, not cost).** Four proposals since launch, none
   approved or rejected. The call is cheap and it skips empty nights, so keep it, but someone should review
   `w2_learnings` weekly (Settings in Witty) or the loop is pure cost.
4. **Everything else is sound.** Two model calls per turn with code deciding before and after each is the right shape;
   fixed replies handle greetings, consent, stop and hand-off without a model; failures fall back to fixed text; the
   extractor's evidence rule stops invented facts. The four developer harnesses ("Test Harness", "Gemini Harness",
   "Latency Lab", "Extractor Eval") are inactive and cost nothing; archiving them is tidiness only.

## 2. Website advisor (Gemini, same prompts as Witty)

`web_advisor_enabled = true`, models `gemini-3.6-flash` for both counselor and extractor, prompts taken from Witty's
(`web_agent_core_prompts()`), per-session budget 40 turns and 60,000 tokens (`web_advisor_budget`), cost logged per
session. **Zero sessions ever**, so nothing has been spent. No change needed. When it does see traffic, Witty's finding
1 applies to it too if its code caches prompts (the website's code is outside this repository).

## 3. Spark, the B2C CRM (Claude)

**Where the model is called** (`b2c-crm/web/lib/ai.ts`, `classify.ts`, `analytics-ai.ts`, `analytics-jobs.ts`):

- **Reply classification** of WhatsApp replies that the keyword rules could not decide (`reply_classify_take`, up to
  20 a minute in the urgent sync); model from `settings.nurture.classify_model`, default **`claude-haiku-4-5`**.
- **Lead briefs**: one call per lead when a counsellor opens it or a call is due within the hour (`brief_due_take`,
  3 a minute), Sonnet 5.5, refreshed when something important changes.
- **Ask** (a question turned into a query spec, never data), **Explain** (aggregates), and the **insights feed** once
  a day after 07:00 IST. Model `claude-sonnet-5-5`, daily cap **₹500**, every call logged in `b2c.ai_calls`.

**What production shows.** `b2c.ai_calls` is empty, `b2c.lead_briefs` is empty, no replies have been classified: the
server has no `ANTHROPIC_API_KEY`, and the code skips every model part without one. Nothing spent, nothing lost.

**Before the key goes in (two settings, no code):**

1. `nurture.classify_model` → `claude-haiku-5-5`. The seeded default is the older Haiku at ten times the price
   (`price_usd_per_mtok` in the same settings: 1/5 against 0.1/0.5 per million). Same job, same quality for a
   five-class label.
2. `ai.daily_cap_inr` 500 → **150**. The cap is twice Eduwit One's and higher than the B2B CRM's for an app with no
   model traffic yet; raise it later on evidence from `b2c.ai_calls`.

Design-wise Spark is frugal: rules before the model, structured outputs, one call per brief with a staleness rule,
aggregates only. The brief is the one feature that can run away (a brief per lead with a call due, every hour the
lead stays stale); watch `b2c.ai_calls` by purpose in the first month.

## 4. The B2B partner CRM (Claude as the allocation optimiser)

`b2b.settings.ai`: `enabled = false`, `mode = advisory`, daily budget $5, models Sonnet 5.5 (regular), Opus 5.5
(deep), Haiku 4.5 (quick). `b2b.ai_runs` has **no rows ever**. Two cron jobs run for it every 5 minutes
(`b2b-ai-schedule`, `b2b-ai-autopilot`); both return at once while the feature is off (and autopilot while routing is
not live). `b2b.ai_state.facts` is refreshed every 5 minutes by `b2b.refresh_facts()`, which the dashboards and the
metric catalogue also use, so that is not AI waste.

**Recommendation:** nothing to cut now. When the feature is switched on, start with the **nightly review and the weekly
report only** (`schedules.light = false`, `schedules.hourly = false`): the hourly optimisation re-reads the same
scorecards every hour and matters only once partner decisions arrive by the hundreds; the light checks fire on every
new alert, which Eduwit One already triages. Set `daily_budget_usd` to 2 for the first month. Replace the quick tier
`claude-haiku-4-5-20251001` with `claude-haiku-5-5` (same ten-fold price gap as in Spark).

## 5. Influencer portal

No model anywhere (`lib/`, `app/`, migrations). Earnings, estimates and attribution are pure, tested code. Nothing to
do.

## 6. Eduwit One (Claude)

**Where the model is called** (`one.ai_schedule()`, 0018 and 0020; the worker `web/lib/ai/worker.ts`):

| Task            | When                                                       | Tier (model)                 | Allowance             |
| --------------- | ---------------------------------------------------------- | ---------------------------- | --------------------- |
| classify        | every new incident, once                                   | quick (Haiku 5.5)            | 2,000 tokens          |
| triage          | every routing of an incident (open, reopened, more severe) | regular (Sonnet 5.5)         | 6,000                 |
| explain         | a P1 or P2 still open after 15 min, and every storm        | **deep (Opus 5.5)**          | 12,000                |
| propose_fix     | a P1 or P2 still open after 60 min                         | regular; deep when high-risk | 12,000                |
| brief           | nightly                                                    | regular                      | 12,000                |
| propose_feature | weekly (Monday)                                            | deep                         | 16,000                |
| ask, chat       | on demand                                                  | regular                      | 6,000 / 4,000 a round |

Daily cap ₹250; from 80 % only classify and triage run; per-task cap ₹50.

**What production shows.** No key yet, so `one.ai_calls` is empty and every task was deferred and then cancelled
after 48 hours: in the last 6 days 58 classify, 95 triage, 53 explain, 50 propose_fix, 5 brief, 1 propose_feature,
about **44 tasks a day** for 63 incidents, almost all of them set-up gaps (a missing token, a heartbeat never written,
an app not yet watched) and none acknowledged by a person.

**What it would cost the day the key is saved** (estimate at list prices, ₹85 to the dollar, typical token counts; the
first week in Audit → AI calls will show the real numbers):

| Task                            | A day | Each      | A day                                                            |
| ------------------------------- | ----- | --------- | ---------------------------------------------------------------- |
| classify (Haiku)                | 10    | ₹0.1      | ₹1                                                               |
| triage (Sonnet)                 | 16    | ₹2        | ₹32                                                              |
| explain (Opus)                  | 9     | ₹8 to ₹20 | ₹77 to ₹180                                                      |
| propose_fix (Sonnet, some Opus) | 8     | ₹4        | ₹34                                                              |
| brief (Sonnet)                  | 1     | ₹5        | ₹5                                                               |
| total                           |       |           | **about ₹150, up to the ₹250 cap on a bad day** (₹4,500 a month) |

**Findings and recommendations** (these are Eduwit One's own settings and code; the settings are versioned and the
owner approves them; the code changes are a small migration and a redeploy):

1. **Explanations on Opus for incidents nobody has looked at are the main waste.** An AI "root cause across apps" of
   "the website's Vercel token is not configured" adds nothing to what the check already says, and Opus is 2 to 4 times
   Sonnet's price. **Change:** `ai.routing.explain` → `regular`; `schedule.explain_after_min` 15 → 60; and in
   `ai_schedule()` explain only a **P1** (or a storm) unless a person has acknowledged the incident (code). Saves about
   ₹70 to ₹170 a day.
2. **Fix proposals for incidents without a fix.** `propose_fix` runs for every P1/P2 open an hour, including the many
   whose check has no catalogue fix and whose cause is a Setup item. **Change:** in `ai_schedule()`, propose a fix only
   when the check has a fix in the catalogue (`one.fixes.checks`) or a person has acknowledged the incident, and after
   24 hours instead of 60 minutes (`schedule.propose_fix_after_min`). Saves about ₹25 a day.
3. **Classification adds little.** An incident already carries app, check, severity and the check's description; the
   classify task adds a category and a "noise" flag shown on the incident page. It is cheap on Haiku (₹1 a day) but it
   is also the one task that runs on every incident for ever. **Change:** a switch `schedule.classify = false` by
   default (code), on again if the category proves useful.
4. **Triage is worth keeping** (the first plain-English summary when a person finally opens the incident), but
   repeated routings of the same incident re-triage it. **Change:** no second triage within 24 hours of the last for
   the same incident unless its severity rose (code). Saves a third of triage calls.
5. **Keep as they are:** the brief (one call a day, the owner's morning read), Ask and the command centre (on demand,
   the person is the value), the weekly feature review (one Opus call a week; defer it until the apps have traffic
   worth reviewing, by `schedule.propose_feature_weekday = null` if the setting is extended, else leave).

With 1 to 4: about **₹55 a day (₹1,650 a month)**, the useful parts intact, and the cap rarely reached.

## 7. Catalogue Engine

Not in production and not in this repository. Its design session was asked, on 29 Oct, which stages call a model and
with what deterministic path before each call, how many calls a run costs, and where tokens and a daily cap are
logged. Its answers go here when they arrive; the questions matter because the engine's extract and enrich stages
run over every partner page and are the one place in the estate where a model could be called per page rather than
per student turn.

## 8. Platform notes (not model cost)

- The n8n instance keeps its own tables in this Supabase project (`public.workflow_entity`, `execution_entity`, the
  `instance_ai_*` tables of n8n's assistant). They hold 0 executions and 0 assistant rows: n8n prunes them, and no
  model is behind them. No action.
- Witty's section 4 (CRM outbox, every minute) and section 8 (Drive sync, every 10 minutes) run around the clock
  without a model; they are the 10,000 workflow executions a month, not an AI cost.

## What to do, in order

| #   | Action                                                                                                                                                                                                      | Who                                                                                      | Saves                                                         |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| 1   | Witty: disable the "Every 15 Minutes · Cache" trigger until traffic passes about 100 turns a day                                                                                                            | the owner or the developer, in n8n (one toggle)                                          | the only real spend today, roughly 90 % of Witty's model cost |
| 2   | Eduwit One: explain on `regular`, after 60 min, P1 or acknowledged only; propose_fix only with a catalogue fix or an acknowledgement, after 24 h; classify off by default; one triage per 24 h per incident | Eduwit One build session (settings + a small migration), the owner approves the settings | ~₹95 of ~₹150 a day once the key is in                        |
| 3   | Spark: `nurture.classify_model = claude-haiku-5-5`; `ai.daily_cap_inr = 150`                                                                                                                                | the owner in Spark's settings, before the key                                            | 10× on classification; a safer cap                            |
| 4   | B2B CRM: when switching the optimiser on, nightly + weekly only, budget $2, quick tier Haiku 5.5                                                                                                            | the owner, when the time comes                                                           | most of the $5 a day it would otherwise be allowed            |
| 5   | Witty: review the four `w2_learnings` proposals, or pause the nightly review                                                                                                                                | the owner / Witty's developer                                                            | value, not cost                                               |
| 6   | Witty: template the ACK replies (later, with traffic)                                                                                                                                                       | Witty's developer                                                                        | ~25 % of counselor calls                                      |

Nothing above changes what the models are allowed to do; it changes how often they are asked and which model answers.
