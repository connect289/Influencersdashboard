# Progress

## Now

- **Current phase:** Phase 6 (Tracking and attribution), step 6.1 (plan). Phase 5 (Briefs and deliverables) complete
  and tagged `phase-5-done`.
- **Open item from Phase 3 closed:** the intermittent CRM import failure was the per-IP staff sign-in limit (30 per 5
  minutes) being reached by the growing suite; staff sessions are now reused within a run (D-98).
- **Phases 1–3:** complete and tagged `phase-1-done` to `phase-3-done`.
- **Tags:** the git proxy in this environment refuses tag pushes; `phase-0-done` to `phase-5-done`
  exist in the local repository only. Push them from a normal clone with `git push origin --tags`.
- **Phase 0:** approved by the owner on 16 Oct 2026 ("approve all defaults"): every default in `PHASE0_FINDINGS.md` §7,
  the ERD, `SHARED_CHANGES.md` (S-1 to S-15, R-1 to R-5), the whitelist with the recommended hidden fields and
  first name + initial, the stage mapping and the integration contracts. Tagged `phase-0-done`.
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
