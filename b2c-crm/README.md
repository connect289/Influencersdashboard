# Eduwit B2C CRM

In-house sales and nurture CRM for Eduwit Learning Services. Spec: `docs/B2C_CRM_PROMPT.md` (final, 14 Oct 2026).

Status: **Phase 1** ("Sell") in progress.

- Database: migrations b1 to b9 (`supabase/migrations/`) are applied to the **staging** project `mplbspysxmtohnlwpbti`
  (eduwit-b2b-staging) as `b2c_b1_access` … `b2c_b9_assignment_ledger` (b4 to b7 in parts). Production is untouched.
  b9 (decision K14): every counsellor assignment and its end goes to the B2B CRM at once, to be recorded like a partner
  hand-off (Addendum 4 §4a).
  Staging matches a local build of the same files: 44 tables, 31 policies, 132 of 134 functions with identical bodies,
  nothing executable by `anon`, cron jobs `b2c-minute`, `b2c-sync-urgent`, `b2c-sync-batch` (every 15 min), `b2c-reconcile`.
- `supabase/manual/staging_b4_pool_calendar.sql` (`pool_save`, `calendar_save`) was run by hand on staging on 14 Oct (the
  automated apply path stalls on any SQL containing DELETE). Staging's copies match the local build.
- Checks: `supabase/tests/test_phase1.sql`, 80 rolled-back checks, all pass on a fresh local database with the migrations applied
  twice. On staging, run it in the SQL editor after the manual file (it clears holidays inside its own rolled-back transaction).
- The HTTP timers do nothing until the app is deployed and `settings.app.base_url` plus the Vault secret `b2c_internal_key` are set.
- App (`web/`): next.

| File | What |
| --- | --- |
| `docs/B2C_CRM_PROMPT.md` | The product specification (Part A: how to work; Part B: the product; B21 wins) |
| `docs/phase0-audit.md` | Phase 0 audit: existing objects with verdicts, `b2c` schema plan, what the B2B CRM must expose, Google Workspace setup, open questions |
| `docs/brand/` | Logo and the settled palette (`palette.md`, `palette-preview.html`) |
| `docs/phase1-plan.md` | Phase 1 plan: migration order, app scope, exit test |
| `docs/WITTY_CHANGES_B2C.md` | Witty release W2: the changes Witty needs for the B2C CRM |
| `supabase/` | Migrations, the manual staging file, local test stubs and the Phase 1 checks |
| `design/` | Clickable design of the three interfaces (sample data) |

Hard limits while building: staging or a Supabase branch only; never run `student_leads_v2_rename.sql`; never change
Witty's `w2_*` objects, `lead_intake()`, the n8n workflows or the B2B CRM (`../b2b-crm`); test leads only.
