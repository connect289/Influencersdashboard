# Eduwit B2C CRM: Phase 3 plan ("Money and analytics")

Version 14 October 2026 · Spec B11, B12, B13, B8.3 ("Brief before you call"), B19.2 row 3 · Builds on Phases 1 and 2
(b1–b18 on staging)

## Rules for the whole phase

The same as Phases 1 and 2:

- Staging only (`mplbspysxmtohnlwpbti`).
- Test leads only.
- Never touch `w2_*`, `lead_intake()`, the n8n workflows, the B2B CRM or `student_leads`.

Every business rule is a `b2c.*` function with rolled-back checks in `tests/test_phase3.sql`.

- **The CRM moves no money.** It books, invoices, matches and reports. Collection is Eduwit's decision (B21 #2d).
- **Ledger rule** (ported from the old `crm_*` money functions): a line is never edited or removed. A correction is a new
  line that reverses it, and every line keeps the rate snapshot it was computed from.
- **Partner rates are read, never copied into an editable table.**
  - The shared `catalog` views (`catalog.partner_rates_v`) don't exist yet.
  - Until they do, one function, `b2c.partner_rates_for(programme, university, on_date)`, reads the B2B CRM's own tables
    read-only: `b2b.partner_programmes` (who offers what, with per-programme commission) and `b2b.rates` (per programme,
    per university or partner-wide).
  - When B2B publishes the view, only that function changes. Nothing in B2B is written.
- **AI** (B13.4, B18):
  - Claude sees only aggregated or de-identified data. Phone numbers and emails never go to the model.
  - Role scoping is enforced by the database, not the model. The model only fills in a query spec, and
    `b2c.analytics_run()` validates it and adds the role's scope.
  - Every call is logged with its query, token counts and cost, under a daily spend cap.

## Database, in migration order

| File | Contents |
| --- | --- |
| `b19_university_money` | **University rates (Eduwit's receivable, B11.1):** `university_rates`, per university with optional programme overrides, versioned by valid-from. Rate types: percent of a fee base, fixed, or tiered by conversion. Each rate has a GST-inclusive flag. **Booking:** `earnings` (expected, then realised when the Admin verifies the enrollment; refunds inside the window book a negative line). **Tiers:** provisional during the period, settled at `period_close()` from verified enrollments ÷ leads (the denominator is a setting). **Invoicing:** `invoices` and `invoice_lines` with gapless numbering per financial year, Eduwit's and the university's GSTIN, the SAC code, gross, GST and net; draft → approved → sent → paid / part-paid / cancelled (a credit note, never an edit). **Receipts:** `receipts` with TDS and bank reference, auto-matched to invoices, with ageing buckets and reminders (an Admin task, plus an email draft). **Statements:** `statement_imports` and `statement_rows`, reconciled into four piles: matched, university only, Eduwit only, amount mismatch. |
| `b20_counsellor_commission` | **Counsellor commission owed to Eduwit (B11.2):** `commission_lines` with a **rate snapshot** (source, partners considered with each one's rate, rate used, fee base, amount, time read). Rate precedence per partner: programme rate, then university rate, then partner-wide; then the **highest** across partners. No partner for the programme but one for the university: the highest university rate, flagged `university_highest`. No partner at all: **needs rate** until the Admin sets `commission_fallbacks` (Admin alerted). Tiers: the partner's tier from the catalog, or the top tier when the Admin sets it. TDS is a setting, off. **Overrides** (per counsellor, per programme, one-off adjustment), Admin only, with a reason, logged and shown to the counsellor. **Lifecycle:** provisional → confirmed (enrollment verified) → due (after the university's refund window) → settled (in a run). **Clawback:** a refund inside the window reverses the line, or carries the reversal to the next run if already settled. **Runs:** `commission_runs`, monthly; the Admin reviews per counsellor, applies clawbacks and approves; this produces the finance CSV and a PDF statement per counsellor. **Published view:** `b2c_enrollment_money_v` (lead ID, enrollment, university commission gross, GST, net, status, invoice, counsellor commission total), versioned and read-only, for the B2B Master Lead Table. Hooks into the existing `enrollment_verify` and refund paths. |
| `b21_performance` | **Team performance (B12):** `targets` per counsellor per month (calls, connected, counselled, applications, enrollments, commission) with progress on Today. The leaderboard, with opt-in visibility per counsellor. The activity monitor: calls and connect rate, WhatsApp and email sent, first-contact time, SLA breaches, overdue tasks, leads untouched for 48 h, calls tapped but not logged. The capacity panel (assigned vs cap) and the hiring trigger. Coaching notes already exist (Phase 1). |
| `b22_analytics` | **Facts** refreshed every minute from `b2c.events`, never by scanning `student_leads`. `fact_leads` has one row per lead: lane, source, reason, partner, programme, university, city, state, owner, stage, sub-stage, score band, dates of each stage reached, first contact, SLA, enrolled, the money totals. `fact_daily` holds per-day counts by type and the main dimensions. **Metric catalogue** `metric_defs`: every B13.2 metric with its formula, allowed dimensions and the roles that may use it. `analytics_run(spec)` validates a spec (metrics, dimensions, filters, date range, comparison) against the catalogue and the caller's role (a counsellor is always restricted to their own leads; a sales head to their team; Marketing reads money), and returns the rows plus the SQL it ran. `analytics_leads(spec, cell)` is the drill-down: the lead IDs behind any number, opened as a Leads-page view. **Dashboards:** `dashboards` and `widgets` (personal, role standard published by the Admin, duplicate, set as home); the standard dashboards of B13.1 are seeded per role. **Schedules:** `dashboard_schedules` (daily, weekly or monthly, PDF or CSV by email). **Alerts:** `metric_alerts` (threshold, or an unusual move against a 28-day baseline) by email and phone alert. **AI:** `ai_calls` (who, purpose, spec or prompt hash, model, tokens, cost, ms) and a daily cap in settings; `insights` (the morning feed and anomalies, each tied to a widget spec). |
| `b23_brief` | **"Brief before you call" (B8.3):** `lead_briefs` (3–5 lines, each line with its source: a field, a Witty message, a partner event, an activity). `brief_input(lead)` builds the model's input from profile fields, the Witty transcript, partner history and the last activities, with phone numbers and emails removed (including any typed inside chat text). A brief goes stale when a key fact changes (programme, stage, a new Witty turn, a partner event, a new call outcome); stale briefs are rebuilt on open or by the minute job. |

The connector still cannot apply DELETE, so as before everything is a soft flag (`archived_at`, `cancelled_at`), and
corrections are reversing lines.

## App

| Area | Routes |
| --- | --- |
| Money (Admin; Marketing read-only) | `/w/money`: Overview (both of Eduwit's amounts per enrollment and per university, side by side), University commission (rates, expected vs realised, gross/GST/net, tier watch), Invoices (draft, approve, PDF, send), Receipts and ageing, Statements (upload CSV, four piles), Counsellor commission (by counsellor, status and month; needs-rate queue; overrides; the partner-rate table per programme with the highest marked, and rate-change alerts), Runs (review, clawbacks, approve, finance CSV, PDF statements) |
| Counsellor commission (Sales, own data) | `/s/money`: four tiles this month (provisional, confirmed, due, settled) and the year to date, one row per enrollment with the rate and the partners it came from, by university and month, 12-month history, target progress, statements to download. Today shows commission this month and target progress. |
| Team (Admin, sales head) | `/w/team-performance`: targets, leaderboard, activity monitor, capacity |
| Analytics (every role, scoped) | `/w/analytics` and `/s/analytics`: the standard dashboards per role (B13.1), the builder (KPI with delta, line, bar, stacked bar, funnel, cohort, table, pivot, leaderboard, gauge, a state map as a tile grid, text note), dashboard-wide filters, date ranges and comparison periods, drill-down to leads, save and set as home, Admin "publish to role", schedules, alerts. **Ask** (plain-language question → a validated query spec → chart, with the spec and SQL shown, saveable as a widget), **Insights** (each morning and on demand), **Explain this chart**. |
| Lead screen | **Brief before you call** at the top of the lead screen (Sales and Workspace): 3–5 lines, each linking to its source, with a refresh button and the time it was written |
| Jobs | The every-minute sync also refreshes stale briefs and evaluates alerts. The nightly job closes facts, runs the insights feed and anomaly checks, sends the schedules, and moves commission lines to *due*. |

**Claude:**

- The model is a setting. The default is `claude-sonnet-5-5` for the brief, Ask, insights and explain.
- Calls use structured output: Ask returns a query spec, never SQL.
- Before each call, the daily spend cap is checked and the call is logged in `ai_calls`. Without an API key, these
  features say so and everything else works.

PDFs (invoices, statements, scheduled dashboards) are made on the server with `pdf-lib`. No headless browser is needed.

## Tests (`tests/test_phase3.sql`, plus unit tests)

The phase's exit test, on test leads and a test month:

1. **One month of money matches a manual check.**
   - University commission: percent, fixed and tiered rates, with GST inclusive and exclusive. A tier changes at period
     close. An invoice is raised, a receipt with TDS is matched to it, and a statement reconciles into the four piles.
   - Counsellor commission: one partner; several partners (the highest is used); no partner for the programme (the
     university's highest, flagged); no partner at all (needs rate, then the Admin's fallback).
   - Overrides, a refund inside the window (a clawback before and after settlement), and a run.
2. **Every counsellor commission line shows** the programme, the partners considered and the rate it was computed from.
   A later rate change doesn't alter a booked line.
3. **Every dashboard number drills down to its leads.** For every standard widget, the drill-down count equals the
   number shown.
4. **A Sales user can't get another counsellor's data.** That holds for a direct `analytics_run`, a hand-written spec
   that names another counsellor, and an Ask question that tries to.
5. **The brief's input never contains a phone number or email**, including ones typed inside the chat.

Unit tests cover:

- the rate precedence and the highest-partner computation;
- GST splits and the invoice numbering format;
- receipt matching;
- statement CSV parsing and the four piles;
- the spec validator;
- the PII scrubber for the brief.

## What I need from you (none blocks the build; all block going live)

1. **From Eduwit's CA:**
   - the GST rate on Eduwit's commission;
   - the SAC code;
   - Eduwit's GSTIN and billing address;
   - the invoice number format;
   - whether TDS applies to counsellor commission;
   - each university's refund window.

   Until then, these are settings marked "to confirm" and nothing is sent.
2. **University commission rates** for each university Eduwit enrolls with directly (the B11.1 example tiers are used
   only in tests).
3. **The tier denominator.** The default is leads handed to B2C for that university in the period. Confirm it, or name
   another.
4. **Partner rates per programme.**
   - On staging, `b2b.rates` holds only partner-wide rates (25%, 20% and 18% of the first-year fee).
     `b2b.partner_programmes.commission` exists for per-programme rates but is empty.
   - I read both, programme first. Until per-programme rates are loaded, every line uses the highest partner-wide rate
     among the partners that offer the programme.
   - The B2B developer should still publish `catalog.partner_rates_v` (Phase 0 audit §5.3).
5. **Run day and collection.** The commission run defaults to the 5th of each month for the previous month. How the
   amount is collected (deduction, invoice or payment) stays your decision.
6. **The Anthropic API key** (the same one as Phase 2) and a **daily AI spend cap**. The default is ₹500 a day across
   brief, Ask and insights.
