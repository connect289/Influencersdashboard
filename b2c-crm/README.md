# Eduwit B2C CRM

In-house sales and nurture CRM for Eduwit Learning Services. Spec: `docs/B2C_CRM_PROMPT.md` (final, 14 Oct 2026).

Status: **Phase 1** ("Sell") and **Phase 2** ("Nurture") built and on staging; waiting for the staging setup and the
end-to-end test. Phase 3 (Money and analytics) next.

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
- `supabase/manual/staging_b4_pool_calendar.sql` (`pool_save`, `calendar_save`) was run by hand on staging on 14 Oct (the
  automated apply path stalls on any SQL containing DELETE). Staging's copies match the local build.
- Checks: `supabase/tests/test_phase1.sql` (99 checks) and `supabase/tests/test_phase2.sql` (45 checks, the Phase 2 exit
  test), all rolled back, all pass on a fresh local database with the migrations applied twice. On staging, run it in the SQL editor after the manual file (it clears holidays inside its own rolled-back transaction).
- The HTTP timers do nothing until the app is deployed and `settings.app.base_url` plus the Vault secret `b2c_internal_key` are set.
- App (`web/`): built. Sign-in (Google or password, emailed code, trusted device), the Sales app, the Workspace, the
  B2B and WhatsApp webhooks, and the sync jobs. Since then: the email composer, Programme fit and sharing, Witty's
  conversation, timeline filter, laptop call view (copy and QR), pipeline drag-and-drop, follow-ups calendar, custom
  views, Admin CSV export, editable guides with a "?" on every screen, phone alerts (web push) and the Workspace
  directory sync. Phase 2: the Nurture page (`/w/nurture`: overview, pool, journeys, campaigns, segments, replies,
  scoring), the journey editor, `/w/templates` with Meta submission, nurture on the lead screen, tracked marketing email
  with one-click unsubscribe, and reply classification with Claude. Typecheck, 57 unit tests and the production build pass; the sign-in
  screen was checked in light and dark mode against staging. Setup steps (expose `b2c`, Vercel, Google, first Admin,
  timers, B2B keys) are in `web/README.md`. Not yet run end to end: needs those steps and Addendum 4 deployed in B2B.

| File | What |
| --- | --- |
| `docs/B2C_CRM_PROMPT.md` | The product specification (Part A: how to work; Part B: the product; B21 wins) |
| `docs/phase0-audit.md` | Phase 0 audit: existing objects with verdicts, `b2c` schema plan, what the B2B CRM must expose, Google Workspace setup, open questions |
| `docs/brand/` | Logo and the settled palette (`palette.md`, `palette-preview.html`) |
| `docs/phase1-plan.md` | Phase 1 plan: migration order, app scope, exit test |
| `docs/phase2-plan.md` | Phase 2 plan (Nurture): built as b14–b18, Marketing workspace, exit test, what is needed to go live |
| `docs/WITTY_CHANGES_B2C.md` | Witty release W2: the changes Witty needs for the B2C CRM |
| `supabase/` | Migrations, the manual staging file, local test stubs and the Phase 1 and 2 checks |
| `design/` | Clickable design of the three interfaces (sample data) |
| `web/` | The app (see `web/README.md`) |

Hard limits while building: staging or a Supabase branch only; never run `student_leads_v2_rename.sql`; never change
Witty's `w2_*` objects, `lead_intake()`, the n8n workflows or the B2B CRM (`../b2b-crm`); test leads only.
