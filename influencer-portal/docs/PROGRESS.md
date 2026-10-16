# Progress

## Now

- **Current phase:** Phase 1 (Foundation), in progress.
- **Current step:** 1.1 scaffold.
- **Phase 0:** approved by the owner on 16 Oct 2026 ("approve all defaults"): every default in `PHASE0_FINDINGS.md` §7,
  the ERD, `SHARED_CHANGES.md` (S-1 to S-15, R-1 to R-5), the whitelist with the recommended hidden fields and
  first name + initial, the stage mapping and the integration contracts. Tagged `phase-0-done`.
- **Blockers:** none for Phase 1. Provider credentials, domain, Vercel and Sentry are needed later (HARD STOP 4); Phase 1
  uses mock providers.

## Phase 1: Foundation

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 1.1 | Scaffold: Next 16, TypeScript strict, Tailwind v4, shadcn-style UI kit, ESLint, Prettier, Vitest, Playwright, next-intl, zod-validated env, `.env.example`, CI workflow | `package.json`, `tsconfig.json`, `eslint.config.mjs`, `lib/env.ts`, `.github/workflows/influencer-portal-ci.yml` | env, formatting units |
| 1.2 | Local Supabase (Docker Hub images), shared-objects baseline generated read-only from production, guarded so it can never run on production | `supabase/config.toml`, `supabase/migrations/00000000000000_shared_baseline.sql`, `scripts/generate-baseline.*` | migrations apply on a fresh stack |
| 1.3 | Schema `inf`: permission tables generated from the matrix, staff, creators core, settings + versions + JSON-schema validator, audit log + trigger, jobs, domain events, notifications core, email codes, trusted devices, sessions, sign-in log, rate limits, terms, storage buckets | `supabase/migrations/2026101*_inf_*.sql`, `lib/auth/permissions.ts` | pgTAP: RLS per role, append-only, validator; Vitest: matrix ↔ SQL drift |
| 1.4 | Auth: Supabase clients, `proxy.ts` (session, idle timeout, CSP nonce, rate limits), staff sign-in (Google or password) + emailed code + trusted devices, creator email OTP + Google, session list and remote sign-out | `lib/supabase/*`, `proxy.ts`, `app/(auth)/*`, `lib/auth/*` | units for CSP, rate-limit keys, code flow; Playwright sign-in |
| 1.5 | Design tokens and components (empty, loading, error states), admin shell (sidebar, ⌘K), creator shell (bottom nav, PWA), settings screens, audit log viewer, staff and roles, system status, account and sessions | `app/globals.css`, `components/ui/*`, `app/(admin)/*`, `app/(creator)/*` | component units; Playwright role guards, mobile |
| 1.6 | Notification adapters (SMTP, Resend, Brevo, Meta Cloud, Mock) and delivery queue; seed framework (local only); Playwright suite; phase gate | `lib/notify/*`, `scripts/seed.ts`, `e2e/*` | units for adapters; gate |


## Phase 0: Discovery and design

### Plan

| Step | What | Output |
| --- | --- | --- |
| 0.1 | Inspect the production database read-only: tables, columns, functions (`lead_intake`), triggers, RLS, grants, catalogue, Witty's code storage, CRM status sources, commission data, cron, storage, auth, advisor | Findings §2–§3 |
| 0.2 | Inspect the B2B and B2C apps for conventions | Findings §4 |
| 0.3 | Proposed ERD | `ERD.md` |
| 0.4 | Shared-object changes with justification | `SHARED_CHANGES.md` |
| 0.5 | Creator-visible lead field whitelist | `LEAD_FIELD_WHITELIST.md` |
| 0.6 | Stage mapping proposal | `STAGE_MAPPING.md` |
| 0.7 | Integration contracts | `INTEGRATION_CONTRACTS.md` |
| 0.8 | Tech decisions, risk register, open questions | Findings §5–§7 |
| 0.9 | State files: `PROGRESS.md`, `DECISIONS.md`, root `CLAUDE.md` | |

No migrations, no app code and no tests in Phase 0 (the spec says "no app code yet"). The phase gate items that need code
(migrations, typecheck, lint, tests, seed) start in Phase 1. The Mermaid diagrams were parse-checked with `mermaid@11.4.1`.

### Requirement checklist (spec Section 22, Phase 0, and Section 23)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Inspect all tables, columns | Done | Findings §2; 141 `student_leads` columns in the whitelist |
| Inspect functions, especially `lead_intake()` | Done | Findings §3.1 (full source read) |
| Inspect triggers | Done | Findings §3.2 |
| Inspect RLS (and grants) | Done | Findings §3.3, `SHARED_CHANGES.md` §E |
| Inspect the `catalog_*` structure | Done | Findings §2; `catalog.*` views including `partner_rates_v` |
| How Witty stores source and referral codes | Done | `INTEGRATION_CONTRACTS.md` §1.1 |
| Where CRM and partner lead statuses live | Done | `STAGE_MAPPING.md` §1 |
| Whether Eduwit commission received per enrollment is recorded | Done | `INTEGRATION_CONTRACTS.md` §3 |
| Inspect existing Next.js apps for conventions | Done | Findings §4 |
| `PHASE0_FINDINGS.md` | Done | |
| Proposed ERD (Mermaid) | Done | `ERD.md` (8 diagrams, parse-checked) |
| Full list of shared-object changes with justification | Done | `SHARED_CHANGES.md` |
| Creator-visible lead field whitelist | Done | `LEAD_FIELD_WHITELIST.md` (5 ASK rows for the owner) |
| Stage-mapping proposal | Done | `STAGE_MAPPING.md` |
| Integration contracts (Witty code format, CRM stage events, commission receipts) | Done | `INTEGRATION_CONTRACTS.md` |
| Final tech decisions list | Done | Findings §5 |
| Risk register | Done | Findings §6 |
| Ask every open question the codebase can't answer (Section 23) | Done | Findings §7: Q1, Q3, Q4 answered; Q10 recommended; Q2, Q5–Q9, Q11–Q20 asked |
| Justify `inf_` prefix vs dedicated schema (spec 2.1) | Done | D-01 |
| Pull the production schema into a local or branch database (build prompt, environment rule 1) | Deferred to Phase 1 step 2 | It is part of setting up the dev database, which is Phase 1 work; approach needs Q13 |

### Phase 0 summary

- **Built:** the eight Phase 0 documents, the decisions log, this file, the root `CLAUDE.md`, the brand palette and the
  logo file. Nothing was changed in any database.
- **Key decisions (pending approval):** schema `inf`; Next.js 16; read-only sweeps instead of a trigger on
  `student_leads`; Route A (portal calls Witty's own code issuer) plus Route B (Witty recognises typed codes);
  commission receipts derived from both CRMs.
- **Known issues found:** legacy influencer objects expose students' full rows to 3 legacy accounts and store plain-text
  passwords (`SHARED_CHANGES.md` §E); leaked-password protection is off; shared Supabase Auth means creators will hold
  `authenticated` JWTs on the same project as every other product (RK-2).
