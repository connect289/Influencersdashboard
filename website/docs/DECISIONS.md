# Decisions made without the owner

Each entry: what was decided, why, and how to change it. Newest at the bottom of each phase. The owner reviews all of
these at the end (spec Section 0).

## Phase 0

### D-001 · The website lives in this monorepo under `website/`
- **Decision:** build in `connect289/Influencersdashboard` under `website/` (Next app in `website/web`, database in
  `website/supabase`, docs in `website/docs`), on branch `claude/inspiring-babbage-8asj1y`. Spec paths such as
  `docs/PROGRESS.md` mean `website/docs/PROGRESS.md`; "CLAUDE.md at the repo root" is `website/CLAUDE.md`, plus a short
  root `CLAUDE.md` that points to each product.
- **Why:** this is where the B2B and B2C CRMs already live side by side (same pattern: `b2c-crm/web`, `b2c-crm/supabase`,
  `b2c-crm/docs`). Creating a new GitHub repository is an outward-facing action that needs the owner.
- **Change:** move `website/` to its own repo with `git subtree split --prefix website`; nothing in the code depends on
  the parent folder.

### D-002 · Phase tags are `website-phase-N-done`
- **Why:** tags are repository-wide and the repo is shared with the CRMs; `phase-N-done` alone would be ambiguous.
- **Change:** `git tag phase-N-done website-phase-N-done` if plain names are preferred.

### D-003 · Next.js 16 (not 15) with Cache Components
- **Decision:** Next.js 16.4, React 19.3, App Router, Server Actions, `cacheComponents: true` (`"use cache"`,
  `cacheLife`, `cacheTag`, `revalidateTag`) for static-first pages and on-demand revalidation; `proxy.ts` (Next 16's
  replacement for middleware).
- **Why:** the spec says "Next.js 15" because it assumed the existing apps run on 15, but both CRMs are on Next 16.3
  (`b2b-crm/web/package.json`, `b2c-crm/web/package.json`). Matching them keeps one toolchain. Every spec requirement
  (RSC, Server Actions, ISR, on-demand revalidation) is available; Cache Components is the 16.x way to do ISR.
- **Change:** not recommended; Next 15 would need `revalidate` exports instead of `"use cache"`.

### D-004 · TypeScript 5.9 (not 7.0)
- **Why:** both CRMs use 5.9.3; TypeScript 7 (the native port) is new and the Next/ESLint toolchain is verified on 5.x.
- **Change:** bump `typescript` in `web/package.json` once Next documents 7.x support.

### D-005 · Students are NOT created in the shared Supabase Auth; the website owns student email verification
- **Decision:** students verify their email with a 6-digit code issued and checked by the website (`web_email_codes`:
  bcrypt-style hash, 10-minute expiry, 5 attempts, resend after 30 s, per-email and per-IP hourly caps), and get a
  signed, httpOnly session cookie (JWT signed with `WEB_SESSION_SECRET`, revocable through `web_student_sessions`). Codes
  are sent through the website's transactional email adapter. **Staff** (admin) sign in with Supabase Auth (Google or
  email) plus an email-code second factor, like the B2C CRM.
- **Why (found in production, 17 Oct 2026):**
  1. Trigger `crm_on_auth_user_created` on `auth.users` inserts every new auth user into `public.crm_users` (the old
     CRM's staff table; role `viewer`, inactive). Every student would become a row in the CRM staff list.
  2. Supabase Auth's OTP expiry, email template ("Magic link" must show `{{ .Token }}`), SMTP sender and email rate limits
     are project-wide. Changing them for the website (10-minute codes, code-only template) changes sign-in for the CRMs
     and the Influencer Portal.
  3. Every RLS policy in `public`, `b2b` and `b2c` grants to role `authenticated` and relies on staff-membership
     functions. They are correct today, but mixing thousands of student sessions into the same role widens the blast
     radius of any future policy mistake.
- **Spec alignment:** the spec says "preferably via Supabase Auth's email OTP"; the same outcomes (6-digit inline code,
  verified session, returning users sign back in with a code, history restored) are delivered without touching shared
  auth. The phone-OTP adapter and settings `require_phone_otp` / `push_unverified_gate_leads` are unchanged.
- **Change:** an `EmailVerifier` adapter interface is used everywhere; a `SupabaseAuthOtpVerifier` implementation is
  included but disabled. Switching to it needs the shared changes listed in `APPROVALS_NEEDED.md` (A-AUTH-1).

### D-006 · The current site could not be crawled from the build environment
- **Decision:** `eduwit.in`, `www.eduwit.in` and `horizons-cdn.hostinger.com` are denied by this environment's network
  policy (CONNECT 403; WebFetch DNS failure; no search-engine copy found). A full browser crawler
  (`web/scripts/crawl-legacy-site.mjs`) is ready to run. Until it runs, migrated copy (hero, services, testimonials, About,
  the six legal pages, consent text) is shown as clearly marked **"Pending migration"** placeholders held in
  `content/legacy/` and `web_` tables — never invented. Business facts given in the spec (address, GST, phone, email,
  29 universities / 715+ programmes, the three service names) are used as given.
- **Change:** allow the three hosts in the environment's network settings, run
  `node web/scripts/crawl-legacy-site.mjs`, then `npm run content:import-legacy` (built in Phase 6) to load the crawl.

### D-007 · Brand palette sampled from the supplied logo
- **Decision:** navy `#062F5B` and amber `#F3A503` (sampled from the logo the owner attached on 17 Oct 2026; matches
  `b2c-crm/docs/brand/palette.md` within rounding). Amber is never used for body text on light surfaces (contrast);
  a darker amber-ink is derived for that.

### D-008 · Local development database
- **Decision:** the Supabase CLI local stack (Docker: Postgres 17, Auth, PostgREST, Mailpit) for day-to-day work, seeded
  with a read-only snapshot of the shared objects the site uses plus the real catalogue rows (no personal data), and a
  second container, `prod-replica` (port 54330), rebuilt from production's own migration history and fingerprint-checked
  against production, for the "copy of the production schema" gate. A Supabase development branch was not created: it
  is billed and lives in the production organisation, and the local replica gives the same assurance.
- **Change:** `supabase branches create` can be used later; the migrations are branch-ready.
