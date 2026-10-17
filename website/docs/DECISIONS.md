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
- **Owner confirmed Concept A on 17 Oct 2026** ("Concept A is better, move ahead with it"). `design_concept` stays `"a"`.
  Concept B remains switchable until the owner asks for it to be removed (removing it would delete the `/concepts/b/*`
  pages and B tokens; nothing in A depends on them).
- **Why / scoring:** `docs/design/CONCEPTS.md`. **Preserved:** all B tokens, layouts and pages stay in the codebase
  (`data-concept="b"`, `/concepts/b/*`), selectable via `web_settings.design_concept`; also a local branch `concept-b`
  at the Phase 1 commit. That branch is **not pushed**: this session may only push `claude/inspiring-babbage-8asj1y`
  (push it with `git push origin concept-b` if wanted).

### D-024 · Concept B uses Inter's display optical size instead of Roboto Flex
- **Why:** Roboto Flex's variable file is 190 KB (Latin); Inter (already the body face) has an optical-size axis whose
  large sizes form a display cut — one 71 KB file serves the whole concept with the same kinetic weight shifts.

## Phase 2

### D-025 · CSP: strict without nonces on static pages, nonce + strict-dynamic on /account and /admin
- **Why:** a nonce forces every page to render per request (Next docs: static optimisation, ISR and CDN caching are
  disabled), which contradicts spec 3A's static-first design and the performance budgets. Prerendered pages contain
  Next's inline RSC payload scripts, so they need `'unsafe-inline'` for scripts; every other directive is strict
  (`object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `frame-ancestors 'none'`, no `unsafe-eval`, host
  allow-lists). The XSS surface is small: all content renders through React escaping; the only raw HTML is the fixed
  boot script and JSON-LD. Dynamic sensitive areas (account, admin) use a per-request nonce with `'strict-dynamic'`.
  **Change:** `lib/security/csp.ts`, `next.config.ts`, `proxy.ts`.

### D-026 · Attribution is first-party and necessary; funnel analytics are anonymous without analytics consent
- **Attribution** (UTM, click ids, referrer host, landing path, creator code) is stored in two first-party httpOnly
  cookies (`ew_ft` first touch, `ew_lt` last touch; 90 days; no personal data) and attached only to the student's own
  enquiry so it is credited correctly — not used to follow people across sites. **Funnel counters** for the admin are
  recorded without any identifier unless analytics consent is given (then a tab-scoped random id in sessionStorage).
  GA4/Clarity need analytics consent, Meta Pixel needs marketing consent. **Change:** `lib/attribution.ts`,
  `lib/client/analytics.ts`, Cookie Policy update proposal (Phase 6).

### D-027 · The website reads its Supabase key from `SUPABASE_SECRET_KEY`
- **Why:** this build environment pre-sets `SUPABASE_SERVICE_ROLE_KEY` to the **B2B staging** project's service key;
  process variables override `.env.local`, so a generic name could silently point the website at another product's
  project. A website-specific name (Supabase's current term for the key) prevents that everywhere.
- **Same for email and AI:** the environment also pre-sets `SMTP_HOST/PORT/USER/PASSWORD/FROM` (a real mail relay used by
  another product) and `ANTHROPIC_BASE_URL`. The website reads `EMAIL_SMTP_*` and passes the Anthropic base URL
  explicitly (`WEB_ANTHROPIC_BASE_URL`, optional), so local tests can never send real email through another product's
  relay or route AI calls through an inherited endpoint.

## Phase 3

### D-028 · Canonical levels: integrated degrees under UG; PGDM, PGDBA and PGCM under "PG Diploma / Certificate"
- **Why:** the catalogue stores BBA+MBA, BCA+MCA and B.Com+MBA as `PG`, but students join them after Class 12, so they
  are browsed with UG programmes (their `min_qualification = BACHELOR` is flagged like the other UG contradictions and
  shown as "Check eligibility"). Post Graduate Diplomas in Business Administration are stored as `DIPLOMA`; they are
  postgraduate, so they map to programme `pgdba` at level `pg_diploma` with PGDM and PGCM. **Change:** `web_tax_programmes`,
  `web_tax_rules_programme` (editable data).

### D-029 · Pure immutable SQL helpers are plain (inlinable) functions
- **Why:** `SECURITY DEFINER` and `SET search_path` stop Postgres from inlining a function, so per-row helpers
  (`web_norm`, `web_eligibility`, `web_duration_bucket`, `web_naac_rank`, `web_jarr`, `web_slugify`) ran as ~200k nested
  statements per search at 10k offerings (487 ms). They read no tables, so definer rights add nothing; they stay
  non-executable by `anon`/`authenticated`. The security test enforces this exact exception (immutable, SQL, no SET, no
  table access). Search at 10k offerings: 20–55 ms filtered, ~145 ms unfiltered (served from the edge cache).

### D-030 · Old offering deep links resolve by university + programme + specialisation + mode
- **Why:** the catalogue replaces a renamed row with a new id and a new `program_key` (the key hashes the name), so
  neither is stable. `web_offering_details` falls back to the current visible offering of the same university, canonical
  group and mode, and reports `moved_from` so the page can update the URL. **Change:** `web_offering_details`.

### D-031 · Catalogue changes are detected by polling; the website adds one pg_cron job
- **Why:** adding a trigger to `catalog_programs` would alter a shared table. `web_catalog_poll()` compares a fingerprint
  (row counts, max `updated_at`, `w2_meta.catalog_version`, taxonomy edits) every minute and refreshes the read model
  only on change, then queues a `revalidate` job in the outbox. Production gets one website-owned pg_cron job
  (`web_catalog_poll`, listed in `APPROVALS_NEEDED.md` A-CRON-1); Vercel Cron calls `/api/internal/catalog-poll` every
  5 minutes as a fallback and `/api/internal/outbox` every minute (per-minute crons need a Vercel Pro plan; otherwise the
  short cache TTL keeps data within 5 minutes). Local stacks without pg_cron skip the schedule.

### D-032 · University facts are parsed only from explicit statements; state stays empty until supplied
- **Why:** no invented facts. NAAC grade, UGC-DEB status, AICTE and NIRF come from the catalogue's structured
  `accreditation_text` (other ranking agencies are never shown as NIRF; NIRF bands such as "Top 200" are shown as bands).
  Every value carries its source statement for the panel and the admin. University state/city are not in the catalogue,
  so the state facet stays hidden until the owner fills `web_university_profiles` (S-46). Admin corrections go in
  `facts_override` with a source note.

### D-033 · "Online" and "distance" in a query are a study-mode filter
- **Why:** spec 6.4's example ("bca online for working professionals") expects structured filters. The catalogue's
  synonyms `onlinemba`/`distancemba` would swallow the mode word, so they are not imported as programme aliases.

### D-034 · A query made only of unknown words returns zero results (with closest matches), not everything
- **Why:** returning the whole catalogue for "zzzz" looks broken. Unknown words next to known ones ("mba xyzzy") are
  ignored and reported ("We ignored: xyzzy"); a query with nothing recognisable goes to the zero-results path: closest
  matches by trigram distance, the count without the query, and "Ask Witty" (spec 6.4).

## Phase 4

### D-035 · Finder metadata streams to browsers; crawlers get it in <head>
- **Why:** the finder's title, description and robots rules depend on the search state, so under Cache Components they
  are rendered per request. Next streams such metadata to browsers and serves it blocking in `<head>` to HTML-limited
  crawlers (its built-in list: Bing, social previews, WhatsApp, Lighthouse…); Google renders the streamed version.
  Lighthouse 13 no longer puts "Chrome-Lighthouse" in its user agent, so `lighthouserc.cjs` sets it to measure the
  crawler path. Finder pages set `instant = false` (navigations into them wait for their metadata; the shell and
  skeleton still prerender).

### D-036 · Finder URL state: server-rendered results, optimistic controls, cumulative "Show more"
- **Why:** spec 6.4 "URL is the state". Filters replace the URL (no history entry per click) and the server renders the
  results; controls update optimistically (`useOptimistic`) so a tick shows instantly. The offering panel uses
  `history.pushState` (`?offering=`) so Back closes it without a server round trip. "Show more" sets `?page=N` and the
  server renders the first N pages (12 groups each), so Back/Forward and reloads restore the same list and scroll.
  Indexable finder URLs: the finder home and single programme (± one specialisation), level, category or university
  views; everything else is `noindex, follow` with a canonical to the nearest indexable view (`lib/search/seo.ts`).

### D-037 · The consent banner is server-rendered and hidden before paint once a choice exists
- **Why:** rendering it after hydration made it the LCP element on the finder (render delay 3.4 s). It now ships in the
  HTML; the inline boot script sets `<html data-consent>` when the `ew_consent` cookie exists and CSS hides the banner
  before first paint. No late paint, no layout shift. **Change:** `ConsentBanner`, `boot-script.ts`, `globals.css`.

### D-038 · "Ask Witty" falls back to a WhatsApp counsellor while Witty is off
- **Why:** spec 6.1 wants "Ask Witty" always visible, but Witty stays off until the shared engine is verified (D-012).
  Every Ask Witty button (`AskWitty`) opens `/witty?q=…` when `web_advisor_enabled` is on, and otherwise WhatsApp to the
  counsellor number with the question pre-filled — never a dead end. The same component serves the circuit breaker later.

### D-039 · Finder client code is kept small
- **Why:** budgets (spec 13.2). URL-state helpers that client code needs live in `lib/search/state.ts` (no zod); parsing
  with zod stays server-side (`lib/search/params.ts`). The offering panel, guided finder, mobile filter sheet, fee
  slider and toast host load on demand; the view toggle is plain buttons. First page = 12 programme groups; separate
  Suspense boundaries split hydration. Result: ~222 KB gz JS on `/programmes` (≈145 KB shared framework), Lighthouse
  mobile 94–97, LCP 1.7 s, TBT ≤ 270 ms, CLS 0.

## Phase 5

### D-040 · Unknown university / curated-view slugs are soft 404s with noindex
- **Why:** both routes are prerendered for known slugs and render new ones on demand (a new university or a newly
  published curated view appears without a rebuild). Under Cache Components the shell streams first, so a not-found
  for an unknown slug keeps status 200 and Next injects `<meta name="robots" content="noindex">` (Next docs: "Status
  codes"; Google treats it as a soft 404). A hard 404 would need `dynamicParams = false`, which hides new slugs until
  the next deploy. Renamed slugs get a 301 through `web_redirects` (Phase 9).

### D-041 · Catalogue EMI amounts are monthly; shown as "Easy EMI from ₹X/month" (refines D-015)
- **Why:** for the 214 offerings with `fee_other.Emi`, total fee ÷ EMI gives whole months (24, 36, 48) — the amount is a
  monthly instalment. Spec 14: show "from ₹X/month" when the catalogue has an amount; otherwise "Easy EMI available".

### D-042 · The application form ships with a mock transport until Phase 7
- **Why:** spec 17 Phase 5 ("form UI inside the panel, with mocks; wired to leads in Phase 7"). The form talks only to
  `ApplicationClient` (`lib/forms/client.ts`); the mock accepts any 6-digit code except `000000` and stores nothing. Phase 7
  swaps in the server implementation (email code, `web_lead_upsert` → `lead_intake`, outbox) without UI changes.
  Field options with no catalogue data (intakes) use neutral timing choices ("Within 3 months"…).

### D-043 · The desktop facet rail mounts only on wide screens
- **Why:** phones hid the rail with CSS but still hydrated it (~100 ms of main-thread work on a mid-range Android). The
  rail's column is reserved and shows placeholders until hydration on desktop (no layout shift); phones use the
  filter sheet. Finder TBT on the throttled phone profile: 160–260 ms (budget 300).

## Phase 6

### D-044 · Interim copy until the current site can be crawled; nothing invented
- **Why:** the environment blocks eduwit.in (D-006, S-01), so the current hero, "bridge between students and
  universities" text, service descriptions, About page, testimonials and legal pages cannot be reused verbatim yet.
  The homepage, About and How it works use plain descriptions of Eduwit's service drawn from the spec's business
  context (`content/home.ts`, `content/about.ts`, flagged for the owner) with numbers from the live catalogue; no claims
  about universities beyond the catalogue ("UGC-DEB entitled" is not claimed for all, D-014). Testimonials, guides and
  stories render only when real, consented rows exist (sections and the Resources nav item hide otherwise). Legal pages
  keep their URLs and show a "being moved — email us" notice with `noindex` until `scripts/import-legacy.mjs` imports
  the verbatim text from the crawl. **Go-live blocker:** the legal pages must be migrated before launch (S-01).

### D-045 · Runtime redirects in the proxy, cached per instance
- **Why:** admin-managed redirects (renamed slugs, old URLs, 404-monitor fixes) must work without a redeploy. The proxy
  reads `web_redirects` through `web_redirects_all()` (cached 60 s in memory, 1.5 s timeout, last good map kept on
  error) and counts hits asynchronously. The legacy URL map stays static in `next.config.ts`.

## Phase 7

### D-046 · Only the signed-in owner can change an application
- **Why:** an attempt id travels through the browser. `web_application_save_step` and `web_application_submit` also
  require the student id from the signed `ew_sid` session (set at verification), so a leaked attempt id cannot enrich
  or submit someone else's application. The verification code hash is bound to the attempt's idempotency key.

### D-047 · Conversions API events only with marketing-cookie consent
- **Why:** the Lead / SubmitApplication events are ads measurement. The outbox handler sends them only when the visitor
  accepted marketing cookies at the time of the form (`attribution.ad_consent`); `_fbp`/`_fbc` are read only then.
  Without `META_CAPI_TOKEN` + `NEXT_PUBLIC_META_PIXEL_ID` (S-17) the event is logged as mocked. Email and phone are
  SHA-256 hashed; the event id is the attempt / application id, for de-duplication with the Pixel (Phase 9).
  **Change:** `lib/server/outbox-handlers.ts`.

### D-048 · Outbox worker schedule: Vercel Cron every minute, pg_cron fallback
- **Why:** `vercel.json` calls `/api/internal/outbox` every minute (needs the Vercel Pro plan, S-47). On Hobby, use the
  documented pg_cron + pg_net call with `WEB_INTERNAL_KEY` (same endpoint, POST). The worker also runs
  `web_push_unverified()` (off unless `push_unverified_gate_leads` is on).

### D-049 · Sign-in with an unknown email creates a verified account without a lead
- **Why:** answering "no account for this email" would reveal who has enquired. A code is sent either way; proving the
  email creates a student record with no lead (`surface = 'signin'` never calls `lead_intake`). The account page then
  shows nothing until they apply or enquire.

### D-050 · Turnstile test keys are mocks outside production and refused in production
- **Why:** CI and local runs must not depend on Cloudflare being reachable. Cloudflare's documented test secrets
  (`1x…AA` pass, `2x…`/`3x…` fail) are evaluated locally and the widget is not loaded for test site keys; in production a
  test or missing secret fails closed. A real key with Cloudflare unreachable lets the attempt through (logged) because
  rate limits, screening and the email code still apply.

### D-051 · Creator pages never claim an endorsement without the portal's data
- **Why:** `/c/<handle>` could otherwise say "Recommended by <anyone>". With no `CREATOR_API_URL`, production renders a
  neutral welcome (the code is still attached through the attribution cookie); outside production a single
  `demo-creator` mock exists for tests. Creator pages are `noindex` (campaign landing pages).

### D-052 · Client IP for rate limits comes from `x-forwarded-for`
- **Why:** on Vercel the header is set by the platform (client-supplied values are overwritten), so limits per IP are
  reliable there; the e2e suite sets a different value per test so repeated local runs do not trip per-IP limits. Raw
  IPs are never stored (hashed with `hashId`).

### D-053 · Junk-risk score is a hint, never a block
- **Why:** spec 7.2. Heuristics (repeated or sequential digits, test words, keyboard runs, vowel-less emails, test
  domains) score 0–100; stored on the attempt; unverified attempts scoring ≥ 50 are never pushed as leads. It reaches the
  lead only after A-LEAD-3.

### D-054 · Document upload is not built in v1
- **Why:** the spec makes it optional behind `document_upload_enabled` (default off) because documents are sensitive.
  Turning it on needs a private storage bucket, retention rules, malware scanning and a Privacy Policy change (legal
  review, S-44), none of which can be decided without the owner. The setting exists and the form shows no upload.
  **Change:** owner decision at or after go-live.

## Phase 8

### D-055 · Wrappers of Witty's shared functions pin `search_path = public`
- **Why:** `w2_build_prompt`, `w2_search_programs` and `w2_kb_search` are SECURITY INVOKER with unqualified table names;
  called from a website function pinned to `search_path = ''` they cannot find their tables. The three read-only
  wrappers (`web_agent_core_prompts`, `web_advisor_search`, `web_advisor_kb`) pin `public` instead (pg_trgm and vector
  live there; only `service_role` can execute them; nobody else can create objects in `public`). Every other web function
  keeps `search_path = ''`.

### D-056 · The local database mirrors Witty's prompts for development
- **Why:** the web channel reads Witty's prompts by reference (never forked into code). Locally, `supabase/seed.sql`
  loads the two production prompt rows from the read-only discovery copy (`docs/discovery/witty-prompts.md`); their md5
  hashes match production (extractor `b53fe530…`, counselor LF-normalised `d0427706…`). Seeds never run on production.

### D-057 · The homepage hero hands the first question to the full-screen chat
- **Why:** spec 7.4 asks for a chat surface in the hero and a full-screen chat on mobile. Hydrating the whole chat in the
  hero would break the homepage's performance budget (TBT ≤ 300 ms). The hero keeps Witty's orb, greeting and starter
  chips, and its ask box is a plain GET form to `/witty?q=…` (works before hydration); the question becomes the first
  interaction there (gate first, then the question is sent). Same flow on desktop and mobile.

### D-058 · Pages with params allow blocking renders; the consent banner moved to the public layout
- **Found in Phase 8:** when a cache tag expired (settings every 5 minutes, or any admin save), every `[slug]` page
  returned 500: Next re-prerendered the routes' shared shell, where `params` and `usePathname()` are runtime data. Fix:
  `instant = false` on the param routes (known params stay prerendered; others render on demand), and the consent banner
  is mounted by the `(site)` layout instead of reading `usePathname()` in the root layout. Regression test in
  `e2e/content.spec.ts`; `/api/internal/revalidate` accepts `expire_now` for flags.

### D-059 · A scripted model provider stands in for Claude without a key
- **Why:** no Anthropic key in this environment or CI (S-14). `lib/server/web-advisor/mock.ts` produces extractor and
  counselor JSON from a few patterns, so the real engine, verifier, placeholder filling, streaming, storage and lead path
  are exercised end to end. It is refused in production; with a key, the Claude provider (prompt caching on the system
  prompt) is used automatically.

### D-060 · Engine decisions the published contract leaves open (to verify under A-AGENT-1)
- Classification needs a stated timeline (Witty shows no COLD leads in 393 conversations); `LIKELY_ELIGIBLE` stays
  unqualified until the score is known; ask order course → specialization (once) → qualification + score → programmes →
  timeline → budget (only when fees come up) → motivation → counsellor offer; three rows, one per university, exact
  matches first, then within budget, then lowest fee; rows are re-listed only when the search changes or the student
  asks; a stated "stop" opts the lead out (as on WhatsApp). Every rule cites its source in `engine.ts`.

### D-061 · Web chat transcripts and leads
- **Why:** turns go to `web_advisor_messages` (exact `w2_messages` columns + `channel='web'` + `session_id`; A-AGENT-2/3)
  and the lead is updated every turn through `lead_intake` (`source_system='web_agent'`, Witty's payload keys and event
  types, idempotency `web:<session>:<turn>`). A retried message (same client id) replays the stored reply. The website
  never writes `w2_*` tables (the STABLE `w2_search_programs`, not the caching variant).

## Phase 9

### D-062 · Only the finder home and curated views are indexable (supersedes part of D-036)
- **Why:** spec 13.1 — "indexable filter combinations: only the curated finder views created in the admin; no index bloat
  from arbitrary facet URLs." Every filtered `/programmes?…` URL is now `noindex, follow` and canonicalises to the curated
  view with the same programme/specialisation/level/category/university/mode filters, else the curated view for its
  programme, else `/programmes`. `?offering=` / `?group=` panel deep links are always noindex. New landing pages come
  from the admin (curated views) and the Phase 11 opportunity finder.

### D-063 · One event id per conversion for the Pixel and the Conversions API
- **Why:** de-duplication (spec 13.3). `Lead`: the gate attempt id (browser `lead_created` and the `capi_lead` job);
  `SubmitApplication`: the application reference (browser `form_submit` and `capi_submit_application`). The Pixel sends
  `SubmitApplication` as Meta's standard event, and only for application forms (not enquiries).

### D-064 · Sitemaps, robots and social images
- **Why:** spec 13.1. `/sitemap.xml` is an index of `/sitemaps/{pages,curated,universities,resources}.xml`, rendered per
  request from cached data so new universities, views and guides appear without a deploy; legal pages join once migrated
  (D-044). `robots.txt` blocks staff, account, API, campaign and utility routes, and everything on preview deployments.
  OG/Twitter images are generated with `next/og` (site default, universities, curated views, guides). Legacy redirects
  return 301 (not Next's default 308) and CI checks every entry.

### D-065 · Tools run only from the project's own pinned binaries (incident, 17 Oct 2026)
- **What happened:** one background Lighthouse run invoked `npx lhci`, and npx resolved the bare name to an unrelated
  public package `lhci@4.1.2` ("placeholder", prints one line) instead of the project's `@lhci/cli`. Its code was read
  afterwards: a single `console.log`, no install scripts, no file or network access. It was deleted from the npx cache.
- **Change:** Lighthouse runs as `npm run lhci` (local `@lhci/cli` only); CI and configs call `npx --no …` so npx can never
  download a same-named package; new dependencies are pinned to versions published at least two weeks earlier
  (e.g. `@anthropic-ai/sdk` 0.131.0).

## Phase 10

### D-066 · One allow-listed, audited save path for all admin content
- **Why:** spec 11 lists a dozen editable content types. Instead of a function per table, `web_admin_entities` declares
  each type's table, key, editable columns, minimum role, cache tags and whether rows may be deleted;
  `web_admin_save` / `web_admin_delete` write only those columns, re-check the role, enforce content rules the tables
  cannot express (testimonials need consent to publish, guides need author + reviewer, accepted consent texts are never
  reworded) and write the audit row (before/after) in the same transaction. The UI is generated from
  `web/lib/admin/entities.ts`; saving expires the entity's cache tags so the public site updates at once.
  Programme data stays in the shared catalogue (read-only here); university pages edit only editorial fields.

### D-067 · Admin roles
- **Viewer:** reads everything. **Content editor:** content, curated views, SEO overrides, redirects, synonyms, taxonomy
  mapping, announcement and homepage sections. **Super admin:** additionally feature flags (Witty on/off, unverified
  pushes, phone OTP, documents), legal pages, consent texts, outbox retries, privacy requests. Enforced in the page
  guard (`requireAdmin`) and again in every database function.

### D-068 · Funnels mix server truth and consented client beacons
- **Why:** gate submitted / code sent / verified / first message / qualified and form steps come from the website's own
  tables (exact). Hero view, gate open, panel open and form start come from `web_funnel_events` beacons, counted per
  anonymous id only with analytics consent (otherwise per event), so the top of the funnel is approximate.

### D-069 · Application form fields configurable in the admin
- **Why:** spec 9.1A. Setting `application_form` lists non-core fields to hide or make optional; the form reads it when
  opened. Contact details, the email code and consent cannot be hidden.


## Phase 11

### D-070 · Search Console without credentials: labelled sample data outside production only
- **Why:** S-20 (service account) is not available. Development and CI import deterministic sample rows built from the
  site's own pages (`source = 'sample'`, shown in amber on the dashboard) so every SEO screen can be exercised and
  tested; production imports nothing until credentials exist. With credentials the same import reads Search Analytics
  (date × query × page) daily through a service account (JWT via `jose`, read-only scope).

### D-071 · Briefs and drafts are grounded in catalogue facts and never self-publish
- **Why:** spec 13.4. A brief lists the search intent, outline, questions, internal links, the facts it may use (offering
  count, university count, fee range from the read model) and the rules. A first draft is Claude-assisted only when an API
  key is set (S-14) and is rejected if it contains a banned claim; otherwise it is a structured skeleton for the author.
  Either way it lands as `draft`; publishing still requires a named author and reviewer (database constraint).

### D-072 · On-page checks run against the rendered pages
- **Why:** the checker fetches each curated view, university page and guide as a crawler sees it (D-035 user agent) and
  checks the HTML that ships: title/description length and uniqueness, one H1, heading order, intro length, FAQs, JSON-LD
  validity, image alt text, internal links in/out, broken internal links, banned claims (the same list as the CI copy
  check, `content/banned-claims.json`). Scores are stored per path; it runs daily (`/api/internal/seo-daily`) and on demand.
  "Before publish" for drafts is the preview in the editor plus the next run after publishing.

### D-073 · Internal links need editor approval; 404s are captured by a beacon
- **Why:** suggestions come from whole-word mentions of curated-view programmes and university names in guides; only
  approved links render (a "Related" block on the guide). 404s are reported by the not-found page itself (path and
  referring host only), since the proxy cannot know a route will 404; a miss becomes a 301 in one click, and redirect
  chains are flagged.

### D-074 · Local SEO without invented hours
- **Why:** the home and contact pages carry `EducationalOrganization` + `LocalBusiness` with the address and phone from
  the spec; opening hours appear only after the owner sets `business_hours` (S-51). The Google Business Profile and
  directory work is a tracked manual checklist.

### D-075 · Related-link blocks on curated views and university pages
- **Why:** the first on-page run scored our own pages 80 on average, mostly for missing internal links in the content
  (spec 9: curated views, university pages and resources link to relevant finder views). Curated views now list the
  universities in their results (by option count) and related curated views; university pages list the curated views for
  the programmes they offer. Both are computed on each render from the curated views and catalogue, so they stay fresh
  without editing. University titles drop "online and distance" for names over 25 characters to stay near 65 characters.
  The checker reads the intro as the first real paragraph after the H1, counts streamed Suspense content (crawlers render
  it), and counts links from header, footer and hub pages (`/`, `/programmes`, `/universities`, `/resources`) as inbound.
  After the change the local average is 95; what remains is content work (university intros in the admin, S-46/S-53).
