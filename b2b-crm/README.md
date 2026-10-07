# Eduwit B2B Partner CRM

Allocates every Eduwit lead to the partner edtech that earns Eduwit the most, keeps it in sync with the partner's CRM,
tells the student who will call, and tracks partner commission. Spec: `../docs/B2B_CRM_PROMPT.md`.
Design: `../docs/b2b-design.md`. Database audit: `../docs/phase0-audit.md`.

Feature guides in `../docs/`: `intake-api.md`, `partner-api.md`, `partner-adapters.md`, `b2c-contract.md`, `capi-setup.md`,
`money.md`, `performance-routing.md`, `ai-optimiser.md`, `dashboards-reports.md`.

This folder is the B2B CRM only. The influencer dashboard lives elsewhere in this repository.

## Databases

| | Supabase project | Use |
| --- | --- | --- |
| Production | `xlseqwgyjuqhktrguhyc` (EDUWIT LEAD TRACK, Mumbai) | Shared with Witty (WhatsApp bot), the old CRM and the influencer dashboard |
| Staging | `mplbspysxmtohnlwpbti` (eduwit-b2b-staging, Mumbai, free plan) | Schema copy from the baseline; synthetic test data only. Free projects pause after a week idle; restore from the dashboard |

## Migrations

`supabase/migrations/` holds every change, named by the version recorded in production's migration history.

- `00000000000000_baseline.sql`: production's `public` schema on 6 Oct 2026, generated from the catalog. Reference only and the
  starting point for staging; never applied to production.
- Every later file: applied to **staging first**, checked, then applied to production with Vikas's approval for that step.
- `supabase/pending/`: changes waiting for a confirmed manual run.

Rules that keep Witty (the live WhatsApp bot) safe:

- Never change `w2_*` or `catalog_*` objects, `lead_intake()` or `w2_crm_owned()` without written approval.
- Never rename, retype or drop a `student_leads` column. Triggers added to `student_leads` only enqueue and never raise.
- New tables go in schema `b2b`, with RLS on and writes only through `SECURITY DEFINER` functions that check `b2b.is_admin()`.
- The Supabase connector holds statements containing `DROP` (and some large migrations) for manual confirmation; keep
  migrations free of `DROP` (use `create or replace`, `if not exists` checks, `alter policy`) or put the drop in `supabase/pending/`.
- RLS policies call helpers as `(select b2b.is_admin())`, never bare `b2b.is_admin()`: the subselect runs once per
  statement instead of once per row (35 ms → 0.5 ms on a 2,000-row scan).
- Every function sets `search_path` (`''` for `b2b` functions, which qualify every name).
- Settings change only through `b2b.set_setting(key, value, reason)`: known keys only, object or array values, a reason
  every time, a version row and an event each change.
- Checks run on staging inside a `begin … rollback` block before anything reaches production; the migration comment
  says what was verified.

## Access

One user: the Admin `connect@eduwit.in`, listed in `b2b.app_users`. `b2b.is_admin()` also requires a TOTP-verified
session (`aal2`) while `require_totp` is on. Any other account that signs in is refused and logged in `b2b.sign_in_log`.

## Brand

Colours from the Eduwit logo: navy `#0B2F5E` (primary) and amber `#F5A800` (accent); logo files in the old CRM's
`crm/web/public/brand/` (`eduwit-logo.png`, `eduwit-mark.png`).
