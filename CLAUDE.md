# CLAUDE.md

This repository holds three separate Eduwit products that share one Supabase project:

| Folder | Product | Rule for Influencer Portal work |
| --- | --- | --- |
| `influencer-portal/` | **Eduwit Influencer Portal** (being built) | Work here |
| `b2b-crm/` | B2B Partner CRM | **Never modify** |
| `b2c-crm/` | B2C CRM (Eduwit Spark) | **Never modify** |
| `docs/` (root) | B2B CRM docs | **Never modify** |

## How to resume

1. Read `influencer-portal/docs/PROGRESS.md`: current phase, step, what's done, what's next, blockers.
2. Read `influencer-portal/docs/DECISIONS.md` for every decision taken without the owner.
3. The spec is `influencer-portal/docs/INFLUENCER_PORTAL_SPEC.md`. The owner's build prompt (in the conversation that
   started this work) overrides the spec where they differ: phases run in order, with hard stops.
4. Re-read the relevant spec sections at the start of each phase.

## Hard stops (stop, explain, wait for the owner)

1. End of Phase 0 (current state until approved).
2. Creating or changing any object outside schema `inf` that differs from the approved `SHARED_CHANGES.md` (including
   triggers on `student_leads`, new columns, changes to `lead_intake()`), even in dev.
3. Anything that could expose a student's phone or email to a creator or agency user, or weaken RLS.
4. Real credentials or external accounts (email/WhatsApp providers, domain, Vercel, Sentry): build against adapters with
   mocks, then list exactly what is needed.
5. Money logic the spec doesn't answer and no configurable default covers.
6. Production go-live (migrations to the live project, production deploys, connecting attribution to live leads).

## Environment rules

- Supabase project `xlseqwgyjuqhktrguhyc` is **live production**, shared with Witty, the B2B CRM and the B2C CRM. Only
  `SELECT` and schema inspection are allowed until go-live is approved. Never run migrations, seeds or writes against
  it. The staging project `mplbspysxmtohnlwpbti` belongs to the B2B/B2C work; don't use it either.
- Develop against a local Supabase (`npx supabase start`, Docker).
- Never modify CRM code, Witty (`w2_*`), `catalog_*`, `lead_intake()`, n8n workflows or Chatwoot.
- Never commit secrets: `.env.local` (git-ignored) plus a committed `.env.example` describing every variable.
- Commit at least once per completed sub-step; tag each phase end (`phase-N-done`). Branch:
  `claude/blissful-goldberg-xaqrbr`.

## Portal conventions

- Next.js 16 App Router, TypeScript strict (no `any`), zod on client and server, Tailwind v4 + shadcn/ui.
- Database objects only in schema `inf`; RLS on every table, with pgTAP tests per role. Every function sets
  `search_path = ''`. Client grants are declared in `inf.client_grants` and applied with
  `call inf.apply_client_grants();` at the end of each migration (never plain GRANT).
- Shared helpers: `inf.has_perm(p)`, `inf.current_creator_id()`, `inf.session_ok()`, `inf.audit_row()` trigger,
  `inf.forbid_mutation()` for append-only tables, `inf.emit_event()`, `inf.job_enqueue()`, `inf.notify()`. Creators read lead data only
  through `SECURITY DEFINER` functions and `inf.creator_lead_feed`, with phone and email masked in the database.
- Ownership checks in SQL: `coalesce(p_creator = inf.current_creator_id(), false)` (or `inf.can_edit_creator()` /
  `inf.can_view_creator()`). A bare comparison is null for staff and makes `if not (...) then raise` silently pass.
- PII (PAN, bank account) goes through `inf.pii_encrypt/decrypt` (Vault key `inf_pii_key`); matching-only PII through
  `inf.pii_hash`. Never return decrypted values except from an audited reveal function.
- Server actions: validate with the zod schema in `lib/<domain>/schemas.ts`, call one RPC, map DB errors to message
  keys, return `ActionResult`. Client components run them with `useAction()` (`components/ui/use-action.ts`).
- Money in integer paise (`bigint`), banker's rounding once per line item. Store UTC, display IST, Indian number format,
  Indian financial year (1 Apr – 31 Mar).
- The compensation engine (`lib/compensation`) and attribution logic are pure, deterministic and fully unit-tested
  before any UI uses them.
- Every screen has empty, loading, error and mobile states. The creator portal is mobile-first.
- Every new feature updates the matching guide in `lib/guides/content` (a test checks guide links resolve).
- No TODOs, placeholder screens or fake data in production code paths; mock data only in the seed script, which
  refuses to run against production.

## Folder structure (`influencer-portal/`; modules marked "later" arrive in their phase)

```
influencer-portal/
  app/(admin)/admin/…      staff console
  app/(creator)/creator/…  creator portal (mobile-first, PWA)
  app/(agency)/agency/…    agency portal (creator-granted access)
  app/(auth)/…             sign-in, verify code, self sign-up
  app/m/[handle]/…         public media kit page and PDF
  app/legal/…              public terms
  app/r/[code]/route.ts    tracking redirect (later)
  app/api/…                health, metrics, signed-contract download, public API, internal jobs
  lib/compensation/        pure engine, simulator, tax estimate + tests
  lib/deals/               deal schemas, builder helpers, offer terms → config, dry-run, loaders
  lib/contracts/           document model, template engine, assembly, counter-offers, generation, PDF, signing
  lib/content/             workflow, compliance scan, URLs, brief document, penalty events (pure) + loaders, uploads
  lib/guides/              in-app guides (one per audience; update them with every feature)
  lib/attribution/         pure rules + tests (later)
  lib/actions/             server actions (validate → one RPC → ActionResult)
  lib/<domain>/            zod schemas, loaders and helpers (creators, agencies, campaigns, media-kit)
  lib/auth/permissions.ts  permission matrix (single source of truth)
  lib/supabase/            server / browser / admin clients
  components/              ui kit and domain components
  messages/                next-intl strings
  supabase/migrations/     inf schema migrations
  supabase/tests/          pgTAP (RLS per role, masking proofs)
  scripts/baseline/        generator + parts of the shared-objects baseline (local only, never applied to production)
  scripts/seed.ts          local demo data
  e2e/                     Playwright journeys
  docs/                    spec, progress, decisions, findings, runbook, guides
```

## Commands (run inside `influencer-portal/`)

| Command | What |
| --- | --- |
| `node scripts/db.mjs start` / `stop` / `reset` | Local Supabase (Docker Hub images; refuses remote targets). Reset rebuilds from the shared baseline + every migration |
| `npm run gen:sql` | Regenerate migrations from the permission matrix, settings registry, compensation schema and system presets (a unit test fails if stale) |
| `node scripts/db.mjs types` | Regenerate `lib/database.types.ts` after a schema change (CI checks drift) |
| `npm run seed` | Local demo data (staff password `Local-Demo-Password-2026`; Mailpit at http://127.0.0.1:54424 shows emails) |
| `npm run dev` | App on http://localhost:3200 (needs `.env.local`; copy `.env.example`, keys from `npx supabase status`) |
| `npm run typecheck` · `npm run lint` · `npm run format` | Static checks |
| `npm test` | Vitest (unit, codegen drift, message keys, contrast) |
| `npm run test:db` | pgTAP files in `supabase/tests` via psql (local DB only) |
| `npm run e2e` | Playwright against a production build; resets and seeds the local DB first (`E2E_RESET=0` to skip) |

Environment note: this cloud environment exports `SUPABASE_SERVICE_ROLE_KEY` for the B2B/B2C staging project. Never
use it. `lib/env.ts` refuses it with a local URL; scripts read `.env.local` first.
