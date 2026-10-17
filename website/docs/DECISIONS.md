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

### D-009 · Lead path: `lead_intake()` with `source_system = 'web_agent'`, through one website wrapper
- **Decision:** every website lead (Witty gate, built-in application form, counselling/enquiry forms) is created and
  enriched by `public.lead_intake(p jsonb)` called from a website-owned wrapper `web_lead_upsert(p jsonb)` (SECURITY
  DEFINER, service role only). In **one transaction** the wrapper calls `lead_intake`, records the submission in
  `web_lead_submissions` (idempotency key unique → double taps never duplicate), stores what `lead_intake` cannot hold
  (email-verified timestamp, exact offering, junk score) in `web_` tables, and writes side effects to `web_outbox`.
  `source_system = 'web_agent'` (already trusted by `lead_intake`: later self-reported values overwrite, first-touch
  attribution and consent never do). `lead.source` (→ `lead_source`) is `website_agent` for the Witty gate (spec 7.2:
  "exact value per the existing contract") and `website_form` for forms (`web|form` → B2B channel `web_form`).
- **Why:** spec rule 2.1 ("leads are written only through `lead_intake()`"); Witty uses the same direct path, so the CRMs
  already handle it; one path keeps duplicate handling (match on phone) identical everywhere.
- **Not chosen:** the B2B Intake API (`POST crm.eduwit.in/v1/leads`), which `docs/HANDOVER.md` suggests for website
  forms. It also ends in `lead_intake`, but as an untrusted `api` source (fills only empty fields, so steps 2–4 of the
  application form could not update a course Witty recorded earlier), adds a network hop to another product on the
  critical path, and cannot share a transaction with the website's outbox. **Change:** the `LeadWriter` interface has an
  `IntakeApiLeadWriter` implementation; switch with `web_settings.lead_writer = 'intake_api'`.

### D-010 · Website chat transcript in `web_advisor_messages` until the shared table has a channel column
- **Decision:** spec 7.5 asks for the shared messages table. `w2_messages` has no channel column and six CRM functions
  compute the WhatsApp 24-hour window from it; writing web turns there would break other products. Web turns go to
  `web_advisor_messages` with **exactly the `w2_messages` columns plus `channel='web'` and `session_id`**; the shared
  change is A-AGENT-2/3. **Change:** after approval, a one-off copy + switching the writer (`web_settings.transcript_target`).

### D-011 · Claude for the website agent, same prompts and contract as Witty (Gemini)
- **Decision:** the spec names the Claude API; Witty runs on Gemini `gemini-3.6-flash`. The website uses Claude with the
  same prompts (by reference) and JSON contracts: extractor on `claude-haiku-5-5`, counselor on `claude-sonnet-5-5`,
  both configurable in `web_settings`. A `ModelProvider` interface keeps a Gemini adapter possible if the owner wants
  identical model behaviour. **Change:** `web_settings.web_advisor_models`.

### D-012 · Witty on the website ships switched off until its engine is verified against Witty's own code
- **Decision:** `web_advisor_enabled` defaults to **false** in production. The web adapter (`lib/witty-core`) implements
  Witty's published contract (fact keys, asks, phases, modes, enums, hand-off texts, guardrails) and is fully built and
  tested, but the exact decision rules (ask order, HOT/WARM/COLD) live in n8n code that could not be read (A-AGENT-1).
  Spec 7.3 forbids inventing different reasoning and allows launch before the agent is ready.
- **Change:** supply the export; verify with the harness; flip the flag in the admin (no redeploy).

### D-013 · "Regular" (on-campus) catalogue rows are hidden from the finder by default
- **Why:** the site markets online and ODL programmes (spec §1); 7 catalogue rows have mode `Regular`.
- **Change:** setting `finder_include_regular_mode` (admin).

### D-014 · The homepage trust line is computed from data and drops claims the data does not support
- **Decision:** "29 universities · 715+ programmes" are counted live from the mapped, visible catalogue. "100% UGC-DEB
  entitled" is shown only when every listed university's catalogue text states UGC-DEB approval/entitlement. Today 4 of
  29 say "Not Stated in Source", so the line reads "29 universities · 715+ programmes · UGC-DEB status shown for every
  programme where the university has stated it" → shortened in UI to "29 partner universities · 715+ online & ODL
  programmes · approvals shown from university records".
- **Why:** spec rule 3 (no invented facts) and 10.4 (no fake counters) outrank the example copy in spec 8.1.
- **Change:** fix the four universities' data in the catalogue; the line updates itself.

### D-015 · "Easy EMI available" appears with every fee; an EMI amount only when the catalogue has one
- **Why:** owner decision (spec 18: "Show the full fee publicly … with 'Easy EMI available' alongside it") and spec 14
  ("If the catalogue has an EMI amount, show 'from ₹X/month'; never invent one"). `fee_other.Emi` holds an amount but not
  its period, so the "from ₹X/month" form is used only once the catalogue confirms the period (A-TAX-2); until then the
  panel shows "EMI from ₹X" without "/month" when an amount exists.

### D-016 · "Talk to a counsellor" opens WhatsApp to Witty's number with a pre-filled message
- **Why:** spec 18 Q8 is open; Witty's engine already treats "talk to a counsellor" as `asks_human` and hands off to a
  human, so conversations stay in one inbox (Chatwoot) and the CRMs see them. Number +91 96439 77407
  (`docs/go-live-setup.md`). The call button uses the business line +91-9650683269.
- **Change:** `web_settings.counsellor_whatsapp` / `counsellor_phone` in the admin.

### D-017 · Email provider assumption: SMTP via the Google Workspace relay, sender `no-reply@eduwit.in`
- **Why:** the B2C CRM already sends through `smtp-relay.gmail.com:587`; no new vendor needed. A Resend adapter is also
  built. **Change:** `EMAIL_PROVIDER` env (S-12).

### D-018 · Creator pages use a typed provider with a mock until the Influencer Portal API exists
- **Why:** no public creator API is specified (spec 9.3, 18 Q9). The website does not read `public.influencers`
  directly (that would publish creator data without an agreed contract). **Change:** set `CREATOR_API_URL` and switch
  `web_settings.creator_provider` to `http`.

### D-019 · Data minimisation on leads: no IP address is sent to `lead_intake`
- **Why:** spec rule 5 (minimal data). Device type is sent; IP is used only transiently for rate limiting and stored only
  as a salted hash in `web_gate_attempts` for abuse analysis (deleted after 90 days).

## Phase 1

### D-020 · Fonts are self-hosted Latin subsets with `font-display: optional`
- **Why:** measured on the production build: `next/font/google` declares every subset, so the ₹ sign (U+20B9, latin-ext)
  pulled a second ~130 KB file; font swaps moved the LCP element and caused CLS. Self-hosting only Latin (₹ uses the
  system font, present on Android/Windows/Apple) and `optional` display (text paints once in a metric-matched fallback;
  the brand font applies when it arrives within the block period — always from cache on later pages) gave CLS 0 and
  LCP 1.7 s (applied throttling). **Change:** `web/lib/fonts.ts`.

### D-021 · Performance budgets are asserted with applied (DevTools) throttling; simulated scores are tracked too
- **Why:** Lighthouse's simulated mode counts the framework JS (~165 KB gz, React DOM + Next runtime) requested before
  LCP as LCP-blocking, although the LCP element is server HTML text painted at FCP (observed 0.2 s). Applied throttling
  (slow 4G + 4× CPU) measures what a mid-range Android user actually experiences. Lighthouse CI asserts LCP < 2.5 s,
  CLS < 0.1, TBT < 200 ms on applied throttling and records simulated scores for trend. **Change:** `lighthouserc` in CI.

### D-022 · Default theme follows the visitor's system setting; Concept A was designed dark-first
- **Why:** spec 10.2 — the non-default theme "stays available via a toggle and prefers-color-scheme". The site setting
  `web_settings.default_theme` is `"system"`; the boot script falls back to dark when no preference is exposed. Owner can
  set `"dark"` to always lead with the luminous theme. The visitor's own toggle choice always wins.

### D-023 · Concept A (Luminous) chosen; Concept B (Prism) preserved and switchable
- **Why / scoring:** `docs/design/CONCEPTS.md`. **Preserved:** all B tokens, layouts and pages stay in the codebase
  (`data-concept="b"`, `/concepts/b/*`), selectable via `web_settings.design_concept`; also a local branch `concept-b`
  at the Phase 1 commit. That branch is **not pushed**: this session may only push `claude/inspiring-babbage-8asj1y`
  (push it with `git push origin concept-b` if wanted).

### D-024 · Concept B uses Inter's display optical size instead of Roboto Flex
- **Why:** Roboto Flex's variable file is 190 KB (Latin); Inter (already the body face) has an optical-size axis whose
  large sizes form a display cut — one 71 KB file serves the whole concept with the same kinetic weight shifts.
