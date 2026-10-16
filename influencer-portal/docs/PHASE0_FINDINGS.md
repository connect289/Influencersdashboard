# Phase 0 findings: Eduwit Influencer Portal

- **Date:** 16 October 2026
- **Method:** read-only SQL (catalog queries, function sources, grants, policies, row counts, cron jobs) against the
  production project `xlseqwgyjuqhktrguhyc` ("EDUWIT LEAD TRACK", ap-south-1, Postgres 17.6), the Supabase security
  advisor, and a read of the B2B and B2C code and docs in this repository. **Nothing was written, altered, enabled or
  granted anywhere.**
- **Status:** HARD STOP 1. Waiting for the owner's review. Phase 1 starts only after approval.

Companion documents (all in `influencer-portal/docs/`):

| Document | What it holds |
| --- | --- |
| `ERD.md` | Proposed schema, 8 Mermaid diagrams (all parse-checked) and the storage decisions |
| `SHARED_CHANGES.md` | Every change or use of a shared object, for approval; the legacy exposures found |
| `LEAD_FIELD_WHITELIST.md` | All 141 `student_leads` columns, with SHOW / BAND / MASK / HIDE / ASK |
| `STAGE_MAPPING.md` | Where lead status lives, creator stages, seed mapping rules, the sync design |
| `INTEGRATION_CONTRACTS.md` | Witty code format and routes, CRM stage events, commission receipts, public API, webhooks, oversight |
| `DECISIONS.md` | Every decision made without the owner, with the reason and how to change it |
| `PROGRESS.md` | Current phase, step, what's next, blockers |

---

## 1. Summary

The portal can be built with **almost no change to shared objects**: no trigger on `student_leads`, no new column, and
no change to `lead_intake()`. Everything it needs to read already exists and is indexed. The remaining approvals are
about the container (schema `inf`, cron jobs, buckets, Realtime), one optional write path into Witty's code issuer, and
a few Supabase Auth settings.

Six findings change or sharpen the spec:

1. **Witty no longer uses `referral_code`.** Witty 2.0 attributes through 6-character **access codes**
   (`w2_issue_code` → `w2_access_codes` → `w2_redeem_code` → `touchpoints.attribution`). A human-friendly creator code
   like `RAHUL-MBA-07` would not be recognised by Witty today. The proposed contract (`INTEGRATION_CONTRACTS.md` §1)
   makes links work **with no Witty change** (Route A), and asks the Witty team for a small change for typed and QR codes
   (Route B). Creator codes must contain a hyphen so they can never collide with Witty's 6-character codes.
2. **The legacy influencer dashboard still exposes students' contact data.** An RLS policy on `student_leads` gives
   any active legacy influencer account **every column** (phone, email, IP) of its referred leads, and passwords sit in
   plain text behind an anon-callable function. The earlier anon exposure of `influencer_leads_dashboard` **was fixed**
   (grants now service_role only). See `SHARED_CHANGES.md` §E; your decision.
3. **Commission received per enrollment is derivable from both CRMs** (B2B `b2b.earnings` → `b2b.invoices`; B2C
   `public.b2c_enrollment_money_v`). Finance doesn't need to type it in, but can override it.
4. **Lead status has one canonical home**, `student_leads.stage` (B2B vocabulary of 17 stages), plus B2C's versioned
   view `b2c_lead_status_v`. A read-only sweep on the existing `updated_at` index replaces the trigger the spec
   suggested, which is less invasive (`STAGE_MAPPING.md` §4).
5. **Production holds almost no data**: 2 leads, 3 touchpoints, 0 enrollments, 0 allocations, 4 auth users. There is
   nothing to backfill, but performance must be proven on synthetic data (100k leads, 1,000 creators).
6. **The sibling apps run Next.js 16** (`^16.3.8`, React 19.3), not 15. I recommend matching them (decision D-02).

---

## 2. Inventory (16 Oct 2026)

| Item | State |
| --- | --- |
| Schemas | `public` (199 tables, 9 views), `b2b` (106 tables, 10 matviews), `b2c` (116 tables, 3 views), `catalog` (4 views + `changes`), plus Supabase's own |
| n8n's internal tables in `public` | ~115 (`workflow_entity`, `execution_entity`, …). Left alone |
| `student_leads` | **141 columns**, 2 rows, RLS on, 13 indexes including `updated_at`, `referral_code`, phone digits, stage |
| `touchpoints` | 3 rows, `attribution jsonb` holding Witty's full click attribution |
| `w2_access_codes` / `w2_clicks` | 385 / 442 rows (376 codes from Witty's test harness) |
| Legacy influencer objects | `influencers` (3 rows), `influencer_auth` (3), `influencer_login_attempts`, view `influencer_leads_dashboard` (service_role only now), functions `current_referral_code()`, `influencer_dashboard_leads()`, `is_admin()` |
| Catalogue | `catalog_programs` (715), `catalog_universities` (29); views `catalog.programmes_v`, `universities_v`, `partner_rates_v` (commission per programme and partner) |
| Extensions | `pg_cron` 1.6.4, `pgmq` 1.5.1, `pg_net`, `pgcrypto`, `supabase_vault`, `pg_trgm`, `vector`, `uuid-ossp`, `pg_stat_statements` |
| Cron jobs | 47 (`b2b-*`, `b2c-*`, `influencer_login_attempts_purge`). Names prefixed per product |
| Storage buckets | `b2b-programme-files`, `b2c-documents`, `b2c-recordings`, `b2c-support`, `b2c-guides` (all private) |
| Vault secrets | 3 |
| Realtime publication | empty |
| Migrations recorded | 229 |
| Supabase branches | none. B2B/B2C use a separate staging project `mplbspysxmtohnlwpbti` |
| Auth | 4 users, 1 MFA factor. Trigger `crm_on_auth_user_created` copies every new user into `public.crm_users` (inactive viewer) |
| Security advisor | 1 error (`w2_latency_daily` is a SECURITY DEFINER view, Witty's), 23 SECURITY DEFINER functions callable by anon (22 B2B machine endpoints, `b2b.api_*` taking an API key and the webhook ingests taking a signature, plus the legacy `influencer_dashboard_leads`), 603 callable by authenticated, 79 mutable `search_path`, leaked-password protection **off**, 216 tables with RLS and no policy (informational) |

---

## 3. Answers to spec Section 22, Phase 0 item 1

### 3.1 `lead_intake()`

`public.lead_intake(p jsonb)`, `SECURITY DEFINER`, `search_path = public`, owner `postgres`, executable by neither
anon nor authenticated (fixed by the B2B CRM's M1).

- Normalises the phone (`crm_norm_phone`: digits, `91` prefix), finds the lead by phone digits, creates it
  (`stage = 'new'`) or merges into it (a lost or enrolled lead is **reopened**: `stage = 'qualifying'`, and
  `cycle_no + 1` when enrolled or lost over 90 days ago).
- Copies only whitelisted keys. **First-touch keys are never overwritten**: `lead_source`, `channel`, `campaign`, all
  `utm_*`, `click_ids`, `landing_url`, `referrer_url`, `referral_code`, `referred_by_code`, `activation_code`, `ip_address`,
  `device`, `fingerprint`, consent stamps, `first_agent_channel`.
- Sets `temperature`, `is_sales_ready` (on the first HOT/WARM/COLD) and the `new → qualifying` step.
- Writes a `touchpoints` row (with the caller's `attribution` JSON) for every event except routine chat turns.
- **Insert, then update:** a new lead is inserted with only phone and defaults; the attribution columns arrive in the
  following `UPDATE`. A trigger on INSERT alone would never see the referral code (one more reason for the sweep).
- Returns `crm_owned` (Witty stops selling once a CRM owns the lead).

### 3.2 Triggers on `student_leads`

`student_leads_touch_trg` (before update: `updated_at`), `crm_auto_assign` (after update of `is_sales_ready`, old CRM),
`student_leads_bulk_delete_guard` and `_truncate_guard`. No insert trigger. The portal adds none.

### 3.3 RLS and grants that matter to the portal

- `student_leads`: policies `crm_staff_select` (old CRM role check) and the legacy **"Influencers can only view their
  own student leads"** (finding 2). `authenticated` holds table grants; RLS is what protects it.
- `w2_access_codes`, `w2_clicks`: anon and authenticated hold full DML grants, and RLS is on with no policies, so the
  grants are blocked by RLS (Witty's design; it calls them through functions).
- `catalog_programs`/`catalog_universities`: select-only policies.

### 3.4 How Witty stores source and referral codes

See `INTEGRATION_CONTRACTS.md` §1.1. In short: `student_leads.activation_code` (access code), `lead_source` (source
slug), `touchpoints.attribution` (code, kind, source, campaign, `utm_*`, `click_id`, `via_code`, fingerprint, ip,
device). `referral_code` is only legacy (both live leads have it empty). `w2_sources` has five rows (`organic`,
`whatsapp_direct`, `website`, `shared`, `legacy`).

### 3.5 Where CRM and partner lead statuses live

See `STAGE_MAPPING.md` §1. `student_leads.stage` (owned by the B2B CRM, which rolls up partner events), Witty's
`lead_status`, enrollment columns, `b2c_lead_status_v` (versioned) and the shared `public.enrollments` table.

### 3.6 Is Eduwit's commission received per enrollment recorded?

Yes, in both CRMs (`INTEGRATION_CONTRACTS.md` §3). Currently empty in production.

---

## 4. Existing apps: conventions to reuse (spec Section 22, Phase 0 item 2)

| Area | What the sibling apps do | Portal decision |
| --- | --- | --- |
| Framework | Next.js `^16.3.8`, React `^19.3`, TypeScript `^5.9` strict + `noUncheckedIndexedAccess`, `"type": "module"`, Node ≥ 20.9 (CI on 22) | Same (D-02) |
| Request hook | Next 16 `proxy.ts` (formerly middleware): session refresh with `getClaims()`, 12 h idle sign-out, per-request nonce CSP, rate limits | Same pattern |
| Supabase clients | `lib/supabase/{server,browser,admin}.ts`; admin (service role) imports `server-only`; `db: { schema: 'b2c' }` | Same, with schema `inf` |
| Data access | Almost all reads and writes are `SECURITY DEFINER` RPCs; the database is the authority | Same. RLS on every table as well (spec) |
| Mutations | Server actions in `*-actions.ts`; route handlers only for auth callbacks, machine endpoints, downloads | Same |
| Staff 2FA | B2C: emailed 6-digit code (hash stored, 10 min, 5 per hour) after password **or Google**, trusted-device cookie (30 days). B2B: Supabase TOTP | B2C's emailed-code model (the spec asks to match it) |
| Env | `lib/env.ts` getters that throw on missing names; `.env.example` | Same, validated with zod (the spec requires zod) |
| UI | B2C: hand-written CSS tokens; B2B: Tailwind v4. Neither uses shadcn | **Tailwind v4 + shadcn/ui** (the spec's stack), with the shared Eduwit tokens (`docs/brand/palette.md`) |
| Brand | Navy `#0B2F5E` (logo samples `#072E5A`), amber `#F4A504`; amber never as text on white; Geist fonts; light default, dark via `data-theme` | Same tokens (sampled again from the attached logo: navy `#042C58`–`#082C58`, amber `#F0A400`–`#F4A404`) |
| Email | B2C: SMTP (Google Workspace) via nodemailer. B2B: Resend or Brevo from Postgres via `pg_net`, keys in Vault | Adapter with SMTP, Resend and Brevo implementations; mock until chosen |
| WhatsApp | Meta Cloud API direct (Graph v21); live only when env, settings and non-test all agree | Same, behind the adapter |
| Rate limiting | Database-backed fixed window (`rate_check` RPC), fail open, 429 with Retry-After | Same pattern in `inf` (fail **closed** for OTP and sign-in) |
| Security headers | X-Frame-Options DENY, HSTS preload, nosniff, strict Referrer-Policy, Permissions-Policy, COOP, nonce + `strict-dynamic` CSP | Same |
| Tests | Vitest; Playwright against **staging**; SQL tests as rolled-back scripts on a local plain Postgres with `local_stubs.sql`; no Docker, no `supabase start` | Vitest + Playwright + **pgTAP on a local Supabase in Docker** (Docker works in this environment); seed only local |
| CI | `b2c-crm-ci.yml`: npm ci, tsc, vitest, `npm audit --omit=dev --audit-level=high`, dependency review | New `influencer-portal-ci.yml` with the same steps plus lint, pgTAP and Playwright |
| Hosting | Vercel region `bom1` | Same |

---

## 5. Final tech decisions (spec Section 3, adjusted)

| Area | Decision |
| --- | --- |
| App | Next.js 16 App Router (D-02), TypeScript strict, Server Components and Actions, route groups `(admin)` at `/admin/*` and `(creator)` at `/creator/*`, installable PWA (manifest + service worker for the creator portal) |
| Location | `influencer-portal/` in this repository, alongside `b2b-crm/` and `b2c-crm/` (D-03). Separate Vercel project with root directory `influencer-portal` |
| Database | Schema `inf` (D-01); migrations in `influencer-portal/supabase/migrations`; `pg_cron` + an `inf.jobs` table (retries, dead letters) rather than pgmq, so jobs are inspectable with plain SQL and covered by RLS tests (D-11) |
| Local dev | Supabase CLI (`npx supabase start`, Docker) with a **shared-objects baseline**: the production definitions of every object the portal reads (`student_leads`, `touchpoints`, `w2_access_codes`, `w2_clicks`, `w2_conversations`, `enrollments`, `b2c_lead_status_v`, `b2c_enrollment_money_v`, `catalog.*` views and their tables, `b2b.earnings`, `b2b.invoices`, `w2_issue_code`, `lead_intake` and its helpers), generated from the production catalog with read-only queries (D-12). The full B2B/B2C schemas aren't needed and aren't copied |
| UI | Tailwind CSS v4, shadcn/ui (Radix), TanStack Table v8 (server-side pagination, sort, filter, column visibility, saved views), dnd-kit, Recharts, react-hook-form + zod, Tiptap (variables, conditional blocks, suggestion mode), lucide icons, sonner toasts, cmdk palette, Geist fonts |
| Documents | `@react-pdf/renderer` for contracts, certificates, statements, advice and media kits (pure Node, works on Vercel); SHA-256 over the canonical JSON and the rendered HTML; PDFs stored in a write-once bucket |
| Uploads | Supabase Storage with TUS resumable uploads (`tus-js-client`), signed URLs only, per-bucket size and type limits in settings |
| Validation | zod v4, shared schemas between client and server; JSON Schema generated from zod for the SQL check on `comp_config` |
| i18n | `next-intl`, English default, every string in message files |
| Notifications | Adapter interfaces: `EmailProvider` (SMTP, Resend, Brevo, Mock), `WhatsAppProvider` (Meta Cloud, Mock), in-app (Realtime). Delivery queued in `inf.notification_deliveries` with retries |
| Payments | `PayoutProvider` interface only (bank file export in v1; RazorpayX later) |
| Auth | Supabase Auth (shared project). Staff: Google or password, then **emailed code** (always, even after Google), trusted device optional. Creators: email OTP or Google, optional phone OTP once a WhatsApp/SMS provider exists. Every request checks an `inf` profile on the server; any other identity is refused |
| Observability | Sentry (`@sentry/nextjs`, behind an env flag; mock until a DSN is supplied), structured JSON logs with request ids, `/api/health`, `/api/metrics/summary`, admin System status page |
| Tests | Vitest (engine, attribution, masking, TDS/GST, milestones), pgTAP via `supabase test db` (RLS per role, masking proofs), Playwright (the 8 journeys) against local Supabase with the seed |
| Lint/format | ESLint (flat config, `typescript-eslint` strict-type-checked, `no-explicit-any` as an error), Prettier |
| CI | GitHub Actions: install, typecheck, lint, unit, pgTAP on a Supabase CLI stack, Playwright, `npm audit`, dependency review |

---

## 6. Risk register

| # | Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| RK-1 | A portal job or query loads the shared production database (Witty's latency) | Low | High | Bounded batches (≤ 500 rows), `statement_timeout` and `lock_timeout` on every job, advisory lock so runs never overlap, no trigger on shared tables, summary tables for dashboards, load test at 100k leads before go-live | Portal |
| RK-2 | Shared Supabase Auth: every creator holds an `authenticated` JWT on the same project, so any unguarded `SECURITY DEFINER` function of another product (603 are executable by `authenticated`) becomes reachable by creators | Medium | High | B2B and B2C functions check their own allowlists (audited by those projects). Before creator sign-up opens, re-run the advisor and list any `public` function without an internal role check for the owners (`w2_*` functions are callable by anon by Witty's design). The portal adds none: every `inf` function checks the caller's role | Owner + other teams |
| RK-3 | The old CRM trigger `crm_on_auth_user_created` inserts every creator account into `public.crm_users` (inactive viewer, no access) | Certain | Low | Harmless while `is_active = false`; noise in the old CRM's user list. Ask the B2C owner whether the trigger can be retired, or accept | Owner (B2C) |
| RK-4 | Legacy influencer objects keep full-row lead access for 3 accounts and plain-text passwords (`SHARED_CHANGES.md` L-1 to L-3) | Exists today | High | Your decision: retire at portal go-live (or deactivate the 3 rows now) | Owner |
| RK-5 | Route A personal access codes are bound to the first phone and expire in 30 days; a student who forwards the pre-filled WhatsApp text to a friend gives the friend a "taken" code, so the friend's lead is not attributed | Medium | Medium | The pre-filled text also carries `ref <CREATOR CODE>`, which Route B (Witty change) recognises; until then such leads show in the attribution review queue as "possible creator lead" via `utm_content` on the click | Witty team (R-1) |
| RK-6 | The B2B team changes the stage vocabulary (it's a setting) or B2C changes its view version | Medium | Medium | Unmapped values raise `inf.stage_unmapped`; the view version is checked on every sweep | Portal |
| RK-7 | Reading `b2b.earnings`/`b2b.invoices` internals for commission receipts | Low | Medium | Isolated in one function; request a versioned contract view (R-4) | Portal + B2B |
| RK-8 | Tax defaults (TDS sections, rates, thresholds, GST treatment, barter under 194R) are wrong for Eduwit's case | Medium | High | Shipped as editable settings marked "confirm with CA" (`confirmed_by_ca = false` banner on every finance screen); payouts can be held until confirmed (setting) | Owner + CA |
| RK-9 | OTP click-sign enforceability and stamp duty | Medium | Medium | Strong evidence trail (hash, consent text version, OTP reference, IP, UA, UTC and IST time) and a settings notice to confirm with counsel; `stamp_duty_reference` field | Owner + counsel |
| RK-10 | Providers, domain, Vercel and Sentry aren't chosen yet | Certain | Medium | Build against adapters with mocks (HARD STOP 4); list exact needs | Owner |
| RK-11 | No Supabase branch, and staging is shared with B2B/B2C | Certain | Low | Develop on a local Supabase in Docker with the generated shared-objects baseline; nothing touches staging or production until go-live | Portal |
| RK-12 | PostgREST timeouts: `authenticated` 8 s, `anon` 3 s | Low | Medium | Dashboards read summary tables refreshed by `pg_cron`; lists paginate on indexed keys | Portal |
| RK-13 | Showing student names to creators (DPDP purpose limitation) | Medium | Medium | Recommend first name plus initial (`LEAD_FIELD_WHITELIST.md`); configurable | Owner |
| RK-14 | Production has 2 leads, so real-world attribution edge cases are unseen | Certain | Low | Synthetic fixtures for every Witty path (Route A, Route B, re-enquiry, merge, opt-out, test numbers) in pgTAP and Playwright | Portal |
| RK-15 | Next.js 16 changes (`proxy.ts`, caching defaults) differ from the spec's Next 15 | Low | Low | Match the sibling apps, which are already on 16 | Portal |

---

## 7. Open questions (spec Section 23 and new ones)

Answered from the codebase and database:

| # | Question | Answer |
| --- | --- | --- |
| Q1 | `student_leads` columns and where Witty stores a creator code | 141 columns (`LEAD_FIELD_WHITELIST.md`). Witty stores access codes, not referral codes (§3.4); contract proposed |
| Q3 | How B2B and B2C lead stages are stored | `STAGE_MAPPING.md` §1 |
| Q4 | Is commission received recorded? | Yes, derivable from both CRMs (`INTEGRATION_CONTRACTS.md` §3); Finance can override |
| Q10 | `inf_` tables in `public` or their own schema? | **Recommend schema `inf`** (D-01), matching `b2b`/`b2c`. Please confirm |

Need your answer (the build continues on the stated default where one exists, except the HARD STOP items):

| # | Question | Default if you agree |
| --- | --- | --- |
| Q2 | Fields hidden from creators beyond phone and email: the five ASK rows in `LEAD_FIELD_WHITELIST.md`, and student name in full or `Riya S.` | Hide all five; first name + initial |
| Q5 | Email provider for portal mail and OTP (SMTP via Google Workspace like B2C, or Resend/Brevo like B2B) and the sender address. WhatsApp: use Witty's number (+91 96439 77407) only for deep links, and a **different** number for portal notifications and OTP? Who owns the WABA? | Witty number for deep links only; a separate notifications number |
| Q6 | Production domain(s) | `creators.eduwit.in` (creator portal and `/r/` short links) with `/admin` on the same app behind staff auth |
| Q7 | Authorised signatory name(s) and designation(s) | (none; no contract can be countersigned until set) |
| Q8 | Bank for bulk payouts and its file format | Configurable CSV; I'll pre-load one format once you name the bank |
| Q9 | TDS sections and rates (confirm with CA). Proposed defaults: commission per enrollment or lead → **194H, 2%**, threshold ₹20,000 per FY; fixed fees, milestones, usage and exclusivity fees, bonuses → **194J (professional), 10%**, threshold ₹50,000 per FY (alternative **194C**: 1% individual / 2% others, ₹30,000 single, ₹1,00,000 per FY); no PAN → **20% (206AA)**; TDS on the amount **excluding GST**; barter or in-kind value → **194R, 10%** above ₹20,000 per FY (Eduwit's liability; it isn't deducted from a payout) | As listed, editable by Finance, flagged "confirm with CA" |
| Q11 | Approve **S-12**: the portal calls Witty's `w2_issue_code()` for WhatsApp links (Route A), and send **R-1** to the Witty team (typed creator codes)? | Route A on; R-1 requested |
| Q12 | Legacy influencer objects (L-1 to L-3): retire at portal go-live, deactivate the 3 rows now, or leave? Migrate `priyansh01`, `vikas01`, `Normie2314` as invited creators? | Retire at go-live; invite real creators afresh |
| Q13 | Development database: OK to develop on a **local Supabase in Docker** with a shared-objects baseline generated from production by read-only queries? Or provide a read-only connection string so I can `pg_dump --schema-only` | Local Docker + generated baseline |
| Q14 | Next.js 16 (matching B2B/B2C) instead of the spec's 15? | Next.js 16 |
| Q15 | Re-enquiry: a lead whose phone was already in `student_leads` (e.g. lost months ago) returns through a creator link. Spec rule: `duplicate`, no credit. Keep strictly, or credit after N days of inactivity? | Strict: duplicate, no credit; setting `attribution.reenquiry_credit_after_days = null` |
| Q16 | Auth settings S-13 to S-15 (sign-ups on, redirect URLs, leaked-password protection) and the `crm_users` side effect (RK-3): OK? | Yes |
| Q17 | Stage mapping (`STAGE_MAPPING.md` §5): approve, including "Qualified" = Witty's first classification? | As proposed |
| Q18 | First staff users and their roles (Super Admin = `connect@eduwit.in`?) | `connect@eduwit.in` as Super Admin + Authorised Signatory |
| Q19 | Default attribution model and window | First touch, assisted touches recorded, 90 days |
| Q20 | When a commission rule confirms "on Eduwit commission received" and the partner pays an invoice **partly**, confirm the creator's commission pro rata or only on full receipt? | Only on full receipt (setting `confirm_partial_receipts = false`) |

---

## 8. Phase 1 plan (after approval)

1. Scaffold `influencer-portal/` (Next 16, TypeScript strict, Tailwind v4, shadcn/ui, ESLint, Prettier, Vitest,
   Playwright, next-intl), `.env.example`, env validation, CI workflow.
2. Supabase local stack (`supabase/config.toml`), the generated shared-objects baseline (reference only, never applied to
   production), schema `inf`, base tables (staff, roles, creators core, settings, audit log, jobs, domain events,
   notifications core, email codes, trusted devices, terms), helpers (`inf.has_perm`, masking, audit trigger),
   storage buckets, RLS and pgTAP tests per role.
3. Permission matrix in `lib/auth/permissions.ts` as the single source of truth, generating the SQL role-permission
   seed and driving UI guards.
4. Auth: staff (Google or password → emailed code, trusted devices, 12 h idle timeout, sign-in log), creators (email
   OTP, Google), `proxy.ts`, CSP, rate limits.
5. Layouts for both portals (admin sidebar and ⌘K; creator bottom navigation, PWA manifest), design tokens, base
   components with empty, loading, error and mobile states.
6. Settings framework (typed keys, JSON schema per key, versions, who and when), audit log viewer skeleton, notification
   adapter skeleton with mocks, seed framework (local only, guarded against production).
7. Phase gate (`PROGRESS.md`), tag `phase-1-done`.
