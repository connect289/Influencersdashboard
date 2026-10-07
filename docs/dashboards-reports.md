# Dashboards, alerts and reports (Phase 4)

Every number in the B2B CRM's analytics comes from one place: the **metric layer**. Dashboards, drill-downs, metric
alerts, scheduled e-mails, reports and "Ask the CRM" all read the same definitions, so the same question always gives
the same number. Screens: **Dashboards** (`/dashboards`) and **Reports** (`/reports`), both under Insights.

## 1. Where the numbers come from

- **Fact views** (M27a). Ten materialized views in schema `b2b`, refreshed every minute without blocking readers:
  `fact_leads`, `fact_allocations`, `fact_enrollments`, `fact_sla`, `fact_money`, `fact_invoices`, `fact_notifications`,
  `fact_capi`, `fact_sync`, `fact_ai`. Test leads are kept but always filtered out. No names, phones or e-mails are in
  them. A dashboard says how old its data is ("Data as of 1 min ago").
- **Metric definitions** (M27b, table `metric_definitions`). 54 built-in metrics in 13 areas (Intake, Routing,
  Duplicates, Sales effort, SLAs, Lead stages, Conversion, Commission, Receivables, Notifications, CAPI, System and
  mapping, AI and ML). Each has a label, unit (count, %, ₹, hours,
  days), whether higher is better, the breakdowns it allows and a plain description. Examples: leads, accept rate,
  duplicate rate, time to first attempt (median and p90), connect rate, SLA compliance, enrolment rate (matured leads),
  NCPL (net commission per lead, realised), NCPL for AI-steered vs holdout leads, commission expected / realised,
  outstanding, collection rate, CAPI sent / failed, sync lag, AI cost.
- **Breakdowns.** Day, week and month, plus what each fact holds: for leads source, channel, campaign, ad platform,
  paid, form, UTM, city, state, course, level, mode, segment, university, lead status, stage, lost reason, language,
  destination and partner; for allocations also routing mode, attempt, status, holdout, scoring mode, model version,
  counsellor and stage reached; and partner, status or kind for SLAs, money, invoices, notifications, CAPI, sync and AI.
- **Calculated metrics.** Admins can add their own as a formula over existing metrics, e.g.
  `commission_realised / allocations`. The formula is checked (known metrics, balanced brackets, operators only) and
  stored as a small program, never as SQL.
- **How a query runs.** `metric_run` builds the SQL from whitelisted pieces only (the metric's aggregate, the allowed
  breakdown columns) with every value bound as a parameter, and returns the value, the previous period's value and up to
  500 rows. Admin-only wrappers: `metric_catalogue`, `metric_query`, `metric_drill_admin`, `metric_save`.

## 2. Dashboards

- **Built in (B13.4), read-only:** Command Center, AI Optimiser, Partner league, Partner deep-dive, Routing flow,
  Sales effort, Commission, Sources and ads, Data quality. *Duplicate* one to change it.
- **Widgets (14):** KPI tile (with change vs the previous period), line, bar, stacked bars, funnel, Sankey flow
  (e.g. source → partner → stage), heatmap / cohorts, table, leaderboard, India map by state, gauge against a target,
  live SLA timers, alerts, and a text note. Each widget can override the period and add its own filters.
- **Builder** (`/dashboards/{id}/edit`): a 12-column grid; add, reorder (drag or arrows), size and configure widgets;
  the builder says what a widget still needs ("Choose a breakdown").
- **Period and filters** sit at the top of every dashboard and live in the URL, so any view is a link. The Admin can make
  any dashboard the **home screen** instead of the Command Center.
- **Drill-down.** Every number is a link to the rows behind it (`/dashboards/drill`), with the same filters. A drill
  list can be saved as a **saved view**.
- **Print / PDF** uses the browser's print to PDF; the print layout hides the navigation.
- On phones widgets stack, KPI tiles sit two per row and wide charts scroll sideways.

## 3. Alerts to the Admin

Dashboards → **Alerts and e-mails**. Nothing is sent until the Admin switches it on and enters recipients.

- **System alerts** (partner paused automatically, SLA breaches, NCPL drop, model fallback, reconciliation items, bad
  webhook signature, failed student notification, AI budget, AI run failure, routing errors) are collected into one
  **digest** every 15 minutes (5–1440, setting `admin_alerts.digest_minutes`); quiet periods send nothing.
- **Metric alerts.** A threshold on any metric with filters and a window, e.g. "duplicate rate for Acme over the last
  24 hours above 30%, when at least 20 leads were routed". Checked every 5 minutes; after firing it waits for its
  cooldown (default 24 hours) before firing again.
- **Channels.** E-mail through the provider already set up for student e-mails (Resend or Brevo; key in Vault), and
  WhatsApp only through a Meta-approved template named in the settings. Students never receive these.
- **Test.** *Send a test* queues one message to the recipients so the setup can be checked.
- Every message is logged (`admin_messages`) with its status and the provider's answer.

## 4. Scheduled e-mails

A dashboard or a saved report can be e-mailed **daily, weekly or monthly** at an hour (IST) to a list of addresses.
The e-mail carries every widget's numbers; tables and breakdowns are attached as CSV. A schedule whose dashboard or
report fails is retried an hour later and raises an alert.

## 5. Reports

`/reports`: three kinds, saved by name, run on screen, exported as CSV, or scheduled by e-mail.

| Kind | What it is |
| --- | --- |
| Tabular | Rows of one fact view, chosen columns, filters, sort; up to 5,000 rows (1,000 by default) |
| Summary | Up to 12 metrics by one or two breakdowns, with totals |
| Matrix | One metric, a breakdown down the side and another across the top |

## 6. Where it is

- Database: M27a (fact views, `refresh_facts`, cron `b2b-refresh-facts` every minute), M27b (metric layer), M28a
  (`dashboards`, `saved_views`, `dashboard_*`, `sla_timers`, `alert_feed`), M28b (`admin_messages`, `metric_alerts`,
  `report_schedules`, `admin_alerts_tick` every minute), M29a (`reports`, `report_run`, `report_csv`).
- Web: `lib/analytics.ts`, `lib/analytics-data.ts`, `lib/reports.ts`, `components/charts/WidgetView.tsx`,
  `app/(app)/dashboards`, `app/(app)/reports`.
