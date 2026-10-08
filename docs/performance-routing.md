# Performance routing and the per-lead model

How the B2B CRM moves from "highest commission wins" to "highest expected net commission per lead wins" (spec B7.2–B7.4,
B7.8.1), and how the Admin controls it. Screens: **Routing → Segments**, **Routing → Engine settings**, a decision's page
(Routing → decision log), and **AI Optimiser → Model registry**.

## 1. The two modes

Every segment (course × level × mode, e.g. `MBA · PG · Online`) is in one of two modes.

| Mode | Who wins | When |
| --- | --- | --- |
| **Commission first** | The partner paying the highest commission (net of GST). An exploration lane (default 20%) sends some leads to an under-sampled partner so its conversion can be learned. | While the segment is immature: until 2 partners each have 30 leads older than 60 days. |
| **Performance** | The partner with the highest expected **net commission per lead** for this student: NCPL = P̂(enrol) × commission × (1 − refund rate). | Once 2 partners each have 30 matured leads in the segment. |

The Admin can pin a segment to either mode (Routing → Segments → a segment → Segment policy), with or without an end date.

Rules always come first and are unchanged: consent, duplicates and attempt limits, B2C hand-offs, partner capacity and
contracts, partner routing rules (a "always send to" rule or a contractual minimum still picks the highest commission
among its partners).

## 2. How P̂ is estimated

Recomputed every hour (`b2b.stats_refresh`, at :07), per partner and segment, and for the course as a whole:

- **Matured leads** (sent to the partner at least 60 days ago) count fully, weighted by recency: a lead 30 days older
  counts half (half-life 30 days).
- **Young leads** count through the stage they reached (leading indicators): "applied" counts as the historical chance
  that an applied lead enrols, and so on (Routing → Segments shows these rates). They weigh up to half a lead, growing
  with age, so a change in a partner's effort shows within days.
- **The prior**: every partner starts with 20 leads' worth of the segment's average (5% when there is no data), so a few
  early results cannot swing the ranking.
- **Thin data**: when a partner has fewer than 30 leads in the segment, its course-level numbers are used.
- **Refund rate**: refunded or cancelled enrolments out of decided ones, per partner, pulled toward the overall rate.
- **Optional factors** (off by default, Engine settings): speed (0.85–1.15, time to first attempt against all partners)
  and reliability (0.7–1.0, SLA breaches and sync errors in the last 7 days).

Ties go to the higher commission, then better SLA compliance, then fewer leads this week.

## 3. Choosing a partner: sampling, not just the best guess

In performance mode the engine does not always take the partner with the best estimate: it draws a plausible enrolment
rate for each partner from its uncertainty and picks the best draw (Thompson sampling). A partner with little data gets
some leads because its true rate might be high; one with lots of poor data does not. This replaces the exploration lane
in performance mode.

**Every decision is reproducible.** Each one stores a random seed; every draw is derived from it. The engine also
replays 200 further seeded draws to record the **selection probability** (how often this partner would win), which is
what makes offline evaluation of new settings and models possible. A decision's page shows P̂, NCPL and the share of
draws each partner won, and **Replay from the seed** shows it reproduces.

## 4. Controls

| Control | Where | Notes |
| --- | --- | --- |
| Maturity, half-life, prior strength, default rate, matured leads for performance | Engine settings | Versioned with a reason |
| Speed and reliability factors | Engine settings | Off by default |
| Pin a segment's mode | Segment policy | Optional end date |
| Exploration share for one segment | Segment policy | 0–50%; empty uses the engine's |
| Share cap for one segment | Segment policy | 50–100%; overrides highest commission, so off by default |
| Kill switch (one segment or all) | Segment policy / Engine settings | Stops scoring and AI changes; leads split between partners in the fixed shares you set (B2C is never part of it) |
| Temporary partner weight | A segment's page | ±10% on NCPL for up to 14 days, with a reason |
| AI holdout | Segments → Holdout and sampling | Default 10% of leads use only your settings, never an AI change |

## 5. Guardrails (every 5 minutes)

A live partner is paused automatically, with an alert, when:

- it missed the first-contact SLA on 5 leads in a row;
- pushes to it have failed for 30 minutes (3 or more failures, no success);
- more than 25% of its last 20 leads came back as duplicates.

Evidence from before the Admin last resumed the partner is ignored. A **drop alert** is raised when a partner's P̂ or
NCPL in a segment falls by more than a third against 30 days earlier. Alerts appear on the Command Center; e-mail and
WhatsApp delivery of Admin alerts comes with Phase 4's metric alerts.

## 6. The per-lead model

Segment-level P̂ treats every student in a segment alike. The model predicts each partner's chance of enrolling **this**
student, from privacy-safe features only: source type, Witty's classification, level and mode, work-experience and budget
bands, enrolment timeline, whether a parent enquired, language, time of enquiry, lead score, the partner, partner × source
and partner × level interactions, and the partner's segment P̂ and SLA compliance. Never: name, phone, e-mail, city,
chat text.

- **Model.** Version 1 is a regularised logistic regression with isotonic calibration, trained inside the database every
  night at 02:00 IST (no extra service or cost). Gradient-boosted trees can replace it later behind the same registry.
- **Activation gate.** A model may decide only after: 500 matured outcomes across 2+ partners; it beats segment P̂ on a
  time-based holdout (log loss and calibration error); and replaying logged decisions shows higher net commission per lead.
- **Promotion.** Shadow (scores, never decides) → Challenger (decides 10% of performance-mode leads) → Champion (decides
  them all), only when the challenger's realised NCPL is higher with 95% confidence on 100+ matured leads each. Holdout
  leads never use a model.
- **Safety.** Rollback is one click (the previous champion comes back). Each day the deciding models' calibration is
  checked on matured leads; above 0.08 the model retires itself and the engine falls back to segment P̂, with an alert.

## 7. Where it is in the database

`b2b.partner_segment_stats`, `segment_stats`, `stage_rates`, `stats_snapshots` (M24a); `route_score`, `thompson_pick`,
`model_score` and `route_decide` (M24b); the Admin functions (M24c); `ml_models`, `ml_training_rows`, `ml_train`,
`ml_tick`, `ml_monitor` and the registry functions (M25). Settings: `engine`, `engine_policy`, `ml`.
