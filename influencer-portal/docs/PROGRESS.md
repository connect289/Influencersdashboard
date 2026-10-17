# Progress

## Now

- **Current phase:** Phase 10 (Scorecards, tiers, compliance and polish): steps 10.1 to 10.5 built; the final gate run is in progress, then `phase-10-done` and **HARD STOP 6
  (production go-live)**: waiting for the owner's approval and the items in `docs/RUNBOOK.md` (G-1 to G-29).
- **Open item from Phase 3 closed:** the intermittent CRM import failure was the per-IP staff sign-in limit (30 per 5
  minutes) being reached by the growing suite; staff sessions are now reused within a run (D-98).
- **Phases 1–3:** complete and tagged `phase-1-done` to `phase-3-done`.
- **Tags:** the git proxy in this environment refuses tag pushes; `phase-0-done` to `phase-10-done`
  exist in the local repository only. Push them from a normal clone with `git push origin --tags`.
- **Phase 0:** approved by the owner on 16 Oct 2026 ("approve all defaults"): every default in `PHASE0_FINDINGS.md` §7,
  the ERD, `SHARED_CHANGES.md` (S-1 to S-15, R-1 to R-5), the whitelist with the recommended hidden fields and
  first name + initial, the stage mapping and the integration contracts. Tagged `phase-0-done`.
- **Owner question (HARD STOP 5, does not block Phase 10):** how a leaderboard-rank bonus ranks creators (measure, population, timing, ties). Until answered, rank bonuses never accrue (D-141, D-152).
- **Blockers:** none. Provider credentials, domain, Vercel, Sentry, a Google OAuth client and (optionally) CAPTCHA keys are
  needed later (HARD STOP 4); everything runs on mock providers until then. Contracts need counsel's review of the
  clause library, consent text and stamp duty before go-live (RUNBOOK G-9 to G-11).

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


### Phase 1 requirement checklist (spec Section 22, Phase 1, plus the spec sections it touches)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Project scaffold (Next 16, TypeScript strict, no `any`) | Done | `package.json`, `tsconfig.json`, ESLint strict-type-checked with `no-explicit-any` |
| CI | Done | `.github/workflows/influencer-portal-ci.yml`: typecheck, lint, format, unit, build, audit, pgTAP on a local Supabase, types drift, Playwright |
| Env handling | Done | `lib/env.ts` (zod; refuses mismatched project keys, mock email in production), `.env.example` documents every variable |
| Staff auth: Google or password, emailed code always (also after Google) | Done | `app/(auth)/*`, `inf.mfa_issue/verify`, trusted devices; Google path built, not exercisable locally (needs a Google OAuth client, HARD STOP 4) |
| Creator auth: email OTP or Google | Done | OTP for invited accounts; Google with linking by verified email |
| Creator phone OTP (optional) | Deferred | Needs an SMS/WhatsApp provider (HARD STOP 4) |
| Roles and the permission matrix as single source of truth for RLS and UI | Done | `lib/auth/permissions.ts` → generated `inf.role_permissions`; `inf.has_perm`; UI hides items (`lib/nav.ts`) |
| Layouts for both portals | Done | Admin: sidebar, ⌘K, mobile drawer. Creator: mobile-first with bottom nav, PWA manifest and service worker |
| Settings framework (typed keys, schema per key, who/when) | Done | Registry → generated definitions; DB validates JSON Schema; versions, history, confirmation for CA/counsel items |
| Audit log | Done | `inf.audit_log` (append-only), row trigger with changed keys only, viewer with filters |
| Notification adapter skeleton | Done | Email (SMTP, Resend, Brevo, mock), WhatsApp (Meta, mock), in-app rows, delivery queue, job runner |
| Storage buckets | Done | Seven `inf-*` buckets; object policies arrive with the features that upload |
| Base schema and RLS with tests | Done | 7 migrations; RLS on every table; 142 pgTAP assertions incl. per-role access, privileges equal declared list, shared-table isolation |
| Design system and components | Done | Tokens from the logo with a WCAG contrast test (both themes); empty/loading/error/no-results states. Data grid: Deferred to Phase 2 (D-35) |
| Seed framework | Done | `scripts/seed.ts`: local only, idempotent, staff for every role, creators in five states, demo terms |
| Session timeout, device/session list, remote logout (spec 19) | Done | DB-enforced idle limit, account page, staff "sign out everywhere" |
| Rate limiting, CSP, security headers (spec 19) | Done | `inf.rate_check`, nonce CSP with `strict-dynamic`, HSTS, frame denial |
| i18n with next-intl, every string externalised (spec 3) | Done | `messages/en.json` with a key coverage test |
| `/api/health`, `/api/metrics/summary` (spec 18) | Done | Booleans only on the public health check; metrics need the internal key |
| Observability: Sentry | Deferred | Needs a DSN (HARD STOP 4); structured redacted logs, request ids, system status page are in place |
| Phase gate: migrations on a fresh database and on the production-schema copy | Done | Each reset builds from nothing: shared baseline (the production copy) + all `inf` migrations; the baseline's guard proven to abort on a database that has the shared objects |
| Phase gate: typecheck, lint, unit, RLS, Playwright green | Done | 405 unit tests, 142 pgTAP assertions, 19 Playwright journeys |
| Phase gate: seed works | Done | Run twice in a row and in every e2e run |

### Phase 1 summary

- **Built:** the foundation above. Screens: staff and creator sign-in, verify code, password set/reset, no-access,
  admin overview (setup checklist from real configuration), staff and roles, settings, audit log, system status,
  account and sessions (both portals), creator home with action centre, terms acceptance, offline page.
- **Decisions:** D-20 to D-35 in `DECISIONS.md`. Notable: client grants as data (Supabase defaults otherwise expose
  every new function to `anon`), DB-enforced idle timeout, per-IP vs per-email rate limits, the staging service key
  found in this environment and guarded against (D-32).
- **Known issues / notes:** Google sign-in and phone OTP need external setup; Sentry needs a DSN; the not-found page
  for hidden screens returns HTTP 200 under streaming (D-30); local Supabase uses Docker Hub images (D-24).

## Phase 2: Creators and campaigns

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 2.1 | Creator profile completion: platforms, rate cards, portfolio, family/self contact hashes; KYC with PAN and bank encrypted (Vault key), masked display, Finance reveal (audited), verification workflow | `supabase/migrations/2026101800*_inf_creators.sql`, `app/(creator)/creator/profile/*`, `app/(admin)/admin/creators/[id]/*` | pgTAP: KYC visible only masked except Finance; encryption round-trip; creators see only own |
| 2.2 | Agencies, members, creator-granted permissions (view, act on deliverables, negotiate/sign, view earnings) | agency tables + RLS helper `inf.agency_can()` | pgTAP per grant |
| 2.3 | Admin creator CRM: server-paginated grid (TanStack) with saved filters and views, kanban pipeline (dnd-kit), Creator 360° (profile, platforms, KYC status, outreach, tasks, audit), bulk CSV import with validation and dedupe (handle/phone/email) and error report, bulk invite/tag/owner, outreach log, follow-ups widget, tasks | `app/(admin)/admin/creators/*`, `components/data-grid/*` | unit: CSV parser and dedupe; Playwright: import + invite |
| 2.4 | Invitations (auth account + email), self sign-up page and onboarding wizard (profile, platforms, KYC, terms, compliance mini-course and quiz), admin approval with auto-approval rule | `app/(auth)/signup/*`, `app/(creator)/creator/onboarding/*` | Playwright journey 1 |
| 2.5 | Campaigns (builder, programmes from catalog, eligibility rules, visibility, slots, budget), marketplace for eligible creators, invites (accept/decline/counter), applications (pitch, proposed terms, samples), review (shortlist/accept/reject with reason templates/counter) with negotiation threads and structured counter-offers | `app/(admin)/admin/campaigns/*`, `app/(creator)/creator/campaigns/*` | pgTAP: eligibility-limited marketplace visibility; Playwright: apply → counter → accept (deal auto-creation lands in Phase 3) |
| 2.6 | Media kit (web page + PDF) from profile data | `app/(admin)/admin/creators/[id]/media-kit`, `lib/pdf/*` | unit snapshot of PDF data |
| 2.7 | Phase gate | | |

### Phase 2 requirement checklist (spec Section 22 Phase 2, and spec 4, 5, 7, 13, 16, 17)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Creator profile: identity, platforms (followers, views, engagement, audience JSON, source), rate cards, portfolio | Done | `20261018000100_inf_creator_profile_kyc.sql`; Profile screen; Creator 360 Profile tab |
| Linked family/team numbers and emails for self-referral checks | Done | Stored as keyed HMAC hashes + last two digits only (D-38) |
| KYC: PAN and bank account encrypted, masked display, Finance reveal (audited), verification with who/when, proof file | Done | Vault key `inf_pii_key` (D-36), `kyc_view` / `kyc_reveal` / `kyc_verify`, private bucket with signed upload (D-39); re-verification on change (D-37) |
| GST status and GSTIN (embedding the PAN) | Done | Validated in zod and in SQL |
| Agencies, members, creator-granted permissions (view, act on deliverables, negotiate/sign, view earnings) | Done | `20261018000200_inf_agencies.sql`, agency portal, creator Manager page (D-42–D-44). "Act on deliverables" and "view earnings" grants are stored and enforced by `agency_can()`; the screens they unlock arrive with deliverables (Phase 5) and earnings (Phase 7) |
| Payout bank details always the creator's | Done | Agencies never read KYC or creator contact details (pgTAP 010) |
| Pipeline Prospect → … → Archived, Blocked flag, Dormant auto-flag after N days | Done | Stage moves with status sync (D-47); nightly dormancy with reactivation (D-46) |
| Kanban and table views with saved filters | Done | dnd-kit board (keyboard accessible), TanStack server-paginated table, URL filters, saved and shared views (D-45) |
| Filters: platform, followers, niche, language, city/state, tier, owner, status | Done | `inf.creator_rows` |
| Filters: deal type, performance | Deferred | Need deals (Phase 3) and scorecards (Phase 9) (D-49) |
| Creator 360°: profile, platforms, KYC, outreach timeline, tasks, agency, audit history | Done | Tabs shown only for modules that exist |
| Creator 360°: deals, contracts, briefs, deliverables, leads (unmasked for authorised staff), earnings, scorecard, messages, documents | Deferred | Added by Phases 3–9 as those modules are built (no placeholders, D-49) |
| Bulk CSV import with validation, de-duplication (handle, phone, email, platform handle), error report | Done | Check-then-import, downloadable report, history (D-48) |
| Bulk invite, tag, assign owner (and move stage) | Done | Table bulk toolbar |
| Outreach log, follow-up reminders, task assignment, "Overdue follow-ups" widget | Done | Creator 360 Outreach/Tasks, Tasks page, overview widgets, assignee notifications |
| Media kit: shareable web page and PDF | Done | `/m/<handle>` + PDF (public, opt-in, no contact details), internal PDF with rates, creator Media kit page, profile photo |
| Invitations and self sign-up | Done | Staff invites (email + auth account), public `/signup` with honeypot and rate limits (D-50, D-53) |
| Onboarding wizard: profile, platforms, KYC, terms, compliance mini-course with quiz | Done | Course v1 with hidden answers, graded in the database (D-51); legal review before go-live (RUNBOOK) |
| Admin approval with configurable auto-approval | Done | Approvals queue, approve / ask for changes / decline, `creators.lifecycle` settings (D-52) |
| Campaign builder: objective, programmes, budget, slots, dates, eligibility, deliverables, visibility | Done | Programmes from the catalogue as soft references (D-55) |
| Campaign builder: deal presets, brief/contract/deliverable templates | Deferred | Presets arrive with the compensation engine (Phase 3), contract templates (Phase 4), brief and deliverable templates (Phase 5); the builder shows a compensation summary meanwhile |
| Marketplace for eligible creators (cards with programme, deliverables, compensation summary, deadline, slots left) | Done | Creator-safe projection without budget or notes (D-56) |
| Invite-only campaigns: invite, accept, decline, counter | Done | Agencies with the negotiate grant can answer for the creator (D-59) |
| Application review: shortlist, accept, reject with reason templates, counter; negotiation thread and structured counter-offers | Done | One open offer at a time, the other side accepts (D-57, D-60) |
| On acceptance, auto-generate deal, contract, brief and deliverables | Partial | Acceptance records the agreed terms and emits `application.accepted`; Phase 3 consumes it to create the deal, Phases 4–5 the contract, brief and deliverables (D-58). Blocked only by those modules not existing yet |
| RLS on every new table, tests per role; no creator/agency path to student phone or email | Done | 7 Phase 2 migrations, pgTAP 009–014; anon allow-list test updated for the public media kit only |
| Every screen: empty, loading, error, mobile states | Done | Shared state components on every list; creator portal mobile-first with the "More" sheet (D-40) |
| Gate: migrations on a fresh database and on the production-schema copy | Done | Fresh reset each run. Production re-checked read-only on 17 Oct 2026: all 101 shared objects the portal reads are identical to the local copy (one local-only sequence-name artefact fixed); production has no `inf` schema |
| Gate: typecheck, lint, format, unit, RLS, Playwright | Done | 1,190 unit tests, 317 pgTAP assertions (14 files), 37 Playwright journeys (2 screenshot specs skipped by design) |
| Gate: seed works | Done | Idempotent; adds a demo agency, demo catalogue programmes (local only) and two demo campaigns |
| Gate: docs updated | Done | `DECISIONS.md` D-36–D-62, this file, `RUNBOOK.md` (started), `CLAUDE.md` conventions |

### Phase 2 summary

- **Built:** creator profiles with encrypted KYC and an audited Finance reveal; agencies with creator-granted
  permissions and their own portal; the admin creator CRM (table and pipeline board, saved views, Creator 360, CSV
  import, outreach, follow-ups, tasks, bulk actions, ⌘K creator search); invitations, public sign-up, the onboarding
  wizard with the compliance course, and approvals; campaigns with the catalogue programme picker, the marketplace,
  invitations, applications, structured negotiation and acceptance; media kits as public pages and PDFs.
- **Fixed along the way:** a staff sign-in on a trusted device no longer asks for a code (D-61); a function prop passed
  from a server page to a client component (caught by e2e); null-unsafe ownership checks (D-41).
- **Decisions:** D-36 to D-62.
- **Not done in Phase 2, by design:** deal/contract/brief generation on acceptance (Phases 3–5), the extra Creator 360
  tabs and filters that depend on later modules, CAPTCHA on sign-up (needs keys).

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

## Phase 3: Deals and the compensation engine

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 3.1 | Compensation config schema (zod), system presets, generated JSON Schema for the database check | `lib/compensation/{money,schema,presets,events}.ts`, `20261018000650_inf_comp_config_schema.sql` | schema units, codegen drift |
| 3.2 | Pure engine: full deterministic replay, stable ledger keys, penalty proposals; ledger diff | `lib/compensation/{engine,diff}.ts` | 66 engine tests (every basis, slabs, recoupment, caps, floors, milestones per trigger, clawbacks, amendments, rounding, presets), mutation-checked |
| 3.3 | Simulator (scenario → events → engine) and TDS/GST estimate | `lib/compensation/{simulator,tax}.ts` | units |
| 3.4 | Deals database: presets, deals, immutable versions, amendments, TDS table, deal from accepted offer, dry-run | `20261018000700_inf_deals.sql`, `lib/deals/*`, `lib/actions/deals.ts` | pgTAP 015 (53), units |
| 3.5 | Screens: deals list, new deal, builder with live simulator, versions, dry-run, presets; creator and agency deal views with accept/decline and a read-only simulator; campaign default preset; Creator 360 deals tab | `app/(admin)/admin/deals/*`, `app/(creator)/creator/deals/*`, `components/deals/*` | Playwright journeys |
| 3.6 | In-app guides for every user type (Super Admin, Influencer Manager, Content Reviewer, Finance, Analyst, creator, agency, developer): a Help area in each portal with setup steps and how each module works, kept current by every later phase | `app/*/help/*`, `lib/guides/*` | units (every guide link resolves, every role has a guide), Playwright |
| 3.7 | Phase gate | | |

### Phase 3 summary

Built: the compensation config schema with a generated SQL check, three system presets, the pure engine (full replay,
stable ledger keys, penalty proposals) with a posting diff, the earnings simulator and TDS/GST estimate, deals with
immutable versions, proposals, amendments and a dry-run, deal creation from accepted campaign offers, the deal
builder with a live simulator, preset management, creator and agency deal views, and in-app guides for every user
type (owner request). Gate on 17 Oct 2026: typecheck, lint and format clean; 1,671 unit tests; 371 pgTAP assertions
(15 files); 46 Playwright journeys passed (2 screenshot specs skipped by design); migrations apply on a fresh
database; production re-checked read-only (all 101 shared objects identical, no `inf` schema). Deferred with reason:
ledger posting runner and penalty approvals (need deliverables and the ledger, Phases 5–7), the Finance TDS editing
screen (Phase 7).

### Phase 3 requirement checklist (spec Section 22 Phase 3, and spec 5 "Deals", 6, 11 TDS defaults, 13 auto-generation)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Compensation engine as a pure TypeScript module, deterministic, no I/O | Done | `lib/compensation/engine.ts` (full replay; D-63) |
| Every component type of 6.1 (fixed + milestones per trigger, commission bases, scope, slabs marginal/retroactive, caps, floors, recoupment none/full/partial, confirmation, clawback windows, effective dates, bonuses with AND/OR, penalties, additional fees, non-cash) | Done | `lib/compensation/schema.ts`; builder covers every field |
| Tests: every basis, both slab modes, recoupment, caps and floors, milestones per trigger, clawbacks inside/outside window, retroactive top-ups, amendments mid-period, rounding, exact presets | Done | `engine.test.ts` (66) + mutation checks; `money`, `schema`, `diff`, `tax`, `simulator` tests |
| Presets Commission only / Fixed + Commission / Fixed only; admins save new presets | Done | Generated system presets; preset pages, "Save as preset" |
| Deal builder with live earnings simulator (per-component breakdown, TDS, net payout, Eduwit cost per enrolment and margin from catalogue commission data) | Done | `components/deals/terms-editor.tsx`, `simulator.tsx`; catalogue estimate via `inf.commission_estimate` (S-11) |
| Creator read-only simulator without Eduwit margin or commission amounts | Done | Server-side `simulateMyDeal` + `forCreator` (D-75, D-79) |
| Deals and immutable versions; any change after agreement is an amendment | Done | `20261018000700_inf_deals.sql` (D-71); pgTAP 015 proves immutability |
| Validated JSONB config with a generated SQL check (D-05) | Done | `inf.comp_config_errors` = generated JSON Schema + cross-field rules; SQL and zod agree on the shared corpus |
| Recompute / dry-run before amending | Done | Dry-run tab over a projected scenario, recorded in `comp_runs` (D-76). The "against posted entries" mode arrives with the ledger (Phase 7) |
| Ledger posting keyed on deal version + rule + subject + event, idempotent | Partial | Keys and the posting diff are built and tested (`diff.ts`); the runner that posts them needs the ledger tables and domain events of Phases 5–7 |
| Deal auto-generated when a campaign offer is accepted | Done | Accept action + `deal.from_application` job (D-74). Contract, brief and deliverables follow in Phases 4–5 |
| TDS table with defaults marked "confirm with CA" | Done | `inf.tds_sections` (194H, 194J, 194R); Finance editing screen arrives with the Finance module (Phase 7); function and permission exist now |
| Campaign builder: default deal preset (deferred in Phase 2) | Done | Campaign form, `campaign_save` |
| Creator 360: deals tab; creator CRM deal-type filter (deferred in Phase 2) | Done | D-78 |
| Penalty proposals table and approval | Deferred | Proposals are computed by the engine now; storing and approving them needs deliverables (Phase 5) and the ledger (Phase 7) |
| In-app guides for every user type (owner request) | Done | Help in all three portals, nine guides, search, contextual links (D-77) |
| RLS on every new table, tests per role; no creator/agency path to student phone or email | Done | pgTAP 015 (53) + 013 job check |
| Every screen: empty, loading, error, mobile states | Done | Shared state components; creator deal pages mobile-first |


## Phase 4: Contracts

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 4.1 | Pure contract template engine: a restricted rich-text document model (the editor's JSON, whitelisted nodes, rendered by us, so no HTML is ever trusted), variables `{{a.b}}` with a picker list, block and inline conditionals `{{#if}}…{{else}}…{{/if}}`, compensation tables generated from the deal config, canonical JSON + SHA-256, word-level diff between versions; seed of 20 clause categories marked "DRAFT — requires legal review" | `lib/contracts/*` | exhaustive units |
| 4.2 | Database: clause library with versions and legal-review marks, templates with ordered clauses, contracts, immutable contract versions, clause comments, change requests, versioned consent texts, signing codes (6 digits, 10 min, 5 attempts, cooldown), append-only signatures; states Draft → Sent → In negotiation → Ready to sign → Signed by creator → Countersigned (Active) → Completed / Terminated / Expired, plus Void and Superseded | `2026101900xxxx_inf_contracts.sql` | pgTAP per role, immutability, append-only |
| 4.3 | Admin: clause library and template editor (rich-text editor, variable picker, conditionals, clause flags, legal-review gate), contract generation from a deal, versions with diffs | `app/(admin)/admin/contracts/*`, `components/contracts/*` | Playwright |
| 4.4 | Creator negotiation: clause-anchored comments, suggested edits on negotiable clauses only, structured compensation counter-offer (creates a proposed deal version), admin accept / reject / counter, every round a new version with a diff, deadline reminders | creator and agency contract pages | Playwright |
| 4.5 | OTP click-sign and countersign: confirm each section, typed legal name, versioned consent, code by the configured channel(s), full signature evidence (version, document hash, IP, user agent, UTC/IST), final PDF with a signature certificate stored immutably and sent to all parties, hash re-verified on every download, deal activated on countersign | `lib/contracts/pdf.tsx`, routes | units + Playwright |
| 4.6 | Amendments (new contract linked to the parent, from an accepted deal amendment), renewals (clone deal and contract), expiry reminders at 30/15/7 days, stamp duty note and reference field | jobs, nightly | pgTAP + units |
| 4.7 | Guides updated for every role; phase gate | `lib/guides/content/*` | gate |

### Phase 4 summary

Built: a whitelisted rich-text document model rendered by our own code; a template language with variables and
conditionals; the clause library (20 draft clauses, versions, flags, legal review by Super Admins) and a Tiptap
template editor with a variable picker and a live preview per deal type; contracts generated from a deal's terms in
force (drafted automatically for accepted campaign offers, campaign or default template); clause-anchored comments,
suggested wording on negotiable clauses and structured compensation counter-offers, answered by accept / counter /
decline, each round a new version with a word diff; OTP click-sign with section confirmations, typed legal name and
versioned consent, countersignature by the Authorised Signatory, the signed PDF with a signature certificate stored
write-once and emailed to every party, hash re-verification on every download; amendments, renewals, negotiation and
expiry reminders; guides for every role. Gate on 17 Oct 2026: typecheck, lint and format clean; 2,010 unit tests; 429
pgTAP assertions (16 files); 57 Playwright journeys passed (2 screenshot specs skipped by design); migrations apply on
a fresh database built from the production baseline; seed works; production re-checked read-only (all 101 shared
objects identical, hash `685ba089…`, no `inf` schema, no `inf-*` buckets). Nothing outside schema `inf` was added
beyond the approved storage bucket (S-4).

### Phase 4 requirement checklist (spec Section 22 Phase 4, and spec 8, 13 auto-generation, 14 campaign template)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Clause library CRUD with the 20 categories, flags (required, negotiable, locked, deal types), versioning (old contracts keep their version) | Done | `/admin/contracts/clauses`, `inf.clause_save` (new version on change) |
| Template editor (Tiptap): insert clauses, variable picker, conditional blocks | Done | `components/contracts/template-editor.tsx`, `rich-editor.tsx` (D-81) |
| Compensation sections generated from the deal config; never typed by hand | Done | Deal tables and texts in `lib/contracts/variables.ts`; counter-offers change the deal first (D-87) |
| Seed draft clauses marked "DRAFT — requires legal review"; setting that blocks sending until a Super Admin reviews | Done | `lib/contracts/library.ts`, legal-review gate (D-84); seed marks reviewed locally only (D-85) |
| Contract states Draft → … → Completed / Terminated / Expired, Void, Superseded | Done | `inf.contracts` status check; pgTAP 016 |
| Creator review on mobile and desktop; comments on any clause | Done | `/creator/contracts/[id]`, `clause-thread.tsx` |
| Edits only on negotiable clauses (suggestion mode) | Done | DB refuses others; D-86 |
| Structured compensation counter-offer creating a deal version | Done | `counter.ts`, `inf.deal_version_from_counter` (D-87) |
| Admin accepts, rejects or counters each request; every round a new version with a visual diff | Done | Change requests tab, Versions tab (D-88) |
| Deadline and reminder schedule for negotiations | Done | `negotiation_deadline`, `inf.contracts_remind` (D-95) |
| OTP click-sign: confirm each section, typed name, versioned consent, code on configured channel(s), enter code | Done | `sign-panel.tsx`, D-89 to D-91; WhatsApp via the mock adapter until credentials (HARD STOP 4) |
| Signature evidence: signer, role, version, document SHA-256, typed name, consent version, channel and reference, IP, UA, UTC and IST | Done | `inf.signatures`; certificate page |
| Countersign by the Authorised Signatory through the same flow | Done | E2E journey |
| Final PDF with signature certificate, stored immutably, copy sent to all parties | Done | `finalize.ts`, `pdf.tsx`, `contract.finalize` job (D-92) |
| Re-verify the hash on every download; flag the contract if it changed | Done | `/api/contracts/[id]/pdf`, `inf.contract_integrity`, `inf.contract_flag` |
| OTP rules: 6 digits, 10-minute expiry, 5 attempts, rate-limited resend, logged | Done | Settings-driven; codes and attempts in `inf.contract_sign_codes`, audit on signatures |
| Amendments linked to the parent; renewals clone the deal and contract; expiry reminders 30/15/7 | Done | D-93 to D-95 |
| Stamp duty note in settings and nullable `stamp_duty_reference` | Done | D-97 |
| Contract auto-generated on accepted campaign offers; campaign builder contract template | Done | D-96 |
| Contracts in each state in the demo seed | Partial | The seed has a sent demo contract and Playwright drives the full lifecycle; seeding every state (needs the server-side PDF step) joins the demo-mode seed in Phase 10 |
| Notifications: contract sent, changed, countered, ready to sign, signed, countersigned, expiring (mandatory) | Done | `inf.contract_notify` → `inf.notify` (in-app, with email copies queued; creator notices mandatory) |
| Outbound webhook `contract.signed` | Deferred | Webhooks are Phase 10 (spec 19); the domain event `contract.countersigned` is emitted now |
| Guides updated for every role | Done | Super Admin, Influencer Manager, creator, agency, developer guides |
| RLS on every new table with tests per role; no creator/agency path to student data | Done | pgTAP 016 (58); contracts never touch lead data |
| Every screen: empty, loading, error, mobile states | Done | Shared state components; creator contract pages mobile-first |


## Phase 5: Briefs and deliverables

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 5.1 | Pure modules: the deliverable workflow (states, per-deliverable stage toggles, allowed moves per side, overdue flag from per-stage due dates, revision counting), the compliance scan (banned phrases and safe patterns, configurable disclosure terms per platform, the ASCI checklist), platform URL validation and oEmbed URLs, the brief document (structured fields + rich text, generated from a template and the deal), and content events → engine events for penalty proposals | `lib/content/*` | exhaustive units |
| 5.2 | Database: banned claims, brief templates, briefs with immutable versions, acknowledgements, Q&A; deliverables with stage toggles, due dates, revision limit, transitions history; versioned submissions (text, file, link), review comments (video timestamp, image region, resolve/reopen), compliance checks with overrides, published posts with verification, metric snapshots (source field for future APIs), penalty proposals; signed resumable uploads to `inf-deliverables` | `20261020000100_inf_content.sql` | pgTAP per role |
| 5.3 | Briefs: templates (admin), the brief builder (Tiptap fields, approved claims from the catalogue, banned claims, disclosures, deliverables table, references, assets, hashtags, CTA, FAQs), versions and publish, creator acknowledgement (milestone event), Q&A; auto-generated with the deal for accepted offers | `app/(admin)/admin/briefs/*`, creator and agency brief pages | Playwright |
| 5.4 | Deliverables: generated from the deal and brief, stage toggles and due dates, admin kanban + list and review queue, creator list; submissions with resumable upload; review with a video player and timestamped comments, image annotations, resolve/reopen; approve / request changes; revision limit with admin-approved extra revisions (optional fee) | `app/(admin)/admin/content/*`, `components/content/*` | Playwright |
| 5.5 | Compliance: banned-claims library, automatic caption/script scan and disclosure check on every submission, the ASCI checklist required before approval, overrides with a reason | | units + Playwright |
| 5.6 | Go-live (URL validation per platform, YouTube oEmbed preview), reviewer verification (live, disclosure, matches the approved version), metrics with screenshots at checkpoints, due-date reminders and overdue escalation, penalty proposals from the deal's rules with approval | jobs, nightly | pgTAP + units + Playwright |
| 5.7 | Guides for every role, navigation, seed, phase gate | | gate |

### Phase 5 summary

Built: brief templates (defaults, stages and due-date offsets) and one versioned brief per deal, created with the deal
for accepted campaign offers (campaign template or default; approved claims written from catalogue facts; programmes
shown with live catalogue details), published to the creator, acknowledged per version (starting the deliverables and
emitting the milestone event) with a Q&A thread; deliverables with per-deliverable stage switches, due dates, revision
limits and full transition history, on a workflow defined once in TypeScript and mirrored in SQL (a generated pgTAP
matrix proves they agree for all 14 × 13 × 64 combinations); versioned, immutable submissions (text, files through
signed resumable uploads, links); a review workspace with timestamped video comments, image area annotations,
resolve/reopen, server-recorded banned-claims and disclosure scans with reasoned overrides, the ASCI checklist at the
last pre-publish approval, and extra revision rounds approved by a manager; go-live with per-platform URL checks and
YouTube oEmbed, reviewer verification, metrics with screenshots at checkpoints, due/overdue/escalation/metrics
reminders, and penalty proposals computed by the compensation engine for a manager to approve; staff list, board and
review queue, the deal Content tab, creator and agency pages (mobile-first), the banned-claims editor and guides for
every role. Gate on 17 Oct 2026: typecheck, lint and format clean; 2,450 unit tests; 551 pgTAP assertions (18 files);
72 Playwright journeys passed (2 screenshot specs skipped by design); migrations apply on a fresh database built from
the production baseline; seed works; production re-checked read-only (all 101 shared objects identical, hash
`685ba089…`, no `inf` schema, no `inf-*` buckets). Nothing outside schema `inf` was added; the brief functions only
read `catalog_*` (approved R-1).

### Phase 5 requirement checklist (spec Section 22 Phase 5, spec 10 and 16)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Brief builder: objective, programmes (live from the catalogue), audience, key messages (Tiptap) | Done | `components/content/brief-editor.tsx`, `brief-fields.tsx`; `inf.brief_detail` returns programmes live |
| Approved claims from catalogue facts; banned claims; mandatory disclosures | Done | `approvedClaims()` (D-102), banned list copied at creation, disclosure rules from the template |
| Do's and don'ts, tone, languages, deliverables table (type, platform, count, duration, aspect ratio, due dates) | Done | Brief fields; deliverables shown from the deal's deliverable rows with specs and due dates |
| References, moodboard, brand assets, hashtags, mentions, FAQs | Done | References (links), assets in the private `inf-briefs` bucket (images, videos, fonts, archives) |
| CTA with auto-inserted tracking link, code and QR per deliverable | Deferred | Tracking links, codes and QR arrive in Phase 6; the CTA text field is ready and the guide says so |
| Templates; auto-generated from the campaign template with the deal | Done | `/admin/briefs/templates`, campaign builder field, `setupContentForDeal` (D-101) |
| Versioned; creator acknowledgement as a timestamped event that can trigger a milestone; Q&A thread | Done | `inf.brief_publish`, `inf.brief_acknowledge` (`brief.acknowledged`), `brief_questions` (D-100) |
| Brief links to its deal and contract | Done | Brief header links to the deal, whose page lists its contracts |
| Deliverable states incl. Cancelled and computed Overdue; stages switchable per deliverable | Done | `lib/content/workflow.ts`, `inf.deliverable_next`, matrix test (D-99) |
| Kanban plus list | Done | `/admin/content` list and board (read-only board, D-112); creator grouped list |
| Submissions: text, files (video, image, PDF) via resumable upload, links; every submission versioned | Done | `uploader.ts` (TUS over 6 MB, D-106), immutable `deliverable_submissions` |
| Video player with timestamped comments that seek; image annotations (point or region); resolve/reopen | Done | `components/content/media-review.tsx` (D-107) |
| Caption checks: banned-claims scan and configurable disclosure rule | Done | `scanSubmission`, `content.review` setting, server-recorded (D-103) |
| Revision limit; extra revisions with admin approval and optional fee | Done | D-105; fee paid through the ledger in Phase 7 |
| Go-live: URL validation per platform, oEmbed where available, reviewer verification (live, disclosure, matches) | Done | `checkPostUrl`, YouTube oEmbed, `inf.post_verify` (D-108) |
| Metrics with screenshots at checkpoints; `source` field for future APIs | Done | `post_metric_snapshots` (D-109) |
| Due-date reminders and overdue escalation | Done | `inf.content_remind` in the nightly job (D-110) |
| Late delivery (and missed, disclosure) proposes penalties per the deal; approval | Done | `penalties.refresh` job, `/admin/content/penalties` (D-111); posting to the ledger is Phase 7 |
| ASCI checklist per deliverable required before approval | Done | D-104 |
| Banned-claims list configurable; matches block approval unless overridden with a reason | Done | `/admin/content/claims`, `compliance.manage`, `compliance.override` (D-103, D-113) |
| Contract compliance tracker per creator (spec 16) | Deferred | Needs the scorecard data of Phase 9; obligations met/missed are recorded now (transitions, checks, penalties) |
| Notifications for brief, submission, review, comments, verification, reminders | Done | `inf.content_notify` → `inf.notify` (in-app plus queued email copies) |
| Guides for every role | Done | Content Reviewer guide rewritten; Influencer Manager, creator, agency, Super Admin settings and developer guides |
| RLS on every new table, tests per role; no creator or agency path to student data | Done | pgTAP 018 (118) and 017 matrix; content never touches lead data |
| Every screen: empty, loading, error, mobile states | Done | Shared state components; creator and agency pages mobile-first; Deliverables is a phone tab |

## Phase 6: Attribution and lead pipeline

Approved approach (Phase 0, SHARED_CHANGES S-3, S-6, S-7, S-8, S-9, S-12; STAGE_MAPPING §4; INTEGRATION_CONTRACTS §1):
read-only sweeps from schema `inf`, **no trigger on `student_leads`, no new column, no change to `lead_intake()`**; the
redirect calls Witty's own `w2_issue_code()` (the portal's only write path into another product's tables). Everything
runs against the local copy of the shared schema; connecting the sweep to live leads is go-live work (HARD STOP 6).

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 6.1 | Pure modules: creator code format and generator, link building (Witty deep link with the message template, website landing page, custom URL with UTMs, short link), crawler detection, the attribution rules (window, model, duplicate with grace and re-enquiry, self-referral, one credited first touch, manual decisions are sticky), stage mapping (priority rules, never backwards, fallback alert), fraud signals | `lib/attribution/*` | exhaustive units |
| 6.2 | Database: tracking links, clicks, lead attributions with decision history, fraud flags, stage mappings (seeded from STAGE_MAPPING.md), stage events, the creator-safe `creator_lead_feed` (masked in the database), sync state; masking and `lead_ref` (keyed hash), the sweep's gather and apply functions, manual override, backfill, `witty_resolve_code` (R-1), Realtime publication for the feed (S-6) | `20261021000100_inf_attribution.sql` | pgTAP per role and masking proofs |
| 6.3 | Links: creator and staff link builder (deal, deliverable, programme), `/r/<code>` redirect (click log with hashed IP, bot detection, Route A access code with timeout fallback), QR PNG and SVG, public creator API for the website | `app/r/[code]/route.ts`, `app/api/public/v1/*` | units + Playwright |
| 6.4 | Sweep job (`inf-lead-sync`, every minute): gather → pure rules → apply; stage events, domain events, creator notifications; fraud evaluation | `app/api/internal/lead-sync`, `lib/attribution/sync.ts` | units + pgTAP |
| 6.5 | Creator lead pipeline: kanban, table with filters and saved views, lead drawer with timeline, Realtime, masked CSV export; agency view with the view grant | `app/(creator)/creator/leads/*` | Playwright |
| 6.6 | Admin attribution console: all leads with role-based detail, attributions, manual override with reason, fraud review queue, stage mapping editor, backfill tool | `app/(admin)/admin/leads/*` | Playwright |
| 6.7 | Guides, seed (test leads through the local `lead_intake()`), phase gate, go-live notes | | gate |

### Phase 6 summary

Tracking links (one created automatically for every deliverable, plus creator- and staff-made links for a deal, post
and programme), the `/r/<code>` redirect (click log with an HMAC of the IP, crawler detection, Witty access code with a
1.5 s fallback, inactive-link page), PNG and SVG QR codes and the public creator API for the website; the attribution
sweep (read-only gather → pure rules and stage mapping → apply), with per-campaign model and message overrides, sticky
manual decisions, fraud signals that only flag, and the `LEAD_SYNC` switch that keeps live leads untouched until
go-live; the masked creator and agency pipeline (board, table, filters incl. programme, saved views, drawer with the
stage timeline and days per stage, Realtime, masked CSV export); the staff console (all leads as table or board,
contacts only for `lead.contacts`, credit and reject with a reason, fraud review, stage rule editor, re-run tool);
guides for every role; seed links and test leads attributed through the same sweep code. Two real defects were found
and fixed on the way: Witty's `w2_issue_code` needed a `search_path` (D-123) and zod 4 enum-keyed records rejected
partial stage facts. Gate on 17 Oct 2026: typecheck, lint and Prettier clean; 2,730 unit tests; 629 pgTAP assertions
(19 files) on a fresh database built from the production baseline; 84 Playwright journeys passed (2 screenshot specs skipped by design); seed works and is idempotent;
production re-checked read-only (all 101 shared objects identical, hash `685ba089…`; `b2c_lead_status_v` columns and
`w2_issue_code` configuration match the local copy; no `inf` schema, no `inf-*` buckets). Nothing outside schema `inf`
was created or changed: no trigger on `student_leads`, no new shared column, `lead_intake()` untouched (S-3, S-12).

### Phase 6 requirement checklist (spec Section 22 Phase 6, spec 9)

| Requirement | Status | Where / note |
| --- | --- | --- |
| A tracking code and link for every creator, deal, deliverable (and optional programme) | Done | Auto-created per deliverable (`inf.deliverable_link_auto`, D-127); link builder for extra links with deal, post and programme |
| Witty deep link with a configurable message (per campaign) containing the code | Done | `attribution.links` setting; campaign override `link_message` (must keep `{code}`, D-128); `renderMessage` |
| Website landing link with UTMs; public read-only creator API | Done | `landingUrl`; `GET /api/public/v1/creators/<handle>` (D-125) |
| Custom URL with UTMs | Done | `withUtm`, https only |
| `/r/<code>` logs the click and redirects; QR PNG and SVG for every link | Done | `app/r/[code]/route.ts` (D-116); `/api/links/<id>/qr` |
| Creators generate links for programmes in their campaigns | Done | `inf.link_create` checks campaign programmes; agencies with negotiate and sign too |
| Attribution window (default 90 days), model (first, last, first with assisted), per-campaign override | Done | `attribution.rules`; `decide`; `modelFor` (D-117, D-128) |
| Duplicate rule with a PII-free reason shown to the creator | Done | `existing_lead` reason; grace and re-enquiry settings |
| Self-referral (own KYC or contacts, flagged family numbers) | Done | Phone, email and declared contacts (hashed) in `inf.lead_sync_candidates` |
| Fraud signals to review, never automatic rejection (velocity, device or IP hash, no Witty reply, off-hours, junk rate) | Done | `lib/attribution/fraud.ts`, `inf.fraud_apply`, review queue (D-120) |
| Manual override with mandatory reason and audit entry | Done | `inf.attribution_override` (decision history plus `audit_row`) |
| Implementation approved least-invasive, re-runnable for backfill | Done | Sweep, no trigger (D-04, S-3); `leads.rerun`, `leads.backfill`, Tools page; `LEAD_SYNC` gate (D-122) |
| Creators see everything except phone and email, masked in the database; exports masked | Done | `inf.creator_lead_feed`, `mask_phone`, `mask_email` (D-119); `/api/leads/export` |
| Approved field whitelist; internal fields hidden | Done | `lead_visibility.creator` setting (Phase 0 approval) |
| Creator stages mapped via `stage_mappings` with reason categories for terminal states | Done | Editable rules, never backwards, unmapped alert (D-118) |
| Kanban, table with filters (campaign, deal, deliverable, link, programme, stage, temperature, city or state, dates) and saved views | Done | `components/leads/*` (D-129) |
| Drawer: stage timeline, source content, programme, days per stage, earning status | Done; earning values deferred to Phase 7 | Timeline, source, programme and days per stage are shown. The earning status reads "pending" until the Phase 7 ledger supplies accrued, confirmed, paid and clawed back (D-121); the ledger is Phase 7 scope |
| Realtime on the creator-safe projection only | Done | Publication holds `inf.creator_lead_feed` only (S-6); `RealtimeRefresh` |
| Staff see the same pipeline across creators, with details per role | Done | `/admin/leads` table and board; contacts only with `lead.contacts` |
| Stage sync least coupled; the portal never writes CRM fields | Done | Read-only gather from `student_leads` and `b2c_lead_status_v`; writes only to `inf` |
| Phase 5 carry-over: brief CTA with auto-inserted link, code and QR per deliverable | Done | Brief and deliverable page show each post's link and QR (D-127) |
| Agency view with the view grant; links only with negotiate and sign | Done | `/agency/creators/<id>/leads`, Links card |
| Guides for every audience | Done | Creator `#links`, `#leads`; agency `#leads`; influencer manager `#leads`, `#fraud`; super admin `#stage-rules`; developer `#attribution` |
| Connecting attribution to live `student_leads` | Deferred (HARD STOP 6) | Ready; RUNBOOK G-14 to G-17 list the steps. Needs the owner's go-live approval |

## Phase 7: Ledger, payouts and tax

Spec Section 22 Phase 7 and spec 11 (with 6.1–6.3, 13). Builds on the Phase 3 engine (`computeLedger`, `diffLedger`,
`estimateTax`), the Phase 5 content facts and penalty proposals, and the Phase 6 attributions. The ledger is
append-only (D-06): amounts never change, corrections are reversal entries, status moves only through
`inf.ledger_transition()`. No money moves automatically (spec 11): payouts are prepared, exported for the bank and
marked paid by Finance; a payment-provider adapter interface is defined for later.

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 7.1 | Pure modules: deal facts → engine events (content, leads, enrolments, receipts, manual releases, deal and campaign close); runner plan (engine → diff → postings, approved penalties); entry lifecycle; payout builder (eligibility, gross, TDS per section with FY aggregates and catch-up, GST, net, carry-forward of negative balances); bank export file; UTR CSV parser; GST invoice checks; Indian FY and quarters; reconciliation of commission units against receipts | `lib/ledger/*` | exhaustive units |
| 7.2 | Database: ledger entries and status events, receipts (sync from B2B/B2C per INTEGRATION_CONTRACTS §3, manual entries), manual releases, payout batches, payouts and items, invoices, TDS records and Form 16A files, payment providers interface log; gather and apply functions for the runner; payable sweep; audited bank export; RLS and grants | `20261022000100_inf_ledger.sql` | pgTAP per role, immutability, lifecycle |
| 7.3 | Runner and wiring: `ledger.run` job per deal from domain events (contract, brief, deliverables, leads, enrolments, receipts, penalties, releases, deal status), nightly full run for time-based confirmations; penalties approved → ledger; dry run against posted entries | `lib/ledger/runner.ts`, `lib/jobs/*` | units + pgTAP + e2e |
| 7.4 | Finance console: ledger with filters, adjustments and holds, receipts and reconciliation, payout batches (select, summary, approve with optional second approver, bank export, mark paid one by one or by CSV, cancel), GST invoice review, TDS summaries and Form 16A upload | `app/(admin)/admin/finance/*` | Playwright |
| 7.5 | Creator and agency earnings: totals (lifetime, FY, month, pending, confirmed, payable, paid), next expected payout, per-deal and per-lead status (the lead feed's earning status), statements (monthly PDF), GST invoice upload, payment advice PDF and notification, TDS certificates | `app/(creator)/creator/earnings/*` | Playwright |
| 7.6 | Guides, seed (posted ledger, a paid batch), phase gate | | gate |

### Phase 7 summary

The creator ledger and everything that pays it out. Each deal is replayed by the compensation engine from its facts
(content, attributed leads, B2B and B2C enrolments, Eduwit's commission receipts, manual releases, breaches, campaign
end and deal completion) and the difference is posted: new lines, growing confirmations, reversals and clawbacks, never
edits (D-130, D-131). Runs are queued per deal by domain events and nightly; managers see a deal's ledger with a dry-run
preview, manual milestone release and breach recording. Finance gets the ledger with adjustments and holds, payout
batches (filters, skipped creators with reasons, gross / TDS / GST / net, two-person approval, the audited bank file
through a payout-provider interface that moves no money, mark paid one by one or from the bank's CSV, failed payments
back to payable), GST invoice review, TDS by quarter with Form 16A uploads, and commission receipts with
reconciliation (D-132 to D-140, D-143). Creators get an Earnings page with every total, the next payout run, payouts
with GST invoice upload and payment advice PDFs, earnings per deal, monthly statement PDFs and TDS certificates;
agencies with the earnings grant see it read-only, and the lead feed's earning status is now real (D-142). Guides were
written or updated for Finance, managers, creators, agencies and developers. The seed runs a real payout end to end as
Finance staff (D-144).

Found and fixed during the gate: the read-only production check showed that the B2B CRM also writes signed tier
settlements and void lines per enrolment, so receipts now count commission plus tier settlement and skip void lines,
and a refunded enrolment always reverses its receipt (D-139, pgTAP added); the self-review added the payout-provider
interface the spec asks for and the payout statement number on the advice.

Gate on 17 Oct 2026: typecheck, lint and Prettier clean; 3,085 unit tests (61 files); 710 pgTAP assertions (21 files)
on a fresh database built from the production baseline, including the generated status matrix; Playwright 93 passed
and 2 screenshot specs skipped by design (95 in total, 8 new finance journeys and a phone check of Earnings); types
regenerated with no drift; seed works and is idempotent; production re-checked read-only (the 100 generated baseline
statements hash to `3f8bdfc5…` on production and on the fresh local database; every `b2b.earnings`, `b2b.invoices`
and `b2c_enrollment_money_v` column the ledger reads exists, with the status values it matches; no `inf` schema and no
`inf-*` buckets). Nothing outside schema `inf` was created or changed: shared tables are only read, from security
definer functions.

### Phase 7 requirement checklist (spec Section 22 Phase 7, spec 11)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Engine runner and event wiring | Done | `lib/ledger/runner-core.ts`, `ledger.run` job, `inf.ledger_on_event`, nightly `inf.ledger_nightly` (D-131) |
| Unified ledger per creator from engine output plus manual adjustments (Finance or Super Admin, with a reason) | Done | `inf.ledger_entries`, `inf.ledger_adjust` (`ledger.adjust`), Finance → Ledger |
| Lifecycle accrued → confirmed → payable → in batch → paid; reversed, on hold, clawed back | Done | `inf.ledger_status_of` = `statusOf()` (generated matrix test), holds per line and per creator (D-130) |
| TDS table per section, rate, per-transaction and FY thresholds, no-PAN rate, per component, "confirm with CA", Finance-only edits | Done | Phase 3 tax settings; applied at payout with FY aggregates and catch-up (D-132); CA confirmation is go-live work (G-18) |
| Quarterly TDS summaries; Finance uploads Form 16A; creators download | Done | Finance → TDS, `inf.tds_summary`, `inf.tds_certificate_record`, Earnings → TDS and Form 16A |
| GST for registered creators with a verified GSTIN; invoice upload validated (GSTIN format, amounts) before payout | Done | `lib/ledger/invoice.ts`, `inf.invoice_submit`, approval blocked until accepted (D-138) |
| Payout statement for creators without GST | Done | `PS-…` record per payout, printed on the payment advice (D-138) |
| Payout batches by filter with gross, TDS, GST and net; optional two-person approval | Done | Finance → Payouts (D-135) |
| Bank bulk-upload file in a configurable column format | Done | `finance.payouts.bank_export`, audited and never stored (D-136) |
| Mark paid with a UTR, one by one or by CSV | Done | `inf.payouts_mark_paid`, `lib/ledger/utr.ts` (D-137) |
| Payment advice PDF per payout and creator notification | Done | `payout.advice` job, `lib/ledger/pdf.tsx`, `payout.paid` notification |
| No automated money movement; payment-provider adapter interface | Done | `lib/ledger/provider.ts`, `PAYOUT_PROVIDER=bank_file` (D-136) |
| Reconciliation against Eduwit's commission receipts; flag unpaid accrued commission after N days | Done | `inf.commission_receipts_sync` (B2B and B2C, read only), manual override, Finance → Receipts (D-139, D-140) |
| Earnings view: lifetime, FY, month, pending, confirmed, payable, paid; next payout; per-deal; per-lead status; monthly statement PDF; invoices; TDS certificates | Done | `/creator/earnings`, `/api/earnings/<id>/statement`, lead feed earning status (D-142) |
| Agency view of earnings with the earnings grant, never bank details | Done | `/agency/creators/<id>/earnings` (read only) |
| Phase 6 carry-over: earning values in the lead drawer | Done | `inf.lead_feed_earnings` refreshed by every run (closes the Phase 6 deferral, D-121) |
| Guides for every audience | Done | Finance `#ledger`, `#payouts`, `#invoices`, `#tds`, `#receipts`; manager `#deal-ledger`; creator `#earnings`; agency `#earnings`; developer `#ledger` |
| Leaderboard-rank bonuses | Deferred to Phase 8 | Leaderboards are a Phase 8 deliverable (spec 12); the engine supports the bonus and receives rank events once they exist (D-141) |
| Connecting receipts and payouts to live data | Deferred (HARD STOP 6) | Receipts read live CRM tables only with `LEAD_SYNC=on`; go-live steps in RUNBOOK G-14, G-18 to G-21 |


## Phase 8: Dashboards and analytics

Spec Section 22 Phase 8 and spec 12. Every metric is defined once in a registry (`lib/analytics/metrics.ts`) that
generates `docs/METRICS.md` and the UI tooltips. Staff dashboards read summary materialised views in schema `inf`
refreshed by `pg_cron`; the creator home reads that creator's live rows through a `SECURITY DEFINER` function. Only
aggregates leave the database; drill-downs open the existing screens, which keep their own permissions and masking.
Tier status (Phase 10 scorecards and tiers) and announcements (Phase 9 communication) are out of this phase's scope.

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 8.1 | Pure modules: date range presets (today, 7, 30, 90 days, this month, last month, this FY, custom; IST) with the previous period; the metric registry (definition, unit, formula, source) and `METRICS.md` generator; funnel and conversion rates, unit economics (cost per lead, qualified lead and enrolment, revenue, net ROI, ROAS), lead quality, deltas; leaderboards; time series buckets | `lib/analytics/*` | exhaustive units, METRICS.md drift test |
| 8.2 | Database: committed spend per deal (zero-performance simulation over the deal's term, stored by the runner), leaderboard opt-in, summary views (leads per attribution, clicks per day, spend per day, revenue per enrolment) with `inf.analytics_refresh()` every 15 minutes, read functions for overview, breakdowns, series, leaderboards, operations, campaign, creator 360, finance and the live creator dashboard | `20261023000100_inf_analytics.sql` | pgTAP per role |
| 8.3 | Dashboard kit: date range control with comparison, KPI cards with tooltip and delta, SVG line, bar and funnel charts with a table fallback, breakdown tables with CSV export, data freshness | `components/analytics/*` | units + Playwright |
| 8.4 | Creator home: earnings cards, fixed fee received vs remaining, the full action centre, lead funnel, leads over time, top content, programme and platform breakdowns, active campaigns and deals, leaderboard position (opt-in) | `app/(creator)/creator/page.tsx` | Playwright (incl. phone) |
| 8.5 | Admin overview: programme health, spend (committed, accrued, paid; by deal model, campaign, creator; budget vs actual), unit economics by creator, campaign, platform, content type, programme and deal model, lead quality, operations, leaderboards | `app/(admin)/admin/analytics/*` | Playwright |
| 8.6 | Campaign dashboard with per-creator comparison, creator 360° analytics, finance dashboard (liabilities, payouts by period, TDS by quarter, reconciliation status) | | Playwright |
| 8.7 | `METRICS.md`, exports, guides, seed, performance check (100k leads, 1,000 creators, p95 under 2 s), phase gate | | gate |

### Phase 8 summary

Every dashboard number is defined once (`lib/analytics/metrics.ts`) with its plain definition behind an info button and
a generated `docs/METRICS.md` (D-145). Date ranges and comparisons follow IST calendar days (D-146). Staff dashboards
read four summary views refreshed every 15 minutes; the creator home is live (D-147). The creator home now has the
full action centre (contracts, briefs, overdue and due-soon deliverables, changes requested, metrics, GST invoices,
KYC), earnings cards, fixed fees earned and to come, the lead funnel with comparisons, leads over time, top content,
programmes, platforms, active deals, the opt-in leaderboard position and a CSV export. Staff get Analytics: programme
health, the funnel, spend (committed, accrued, paid; by deal model; budget against actual by campaign), unit economics
broken down by creator, campaign, platform, content type, programme or deal model, lead quality, operations with links
into each queue, leaderboards and CSV export; a campaign list and per-campaign dashboard with every creator compared; a
finance dashboard; and an Analytics tab on the creator 360. Counting, spend, revenue and splitting rules are D-148 to
D-151; access D-153.

Found and fixed during the phase: the first totals function took 6 s at 100k leads (function calls per row and
unhashable joins); it now groups by a whitelisted plain expression and the slowest query takes 0.43 s (D-154). CSV
exports were quoting negative numbers as text (D-156). The KPI card's info button sat inside a link. Playwright's
readiness check could deadlock on a stale job queue (D-157).

Gate on 17 Oct 2026: typecheck, lint and Prettier clean; 3,254 unit tests (67 files); 739 pgTAP assertions (22 files)
on a fresh database built from the production baseline; Playwright: all journeys pass with 2 screenshot specs skipped
by design (101 in total, 6 new analytics journeys and a phone check), after updating one Phase 1 journey whose action
centre now correctly keeps Riya's open contract and brief; types regenerated; seed works and is idempotent (it now also
records committed spend and refreshes the views); performance measured at 100k leads and 1,000 creators (D-154);
production re-checked read-only (no `inf` schema or buckets; shared baseline identical, hash `3f8bdfc5…`; the programme
columns the analytics reads exist). Nothing outside schema `inf` was created or changed.

### Phase 8 requirement checklist (spec Section 22 Phase 8, spec 12)

| Requirement | Status | Where / note |
| --- | --- | --- |
| A written definition for every metric in `METRICS.md` and a tooltip in the UI | Done | Registry + generated doc + info buttons (D-145) |
| Date range presets (today, 7, 30, 90 days, this month, last month, this FY, custom) and comparison to the previous period | Done | `lib/analytics/ranges.ts`, `RangeControl` (D-146) |
| Drill-down to the underlying records | Done | KPI cards and rows link to leads, creators (360 analytics), campaigns, deals, content, contracts, payouts, KYC, receipts and fraud review |
| CSV export (masked for creators) | Done | Staff breakdown export; creator export of their own counts (D-153) |
| Creator home: earnings cards, fixed fee received vs remaining, action centre, funnel with conversion rates, leads over time, top content, programme and platform breakdowns, active campaigns and deals, leaderboard position (opted in) | Done | `app/(creator)/creator/page.tsx`, `inf.creator_dashboard` |
| Creator home: tier status and progress; announcements | Deferred to Phase 10 and Phase 9 | Tiers are Phase 10 scope, announcements Phase 9 (D-155) |
| Admin overview: programme health (active, new, dormant, pipeline) | Done | `inf.analytics_health` |
| Spend: committed, accrued, paid; by deal model, campaign, creator; budget vs actual per campaign | Done | `inf.analytics_spend`, committed from the engine (D-149); by creator in the breakdown table |
| Unit economics: cost per lead, qualified lead and enrolment, revenue, net ROI, ROAS; by creator, campaign, platform, content type, programme and deal model | Done | `inf.analytics_totals`, breakdown table (D-150, D-151) |
| Lead quality: qualification rate, junk %, duplicate %, enrolment rate per creator | Done | Lead quality cards and per-creator table (D-148) |
| Operations: overdue deliverables, pending reviews, pending negotiations, contracts expiring, payouts due, KYC pending, fraud flags | Done | `inf.analytics_operations` |
| Leaderboards: enrolments, ROI, on-time delivery | Done | D-152 |
| Campaign dashboard with per-creator comparison | Done | `/admin/analytics/campaigns`, `/admin/analytics/campaigns/<id>` |
| Creator 360° analytics: trends, content performance, lead-quality history | Done | Creator page → Analytics tab |
| Finance dashboard: liabilities, payouts by period, TDS by quarter, reconciliation status | Done | `/admin/analytics/finance` |
| Materialised views or summary tables refreshed by pg_cron | Done | `inf.an_*`, `inf-analytics` every 15 minutes (D-147) |
| Under 2 s at p95 with 100k leads and 1,000 creators | Done | Measured 0.41 s p95 for the slowest query (D-154) |
| Guides for every audience | Done | All staff `#analytics`, `#analytics-campaigns`, `#analytics-finance`; viewer; creator `#home`; developer `#analytics` |
| Leaderboard-rank bonuses in the engine (Phase 7 carry-over) | Blocked (HARD STOP 5) | The engine accepts rank events, but paying money on rank needs the owner to define the leaderboard: which measure (enrolments, ROI, on-time), among which creators (all, the campaign, opted-in only), at which moment, and how ties are paid. No spec answer or configurable default exists; listed under Blockers |


## Phase 9: Communication

Spec Section 22 Phase 9, spec 14 and the webhook part of spec 18. Builds on the Phase 1 notification core
(`inf.notify`, deliveries, preferences, templates table, mock/SMTP/Resend/Brevo/Meta adapters behind `LIVE_MODE`) and
the Phase 2 application threads. Nothing leaves the system until real providers are configured (HARD STOP 4):
emails and WhatsApp messages go to the mock adapters, webhooks are delivered only to endpoints staff register.

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 9.1 | Pure modules: the event catalogue (audience, mandatory, channels, variables, default copy), template rendering with variables and escaping, preference resolution, announcement segments, digest building, @mention parsing, webhook signing (HMAC-SHA256) and retry schedule | `lib/notify/*`, `lib/messaging/*`, `lib/webhooks/*` | exhaustive units |
| 9.2 | Database: threads on every entity (campaign, application, deal, contract clause, brief, deliverable, payout, lead for staff only, support) with attachments, mentions, read receipts, unread counts and full-text search; notification centre and preferences; template versions; announcements with segments and scheduling; digests; webhook endpoints, subscriptions and delivery log; the missing catalogue events | `20261024000100_inf_communication.sql` | pgTAP per role |
| 9.3 | Notification centre: bell with unread count (Realtime), the centre page, mark read, per-event channel preferences (mandatory events locked) | `components/notifications/*` | Playwright |
| 9.4 | Threads everywhere: one thread panel on each entity page for staff, creators and agencies (with their grants), support conversations, staff inbox with search | `components/threads/*` | Playwright |
| 9.5 | Admin tools: template editor (variables, preview, test send), announcements (segment, schedule), digests, webhooks (endpoints, events, signing secret, delivery log, test) | `app/(admin)/admin/communication/*` | Playwright |
| 9.6 | Guides, seed, phase gate | | gate |

### Phase 9 summary

Every notification the portal sends is in one catalogue (`lib/notify/catalogue.ts`, about 66 events) generated into
the database, which decides required events and default channels (D-158, D-159). Everyone has a bell with a live unread
count, a notification centre and settings where required notifications stay on and the digest can be chosen (D-164,
D-167). Every application, campaign (one private conversation per creator), deal, contract, brief, deliverable and
payout has a conversation at the bottom of its page for staff, the creator and agencies with the matching grant; leads
carry staff-only notes; each creator has a support conversation (D-160 to D-162). Messages take files (D-163),
@mentions for staff, read receipts and unread counts; staff have an inbox with search and filters, creators and agencies
a Messages page. The admin Communication console has notification templates with variables, preview, versions and test
send (D-165), announcements to all creators or a segment, now or scheduled, shown on the creator home (D-166), and signed
outbound webhooks with retries, a delivery log and SSRF protection checked at connect time (D-168). The catalogue events
still missing were added: "₹X earned", clawbacks, payable amounts, fraud flags and the daily staff nudges (D-169).
Delivery jobs render templates, send WhatsApp only with an approved template (`notify.deliver`), build digests
(`digest.run`) and deliver webhooks (`webhook.deliver`); nothing leaves the system while `LIVE_MODE` is off.

Found and fixed during the phase: the notification template functions first reused the name of Phase 4's contract
`template_save` (renamed `notification_template_*`); `inf.notify()`'s default channel argument would have emailed every
event; a confirmation dialog submitted the form around it, so "Send now" also saved a draft (D-170); background server
actions could hold up navigation, so they became route handlers (D-171).

Gate on 17 Oct 2026: typecheck, lint and Prettier clean; 3,473 unit tests (75 files); 813 pgTAP assertions (23 files,
74 new for communication) on a fresh database built from the production baseline; Playwright: 110 passed with 2
screenshot specs skipped by design (11 new communication journeys); types regenerated with no drift; seed works and is
idempotent (now with conversations, an announcement, a template and a webhook endpoint); production re-checked read-only
(no `inf` schema, buckets or publication entries; shared baseline identical, 100 statements, hash `3f8bdfc5`). Nothing
outside schema `inf` was created or changed: attachments use the existing `inf-documents` bucket and the bell uses the
Phase 1 Realtime entry for `inf.notifications`.

### Phase 9 requirement checklist (spec Section 22 Phase 9, spec 14 and the webhook part of 18)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Threads on campaign, application, deal, brief, deliverable, payout, lead (staff only) and support | Done | `inf.thread_*`, `components/messaging/*` on every entity page (D-160) |
| Threads on contract clauses | Done (Phase 4) | Clause comments and change requests stay in the contract negotiation; a general contract thread sits beside them (D-161) |
| Attachments, @mentions for staff, read receipts, unread counts, full-text search | Done | D-162, D-163; search over `inf.messages.search` in the staff inbox |
| Notification centre (in-app, Realtime) | Done | Bell + `/…/notifications` for all portals (D-164) |
| Email and WhatsApp templates with per-user channel preferences | Done | Template editor, `notify.deliver`, settings page (D-165) |
| Mandatory events cannot be turned off | Done | D-159; database and form both enforce it |
| Minimum event catalogue | Done | All listed events exist; added ones in D-169 |
| Template editor with variables, preview and test send | Done | `/admin/communication/templates`; test send needs live sending |
| Announcements to all or a segment (tier, campaign, platform, language) with scheduling | Done | `/admin/communication/announcements`, `inf-announcements` cron (D-166) |
| Daily or weekly digest by email or WhatsApp for creators and staff | Done | `digest.run`, `inf-digests` cron (D-167); WhatsApp digests need an approved template (G-23) |
| Outbound webhooks: HMAC-signed, retries, delivery log, the six events | Done | `/admin/communication/webhooks`, `webhook.deliver` (D-168) |
| Idempotent notifications and webhook handlers | Done | Idempotency keys on every notify call, `(endpoint, event_id)` unique deliveries, one digest per person per day |
| Guides for every audience | Done | Creator, agency and staff `#notifications` and `#messages`; Super Admin `#communication`, `#webhooks`; Influencer Manager `#announcements`; developer `#communication` |
| Live email/WhatsApp providers, approved WhatsApp templates | Blocked (HARD STOP 4) | Mock adapters until credentials exist; listed in RUNBOOK G-23 |


## Phase 10: Scorecards, tiers, compliance and polish

Spec Section 22 Phase 10, spec 15, 16, 19 and 20. The last build phase: after its gate the remaining step is production
go-live, which waits for the owner (HARD STOP 6) together with the provider credentials (HARD STOP 4) and the legal and
tax sign-offs already listed in the RUNBOOK.

### Plan

| Step | What | Main files | Tests |
| --- | --- | --- | --- |
| 10.1 | Pure modules: scorecard (delivery reliability, content performance against the creator's own baseline, lead quality, economics, compliance; weighted composite from `scorecard.weights`), tier evaluation (entry rules, highest tier met, manual override), rules-based recommendations behind a pluggable `Recommender` interface, contract compliance obligations (met, missed, open), DPDP export bundle shape, retention rules. Phase 9 follow-ups: digest defaults and hour, and quiet hours for WhatsApp and digests, from `notifications.delivery` | `lib/scorecards/*`, `lib/compliance/*`, `lib/privacy/*` | exhaustive units |
| 10.2 | Database: monthly scorecards (frozen inputs and scores, on-demand recompute), tier history with reasons and manual overrides, tier benefits (default commission uplift suggested in the deal builder, early campaign access, payout cycle shown to Finance), compliance obligations per creator, consent records for communications, data export and deletion requests (financial and contract records kept for the retention period), retention jobs (click anonymisation, sign-in log and audit retention) | `20261025000100_inf_insight_privacy.sql` | pgTAP per role |
| 10.3 | Screens: tiers and scorecard settings, creator 360 Scorecard and Compliance tabs, programme scorecard list, creator home tier status and progress, recommendations at deal renewal, creator privacy page (download my data, request deletion, communication consents) and the staff privacy-requests queue, audit viewer filters | `app/(admin)/…`, `app/(creator)/…`, `components/scorecards/*`, `components/privacy/*` | Playwright |
| 10.4 | Passes: accessibility (axe checks on key screens, keyboard paths), performance (paginated lists, scorecard computation at 1,000 creators), security review (OWASP checklist, rate limits, CSP, file checks, service-role use) written to `docs/SECURITY_REVIEW.md`, and the spec 20 end-to-end journeys mapped to specs with any missing one added | `e2e/*`, `docs/SECURITY_REVIEW.md` | gate |
| 10.5 | Docs: production runbook completed, `docs/ADMIN_GUIDE.md` and `docs/CREATOR_GUIDE.md` generated from the in-app guides (a test keeps them in step), seed, phase gate | `docs/*`, `scripts/*` | gate |

### Phase 10 summary

Every approved creator gets a monthly scorecard (and one on demand): delivery, content against their own baseline, lead
quality, economics and compliance, each 0–100, with a weighted composite from the score weights setting; parts without
data are left out instead of scored zero (D-172, D-173). Tiers have entry rules and benefits set by the Super Admin; the
monthly run promotes at once and demotes only after the configured months below, and a manual tier holds until its
date (D-174). Benefits act where they belong: the commission uplift is offered in the deal builder, early access delays
new campaigns for lower tiers, and Finance sees each tier's payout cycle when preparing a batch (D-180). Renewal
recommendations come from rules behind a `Recommender` interface, each with the facts that triggered it (D-175). The
creator 360 has Scorecard and Compliance tabs (obligations met, missed, open or waived per deliverable, D-176),
Analytics has a paginated programme scorecard list, and the creator home shows the tier and what the next one needs.
DPDP: consent records for every change to notification channels and digests, a data export built on download, and
deletion requests decided by staff with `privacy.manage` from a plan of what is erased and what is kept until the
retention period ends; the purge date is computed in the database and storage files are removed (D-177, D-181, D-187).
Retention runs nightly (D-178). The audit viewer gained a record-id filter (D-182).

The polish passes: axe checks (WCAG 2.1 A/AA) on the key screens of every portal fixed muted-text contrast on tinted
surfaces, text in the faint colour, keyboard scrolling of wide tables and in-text links; the performance script now
times scorecard facts at 1,000 creators (about 5 seconds for the whole monthly run) and the programme list (under
10 ms a page). The security review (`docs/SECURITY_REVIEW.md`) found one high issue (agency owner checks that a null
comparison silently passed) and fixed it with the medium and low findings (D-186). The spec 20 journeys are mapped in
`docs/TESTING.md`; the missing ones (enrolment to confirmed commission, duplicate and self-referral reasons, clawback,
deal kinds against exact ledgers) were added in `e2e/journeys.spec.ts` on the real sweep, runner and Finance screens,
and they found three defects in earlier phases: commission subjects did not match their consumers, so lines were not
tied to leads, reconciliation was empty and the enrolment notification never fired (D-183); a receipt could not be
recorded from a reconciliation row before a CRM receipt existed (D-184); and a clawback did not notify the creator
(D-185). The runbook now has the full go-live checklist (G-1 to G-29), deployment, rollback, backups and incidents;
`docs/ADMIN_GUIDE.md` and `docs/CREATOR_GUIDE.md` are generated from the in-app guides with a drift test; unhandled
server errors are logged with their digest (`instrumentation.ts`).

Gate: unit, pgTAP, typecheck, lint, Prettier, types and seed are green; the final full Playwright run is in progress and its result is recorded here when it completes.

### Phase 10 requirement checklist (spec Section 22 Phase 10, spec 15, 16, 19 and 20)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Monthly and on-demand scorecard: delivery, content vs baseline, lead quality, economics, compliance | Done | `lib/scorecards/score.ts`, `inf.scorecard_facts`, `scorecards.run` (D-172, D-173) |
| Weighted composite with weights in settings | Done | Setting `scorecard.weights` |
| Tiers with configurable entry rules and benefits (uplift, priority access, faster payout cycle) | Done | Settings → Tiers; uplift in the deal builder, early access in the marketplace, cycle on the Finance prepare card (D-174, D-180) |
| Rules-based renewal recommendations, pluggable for AI | Done | `lib/scorecards/recommend.ts` (`Recommender`), deal Terms tab (D-175) |
| ASCI checklist, claims library and banned-claims scan, KYC gate, terms re-acceptance | Done (Phases 2, 5, 7) | Unchanged |
| Contract compliance tracker per creator | Done | Creator 360 → Compliance (D-176) |
| DPDP: masked student data, export and deletion with financial retention, communication consents | Done | Creator Account → Manage my data, Admin → Privacy requests (D-177, D-181, D-187) |
| Audit log viewer with filters | Done | `/admin/audit`: type, action, person, record id, dates (D-182) |
| Data retention configurable; click logs anonymised | Done | `inf.retention_run()` nightly (D-178) |
| Accessibility pass | Done | `e2e/a11y.spec.ts`, contrast test extended |
| Performance pass (paginated lists, scorecards at 1,000 creators) | Done | `scripts/perf/analytics.sql`; programme list paginated |
| Security review | Done | `docs/SECURITY_REVIEW.md` (D-186) |
| Full end-to-end suite covering spec 20 | Done | `docs/TESTING.md`, `e2e/journeys.spec.ts` |
| Production runbook | Done | `docs/RUNBOOK.md` |
| Admin and creator user guides | Done | `docs/ADMIN_GUIDE.md`, `docs/CREATOR_GUIDE.md` (generated) |
| Error tracking | Partly (HARD STOP 4) | Structured `request.error` logs now; Sentry needs a DSN (G-27) |
| Production go-live | Waiting (HARD STOP 6) | Owner approval, providers, legal and CA sign-offs (RUNBOOK) |
