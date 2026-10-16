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

## Portal conventions (from Phase 1)

- Next.js 16 App Router, TypeScript strict (no `any`), zod on client and server, Tailwind v4 + shadcn/ui.
- Database objects only in schema `inf`; RLS on every table, with pgTAP tests per role. Creators read lead data only
  through `SECURITY DEFINER` functions and `inf.creator_lead_feed`, with phone and email masked in the database.
- Money in integer paise (`bigint`), banker's rounding once per line item. Store UTC, display IST, Indian number format,
  Indian financial year (1 Apr – 31 Mar).
- The compensation engine (`lib/compensation`) and attribution logic are pure, deterministic and fully unit-tested
  before any UI uses them.
- Every screen has empty, loading, error and mobile states. The creator portal is mobile-first.
- No TODOs, placeholder screens or fake data in production code paths; mock data only in the seed script, which
  refuses to run against production.

## Folder structure (planned, `influencer-portal/`)

```
influencer-portal/
  app/(admin)/admin/…      staff console
  app/(creator)/creator/…  creator portal (mobile-first, PWA)
  app/(auth)/…             sign-in, verify code
  app/r/[code]/route.ts    tracking redirect
  app/api/…                health, metrics, public API, internal jobs
  lib/compensation/        pure engine + tests
  lib/attribution/         pure rules + tests
  lib/auth/permissions.ts  permission matrix (single source of truth)
  lib/supabase/            server / browser / admin clients
  components/              ui kit and domain components
  messages/                next-intl strings
  supabase/migrations/     inf schema migrations
  supabase/tests/          pgTAP (RLS per role, masking proofs)
  supabase/baseline/       generated shared-objects baseline (local only, never applied to production)
  e2e/                     Playwright journeys + seed
  docs/                    spec, progress, decisions, findings, runbook, guides
```

## Commands (from Phase 1)

To be filled in when the scaffold exists: `npm run dev`, `npm run typecheck`, `npm run lint`, `npm test`,
`npm run test:db`, `npm run e2e`, `npm run seed`.
