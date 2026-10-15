# Eduwit B2C CRM

In-house sales and nurture CRM for Eduwit Learning Services. Spec: `docs/B2C_CRM_PROMPT.md` (final, 14 Oct 2026).

Status: all four phases built and on staging: **Phase 1** ("Sell"), **Phase 2** ("Nurture"), **Phase 3** ("Money and
analytics") and **Phase 4** ("Telephony and depth", `docs/phase4-plan.md`: Exotel behind an adapter but switched off,
ad spend and ROAS, performance-weighted allocation, Google Calendar; no Hindi, by decision). Waiting for the staging
setup and the end-to-end test.

- Database: migrations b1 to b18 (`supabase/migrations/`) are applied to the **staging** project `mplbspysxmtohnlwpbti`
  (eduwit-b2b-staging) (b4 to b7, b11 and b12 in parts). Production is untouched.
  b11: Witty's transcript (read-only from `w2_messages`), Programme fit and sharing, editable guides with read tracking,
  web push subscriptions, directory sync that reassigns suspended accounts, daily `b2c-directory` job. b12: the first
  sales, admin and marketing guides (28 articles). b13: custom views. Every function added since b10 was checked
  identical on staging and in the local build.
  b9 (decision K14): every counsellor assignment and its end goes to the B2B CRM at once, to be recorded like a partner
  hand-off (Addendum 4 §4a).
  Phase 2 (`docs/phase2-plan.md`): b14 per-channel marketing consent, suppressions and the single guardrail
  `may_market()` (consent, quiet hours, frequency caps, Witty chats, active sales, partner holds, one journey at a time),
  marketing WhatsApp and email templates; b15 segments and campaigns (A/B, throttle, send window, recurring); b16
  versioned journeys, the step engine and 13 starter journeys (published, **paused** for review) with 12 draft WhatsApp
  and 3 email templates; b17 scoring with decay and the rise-to-60 re-engagement, reply classification and the Replies
  inbox, dormancy and the nurture timers; b18 the Marketing guide for these screens (36 guide articles in all).
  Staging matches a local build of the same files: 62 tables, 44 policies, all 215 functions with identical bodies,
  identical guide articles, nothing executable by `anon`, cron jobs `b2c-minute`, `b2c-nurture` (every minute),
  `b2c-sync-urgent`, `b2c-sync-batch` (every 15 min), `b2c-reconcile` (every 5 min), `b2c-directory` and `b2c-nightly` (daily).
- Phase 3: b19 university commission (rates by date, GST, tiers settled at period close, gapless invoices and credit
  notes, receipts with TDS, statement reconciliation into four piles); b20 counsellor commission at the highest partner
  rate (rate snapshot with every partner considered, needs-rate queue, fallbacks, overrides, clawbacks, monthly runs,
  `public.b2c_enrollment_money_v` for the B2B CRM); b21 targets, leaderboard (opt-in names), activity monitor, capacity;
  b22 analytics (facts refreshed every minute, 62 metrics and 37 dimensions with role scoping in the query layer,
  drill-down, 17 standard dashboards, schedules, alerts, the AI log and daily cap, insights); b23 Brief before you call
  (PII scrubbed in the database, sources checked); b24 the corrected AI prices, `ai_call_attach`, `money_universities`,
  `money_rules` and 9 Phase 3 guide articles (45 in all). Staging matches the local build: 93 tables, 331 functions with
  identical bodies, identical guides, nothing executable by `anon`; crons add `b2c-money`, `b2c-facts`, `b2c-alerts`,
  `b2c-anomalies`. **To run by hand on staging:** `supabase/manual/staging_phase3_ledger_guards.sql` (stops anyone
  deleting a money ledger row; the automated path cannot send it).
- Phase 4: b25 telephony (provider none by default: counsellors keep dialling from their own phones; with Exotel a call
  is bridged, recorded and logged by itself, missed calls become call-back tasks, recordings in a private bucket with a
  retention period; test leads only ever reach the mock), b26 ad spend (Meta and Google CSV imports, campaign matching,
  the `ads` analytics source with cost per lead, cost per enrolment and ROAS, the Ad spend dashboard), b27
  performance-weighted allocation (smoothed conversion, floor and cap, explained in each decision), b28 Google Calendar
  sync of follow-ups (one way, no phone or email in events), b29 six guide articles (51 in all). Applied to staging; the
  local build has 99 tables, 359 functions, 71 policies.
- After Phase 4 (15 Oct): b30 phone numbers (the Admin allocates, changes or moves each counsellor's and sales manager's
  work mobile and own caller ID, with a reason and a history; counsellors ask for changes by support ticket) and b31
  support tickets (everyone raises tickets with links and screenshots; each message is emailed to the developer, whose
  answers come back by replying to the email or through a signed link and update the ticket; open, in progress and
  closed; the Admin sees every ticket). Staging matches the local build: 102 tables, 377 functions, 71 policies, 54
  guide articles. Checks: `supabase/tests/test_support_phones.sql` (28, safe to run on staging).
- Step 1 of running the app (16 Oct): the app runs against staging with five test people and 30 test leads
  (`web/e2e/seed.mjs`); every screen was opened as each role at laptop and phone sizes. b32 fixes what that found:
  test counsellors now see their own test leads on Leads and Pipeline, the Nurture Pool and Programme counts, and the Pool
  and Inbox searches no longer match everything when the words have no digits. Checks:
  `supabase/tests/test_walkthrough_fixes.sql` (8, safe on staging). Staging matches the local build: 102 tables,
  377 functions, 71 policies.
- `supabase/manual/staging_b4_pool_calendar.sql` (`pool_save`, `calendar_save`) was run by hand on staging on 14 Oct (the
  automated apply path stalls on any SQL containing DELETE). Staging's copies match the local build.
- Checks: `supabase/tests/test_phase1.sql` (99 checks), `test_phase2.sql` (45, the Phase 2 exit test) and
  `test_phase3.sql` (91, the Phase 3 exit test) and `test_phase4.sql` (47, the Phase 4 exit test); the last two run
  only on the local `b2c_fresh` database because they write catalogue fixtures. All rolled back, all pass on a fresh local database with the migrations applied twice. On staging, run it in the SQL editor after the manual file (it clears holidays inside its own rolled-back transaction).
- The HTTP timers do nothing until the app is deployed and `settings.app.base_url` plus the Vault secret `b2c_internal_key` are set.
- App (`web/`): built. Sign-in (Google or password, emailed code, trusted device), the Sales app, the Workspace, the
  B2B and WhatsApp webhooks, and the sync jobs. Since then: the email composer, Programme fit and sharing, Witty's
  conversation, timeline filter, laptop call view (copy and QR), pipeline drag-and-drop, follow-ups calendar, custom
  views, Admin CSV export, editable guides with a "?" on every screen, phone alerts (web push) and the Workspace
  directory sync. Phase 2: the Nurture page (`/w/nurture`: overview, pool, journeys, campaigns, segments, replies,
  scoring), the journey editor, `/w/templates` with Meta submission, nurture on the lead screen, tracked marketing email
  with one-click unsubscribe, and reply classification with Claude. Phase 3: Money (`/w/money`), My money (`/s/money`), Team performance, Analytics
(`/w/analytics`, `/s/analytics`) with Ask, Explain, drill-down to the Leads page, schedules and alerts, the Brief on the
lead screen, the month's progress and leaderboard on Today. Phase 4: the Call button through `call_start` (the old
flow while telephony is off; a bridged-call sheet with the mock for test leads), the Exotel webhook, recordings on the
timeline, Money → Ad spend, performance settings and a share preview on rules, Calendar switches under Connectors and
Me, telephony status and unknown callers under Connectors. Typecheck, 90 unit tests and the production build pass; the sign-in
  screen was checked in light and dark mode against staging. Setup steps (expose `b2c`, Vercel, Google, first Admin,
  timers, B2B keys) are in `web/README.md`. Not yet run end to end: needs those steps and Addendum 4 deployed in B2B.

| File | What |
| --- | --- |
| `docs/B2C_CRM_PROMPT.md` | The product specification (Part A: how to work; Part B: the product; B21 wins) |
| `docs/phase0-audit.md` | Phase 0 audit: existing objects with verdicts, `b2c` schema plan, what the B2B CRM must expose, Google Workspace setup, open questions |
| `docs/brand/` | Logo and the settled palette (`palette.md`, `palette-preview.html`) |
| `docs/phase1-plan.md` | Phase 1 plan: migration order, app scope, exit test |
| `docs/phase2-plan.md` | Phase 2 plan (Nurture): built as b14–b18, Marketing workspace, exit test, what is needed to go live |
| `docs/phase3-plan.md` | Phase 3 plan (Money and analytics): b19–b23, money and analytics screens, Brief before you call, exit test, what is needed to go live |
| `docs/phase4-plan.md` | Phase 4 plan (Telephony and depth) with the decisions of 15 Oct: built as b25–b29 (telephony adapter switched off, ad spend and ROAS, performance-weighted allocation, Google Calendar; no Hindi) |
| `docs/WITTY_CHANGES_B2C.md` | Witty release W2: the changes Witty needs for the B2C CRM |
| `supabase/` | Migrations, the manual staging files, local test stubs and the Phase 1–4 checks |
| `design/` | Clickable design of the three interfaces (sample data) |
| `web/` | The app (see `web/README.md`) |

Hard limits while building: staging or a Supabase branch only; never run `student_leads_v2_rename.sql`; never change
Witty's `w2_*` objects, `lead_intake()`, the n8n workflows or the B2B CRM (`../b2b-crm`); test leads only.
