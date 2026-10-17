# Eduwit Website — Claude Code Build Prompt

> **How to use this file:** Save it in a new repo as `docs/WEBSITE_SPEC.md`. Give Claude Code read access to the Supabase project, the CRM code folder, and the Witty n8n workflow export. Start Claude Code in normal mode and paste the kickoff prompt you were given (or: *"Read docs/WEBSITE_SPEC.md end to end and follow the EXECUTION INSTRUCTIONS in Section 0. Build every phase in one continuous run."*). It builds all phases in one go, step by step, and stops only for production go-live. Everything below the line is written for Claude Code.

---

## 0. Execution instructions (read first)

You are the lead engineer and lead designer rebuilding **eduwit.in**, the public website of Eduwit Learning Services. This document is the source of truth. **Build the entire site, Phase 0 through Phase 12 (Section 17), in one continuous run.** Work through the phases in order, step by step, moving from each phase to the next on your own. Do not stop to ask for approval between phases. The owner reviews the result at the end.

### One-run rules
- **Production is never touched during the build.** All development, migrations and seeds run against a local Supabase (Docker) or a Supabase development branch, using a pulled copy of the production schema. Production is only read (SELECT and schema inspection) until the owner approves go-live.
- **Changes to shared objects** (`catalog_*`, `student_leads`, `lead_intake()`, the messages table, `w2_*`) may be made **in your local dev database** so the build can proceed, but each one must be written as a separate, reviewable migration and listed in **`docs/APPROVALS_NEEDED.md`** (what, why, risk, rollback, and which other products it affects). They are applied to production only after owner approval at go-live. Where an approach is possible without touching shared objects (e.g. `web_` taxonomy tables keyed to catalogue IDs), prefer it and note the shared alternative.
- **Never modify** the existing CRM code, the Witty n8n workflows, or Chatwoot. Anything those systems would need to change goes into `APPROVALS_NEEDED.md` as a handoff note for their owners.
- **Missing credentials or accounts** (email provider, analytics IDs, Vercel, DNS, Turnstile, Claude API key): build against the adapter interfaces with mock providers and keep going. List exactly what is needed in `docs/SETUP_CHECKLIST.md`.
- **Owner-choice items** (such as the design concept in Phase 1): make the best-justified choice yourself using the criteria in this spec, keep the alternative available (e.g. a switchable theme or preserved branch), and log it in `DECISIONS.md` for the owner's end review.
- **Ambiguity:** choose the most sensible option that keeps behaviour configurable, log it in `DECISIONS.md`, and continue. Don't stop for UI details, naming, or library choices within the stack.

### The only times you stop and wait
1. **Go-live (end of Phase 12):** applying migrations to production, deploying to production, or switching DNS from Hostinger. Prepare everything (migrations, dry-run report, rollback scripts, redirect map, `docs/RUNBOOK.md`, a go-live checklist), present the final report, then stop.
2. **Truly blocked:** only if every remaining task depends on something in `APPROVALS_NEEDED.md` or `SETUP_CHECKLIST.md` that cannot be mocked. Before stopping, finish everything else possible.
3. **Anything that would expose commercial data** (partner commission, internal fields) or personal data in a way this spec forbids: never do it; record it and continue with the safe option.

**For each phase:**
1. Write the phase plan in `docs/PROGRESS.md`.
2. Build step by step. After each step: typecheck, lint, run tests, fix failures, commit.
3. Run the phase gate:
   - migrations apply cleanly on a fresh database AND on a copy of the production schema
   - all tests green
   - Lighthouse and accessibility checks pass for pages built so far
   - docs updated
4. Self-review: list every requirement for the phase from this spec and mark each one Done / Partial / Deferred-with-reason in `PROGRESS.md`. Nothing is silently skipped. Fix Partials unless blocked.
5. Write a phase summary, tag the phase (`phase-N-done`), and continue.

**Keep state so work survives context resets:**
- `docs/PROGRESS.md`: current phase and step, what's done, what's next, blockers. Update it after every step.
- `docs/DECISIONS.md`: every assumption or decision made without the owner, with the reason and how to change it.
- `docs/APPROVALS_NEEDED.md` and `docs/SETUP_CHECKLIST.md`: as above.
- `CLAUDE.md` at the repo root: conventions, commands, structure, and "to resume, read docs/PROGRESS.md and continue from the current step."
- Use git: commit after every completed step with clear messages, and tag each phase (`phase-N-done`).
- If context gets long, update `PROGRESS.md` and keep going; a fresh session must be able to resume from the files alone.

**Final report (end of Phase 12):** what was built, test and Lighthouse results, the design choice made and how to switch, everything in `DECISIONS.md`, `APPROVALS_NEEDED.md` and `SETUP_CHECKLIST.md`, known issues, and the go-live steps.

---

## 1. Business context

**Eduwit Learning Services** is a GST-registered EdTech lead-generation marketplace based in Ghaziabad, Delhi NCR.

- GST number: 09BXLPJ7928K1ZP
- Address: 267-F3, Neeti Khand-1, Indirapuram, Ghaziabad, UP 201014
- Phone: +91-9650683269. Email: connect@eduwit.in
- It is an authorised admission partner for **29 UGC-DEB entitled universities** offering **715+ online and ODL programmes** (UG and PG: BA, B.Com, BBA, BCA, MA, M.Com, MBA, MCA, and more). This will grow into thousands of programmes.
- Leads are qualified by **Witty**, an AI WhatsApp assistant, then allocated by the CRMs to partner edtechs or the in-house team.

**The website is one of six separate but integrated products:**
1. Witty
2. B2B CRM
3. B2C CRM
4. **Website** (this build)
5. **Website AI agent** (built into this site's homepage)
6. Influencer Portal

**Shared foundation:**
- All products share **one Supabase project** (Mumbai, ref `xlseqwgyjuqhktrguhyc`).
- `student_leads` is the master lead table. All intake goes through `lead_intake()`.
- `catalog_*` holds the shared programme catalogue, the same programmes and knowledge that Witty and the CRMs use.
- Witty's tables are `w2_*`. Witty runs on n8n (`n8n.eduwit.in`).
- A shared **messages table** is reserved exclusively for Witty and the website agent. Sales and marketing email or WhatsApp never go there. Conversations stored there are used to analyse and improve the agents.
- Existing apps run on Next.js 15 on Vercel with Supabase Auth.

**The current site** is on Hostinger Horizons. Its content must be **reused**:
- hero copy, stats, course offerings, the "bridge between students and universities" section
- services: Educational Counselling, Course Discovery & Comparison, Application & Enrollment Support
- testimonials
- contact details and the consent text on the contact form
- the About page
- six legal pages: `/legal/terms-and-conditions`, `/legal/privacy-policy`, `/legal/disclaimer`, `/legal/refund-policy`, `/legal/cookie-policy`, `/legal/data-privacy-opt-out`

Crawl the whole site in Phase 0 and inventory every page, text block, image, and URL.

**Goals, in priority order:**
1. Turn visitors into **verified leads**: AI advisor first, then programme enquiries and counselling forms.
2. Make finding the right programme among thousands **effortless and logically flawless**.
3. Build trust: accuracy, approvals, transparency, no hype.
4. Win organic search through a small set of curated, pre-filtered finder views (e.g. "Online MBA") and university pages. There are **no separate pages per programme**, because the catalogue doesn't hold enough detail per programme to make each page genuinely useful.
5. **Look like something from the future** (Section 10), built on best-in-class system design (Section 3A), while staying fast on mid-range Android phones on 4G.

---

## 2. Non-negotiable rules

1. **Never break other products.**
   - Website-owned tables use the `web_` prefix.
   - Migrations are additive only. Never alter or drop shared objects.
   - Reads from `catalog_*` and `student_leads` go through approved views or functions.
   - Leads are written **only through `lead_intake()`**.
   - Agent messages are written only to the shared messages table, in its existing format.
2. **Production Supabase is live.** Develop against local Supabase (Docker) or a Supabase branch, using a pulled copy of the production schema. Only read production until go-live is approved.
3. **No invented facts.** Every fee, approval, accreditation, ranking, duration and eligibility rule shown anywhere (pages, cards, AI answers) comes from the catalogue. If a field is missing, show nothing or "Ask an advisor," never a guess. Every fee shows a "last verified" date and a disclaimer.
4. **Commercial data is never exposed.** Partner commission rates, partner names (if confidential), and internal fields never reach the browser, public APIs, page source, or the AI agent's replies.
5. **Privacy:** DPDP-compliant consent, minimal data, a verified email before any lead is created (phone is collected and validated, but not OTP-verified at launch), no PII in URLs, logs, or analytics events.
6. **TypeScript strict**, zod validation on both server and client, RLS on every `web_` table, secrets in env only.
7. **Performance is a feature.** The homepage must still hit Core Web Vitals targets with the AI hero (Section 13).

---

## 3. Tech stack

- **App:** Next.js 15 (App Router, React Server Components, Server Actions), TypeScript strict, deployed on Vercel.
  - **ISR / static generation** for university pages and curated finder views.
  - **On-demand revalidation** when catalogue data changes, via a webhook or DB trigger that calls a revalidate endpoint.
- **UI:** Tailwind CSS, shadcn/ui (Radix), **Framer Motion** for motion, and Lucide icons.
  - Use `next/font` for fonts and `next/image` with AVIF/WebP.
- **Data:** the shared Supabase project (Postgres, Auth, Storage, Realtime, Edge Functions, `pg_cron`).
- **Search:** Postgres-native, using `tsvector` full-text with weights, `pg_trgm` for typo tolerance, a synonyms table, and `unaccent`. Precompute facet counts with a SQL function. Design a search adapter interface so Typesense or Meilisearch could replace it later without UI changes.
- **AI agent:** the Claude API with streaming, behind a server route, using **the same agent core as Witty** (Section 7.3).
- **Email verification:** 6-digit email codes, preferably via Supabase Auth's email OTP (which also gives the session), sent through a transactional email provider configured as Supabase's SMTP. Also build a phone-OTP adapter interface (SMS or WhatsApp), **disabled by default** behind a setting, so phone OTP can be switched on later without code changes. Use mock adapters until credentials are supplied.
- **Content:** site-managed content in `web_*` tables, edited through a small admin (Section 11). Blog and resources as rich text in the database, or MDX if Phase 0 recommends it.
- **Language:** English only. No Hindi version is planned, so no i18n framework is needed. Keep copy in organised constants or the admin, not scattered inline. Search must still understand Hinglish queries (Section 6.4).
- **Bot protection:** Cloudflare Turnstile on the sign-up gate and forms. Rate limiting on email-code, chat and form endpoints.
- **Analytics:** GA4, Meta Pixel plus **Meta Conversions API** (server-side), and optionally Microsoft Clarity, all behind a cookie-consent manager.
- **Quality:** Vitest, Playwright, axe accessibility checks, Lighthouse CI, ESLint and Prettier, and CI on every push.
- **Observability:** Sentry, structured logs, and `/api/health` (the future oversight system will poll it).

---

## 3A. System architecture

Design the system to the standard of a top-tier consumer product. In Phase 0, produce `docs/ARCHITECTURE.md` with a Mermaid diagram of every component and data flow below, then build to it.

### Principles
- **Static-first, dynamic where it matters.** Pages are server-rendered and cached at the edge; only the finder results, Witty, forms and the account are dynamic islands.
- **Co-locate compute with data.** Run Vercel serverless functions in the **Mumbai region (`bom1`)**, next to the Supabase project, so every database round trip is a few milliseconds. Static assets are served from the global edge.
- **Deterministic logic in typed, tested layers.** Business rules (search ranking, eligibility, facets, attribution, consent) live in pure TypeScript modules or Postgres functions with tests, never scattered across components.
- **Never lose a lead.** Lead creation is synchronous and confirmed; every side effect after it is asynchronous, retried, and idempotent.
- **Graceful degradation everywhere.** Every dependency (AI, email, search, analytics) has a defined fallback, and the student is never shown a dead end.

### Read path (finder and panels)
- Catalogue data → a denormalised **search read model** (e.g. a materialised view `web_offering_search` joining offerings, taxonomy, universities and approvals, with a weighted `tsvector`, trigram columns and pre-computed facet fields).
- The read model refreshes (`REFRESH MATERIALIZED VIEW CONCURRENTLY`) when catalogue data changes, via a trigger that enqueues a refresh plus page revalidation, never on the request path.
- One Postgres function per query returns **results and facet counts in a single round trip**, called server-side only.
- Identical normalised queries are cached briefly at the edge (`s-maxage` with `stale-while-revalidate`). Popular queries are pre-warmed.
- Target: p95 search under 150 ms end to end (Section 6.4), measured in production.

### Write path (gate, forms, account)
- All writes go through server actions or route handlers. The browser never holds a service key; the anon key is used only for RLS-protected public reads, if at all.
- Every submit carries an **idempotency key**, so retries and double-taps never create duplicate leads or form steps.
- Leads are written via `lead_intake()` in the request. Side effects (confirmation email, Meta Conversions API event, revalidation, notifications) are written to a **transactional outbox** table (`web_outbox`) in the same transaction and processed by a worker (`pg_cron` or a queue consumer) with retries, backoff, and a dead-letter state visible in the admin.

### Witty (`web_advisor`) path
- A streaming route on the Node runtime in `bom1`, using the shared agent core (Section 7.3), loaded by version and cached in memory.
- Tool calls go to read-only Postgres functions over the same search read model, so Witty and the finder always agree.
- Conversation state lives in the shared messages table plus a `web_advisor_sessions` table (session, lead, agent-core version, token usage).
- Prompt caching, a per-session token budget, and a per-turn timeout. A **circuit breaker** switches the hero to the guided finder and application form if the AI provider is degraded, and switches back automatically.
- Metrics: time to first token, full-response time, tool-call latency, tokens and cost per conversation, and handoff rate.

### Cross-cutting
- **Fast key-value store** (Upstash Redis or Vercel KV; decide in Phase 0) for rate limits, email-code attempt counters, and hot search caching.
- **Feature flags and settings** in `web_settings`, cached at the edge with a short TTL, changeable from the admin without a redeploy.
- **Observability:** a request ID propagated through every layer, Sentry tracing across server actions, the agent route and the outbox worker, and dashboards for search latency, agent latency, error rates and the lead funnel.
- **Load targets:** 10,000+ offerings, 1,000 concurrent visitors during ad spikes, and 200 concurrent Witty conversations, verified by load tests in Phase 12.

---

## 4. Information architecture

| Route | Purpose |
|---|---|
| `/` | Home, with the AI advisor hero |
| `/programmes` | **Programme finder** (search, facets, results). This is the only place programmes are shown; there is **no separate page per programme**. |
| `/programmes?…&offering=<id>` | Deep link that opens one offering's **detail panel** (with the built-in application form) over the finder. Shareable. See Section 6.6. |
| `/programmes/[curated-view]` e.g. `/programmes/online-mba` | Optional **curated finder views**: the same finder with filters pre-applied plus a short admin-written intro and FAQs. Only created deliberately in the admin for high-demand searches; not auto-generated per programme. |
| `/universities` and `/universities/[slug]` | University directory and profile: approvals, NAAC, NIRF, all programmes offered |
| `/compare` | Compare up to 4 offerings (state lives in the URL) |
| `/witty` | Full-screen chat with **Witty** (the website AI advisor; internal code name `web_advisor`), the same agent as the hero |
| `/account` | Student account: shortlist, saved comparisons, chat history, profile, consent and opt-out |
| `/about`, `/contact`, `/how-it-works` | Migrated and improved content |
| `/resources` and `/resources/[slug]` | Blog and guides (e.g. "Is an online MBA valid for government jobs?") |
| `/c/[creator-handle]` | Co-branded creator landing page (Section 9.3) |
| `/legal/*` | The six legal pages, **same URLs as today** |
| `/thank-you`, `/404`, `/500`, `/sitemap.xml`, `/robots.txt` | Housekeeping |

Final slug patterns are decided in Phase 0. They must be stable, readable, lowercase, hyphenated, and unique.

---

## 5. Programme catalogue and taxonomy

The finder can only be "logically flawless" if the data is.

### 5.1 Phase 0 investigation
Inspect every `catalog_*` table: columns, row counts, how programmes, specialisations, universities, fees, durations, eligibility and approvals are stored, how duplicates and naming variants appear, and how Witty and the CRMs read it. Report data-quality issues with examples.

### 5.2 The model the website needs

**Level** (Certificate · Diploma · UG · PG Diploma · PG · Doctorate if offered)
→ **Programme** (canonical: MBA, MCA, BBA, BCA, B.Com, M.Com, BA, MA, and so on)
→ **Specialisation** (canonical: Marketing, HR, Finance, Data Science, …, or "General")
→ **Offering** (one university × programme × specialisation, with fees, duration, mode, eligibility, intakes, approvals)

- Each **university** carries approvals (UGC-DEB entitlement and validity), NAAC grade, NIRF rank, AICTE where relevant, state, type, logo, and a short description.
- **Synonyms and aliases:**
  - "Master of Business Administration", "M.B.A.", "MBA (Online)" → MBA
  - "HR", "HRM", "Human Resources" → Human Resource Management
  - common Hinglish and misspellings ("mba online karna hai", "bcom", "b com")
- **Category groupings** for browsing: Management, Computer Applications & IT, Commerce, Arts & Humanities, Science, and so on.
- **Career outcome tags** and **goal tags** (career switch, promotion, government job eligibility, higher studies) for guided discovery. These must be editable data, not code.

### 5.3 Where the taxonomy lives
Propose this in Phase 0 (record the shared option in `APPROVALS_NEEDED.md`). The preferred end state is a **shared, versioned taxonomy layer** that Witty and the CRMs can also use: canonical programme, specialisation and synonym mapping tables linked to existing catalogue rows. One taxonomy for all products avoids the website and Witty describing programmes differently.

**For the build, use `web_` taxonomy tables keyed to catalogue IDs** plus an admin mapping tool, designed so they can be promoted to the shared layer later with a straightforward migration once approved.

Build an **unmapped-rows report** and admin tool so every new catalogue row gets mapped. Unmapped offerings are hidden from the finder, but never silently lost.

---

## 6. Programme finder (`/programmes`)

### 6.1 Entry points (all lead to the same results state)
1. **Search box**, with instant suggestions grouped as Programmes · Specialisations · Universities · Guides. Keyboard navigable.
2. **Guided finder:**
   - "I have completed…" (10th / 12th / Graduation / Post-graduation / Diploma)
   - then "I want to…" (goal tags)
   - then optional budget and duration
   - Each answer narrows results live. Clear back and edit at every step.
3. **Browse:** by level, category, or university.
4. **Witty (AI advisor):** "Not sure? Ask Witty" is always visible.

### 6.2 Results presentation (the core decision)
- **Group results by Programme + Specialisation**, not as flat offering rows. Each group card shows:
  - name and level
  - how many universities offer it
  - fee range and duration range
  - best NAAC grade available
  - an "Easy EMI available" badge
  - top 3 university logos
- Expand a group to see **offerings** (one row per university) with: the **full fee** (total, plus per semester or year where available) with an "Easy EMI available" note, duration, NAAC, NIRF, approvals, intakes, eligibility match, shortlist and compare buttons.
- A toggle switches to a flat "All offerings" view for power users.
- **Eligibility awareness:** if the guided finder or profile knows the user's qualification, mark offerings Eligible / Check eligibility / Not eligible, and hide Not eligible by default with a toggle.

### 6.3 Facets
- Level, Category, Programme, Specialisation, University
- Total fee range (slider plus presets)
- Duration, Mode (Online / ODL)
- NAAC grade, NIRF ranked, approvals
- Eligibility (minimum qualification, minimum %, work experience required)
- Entrance exam required (Yes / No), Intake (month), University state

**Facet rules:**
- Counts update live.
- Zero-count options are **disabled, not hidden**, so users understand why.
- Facets are hierarchy-aware: choosing a programme narrows the specialisation options.
- Applied filters show as removable chips, with "Clear all."
- Mobile uses a bottom-sheet filter panel with sticky Apply and a live result count.

### 6.4 Search behaviour
- Typo tolerance, synonyms, prefix matching, and relevance ranking: exact programme or specialisation match > university match > description match. Popularity is a tie-breaker.
- Natural-language parsing for common patterns ("mba in marketing under 2 lakh", "bca online for working professionals") into structured filters, done with deterministic parsing first and no LLM call needed.
- Sorting: Relevance, Fee (low to high, high to low), NAAC grade, Duration, Popularity.
- **URL is the state:** every query, filter and sort is in the URL, so searches can be shared, back and forward work, and important combinations are indexable (Section 13).
- **Zero results never dead-end:** show the closest matches, which filter to relax, and an "Ask Witty" prompt with the query pre-filled.
- Pagination or infinite scroll with a "load more" fallback, and scroll restored on back navigation.
- Search must respond in **under 150 ms at p95** for 10,000 offerings.

### 6.5 Compare and shortlist
- Compare up to 4 offerings: fees, duration, approvals, NAAC, NIRF, eligibility, intakes, EMI, exam requirement, and key highlights. Differences are highlighted, rows can be hidden when identical, and the comparison can be shared via URL.
- **Shortlist:** works anonymously in local storage, and syncs to the account after sign-up.
- Both offer "Discuss with Witty" (passes context into the chat) and "Talk to a counsellor."

### 6.6 Offering detail panel (no separate programme pages)
**Owner decision:** there is no standalone page per programme, because the catalogue does not hold enough information for each one. Instead, every offering in the finder opens a **detail panel**: a right-side drawer on desktop, a full-screen sheet on mobile, deep-linkable via `?offering=<id>` and closable back to the same results and scroll position.

- **What the panel shows: only what the catalogue actually has**, laid out so missing fields simply don't appear (no empty headings, no "N/A" walls):
  - programme, specialisation, level, university (with logo if permitted)
  - **full fee** (total, plus per semester or year where available) with "Easy EMI available"
  - duration, mode, intakes, eligibility, entrance exam requirement
  - university approvals, NAAC grade, NIRF rank, with short plain-language explanations ("What UGC-DEB entitlement means")
  - "Data last verified: DD MMM YYYY" and the fee disclaimer
  - other universities offering the same programme and specialisation (switches the panel), and shortlist and compare buttons
- **The detailed, built-in application/enquiry form** (Section 9.1A) sits inside the panel, below the summary, with a sticky "Apply now" button that scrolls to it. There is also an "Ask Witty about this programme" button that opens the chat with this offering as context.
- Programme groups (Programme + Specialisation) also have a lighter panel showing the universities offering it, the fee and duration ranges, and the same form with a university picker.
- **Curated finder views** (`/programmes/[curated-view]`): created in the admin only where there is real search demand. Each is the finder with filters pre-applied, plus an admin-written intro and FAQs, so it is a genuinely useful landing page without needing per-programme data.
- **University pages** (`/universities/[slug]`) stay, because they need only university-level facts (approvals, NAAC, NIRF, about text). They list that university's offerings in the finder's results format, each opening the same detail panel. If university-level data is also too thin, report it in Phase 0 and propose dropping these pages too.

---

## 7. AI advisor (homepage hero and `/witty`)

### 7.0 Naming (owner decision)
- **Public name: Witty.** To students, the website agent *is* Witty: the same name and the same personality, tone and greeting style as Witty on WhatsApp. Every user-facing string (buttons, headings, chat header, page titles, emails, consent text, analytics event *labels* shown in reports) says **Witty**, never "AI advisor" or "chatbot".
- **Internal code name: `web_advisor`.** Use it in code, folder and module names, database identifiers (e.g. the agent/channel identifier on the shared messages table), env vars, feature flags (`web_advisor_enabled`), logs and docs, so the website agent is never confused with the WhatsApp agent.
- **In this spec**, "Witty" on its own means the existing **WhatsApp agent** (whose internal name stays Witty), and "AI advisor" / "advisor" means **this website agent**. Both share one agent core (Section 7.3); only the channel differs.
- The public URL is `/witty`. Never expose `web_advisor` in the UI, URLs, page source text, or messages to students.

### 7.1 Purpose
It performs **the same function as Witty**, through the website's own interface instead of WhatsApp:
- understand the student's background, goals, budget and constraints
- **ask all necessary questions before suggesting programmes** (no premature suggestions)
- match them to the most suitable programmes from the catalogue
- answer course, career and job questions honestly from catalogue data
- collect a data-rich, sales-ready lead profile
- classify the lead (HOT / WARM / COLD) per Witty's contract

### 7.2 Access gate (before the first message)
**Owner decisions:** no phone OTP at launch; email verification is required.

- Collect **full name**, **phone**, and **email**, plus a **consent checkbox**.
  - Reuse the current site's consent text, updated to mention AI chat storage and partner sharing.
  - Consent text is versioned and the accepted version is stored.
- **Phone:** +91 default, Indian mobile validation (10 digits starting 6–9), normalised to E.164. **Not OTP-verified.** Mark it unverified on the lead if the schema supports a flag; otherwise propose the approved way in Phase 0.
- **Email verification:**
  - A 6-digit code is sent to the email and entered **inline in the gate**, so the user never has to leave the page.
  - 10-minute expiry, a maximum of 5 attempts, resend allowed after 30 seconds, and a "change email" link.
  - Show a clear "check your spam folder" hint.
- **The chat starts, and the lead is created, only once the email is verified.** The lead goes via `lead_intake()` with:
  - `source = website_agent` (exact value per the existing contract)
  - UTM parameters, landing page, referrer
  - any **creator/referral code** (Section 9.3)
  - consent version and timestamp, and the email-verified flag
- **Drop-offs** (gate submitted but email never verified) are recorded in `web_gate_attempts` for funnel analytics. A setting `push_unverified_gate_leads` (default **off**) can later push them to `lead_intake()` flagged as unverified after N minutes.
- **Phone OTP later:** a setting `require_phone_otp` (default **off**) adds a phone OTP step using the disabled phone adapter, with no code changes.
- The flow should be fast:
  - the hero shows the agent's greeting and suggested starter questions before sign-up, which teases value
  - the gate opens on first interaction
  - one compact form (name, phone, email, consent), then the code step
- **Existing user:** if the email or phone already exists in `student_leads`, don't create a duplicate. Follow the existing duplicate handling in `lead_intake()`, link the session, and restore chat history.
- **Session persistence:** verified users stay signed in via Supabase Auth's email OTP session. Returning users can sign back in with an email code and resume their conversation.
- **Abuse protection** is stronger because there's no phone OTP:
  - Cloudflare Turnstile
  - rate limits per IP, device and email
  - a disposable-email blocklist
  - a honeypot field
  - a block list
  - a junk-risk score on each gate attempt (e.g. repeated digits, mismatched patterns), passed to the lead as a field if supported

### 7.3 Same brain as Witty
If true sharing needs changes to Witty or n8n, implement the shared core on the website side in a form Witty can adopt (e.g. a versioned shared table or package), keep behaviour identical to Witty's current contract, and put the Witty-side changes in `APPROVALS_NEEDED.md`. Never invent different reasoning, questions or classification rules.

- In Phase 0, find out how Witty's agent is built today: the system prompt(s), tools, qualification fields, conversation phases, HOT/WARM/COLD rules, and JSON output contract (in the n8n workflow and Supabase). Witty is being rebuilt as a multi-agent system (Witty 2.0); check its current state.
- **Do not copy Witty's prompts into this repo as a fork.** Propose an architecture where the agent core (prompts, tools, schemas, classification rules, versions) is **shared and channel-agnostic**, and the website is a **web channel adapter**. For example:
  - prompts and config in a versioned shared table read by both channels, or
  - a shared agent service or package
  - with channel-specific formatting rules (web can render cards; WhatsApp is text only).
- Tools the agent uses (all read-only, grounded in the catalogue):
  - `search_programmes`
  - `get_offering_details`
  - `compare_offerings`
  - `check_eligibility`
  - `get_university_details`
  - `save_lead_fields`, which updates the lead via the approved path
- **No hallucination:** facts about programmes come only from tool results. The agent says "I'll have a counsellor confirm that" when data is missing.
- Response speed: stream tokens. Target time to first token under 1.5 s. Use prompt caching and keep token cost per conversation low.
- **Feature flag (`web_advisor_enabled`):** the advisor can be switched off without a redeploy. When off, the hero becomes the guided finder plus "Get free counselling." The site must be able to launch before Witty 2.0 is ready.

### 7.4 Web chat interface
- **Hero version:** a large, beautiful chat surface as the main homepage banner, with a headline, the agent greeting, and 3–4 starter chips ("Find an online MBA under ₹2L", "Which degree after 12th?", "Is online BCA valid for jobs?").
- Mobile: tapping opens a **full-screen** chat.
- Messages: streaming text with markdown, **rich components** (programme cards with shortlist and compare buttons, comparison tables, fee breakdowns, eligibility checklist), quick-reply chips, and a typing indicator.
- Actions inside the chat: shortlist, compare, open the offering's detail panel (with its application form), **"Talk to a counsellor"** (WhatsApp click-to-chat or callback request), **"Book a callback"** (time-slot picker that writes to the lead via the approved path).
- Conversation history in the account. Restart conversation option. A feedback thumbs up/down per answer, stored for agent improvement.
- Accessibility: screen-reader live regions, keyboard operable, reduced-motion support.
- Edge cases: network loss (retry and queue), long responses, an off-topic or abusive user (polite boundary), a user requesting deletion (route to the opt-out flow).

### 7.5 Storage
- Every message (user and agent), with `channel = web`, session ID, lead ID, timestamps, tool calls and results (as the existing schema allows), goes to the **shared messages table** in its existing format. Any new column is added only in dev and listed in `APPROVALS_NEEDED.md`.
- Lead fields collected during the chat update `student_leads` through the approved function, the same way Witty does.
- Follow-ups after the chat are handled by the CRMs (the B2C CRM follows up after 18 hours). The website does **no** routing, allocation, or nurture.

---

## 8. Homepage

Order (final arrangement in the design phase):
1. **Hero: Witty, the AI advisor** (Section 7.4) with a trust line ("29 universities · 715+ programmes · 100% UGC-DEB entitled", with numbers pulled live from the catalogue).
2. **Quick programme search** plus level chips (UG / PG / Diploma) and popular searches.
3. **Popular programmes** carousel (data-driven).
4. **Partner universities** strip with logos (only with permission; see Section 14), linking to university pages.
5. **How it works:** Explore → Get matched → Apply with support.
6. **Why Eduwit:** reuse the existing "bridge between students and universities" copy and the three services; emphasise trust, transparency and consent.
7. **Student stories:** the existing testimonials, managed in the admin.
8. **Guided finder teaser**, for users who prefer not to chat.
9. **Resources** (latest guides).
10. **FAQ** (with FAQPage schema).
11. **Final CTA:** Ask Witty / Get free counselling, plus contact details.
12. **Footer:** contact, GST number, address, legal links, social links, sitemap links (top programmes and universities).

The persistent header holds the logo, Programmes, Universities, Compare (with a count badge), Resources, About, Contact, an "Ask Witty" button, and Account. On mobile: a compact header plus a bottom action bar (Search · Ask Witty · Shortlist · Call).

---

## 9. Forms, lead capture and integrations

### 9.1A Built-in application/enquiry form for every programme (owner requirement)
**Every programme in the finder has a detailed application/enquiry form built in**, inside its detail panel (Section 6.6). It is a pre-application: Eduwit collects the student's details and a counsellor completes the actual university application. The form never takes payments.

- **Context-aware and pre-filled:**
  - From an **offering's detail panel**, the programme, specialisation and university are pre-selected and shown as a summary card (with the full fee and "Easy EMI available").
  - From a **programme group panel**, the student picks one or more preferred universities from those offering it (or "Help me choose").
  - From a **university page**, the student picks the programme and specialisation from that university's list.
  - From **compare** or the **AI advisor**, the compared or recommended offering is pre-selected.
  - All options come live from the catalogue, through the same taxonomy as the finder.
- **Multi-step, so the long form doesn't hurt conversion.** A progress bar shows steps; each step validates before moving on:
  1. **Contact:** full name, phone (+91, validated, not OTP-verified), email, consent checkbox. Email is then **verified by a 6-digit code inline**, using the same flow as the advisor gate (Section 7.2). **The lead is created via `lead_intake()` as soon as the email is verified**, so a drop-off after step 1 is still a captured lead.
  2. **Academic background:** highest qualification, stream or subject, percentage or CGPA, year of passing (or "currently studying"), board or university.
  3. **Work and goals:** currently working (yes/no), years of experience, current role and industry (optional), career goal (goal tags), why this programme (optional).
  4. **Preferences:** preferred intake (from the offering's intakes), budget range, interested in EMI (yes/no), preferred university(ies) if not pre-selected, city and state, preferred contact mode (call / WhatsApp / email) and best time to call, any questions.
  5. **Review and submit:** summary of everything entered, with edit links. Submit marks the lead as an **application request** for that programme.
- Steps 2–4 **enrich the same lead** through the approved update path. Each step saves on "Next", so partial progress is never lost.
- **Map every field to the same qualification fields Witty collects** (exact column names decided in Phase 0), so a form lead is as sales-ready as a Witty lead. Fields with no existing column are added in dev only and listed in `APPROVALS_NEEDED.md` (or stored in a `web_` table keyed to the lead until approved), never invented silently.
- **Eligibility check while filling:** compare the academic answers with the offering's eligibility from the catalogue and show a friendly note ("You meet the eligibility" / "A counsellor will confirm your eligibility"). Never block submission.
- **Signed-in users** (already verified through the advisor or an earlier form) skip email verification, and known fields are pre-filled.
- **Submission state:** a thank-you panel with what happens next, an application reference number, "Talk to a counsellor" (WhatsApp), and "Explore similar programmes". A confirmation email goes to the student.
- **Document upload:** not in v1. Build it behind a setting (default **off**), because documents are sensitive data.
- The form, its options, and field order are configurable in the admin (show/hide or make optional any non-core field), but the core contact step and consent stay locked.
- Mobile-first: one question group per screen, large touch targets, native input types, autofill hints, and the sticky step progress bar.
- Analytics: `form_view`, `form_step_complete` (step number), `form_submit`, plus `lead_created` and the Meta Conversions API `Lead` event on email verification, and a separate `SubmitApplication` event on final submit.

### 9.1 Other counselling and enquiry forms
- A shorter enquiry form appears on Contact and as a modal elsewhere. Fields: name, phone (validated, not OTP-verified), email (verified by code, same flow as the advisor gate), programme of interest (pre-filled from context), message, consent.
- Leads go via `lead_intake()` with the source and page context. Show a thank-you state with next steps.

### 9.2 Attribution
Capture and persist (first-party cookie or local storage, respecting consent) UTM parameters, gclid, fbclid, referrer, landing page, and creator code. Attach them to every lead created on the site.

### 9.3 Influencer Portal integration
- `/c/[creator-handle]?code=…` pages render a co-branded landing page ("Recommended by …") using the Influencer Portal's **public read-only API** (creator display name, photo, featured programmes, code).
- If that API isn't live yet, build against a typed interface with a mock, and log it in `DECISIONS.md`.
- The `code` parameter persists and is attached to the lead for attribution. Creator codes never gate access.

### 9.4 Other products
- Expose `/api/health` and a metrics summary endpoint for the oversight system.
- Fire server-side conversion events (Section 13.3) when a verified lead is created.

---

## 10. Design direction

**Owner direction: the website must look like something from the future.** Not a template, not "another edtech site". The bar is the most forward-looking product sites of 2026 (AI labs, next-generation fintech, spatial-computing product pages), applied to education, while staying fast on a mid-range Android phone and trustworthy to a first-generation online learner and their parents.

Load the `frontend-design` skill (if available) before Phase 1. Phase 1 produces the design system and **two distinct futuristic concepts** for the homepage hero, the finder, the detail panel and the Witty chat, rendered as real pages with seed data and recorded as short screen captures. **Choose the stronger concept yourself** against the principles in 10.1, the guardrails in 10.4 and the Lighthouse scores, explain the choice in `DECISIONS.md`, and keep the other concept preserved (its theme stays selectable and its pages are kept on a `concept-b` branch) so the owner can swap at the end review.

### 10.1 Design principles
1. **AI-native, not AI-decorated.** Witty is the centre of the experience, not a chat bubble in a corner. The interface feels like talking to a living system that understands you.
2. **Spatial and luminous.** Depth, light and layering replace flat boxes: surfaces float, light reacts, content has a z-axis.
3. **Calm power.** Motion is fluid and physical but never noisy. Everything settles into stillness so reading and deciding are easy.
4. **Data as delight.** Fees, approvals and comparisons are presented as beautiful, instantly legible visual objects, not tables of text.
5. **Futuristic but credible.** Trust signals (UGC-DEB, NAAC, "last verified" dates, real contact details) are crisp and prominent. Nothing feels like a gimmick or a scam.

### 10.2 Visual language
- **Brand:** keep the current Eduwit logo unchanged (https://horizons-cdn.hostinger.com/0dd7d01a-e246-4b29-9e01-202d498bb010/1d0763850c8c7b80249b070da984caec.jpg). Infer the palette from it, then extend it into a futuristic system: a deep base, luminous brand-derived accents, gradient ramps for light effects, and contrast-checked text colours. If no vector logo is in the repo, produce a clean SVG trace of the current logo in Phase 1, use it, and add "confirm logo trace or supply vector file" to `SETUP_CHECKLIST.md`.
- **Theme:** design both a **dark "luminous" theme** and a **light "daylight" theme** as first-class. Concept A should lead with dark, Concept B with light; the owner picks the default, and the other stays available via a toggle and `prefers-color-scheme`.
- **Typography:** a striking variable display face with optical sizing (kinetic headline reveals, weight shifts on interaction) paired with a highly legible body face. Large, confident type scale; tight, precise numerals for fees (tabular figures).
- **Surfaces:** layered translucent panels with real depth (backdrop blur, fine noise grain, soft inner light, hairline luminous borders), used with discipline so text always sits on sufficient contrast.
- **Light and atmosphere:** a living aurora / gradient-field background in the hero, rendered with a lightweight WebGL fragment shader (Section 10.4 guardrails), subtly reacting to scroll, pointer and Witty's activity.
- **Layout:** bento-style grids, generous negative space, asymmetric compositions, sticky contextual elements.
- **Iconography and illustration:** custom line icons with consistent stroke and subtle glow states; abstract 3D-feel illustrations or renders (licensed or generated, never scraped). Photography of real Indian learners and working professionals, colour-graded to match the palette.

### 10.3 Signature experiences (build all of these)
- **The Witty presence:** an animated orb / light-form that *is* Witty's visual identity. It breathes at rest, ripples while the student types, pulses with streaming tokens, and morphs into a compact chat-head on scroll. Built with SVG/canvas or a small shader; tiny and GPU-cheap.
- **Generative UI in chat:** Witty's answers render as live components (programme cards that assemble in, fee bars that fill, eligibility checks that tick, comparison grids that build column by column), not walls of text.
- **Instant command search:** the search box behaves like a command palette (⌘K / tap): results stream in per keystroke, grouped and keyboard navigable, with matched text highlighted.
- **Fluid finder:** filtering uses layout animations (cards reflow and morph via shared-element transitions), facet counts tick like odometers, the fee slider shows a live distribution histogram, and opening an offering uses the **View Transitions API** so its card expands seamlessly into the detail panel.
- **Visual comparison:** compare view shows offerings as aligned luminous columns, with differences highlighted by light, plus small visual meters for fee, duration and NAAC.
- **Scroll storytelling:** "How it works" and "Why Eduwit" use scroll-driven animations (CSS scroll timelines where supported) for a cinematic, step-by-step reveal.
- **Live trust layer:** the trust line ("29 universities · 715+ programmes · 100% UGC-DEB entitled") counts up from live catalogue numbers; approval badges have a subtle verified shimmer.
- **Micro-interactions everywhere:** magnetic primary buttons on desktop, pointer-reactive glow on cards, satisfying press states and haptic-style feedback on mobile (the Vibration API, used lightly and only after interaction), skeletons that shimmer in brand light.
- **The application form** (Section 9.1A) feels like a guided conversation: one question group at a time, smooth step transitions, a luminous progress track, and celebratory confirmation on submit.

### 10.4 Futuristic, but fast and accessible (hard guardrails)
- **Progressive enhancement:** every screen works and looks premium as static HTML/CSS. Shaders, 3D and heavy motion are enhancements layered on top.
- **Capability tiers:** detect `prefers-reduced-motion`, `Save-Data`, `navigator.deviceMemory`, `hardwareConcurrency`, battery saver and WebGL support. Low-tier devices get a static gradient poster and CSS-only motion; high-tier devices get the full experience. Document the tier rules.
- **Never block content:** the LCP element is real text, never a canvas. Shaders load after first paint, run at reduced resolution, pause when off-screen or the tab is hidden, and cap frame rate.
- **Budgets:** hero shader plus Witty orb under 30 KB gzipped combined; no Three.js-scale libraries on the critical path (a minimal WebGL helper such as OGL, or hand-written shaders). Core Web Vitals targets in Section 13.2 still apply.
- **Accessibility:** WCAG 2.1 AA contrast on every translucent surface (test on real backgrounds), visible focus rings styled as part of the design, full keyboard support, and reduced-motion equivalents for every animation.
- **No gimmicks that cost trust:** no autoplaying sound, no scroll-jacking, no fake counters, no fake urgency.

### 10.5 Design system deliverables
- Tokens for colour (both themes), type, spacing, radius, elevation/depth, blur, glow, motion (durations, easings, spring presets) and z-layers.
- A component library covering every UI element in this spec, each with all states.
- A living style guide at `/styleguide` (not indexed) including a **motion gallery** showing each animation and its reduced-motion fallback.
- **Mobile-first:** most traffic comes from Android phones via Meta and Instagram. Design for 360–414 px first; the futuristic feel must be fully present on mobile, not a desktop-only effect.

---

## 11. Admin (`/admin`, staff only)

- Auth: Supabase Auth with Google or email, plus **email-code 2FA required even after Google sign-in** (matches the CRM). Roles: Super Admin, Content Editor, Viewer.
- **Manage:**
  - testimonials, FAQs (global and per page), homepage sections and banners
  - popular searches, resources and blog posts, curated finder views (filters, intro, FAQs) and editorial content for university pages
  - SEO overrides (title, description, OG image), redirects
  - announcement bar, feature flags (AI advisor on or off, sections on or off)
  - consent text versions
- **Taxonomy mapping tool** (Section 5.3): unmapped catalogue rows, mapping to canonical programme and specialisation, synonym management.
- **Data quality dashboard:** offerings missing fees, stale "last verified" dates, missing approvals, unmapped rows.
- **Advisor insights (read-only):** conversation counts, gate conversion funnel (hero view → gate open → gate submitted → email code sent → email verified → first message → qualified), plus the same funnel for the built-in application forms (panel opened → form started → each step → submitted), top questions, thumbs-down answers. No editing of agent prompts here; that belongs to the shared agent core.
- Revalidate pages on publish. Audit log for every admin change.
- **Programme data itself is not edited here.** It is managed in the shared catalogue.

---

## 12. Accounts

- Students sign in with an email verification code (the same identity as the advisor gate).
- Account pages: profile, shortlist, saved comparisons, chat history, consent status, **data opt-out and deletion request** (links to the existing Data Privacy / Opt-out process).

---

## 13. SEO, performance and analytics

### 13.1 SEO
- Unique titles, descriptions and H1s for every page type, generated from templates with admin overrides.
- Structured data:
  - `EducationalOrganization` (Eduwit and each university)
  - `ItemList` of `Course` entries on curated finder views and university pages (offerings appear in lists, not on pages of their own)
  - `BreadcrumbList`, `FAQPage`, `Organization`
  - `WebSite` with `SearchAction`
- Offering detail-panel deep links (`?offering=`) are `noindex` and canonicalise to the finder view they belong to, since they are not standalone pages.
- A **sitemap index** split by type (curated finder views, universities, resources, pages). `robots.txt`, canonical URLs, OG and Twitter images (auto-generated per page with `next/og`).
- Indexable filter combinations: only the curated finder views created in the admin, with canonical rules for everything else. **No index bloat from arbitrary facet URLs.**
- **Migration:** inventory every old URL (crawl plus Hostinger sitemap), build a **301 redirect map**, keep `/about` and `/legal/*` paths identical, and test redirects in CI.
- Internal linking: curated finder views, university pages, resources linking to relevant finder views, breadcrumbs, and footer hubs.

### 13.2 Performance budgets (mobile, 4G, mid-range Android)
- LCP < 2.5 s, INP < 200 ms, CLS < 0.1 on the homepage, finder (including opening a detail panel), and university pages.
- The hero renders as static server HTML first; the chat bundle loads after interaction or when idle.
- JavaScript budget per route documented and enforced in CI with Lighthouse CI.

### 13.3 Analytics
- A cookie-consent manager (honouring the existing Cookie Policy) gates GA4, Meta Pixel and Clarity.
- Events (no PII):
  - `search`, `filter_apply`, `programme_view`, `offering_view`, `compare_add`, `shortlist_add`
  - `advisor_gate_open`, `gate_submitted`, `email_code_sent`, `email_verified`, `advisor_message`
  - `lead_created`, `counsellor_click`, `callback_booked`
- **Meta Conversions API:** send `Lead` server-side on verified lead creation, with hashed identifiers per Meta's spec, deduplicated with the Pixel via event ID. Purpose: Meta campaigns optimise on verified leads. Respect consent.

---

### 13.4 SEO toolkit (built into the admin)
Technical SEO (13.1) is the foundation. Ranking also needs ongoing content and monitoring, so build the tools for that into the admin, so Eduwit runs its whole SEO operation from one place.

- **Google Search Console integration:** connect via OAuth (service account or owner login; credentials go in `SETUP_CHECKLIST.md`). Pull queries, impressions, clicks, CTR and average position daily into `web_seo_*` tables. Dashboard: trends, top queries, top pages, rising and falling pages, and pages with impressions but low CTR (title/description fix candidates). Also show index coverage and Core Web Vitals status where the API exposes them.
- **Opportunity finder:** surfaces queries Eduwit already gets impressions for (or that match the taxonomy, e.g. "online MBA for working professionals", "online BCA fees") but has **no dedicated landing page** for. One click creates a draft **curated finder view** (pre-applied filters, suggested title, intro and FAQs) for review. Also suggests resource articles for question-style queries ("is online degree valid for government jobs").
- **Keyword list:** owner-managed target keywords with priority, mapped to a landing page (curated view, university page, resource or home), with position tracking from Search Console data. Flags keyword cannibalisation (two pages targeting the same keyword).
- **Content planner:** pipeline of Idea → Brief → Draft → Review → Published → Refresh due.
  - Claude assists with briefs (search intent, outline, questions to answer, internal links) and first drafts, grounded only in catalogue facts and approved claims.
  - **Every piece needs a named human author and reviewer before publishing** (e.g. a counsellor byline with a short bio), for credibility and Google's standards on education content. No mass-generated pages.
  - "Refresh due" reminders for content older than N months or losing rankings.
- **On-page checker:** runs on every curated view, university page and resource, before publish and on a schedule. Checks title and description length and uniqueness, H1, headings structure, intro length and quality flags, FAQs present, schema validity, images with alt text, internal links in and out, broken links, and banned claims. Shows a score with fix suggestions.
- **Internal linking engine:** automatically suggests and inserts links from resources to relevant curated finder views and university pages (based on taxonomy matches), with editor approval, and keeps related-content blocks fresh.
- **Redirects and 404 monitor:** admin-managed redirects, a log of 404 hits with one-click redirect creation, and redirect-chain detection.
- **Local SEO:** `LocalBusiness` / `EducationalOrganization` schema with the Indirapuram address, phone and hours; a checklist for Google Business Profile and directory listings (manual tasks, tracked in the admin).
- **SEO checks in CI:** on every deploy, validate structured data, sitemaps, canonical and robots rules, redirect map, and Lighthouse SEO and performance budgets. Fail the build on regressions.

## 14. Compliance and trust

- **DPDP:** clear consent at the gate and on forms, purpose statement, versioned consent records, easy withdrawal and deletion requests.
- Update the **Privacy Policy** to cover AI chat storage, email verification, application form data, and analytics. Flag the text for legal review rather than finalising legal language yourself. Migrate the six legal pages verbatim first, then propose edits in a separate reviewable diff.
- **Accuracy:** approval and accreditation claims come only from catalogue data and are explained plainly. No "guaranteed job", "100% placement", or "equivalent to regular degree" claims unless the data explicitly supports a specific, sourced statement. Maintain a banned-phrase list checked in CI against site copy.
- **Fees:** show the **full fee** for every offering, with **"Easy EMI available"** alongside it, a "last verified" date, and a disclaimer ("Fees are set by universities and may change; confirm with your counsellor"). If the catalogue has an EMI amount, show "from ₹X/month"; never invent one.
- **University logos and names:** use them only when the owner confirms permission. Keep a per-university `logo_permitted` flag, with a text fallback otherwise.
- Accessibility: **WCAG 2.1 AA**.

---

## 15. Non-functional requirements

- **Security:** OWASP Top 10, strict CSP, rate limiting, Turnstile, signed cookies, no service keys in the client, and RLS on all `web_` tables with tests. Public APIs are read-only and rate-limited.
- **Reliability:** graceful degradation. If the AI or email provider fails, fall back to the counselling form and log the failure. If search fails, fall back to browse.
- **Scalability:** built for 10,000+ offerings and traffic spikes from ad campaigns. Pages are statically cached at the edge.
- **Observability:** Sentry, structured logs, an uptime check, and an `/api/health` endpoint covering the database, AI provider, email provider, and search.
- **Backups:** handled by Supabase; document the restore procedure for `web_` data.

---

## 16. Testing and acceptance

- **Unit (Vitest):** query parsing, synonym resolution, facet logic, eligibility matching, slug generation, URL state serialisation, attribution capture, consent logic.
- **Search quality suite:** at least 60 real-world queries with expected top results, including misspellings, Hinglish, synonyms and natural-language budgets ("mba hr", "bcom online", "mca kitne ka hai", "online mba under 2 lakh", "nmims mba"). Must pass at least 95%.
- **RLS tests** for `web_` tables.
- **End-to-end (Playwright):**
  1. Search, filter, open a group, compare, shortlist.
  2. Guided finder from "12th pass" through a goal to eligible results.
  3. Advisor gate: name, phone (validated), consent, email code verified, lead created via `lead_intake()` (test fixture) only after email verification, chat streams and renders programme cards. An unverified gate attempt creates no lead.
  4. Returning user resumes chat; duplicate phone does not create a duplicate lead.
  5. Creator landing page with code leads to a lead carrying the code.
  6. Built-in application form: open an offering's detail panel from the finder (and via its `?offering=` deep link); programme and university are pre-filled; step 1 with email code creates the lead; steps 2–4 enrich the same lead; drop-off after step 2 keeps the data; final submit marks it as an application request and shows the reference number. Also the short counselling form.
  7. Old URLs 301 to the new ones.
  8. Advisor feature flag off: the hero falls back correctly.
- Lighthouse CI budgets and axe accessibility checks pass on key templates.

---

## 17. Phases

| Phase | Scope |
|---|---|
| **0 — Discovery** (read-only) | Crawl eduwit.in and inventory all content and URLs. Inspect `catalog_*`, `student_leads`, `lead_intake()`, the messages table, `w2_*`, the Witty n8n workflow and prompts, and the CRM code conventions. Produce `docs/PHASE0_FINDINGS.md`, `TAXONOMY_PROPOSAL.md` (with sample mappings and a data-quality report), `SCHEMA_PLAN.md` (ERD, `web_` tables, proposed shared changes), `ARCHITECTURE.md` (full system design per Section 3A), `AGENT_ARCHITECTURE.md` (how the website shares Witty's core), `URL_REDIRECT_MAP.md`, `TECH_DECISIONS.md`, `RISKS.md`, and start `APPROVALS_NEEDED.md` and `SETUP_CHECKLIST.md`. Answer the open questions in Section 18 from the code and database; log the rest as assumptions in `DECISIONS.md`. Then continue straight to Phase 1. |
| **1 — Design system and concepts** | Tokens (both themes), typography, components, motion system and capability tiers, `/styleguide` with motion gallery, and **two futuristic concepts** (Section 10) covering the hero with the Witty presence, the finder, the detail panel and the chat, with seed data, screen recordings, and Lighthouse scores on a throttled mid-range Android profile. Choose the stronger concept, preserve the other (Section 10), and continue. |
| **2 — Foundation** | Scaffold, CI, env, Supabase local dev with the pulled schema, auth for admin, layouts, header and footer, analytics and consent framework, error pages, health endpoint. |
| **3 — Catalogue and taxonomy** | `web_` taxonomy tables and mapping (shared version queued in `APPROVALS_NEEDED.md`), the search read model (Section 3A), catalogue read views, search index (`tsvector`, trigram, synonyms), facet functions, revalidation hooks, unmapped-rows tooling. |
| **4 — Programme finder** | Search, suggestions, guided finder, facets, grouped results, URL state, sort, zero-results handling, compare, anonymous shortlist, search quality suite. |
| **5 — Detail panel and university pages** | Offering and programme-group detail panels (drawer / full-screen sheet, deep links, scroll restore), curated finder views, university pages, ISR, structured data, sticky "Apply now", and the application form UI inside the panel (with mocks; wired to leads in Phase 7). |
| **6 — Content and migration** | Home (without live AI; flag off), About, How it works, Contact, Resources, legal pages migrated verbatim, testimonials, FAQs, redirects. |
| **7 — Gate, email verification and accounts** | Email verification (phone-OTP adapter built but disabled), Turnstile and abuse controls, consent versioning, lead creation via `lead_intake()`, duplicate handling, sessions, account pages, the multi-step built-in application form (Section 9.1A) and other counselling forms, attribution and creator pages. |
| **8 — Witty on the website (`web_advisor`)** | Shared agent core integration per `AGENT_ARCHITECTURE.md`, the Witty presence (orb) and generative UI, circuit breaker, tools, streaming chat UI (hero and full-screen), rich components, message storage, callback and counsellor hand-off, feature flag, guardrails, cost and latency tuning. |
| **9 — Technical SEO and analytics** | Sitemaps, OG images, structured data, canonical and indexing rules, redirects tested in CI, GA4, Pixel, Conversions API (via the outbox), event tracking, performance pass. |
| **10 — Admin** | Content management, curated finder views, taxonomy tool, data-quality dashboard, advisor insights, outbox and dead-letter monitor, feature flags, audit log. |
| **11 — SEO toolkit** | Everything in Section 13.4: Search Console integration and dashboard, opportunity finder, keyword list and tracking, content planner with Claude-assisted briefs and drafts plus mandatory human author and review, on-page checker, internal linking engine, 404 monitor, local SEO schema and checklist, SEO checks in CI. |
| **12 — Hardening and go-live prep** | Security review, accessibility audit, full end-to-end suite, load tests (Section 3A targets), `docs/RUNBOOK.md`, DNS cut-over plan (Hostinger to Vercel) with rollback, production migration dry-run including every item in `APPROVALS_NEEDED.md`, final report. **STOP before go-live** and wait for the owner. |

---

## 18. Owner decisions and open questions

### Already decided by the owner
- **No phone OTP at launch.** Phone is validated only; the phone-OTP adapter is built but disabled (Section 7.2).
- **Email verification is required** before the chat starts and before a lead is created, using a 6-digit code entered inline.
- **Show the full fee publicly** for every offering, with **"Easy EMI available"** alongside it.
- **Keep the current logo** and infer the brand palette from it.
- The owner will provide access to Hostinger DNS, Vercel, GA4, Meta Pixel and the Conversions API token.
- **English only.** No Hindi version.
- **No separate page per programme**, because the catalogue lacks enough per-programme detail. Programmes live in the finder; each opens a detail panel (Section 6.6).
- **Every programme has a detailed, built-in application/enquiry form** inside its detail panel (Section 9.1A).
- **The website AI advisor is called "Witty" in public**, same as the WhatsApp agent. Internally it is code-named **`web_advisor`** (Section 7.0).
- **Build in one continuous run**, step by step, stopping only for go-live (Section 0).
- **SEO is built in:** technical SEO (13.1) plus a full SEO toolkit in the admin (13.4).
- **The website must look like something from the future** and use the best system design and logic (Sections 10 and 3A), without compromising speed, accessibility or trust.

### Still open (answer from the code and database where possible; for the rest, make a sensible assumption, log it in `DECISIONS.md` or `SETUP_CHECKLIST.md`, and keep building)
1. Exact `catalog_*` structure and how Witty and the CRMs use it. Can a shared taxonomy layer be added?
2. Exact `student_leads` columns (is there a phone-verified / email-verified flag?), the `lead_intake()` signature and duplicate logic, and the value to use for `source`.
3. The messages table name and schema, and how Witty writes to it.
4. Witty's current agent implementation (n8n, prompts, tools, output contract) and Witty 2.0's status. What is the best way to share the core?
5. Transactional email provider for verification codes (sender address, e.g. no-reply@eduwit.in, with SPF/DKIM/DMARC set up).
6. Which university logos is Eduwit permitted to use?
7. Is a vector or high-resolution logo file available?
8. WhatsApp number for "Talk to a counsellor" hand-off. Should it differ from Witty's number?
9. Has the Influencer Portal's public creator API been specified yet?

**Begin with Phase 0 now and build every phase through Phase 12 in one continuous run. Production stays read-only throughout. Stop only for go-live.**
