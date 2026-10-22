# Build progress

**Build complete (Phases 0–12). Owner approved deploying on Vercel against the production database (17 Oct 2026); DNS and eduwit.in stay untouched until a separate go-live approval — read `docs/FINAL_REPORT.md` and `docs/GO_LIVE_CHECKLIST.md`.**

## Production deployment state (17 Oct 2026)
- Production Supabase (owner's choice "Production (go-live step)"): before applying, production's shared-schema
  fingerprint was identical to `scripts/db/fingerprint.prod.txt` (42/42 rows). No `pg_dump` was possible (no database
  password in the build environment); the migrations write no shared table.
- Applied through the Supabase connector: web1–web8, web10, web12, web13, web9 split into `web9_admin` + `web9_admin_part3`
  (connector request timeouts). Read model: 715 offerings, 708 visible, 0 unmapped; jobs `web_catalog_poll`,
  `web_outbox_worker`, `web_seo_daily` scheduled.
- **Pending (owner runs in the SQL Editor; the connector cancels statements it flags as destructive):** web9's
  `web_admin_save`/`web_admin_delete` + web11 (file given to the owner, built verbatim from the migration files), and the
  Vault secret `web_internal_key`. Shared proposals s01–s07: none applied (approvals pending).
- Vercel: project `eduwit-website` (team eduwit, Hobby — Pro needed before a commercial go-live), Git-connected to this
  repo, root `website/web`, production branch `claude/inspiring-babbage-8asj1y`. Env: `APP_ENV=preview` (noindex,
  Turnstile mocked until keys exist), `NEXT_PUBLIC_SITE_URL=https://eduwit-website.vercel.app`, Supabase URL and
  publishable key; the three secrets were added by the owner. No email provider yet (verification codes not delivered).
- Deployed (19 Oct): production deployment Ready; `internal_base_url` = `"https://eduwit-website.vercel.app"`; the outbox
  worker reaches the site (HTTP 200, Vault key = Vercel key); web9 part 2 + web11 and the Vault secret applied by the owner.
  `default_theme` set to `"dark"` (Concept A is dark-first; on light-mode devices it looked like Concept B).
- Witty (22 Oct, owner: "Turn on Witty", with a Gemini key): Gemini provider added (D-083); `web_advisor_models` =
  `gemini-3.6-flash`. **Waiting for the owner** to add `GEMINI_API_KEY` and the email variables (`EMAIL_PROVIDER=smtp`,
  Gmail SMTP as connect@eduwit.in with a new app password) in Vercel and redeploy; then `web_advisor_enabled` → true
  and verify a real chat (model column = gemini, lead in the CRM).
- Legal pages (22 Oct): the five policies from the owner's documents and a Data Privacy & Opt-out page drafted for the DPDP
  Act 2023 are live (`web_legal_pages`, saved through `web_admin_save`, audited). Owner instruction: no organisation other
  than Eduwit is named (Google/Facebook/Microsoft/UGC etc. removed; the opt-out page keeps the statutory reference to the
  Data Protection Board). Open points for the owner/lawyer (S-44): Privacy Policy §5 still mentions sharing with service
  providers and advertising platforms; §8 cites the 2011 SPDI Rules rather than the DPDP Act; under-16 vs under-18
  children wording; arbitration seat Varanasi; a named Grievance Officer.

Resume rule: read this file top to bottom, then continue from the current step. Each phase has a plan, a step log and a
self-review table (Done / Partial / Deferred-with-reason). Tags: `website-phase-N-done` (D-002).

## Environment state (17 Oct 2026)
- Docker daemon started manually (`dockerd`), registry mirror `mirror.gcr.io` in `/etc/docker/daemon.json` (Docker Hub
  rate-limits this environment). Containers do not survive a new session: restart dockerd, then `npx supabase start`.
- Supabase CLI 2.121 is a dev dependency of `web/`: `npm run db:start` (from `web/`) starts the local stack from
  `website/` (API 54321, DB 54322, Mailpit 54324 UI / 54325 SMTP; `-x studio,imgproxy,edge-runtime,logflare,vector,supavisor`).
- The environment pre-sets `SUPABASE_SERVICE_ROLE_KEY`, `SMTP_*` and `ANTHROPIC_BASE_URL` for other products: the
  website reads only `SUPABASE_SECRET_KEY`, `EMAIL_SMTP_*`, `WEB_ANTHROPIC_BASE_URL` (D-027). `web/.env.local` is gitignored.
- `prod-replica` container (port 54330): production-schema replica, built by `scripts/db/build-replica.sh` (~50 s);
  **all 42 fingerprint rows match production** for public, b2b, b2c, catalog (report: `docs/discovery/replica.md`).
- Video recording: Playwright 1.64 wants ffmpeg-1013; use `PLAYWRIGHT_BROWSERS_PATH=<dir>` with
  `ffmpeg-1013/ffmpeg-linux -> /usr/bin/ffmpeg` (apt `ffmpeg` installed) — see `web/scripts/record-concepts.mjs`.
- Stopping the prod server: `fuser -k 3100/tcp` (never `pkill -f "next …"` — it matches the calling shell).
- Chromium for Playwright: `/opt/pw-browsers/chromium` (pass `executablePath`; do not run `playwright install`).
- `eduwit.in` is blocked by the environment's network policy (D-006, S-01).
- Superuser for profiling the local DB: `postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres` (auto_explain).
- Re-apply one migration without a full reset: `scripts/db/reapply.sh <file>` (drops the read model first).

---

## Phase 0 — Discovery (read-only) ✅ `website-phase-0-done`

### Plan
1. Set up `website/`, local Supabase stack, state docs.
2. Discovery tracks (parallel, read-only): production database, Witty's agent, CRM conventions, production-schema replica.
3. Crawl the current site → blocked; crawler prepared.
4. Write the Phase 0 documents; answer Section 18.
5. Gate, self-review, summary, tag.

### Step log
- 0.1 ✅ `website/` created; spec in `docs/WEBSITE_SPEC.md`; logo in `web/public/brand/`; Supabase CLI stack running;
  Next 16 dependencies installed; crawler written; state docs started. (commit 9a8a4ff)
- 0.2 ✅ Discovery reports: `docs/discovery/crm-conventions.md`, `db.md`, `witty.md`, `witty-prompts.md`; snapshots
  `supabase/prod-snapshot/{catalog,leads,messages}.sql`; catalogue export `supabase/seed/catalog_sample.json`.
- 0.3 ✅ Logo vectorised (potrace, per colour and region): `web/public/brand/eduwit-logo.svg`, `-mark.svg`,
  `-wordmark.svg`, `-logo-dark.svg` (visually checked against the original).
- 0.4 ✅ Documents: `PHASE0_FINDINGS.md`, `TAXONOMY_PROPOSAL.md`, `SCHEMA_PLAN.md`, `ARCHITECTURE.md`,
  `AGENT_ARCHITECTURE.md`, `URL_REDIRECT_MAP.md` (partial — crawl blocked), `TECH_DECISIONS.md`, `RISKS.md`,
  `APPROVALS_NEEDED.md`, `SETUP_CHECKLIST.md`, `DECISIONS.md` (D-001…D-019), `legal/consent-texts.md`.
- 0.5 ✅ Gate: no migrations or pages yet (nothing to apply/test/Lighthouse); docs complete; secrets scan clean.

### Self-review (spec Section 17, Phase 0 row, and Section 0)
| Requirement | Status | Note |
|---|---|---|
| Crawl eduwit.in; inventory every page, text block, image, URL | **Deferred (blocked)** | Network policy denies the hosts; crawler ready; S-01; go-live checklist item |
| Inspect `catalog_*` | Done | db.md §1 |
| Inspect `student_leads`, `lead_intake()` | Done | db.md §2–3, leads.sql |
| Inspect the messages table, `w2_*` | Done | db.md §4, witty.md §7 |
| Witty n8n workflow and prompts | Partial | Prompts read verbatim; workflow not readable (n8n connector down; no export) → S-02, A-AGENT-1 |
| CRM code conventions | Done | crm-conventions.md |
| `PHASE0_FINDINGS.md` | Done | |
| `TAXONOMY_PROPOSAL.md` with sample mappings and data-quality report | Done | |
| `SCHEMA_PLAN.md` (ERD, `web_` tables, proposed shared changes) | Done | |
| `ARCHITECTURE.md` (Section 3A, Mermaid) | Done | |
| `AGENT_ARCHITECTURE.md` | Done | |
| `URL_REDIRECT_MAP.md` | Partial | Known URLs only until the crawl |
| `TECH_DECISIONS.md`, `RISKS.md` | Done | |
| Start `APPROVALS_NEEDED.md`, `SETUP_CHECKLIST.md` | Done | |
| Answer Section 18 open questions; log assumptions | Done | PHASE0_FINDINGS §4; D-016…D-018 |
| Slug patterns decided (spec §4) | Done | see below |
| University pages viability (spec 6.6) | Done | keep (PHASE0_FINDINGS §3) |

### Slug patterns (spec §4)
- Universities: `/universities/<slug>` where slug = kebab-case of the common name, e.g. `amity-university`,
  `nmims`, `lovely-professional-university` (stored in `web_university_profiles.slug`, unique, editable, old slugs →
  `web_redirects`).
- Curated finder views: `/programmes/<slug>` e.g. `online-mba`, `online-mba-marketing`, `online-bca` (admin-created).
- Resources: `/resources/<slug>` from the title (unique, editable with redirect).
- Offering deep link: `/programmes?…&offering=<catalog_programs.id>` (numeric id; a replaced/renamed row resolves to the
  current offering of the same university + programme + specialisation + mode — D-030).
- Creator pages: `/c/<handle>` lower-case, `[a-z0-9-]{2,40}`.

### Phase 0 summary
Discovery done read-only. Key outcomes: website-owned student verification (shared Auth trigger risk), lead path via
`lead_intake` as `web_agent`, Witty contract package with the advisor off until verified, web transcript in
`web_advisor_messages`, taxonomy layer over a messy specialisation field. Two go-live blockers for the owner (A-B2B-1
routing setting, A-CONSENT-1 consent registration) and one environment blocker (S-01 crawl).

---

## Phase 1 — Design system and concepts

### Plan
1. App scaffold just enough to render real pages: root layout, fonts, `tokens.css` (both themes, both concepts),
   Tailwind 4 theme mapping, theme + concept switching (`data-theme`, `data-concept`), capability-tier script.
2. Brand components: SVG logo component (theme-aware), icons (Lucide + custom line icons with glow states).
3. Motion system: tokens (durations, easings, springs), `lib/motion.ts` presets, reduced-motion equivalents.
4. WebGL: tiny helper + aurora shader (Concept A) and prism-light shader (Concept B); Witty orb (SVG/canvas, breathes,
   ripples while typing, pulses with tokens); budgets < 30 KB gz combined; pause off-screen; tiers.
5. Component library (`components/ui`): Button (magnetic), IconButton, Badge (verified shimmer), Chip, Input/Select/
   Checkbox/Radio/Slider (with histogram), SegmentedControl, Card (pointer glow), Panel/Drawer/Sheet, Tabs, Accordion,
   Tooltip, Toast, Skeleton, Progress track, Stepper, Command palette, Odometer number, Fee bar, NAAC meter, Empty state.
6. `/styleguide` (noindex): tokens, type, colour/contrast table, components with all states, motion gallery with
   reduced-motion fallback toggles.
7. Two concepts rendered with real seed data (catalogue export): `/concepts/a/*` and `/concepts/b/*` — hero with the
   Witty presence, finder, detail panel, chat.
8. Screen recordings (Playwright video, Pixel 7 + desktop) and Lighthouse (throttled mobile) for both; choose; record
   in `DECISIONS.md`; preserve the other (`concept-b` branch + selectable theme).
9. Gate, self-review, tag `website-phase-1-done`.

### Step log
- 1.1 ✅ Scaffold: tsconfig (strict + noUncheckedIndexedAccess), Next 16 config (Cache Components), Tailwind 4,
  ESLint flat config, Prettier, Vitest; root layout with inline boot script (theme + capability tier before paint).
- 1.2 ✅ Tokens (`app/tokens.css`): brand scales, dark "luminous" + light "daylight" semantic tokens, concept B overrides,
  type/space/radius/blur/motion/z-layers; contrast pairs tested (29 tests).
- 1.3 ✅ Brand: SVG logo variants incl. header lockup and dark variants; `Logo` component (theme-scoped).
- 1.4 ✅ WebGL helper (`lib/client/gl.ts`), aurora + prism shaders, Witty orb shader, presence store; 7 KB gz total.
- 1.5 ✅ Component library (`components/ui/*`) with all states; finder demo (grouped/flat, facets with live counts,
  histogram slider, chips, bottom sheet, panel, compare tray); generative chat UI (cards, fee bars, eligibility ticks,
  comparison grid); orb → chat-head morph on scroll.
- 1.6 ✅ `/styleguide` with contrast table, type, space, components, motion gallery (reduced-motion preview), tiers.
- 1.7 ✅ Concepts A and B: home, finder + panel, chat (`/concepts/*`), real catalogue seed (`content/seed`).
- 1.8 ✅ Measured on production build: Lighthouse (applied + simulated), axe (both themes, 0 violations), recordings
  (`docs/design/recordings/*.webm`). Fixes from measurement: fonts self-hosted Latin + optional (D-020), Roboto Flex
  dropped (D-024), odometer width reservation, zero-JS FAQ, per-route page modules.
- 1.9 ✅ Choice: Concept A (D-023, `docs/design/CONCEPTS.md`); B preserved (switchable + local branch `concept-b`).

### Phase gate
- Migrations: none in this phase. Unit tests: 29/29 green. Typecheck + lint clean. Production build: all routes static.
- Lighthouse (mobile, applied throttling): A home 98 (LCP 1.7 s, CLS 0, TBT 130 ms); B home 98. Simulated: 89–95.
- axe WCAG 2.1 AA: 0 serious/moderate violations on all 7 pages in both themes.
- Docs: `docs/design/DESIGN_SYSTEM.md`, `docs/design/CONCEPTS.md`, DECISIONS D-020…D-024.

### Self-review (spec Section 10 and Phase 1 row)
| Requirement | Status | Note |
|---|---|---|
| Tokens: colour (both themes), type, spacing, radius, elevation/depth, blur, glow, motion, z-layers | Done | `app/tokens.css` |
| Component library covering every UI element, all states | Done (for elements known so far) | Further components (command palette, stepper form, compare columns) are built in their phases with the same tokens |
| `/styleguide` (noindex) incl. motion gallery with reduced-motion fallback | Done | |
| Capability tiers detected and documented | Done | boot script + ARCHITECTURE §8 + style guide |
| Two futuristic concepts: hero with Witty presence, finder, detail panel, chat — real pages with seed data | Done | |
| Screen recordings | Done | 4 videos (phone + desktop per concept) |
| Lighthouse on throttled mid-range Android profile | Done | applied + simulated, D-021 |
| Choose stronger concept, explain in DECISIONS, keep the other selectable + on `concept-b` branch | Done | branch is local only (push restricted, D-023) |
| Logo unchanged; SVG trace; palette inferred | Done | S-40 to confirm trace |
| Dark luminous + light daylight both first-class; toggle + prefers-color-scheme | Done | D-022 |
| Variable display face with optical sizing; kinetic headline; tabular fee figures | Done | |
| Surfaces: translucent panels, blur, grain, inner light, hairline borders, contrast on real backgrounds | Done | AA tested; solid fallback on low tier |
| Living aurora WebGL hero reacting to scroll, pointer, Witty activity | Done | |
| Witty orb: breathes, ripples while typing, pulses with tokens, morphs to chat-head on scroll | Done | |
| Generative UI in chat | Done | |
| Instant command search (⌘K) | Deferred → Phase 4 | belongs to the real finder search with suggestions |
| Fluid finder: layout animations, odometer counts, histogram slider, card → panel View Transition | Partial → Phase 4/5 | reflow + odometer + histogram done; card→panel shared-element morph completed with the real panel in Phase 5 |
| Visual comparison columns | Partial → Phase 4 | comparison grid (chat) done; `/compare` page in Phase 4 |
| Scroll storytelling (CSS scroll timelines) | Done (basic) | How it works / Why Eduwit reveal; refined in Phase 6 |
| Live trust layer counting from live catalogue numbers | Done | live numbers wired in Phase 3 (`web_catalog_stats`) |
| Micro-interactions: magnetic buttons, pointer glow, press states, light haptics, brand-light skeletons | Done | |
| Application form as guided conversation | Deferred → Phase 5/7 | progress track component ready |
| Guardrails: progressive enhancement, never block content, budgets, a11y, no gimmicks | Done | measured |
| Mobile-first 360–414 px, futuristic feel on mobile | Done | Pixel 7 recordings/screens |
| Load `frontend-design` skill if available | N/A | not available in this session |

### Phase 1 summary
Design system, component library, style guide and two concepts built over real catalogue data and measured on a
production build. Concept A (Luminous) chosen; B preserved. Performance work during the phase removed ~320 KB of fonts
and all layout shift.

---

## Phase 2 — Foundation ✅ `website-phase-2-done`

### Plan
1. Supabase CLI as a dev dependency; `supabase/migrations/00000000000000_prod_snapshot.sql` (shared objects the site
   uses, from the read-only snapshots; never applied to production) + seed (catalogue export); `db:reset`, `db:test`
   scripts; run website migrations on both the fresh local DB and `prod-replica`.
2. First website migration `web1_foundation`: `web_settings` (+history), `web_outbox`, `web_admin_users`,
   `web_audit_log`, `web_funnel_events`, health function; RLS on, no anon/authenticated access; SQL tests.
3. Env and config: `lib/server/env.ts` (zod-validated), `.env.example`, settings loader with cache tag.
4. Security: `proxy.ts` (request id, security headers, CSP: hashed boot script on static pages, nonce on dynamic),
   verify CSP against the production build.
5. Layout: site header (logo, nav, Compare badge, Ask Witty, Account, theme toggle), mobile bottom action bar, footer
   (contact, GST, address, legal, social, sitemap links), skip link, error pages (404/500/global-error), thank-you.
6. Analytics + consent framework: consent manager (necessary/analytics/marketing), event API with no PII, loaders for
   GA4/Pixel/Clarity gated by consent and env; attribution capture (UTM, click ids, referrer, landing, creator code).
7. Observability: structured logger with PII scrubbing, request id propagation, Sentry adapter (DSN-gated),
   `/api/health` (db, read model, email, AI, search) and `/api/metrics`.
8. Admin auth skeleton: Supabase Auth (Google/email) + email-code second factor + trusted device, roles, `/admin` gate.
9. CI: GitHub Actions workflow for `website/web` (typecheck, lint, unit, SQL tests on a Supabase CLI stack, build,
   Playwright smoke + axe, Lighthouse CI with budgets, npm audit prod deps).
10. Gate, self-review, tag.

### Step log
- 2.1 ✅ Local DB baseline: Supabase CLI dev dep; `00000000000000_prod_snapshot.sql` generated from the replica by
  `scripts/db/make-min-snapshot.sh` (15 shared tables + 15 functions, policies/foreign triggers filtered); seed from the
  catalogue export (`make-seed.mjs`); `db:reset`, `db:test`; `web1_foundation` (settings + history, outbox with backoff,
  audit log, funnel events, rate events, health); SQL security test (146 checks: RLS on, no anon/authenticated grants,
  definer + empty search_path on every `web_` function). Commit 5b3b62f.
- 2.2 ✅ `lib/server/env.ts` (zod; production refuses dev secrets), settings loader (`"use cache"` + tag), DB rpc helper,
  KV (Upstash or memory), rate limits, logger with PII scrub, request id.
- 2.3 ✅ Security: `proxy.ts` (request id, attribution cookies, nonce CSP on /account + /admin); static CSP + security
  headers in `next.config.ts` (D-025). Verified on the production build: no CSP violations (e2e).
- 2.4 ✅ Site shell: header (native popover menu), mobile action bar, footer (GST, address, legal, contact),
  announcement bar, 404/error/global-error, thank-you.
- 2.5 ✅ Consent (necessary/analytics/marketing) + loaders gated by consent and env; event API with allowlist and PII
  strip; first-party attribution (D-026). Commit fb54a62.
- 2.6 ✅ Observability: Sentry adapter (DSN-gated, idle-loaded on the client), `/api/health`, `/api/metrics` (bearer).
- 2.7 ✅ Email adapter (SMTP / Resend / console) + templates; Mailpit locally.
- 2.8 ✅ Admin auth: Supabase Auth sign-in + website email-code second factor (10 min, 5 attempts, 5 codes/h), signed MFA
  cookie, trusted devices (30 days), roles, `web2_admin_auth` migration + 15 SQL checks; e2e sign-in passes. Commit 6ef7de7.
- 2.9 ✅ CI: `.github/workflows/website-ci.yml` (typecheck, lint, unit, banned-claim copy check, prod-dep audit; SQL
  tests on the Supabase CLI stack, build, Playwright smoke + axe both themes + admin auth, Lighthouse CI budgets via
  `web/lighthouserc.cjs`). New: `e2e/smoke.spec.ts`, `scripts/check-banned-phrases.mjs` (`npm run check:copy`).
- 2.10 ✅ Gate (below).

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 54 unit tests, copy check) | ✅ |
| `npm run db:gate`: replica rebuilt → web1+web2 applied → SQL tests (146+18+15) → shared objects unchanged vs production → local reset → SQL tests | ✅ all pass; "shared objects unchanged: all rows match production" |
| `npm run build` | ✅ |
| Playwright (laptop + Pixel 7): smoke, consent, 404, health, headers, attribution PII, axe WCAG 2.1 AA both themes on /, /thank-you, /styleguide, admin sign-in | ✅ 25 passed, 1 skipped (admin flow runs on laptop only) |
| Lighthouse CI (mobile, applied throttling, median of 2) | ✅ `/` perf 98 · a11y 100 · BP 96 · SEO 100 · LCP 1.7 s · TBT ≤120 ms; `/thank-you` perf 99; `/admin/login` perf 97–98 (both noindex by design) |
| `npm audit --omit=dev` | ✅ 0 vulnerabilities |

### Self-review (spec Section 17, Phase 2 row; Section 3A; Section 13)
| Item | Status |
|---|---|
| Next.js app, TS strict, Tailwind, tokens from Phase 1 | Done |
| Supabase local + replica, website migrations additive, RLS on every `web_` table, service-role only | Done |
| Settings table + admin-editable flags (`web_advisor_enabled` off) | Done (admin UI in Phase 10) |
| Outbox with retries/backoff/dead letter | Done (worker + pg_cron call in Phase 7, when there is something to send) |
| Security headers, CSP, rate-limit primitives, PII scrub | Done |
| Consent manager + analytics framework, no PII in events | Done (GA4/Pixel/Clarity IDs pending S-16..S-18) |
| Attribution capture | Done (lead mapping used in Phase 7) |
| Sentry, health, metrics, structured logs | Done (DSN pending S-19) |
| Admin auth (Supabase Auth + second factor + roles) | Done (Google provider needs S-21; email sign-in works) |
| CI with Lighthouse/axe gates | Done (workflow runs on PRs touching `website/**`; not yet observed on GitHub runners) |
| Preview deploys on Vercel | Deferred — needs S-10 (Vercel project) |

---

## Phase 3 — Catalogue and taxonomy ✅ `website-phase-3-done`

### Plan
1. `web3_taxonomy`: canonical levels/categories/programmes/specialisations/formats, goal and career tags, synonyms
   (generated normalised + compact forms), data-driven mapping rules, offering map, university profiles; auto-mapper,
   unmapped report, admin override (audited).
2. `web4_read_model`: derived facts (duration, NAAC/UGC-DEB/NIRF/AICTE parsers, eligibility), `web_offering_search`
   materialised view (allow-listed columns, weighted tsvector, trigram), facet values, polling refresh + revalidation,
   query resolver, `web_search` (results + facets in one call), suggest, details, compare, universities, stats, browse,
   search log, data-quality report.
3. SQL tests (taxonomy rules, parsers, eligibility, facet logic, zero results, allow-list, polling).
4. 10k benchmark and tuning (target p95 < 150 ms).
5. TypeScript: URL state, deterministic NL parser, eligibility mirror, SearchAdapter (cached, tagged), API routes,
   outbox worker for revalidation, Vercel Cron fallback.
6. Shared-taxonomy proposal (A-TAX-1) checked on the replica; docs; gate.

### Step log
- 3.1 ✅ `20261017100200_web3_taxonomy.sql`: 21 programmes, 64 specialisations with ~330 aliases, Hinglish stopwords,
  university aliases via `web_tax_sync_catalog()`; first run maps **715/715** rows (416 exact, 277 synonym, 19 split,
  3 from the name, 0 fuzzy).
- 3.2 ✅ `20261017100300_web4_read_model.sql`: read model (708 visible; 7 Regular hidden), 197 groups; parsers verified
  against all 29 universities (NAAC for 28, UGC-DEB for 25, NIRF ranks/bands for 15); duration known for 372 rows.
- 3.3 ✅ SQL tests: `30_web_taxonomy` (48 checks), `40_web_search` (41 checks); security test now 460 checks.
- 3.4 ✅ Benchmark `npm run db:bench` (10k offerings, rolled back): first version 487 ms unfiltered → nested-statement
  overhead from definer helpers (D-029) and wide CTE rows → grouping-set facet counts, narrow rows, precomputed
  goal ids: **filtered 20–55 ms, typo 22 ms, suggest 23 ms, unfiltered grouped 145 ms, flat 130 ms** (both edge-cached).
  Real catalogue: 5–35 ms. Known slow edge: zero-results at 10k (~235 ms, recomputes the query-less count).
- 3.5 ✅ `lib/search/{types,params,parse}.ts`, `lib/finder/eligibility.ts` (+29 unit tests), `lib/server/search.ts`,
  `lib/server/outbox.ts`, routes `/api/search`, `/api/suggest`, `/api/offerings/[id]`, `/api/internal/{revalidate,
  outbox,catalog-poll}`, `vercel.json` crons, `CRON_SECRET` accepted on internal routes.
- 3.6 ✅ `supabase/migrations-shared/s03_shared_taxonomy.sql` + `scripts/db/check-shared-proposals.sh` (part of
  `db:gate`); docs: D-028…D-034, A-CRON-1, S-46/S-47, TAXONOMY_PROPOSAL result, SCHEMA_PLAN.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 83 unit tests, copy check) | ✅ |
| `npm run db:gate` (replica: web1–4 applied, 460+18+15+48+41 SQL checks, shared objects unchanged vs production, s03 proposal applies and rolls back; local reset + same tests) | ✅ |
| `npm run build` | ✅ |
| Playwright (smoke, axe both themes, admin auth, catalogue API) | ✅ 30 passed, 6 skipped (single-project checks) |

### Self-review (spec Section 17 Phase 3 row; 5; 3A read path; 6.3–6.4 data side)
| Item | Status |
|---|---|
| `web_` taxonomy tables keyed to catalogue ids + mapping; editable data, not code | Done |
| Shared version queued (A-TAX-1, `s03_shared_taxonomy.sql`, verified on replica) | Done |
| Search read model (MV, allow-listed columns, weighted tsvector, trigram) | Done |
| Catalogue read views/functions (details, compare, universities, stats, browse) | Done |
| Synonyms, typo tolerance, prefix matching, relevance order (programme/spec > university > text, popularity tie-break) | Done |
| Facet functions: counts exclude own selection, zero-count options kept, hierarchy-aware | Done |
| NL parsing without an LLM | Done (budget, duration, qualification, goals in TS; entities in SQL) |
| Revalidation hooks: polling (pg_cron, A-CRON-1) → refresh → outbox `revalidate` → `revalidateTag` | Done |
| Unmapped-rows tooling | Done in DB (`web_tax_unmapped`, `web_tax_set_mapping`, `npm run tax:report`); admin UI in Phase 10 |
| p95 < 150 ms at 10k | Done for filtered queries; unfiltered default ~145 ms DB time and served from the edge cache; measured again in Phase 12 load test |
| Intakes facet | Deferred — no data in the catalogue (A-TAX-2); facet hidden |
| University state facet | Deferred — needs S-46; facet appears automatically when data exists |

---

## Phase 4 — Programme finder ✅ `website-phase-4-done`

### Plan
1. Search box with grouped, keyboard-navigable suggestions; free text → structured filters (`/api/search/resolve`).
2. `/programmes`: server-rendered results from URL state; facet rail (desktop) and staged bottom sheet (mobile);
   applied-filter chips; sort; grouped/flat views; cumulative "Show more"; eligibility marking; indexing rules.
3. Group cards (expand on demand with current filters), offering rows, offering panel (deep link `?offering=`).
4. Guided finder (qualification → goal → budget/duration), browse-by-category entry, Ask Witty (with fallback).
5. Zero results: relaxations with counts, closest matches, Ask Witty.
6. Compare (tray, `/compare?ids=`, highlights, hide identical, share) and anonymous shortlist (`/shortlist`).
7. Search quality suite; finder e2e + axe; Lighthouse budgets on the finder.

### Step log
- 4.1 ✅ `SearchBox` (WAI-ARIA combobox), `/api/search/resolve` + `web_resolve_to_filters` (entities → URL filters,
  unknown words dropped or kept as text only if they match the catalogue).
- 4.2 ✅ `/programmes` page, `FinderView`, `FacetPanel` (all spec 6.3 facets that have data; zero-count disabled;
  hierarchy via counts), `MobileFilters` (staged, live count), `lib/client/use-finder.ts` (URL navigation, optimistic
  state, panel pushState), `lib/search/{labels,seo,state}.ts` (+ tests).
- 4.3 ✅ `ResultGroup`, `OfferingResult`, `UniversityMark`, `OfferingPanel` (fees + breakdown, key facts with sources,
  eligibility text, approvals with plain-language explainers in `content/explainers.ts`, other universities,
  "Data last verified", fee disclaimer; Apply section is a counsellor hand-off until the form lands in Phase 5/7).
- 4.4 ✅ `GuidedFinder`, category browse pills, `AskWitty` fallback (D-038).
- 4.5 ✅ `ZeroResults`; SQL: fee facet always an object (bug found by e2e), fee histogram for the slider.
- 4.6 ✅ `CompareTray`, `CompareTable` + `lib/finder/compare.ts` (+ tests), `/compare`, `/shortlist`,
  `/api/offerings?ids=` + `web_offering_cards`; mobile bar's Shortlist → `/shortlist`; `Toaster`.
- 4.7 ✅ `supabase/tests/50_search_quality.test.sql` (31 real-catalogue queries: abbreviations, full names, Hinglish,
  typos, universities, levels, modes, categories, no dead ends; skipped on the empty replica); `e2e/finder.spec.ts`
  (11 tests × 2 devices incl. axe with the panel open, both themes); Lighthouse: consent banner SSR (D-037), JS diet
  (D-039).

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 93 unit tests, copy check) | ✅ |
| SQL tests local (460 + 18 + 15 + 48 + 42 + 31 quality) | ✅ |
| `npm run build` | ✅ |
| Playwright (smoke, a11y, admin, catalogue API, finder) | ✅ 48 passed |
| Lighthouse CI mobile, applied throttling | ✅ `/` 97–98; `/programmes` 94–96; `/programmes?programme=mba&spec=marketing` 97; LCP 1.6–1.7 s; TBT ≤ 270 ms; CLS 0; a11y 100; SEO 100 |

### Self-review (spec 6.1–6.5, Phase 4 row)
| Item | Status |
|---|---|
| Search box with grouped instant suggestions, keyboard navigable | Done (Guides group arrives with resources in Phase 6) |
| Guided finder with live narrowing, back/edit at every step | Done |
| Browse by level, category, university | Done (facets + category pills; university directory in Phase 5) |
| "Not sure? Ask Witty" always visible | Done (counsellor fallback while Witty is off) |
| Grouped results with the spec's card fields; expand to offerings; flat view | Done (logos only where permitted, S-41) |
| Eligibility awareness; hide not eligible with a toggle | Done |
| Facets incl. live counts, disabled zero options, hierarchy, chips, clear all, mobile sheet with live count | Done; intake and state facets wait for data (A-TAX-2, S-46) |
| Typo tolerance, synonyms, prefix, relevance; NL parsing; sorting; URL state | Done |
| Zero results never dead-end | Done |
| Pagination with load-more and scroll restore | Done (cumulative pages) |
| p95 < 150 ms | Done (Phase 3 benchmark; edge-cached API) |
| Compare up to 4 with highlights, hide identical, shareable URL; Discuss with Witty / counsellor | Done |
| Anonymous shortlist; sync after sign-up | Done locally; sync in Phase 7 |
| Search quality suite | Done (31 cases) |

---

## Phase 5 — Detail panel and university pages ✅ `website-phase-5-done`

### Plan
1. Offering panel: application form inside, sticky "Apply now", EMI per month where the catalogue has it.
2. Programme-group panel (`?group=`): universities, fee/duration ranges, form with a university picker.
3. Multi-step application form UI (spec 9.1A) with validation, inline email code, eligibility note, review, thank-you —
   mock transport (D-042).
4. University directory and profiles (facts with explainers, programmes in the finder format, apply with a programme
   picker); curated finder views (`web_curated_views`, intro + FAQs); JSON-LD; prerendering (ISR via cache tags).
5. Tests (unit, e2e), Lighthouse on the new pages, gate.

### Step log
- 5.1 ✅ `web_offering_card` carries `fee.emi_monthly` (D-041); `OfferingPanel` embeds the form (lazy).
- 5.2 ✅ `GroupPanel`, `PanelHost` (lazy panels for `?offering=` / `?group=`), "Programme overview and apply" on cards.
- 5.3 ✅ `components/forms/ApplicationForm.tsx`, `lib/forms/{validate,client}.ts` (+ tests: Indian mobile, email, names
  incl. Devanagari, step rules), `content/{consent,india}.ts`; CodeInput auto-submit fix.
- 5.4 ✅ `/universities`, `/universities/[slug]`, `UniversityProgrammes`; `20261017100400_web5_curated_views.sql`
  (+ three starter views: online-mba, online-bca, online-mca) and `/programmes/[slug]`; `lib/seo/jsonld.ts` (+ tests),
  `components/seo/JsonLd.tsx` (Course, ItemList, CollegeOrUniversity, FAQPage, BreadcrumbList); copy no longer claims
  "UGC-entitled universities" (3 catalogue universities state no UGC-DEB status — D-014).
- 5.5 ✅ `e2e/panels.spec.ts` (form end to end incl. wrong code, group deep link, university page + JSON-LD, curated
  view); a11y fix (underlined links inside consent text); CLS fix (no Suspense on prerendered pages); D-043.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 101 unit tests, copy check) | ✅ |
| `npm run db:gate` (replica: web1–5, 483+18+15+48+42 checks, shared unchanged, s03 proposal; local reset + same + 31 quality) | ✅ |
| `npm run build` (universities and curated views prerendered) | ✅ |
| Playwright | ✅ 56 passed |
| Lighthouse CI mobile (applied throttling) | ✅ `/programmes` 94, MBA·Marketing 97, `/programmes/online-mba` 95–96, `/universities` 96, `/universities/nmims` 95–98; LCP ≤ 1.8 s; TBT ≤ 260 ms; CLS 0; a11y 100 |

### Self-review (spec 6.6, 9.1A UI, Phase 5 row)
| Item | Status |
|---|---|
| Offering panel: drawer/full-screen sheet, deep link, closes back to results and scroll | Done |
| Only catalogue facts; missing fields don't appear; explanations of approvals; last verified; disclaimer | Done |
| Other universities for the same programme (switches the panel); shortlist and compare | Done |
| Sticky "Apply now" + form inside the panel; "Ask Witty about this programme" | Done (counsellor fallback while Witty is off) |
| Programme-group panel with university picker | Done |
| Curated finder views (admin-created, intro + FAQs) | Done (table + 3 starter views; admin editor in Phase 10) |
| University pages with facts and offerings in the finder format opening the same panel | Done |
| ISR / static + revalidation | Done (prerendered; `catalog`/`content` tags revalidated by the poller and admin) |
| Structured data | Done (Course, ItemList, CollegeOrUniversity, FAQPage, BreadcrumbList; Organization helper for Phase 6) |
| Application form UI: 5 steps, validation, inline email code, eligibility note, review, thank-you + reference | Done with mock transport (Phase 7 wires it) |
| Form context: offering / group / university / compare | Done (compare links to "Details and apply"); advisor context in Phase 8 |
| Admin-configurable fields | Prop-level config in place (`FormConfig`); admin UI + settings key in Phase 10 |
| Document upload behind a setting (off) | Deferred to Phase 7 (setting `document_upload_enabled` exists, default off) |

---

## Phase 6 — Content and migration ✅ `website-phase-6-done` (verbatim migration blocked on S-01)

### Plan
1. `web6_content`: legal pages, testimonials, FAQs, authors + resources (author/reviewer required to publish), popular
   searches, runtime redirects, page SEO overrides; read functions.
2. Homepage (spec 8 order; Witty off → search + guided finder + free counselling; live trust line; sections toggled).
3. About, How it works, Contact (+ enquiry form), Resources (list + article with bylines), six legal pages at their URLs.
4. Legacy import path (crawl → reviewable SQL), Privacy Policy proposed additions, runtime redirects.
5. Tests, Lighthouse, gate.

### Step log
- 6.1 ✅ `20261017100500_web6_content.sql` (8 tables, 8 functions; seeded legal-page shells, 8 FAQs, 8 popular searches).
- 6.2 ✅ `HomeHero` (flag-aware), `components/home/HomeSections.tsx`, `/` with Organization + FAQPage JSON-LD.
- 6.3 ✅ `/about`, `/how-it-works`, `/contact` (`EnquiryForm`, mock transport), `/resources`, `/resources/[slug]`
  (Article JSON-LD with author and reviewer), `/legal/[slug]` (`Blocks` renderer; pending notice + noindex);
  data-driven footer hubs; Resources hidden from navigation until a guide is published; `?guided=1`.
- 6.4 ✅ `scripts/import-legacy.mjs` + `scripts/lib/legacy-blocks.mjs` (+ tests), `docs/legal/privacy-policy-proposed-additions.md`,
  `lib/server/redirects.ts` + proxy (D-045).
- 6.5 ✅ `e2e/content.spec.ts` (home, guided link, about/how/contact, enquiry flow, legal pages, guides empty state,
  redirects); axe now covers 11 pages × 2 themes × 2 devices; the banned-phrase check caught a negated quote (fixed).

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 103 unit tests, copy check) | ✅ |
| `npm run db:gate` (web1–6 on the replica: 595+18+15+48+42 checks, shared unchanged, s03; local + 31 quality) | ✅ |
| `npm run build` | ✅ (all content pages prerendered) |
| Playwright | ✅ 102 passed |
| Lighthouse CI mobile | ✅ `/` 93–94 (LCP 1.8 s, TBT ≤ 270 ms), finder 96–98, curated 96, universities 93–98, about 96–97, contact 96–98; CLS 0; a11y 100; SEO 100 |

### Self-review (Phase 6 row; spec 8, 9.1, 14)
| Item | Status |
|---|---|
| Home without live AI (flag off) in spec 8 order | Done (stories/resources hidden until real content) |
| About, How it works, Contact | Done with interim copy (D-044, S-48) |
| Resources | Done (empty state; guides need named author + reviewer — S-50, Phase 11 planner) |
| Legal pages migrated verbatim | **Blocked** on S-01 (crawl). Pages live at the same URLs with a notice + noindex; importer ready |
| Testimonials | Table + section ready; legacy ones need the crawl and consent confirmation (S-49) |
| FAQs (with FAQPage schema) | Done |
| Redirects | Done (legacy static map + admin runtime map); CI redirect tests extended in Phase 9 |
| Privacy Policy edits as a separate reviewable diff | Done (`docs/legal/privacy-policy-proposed-additions.md`) |

## Phase 7 — Gate, email verification, accounts, forms ✅ `website-phase-7-done`

### Plan
1. `web7_students_leads`: consent texts, students, hashed codes, gate attempts, consent ledger, sessions, applications,
   shortlists, comparisons, block list, disposable domains, privacy requests; lead via `lead_intake` only after the code.
2. Server: verification core (honeypot, Turnstile, limits per IP / device / email, screening, junk score), signed
   student session, server actions for forms and accounts, outbox handlers (confirmation email, CAPI), creator provider.
3. UI: wire the application and enquiry forms, account pages, save comparison, shortlist sync, creator pages.
4. Tests (unit, SQL, e2e with Mailpit codes), docs, gate.

### Step log
- 7.1 ✅ `20261017100600_web7_students_leads.sql` (14 tables, 22 functions) + `supabase/tests/60_web_leads.test.sql`
  (42 checks through the real `lead_intake`: lead only after verification, exactly once, duplicate phone → merged,
  first touch kept, trusted skip, owner check, consent withdrawal opt-out, unverified push off by default).
- 7.2 ✅ `lib/forms/junk.ts`, `lib/forms/lead-fields.ts` (SCHEMA_PLAN §4.1 mapping), `lib/server/{gate,student-session,
  turnstile,capi,creators,outbox-handlers}.ts`, `app/actions/{forms,account}.ts` (D-046–D-053).
- 7.3 ✅ Forms on the server transport (`lib/forms/server-client.ts`): resend, spam hint, honeypot, Turnstile, pre-fill and
  code skip for signed-in students; `/account`, `/account/sign-in` (per-request nonce; signed-out → 307 in the proxy),
  "Save comparison", shortlist sync, `/c/[handle]`; banned-phrase check now also catches blanket approval claims.
- 7.4 ✅ `e2e/leads.spec.ts` (application flow with wrong/right code and lead assertions; enquiry + duplicate phone;
  unverified attempt and honeypot; creator code on the lead; sign-in, account, trusted skip, privacy request, sign out);
  axe now also covers `/account/sign-in` and `/c/demo-creator`; redirect fixture moved into the seed.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 115 unit tests, copy check) | ✅ |
| `npm run db:gate` (web1–7 on the replica: 809+18+15+48+42+1+42 checks, shared unchanged, s03; local + 31 quality) | ✅ |
| `npm run build` | ✅ (`/account*` per request for the CSP nonce; `/c/demo-creator` prerendered) |
| Playwright | ✅ 116 passed (laptop + Pixel 7), incl. 5 lead/account flows with real Mailpit codes |
| Lighthouse CI mobile | ✅ `/` 93–95, finder 94–97, curated 93–96, universities 97–98, about 98–99, contact 97, sign-in 98–99, creator 96–98; LCP ≤ 1.9 s; TBT ≤ 291 ms; CLS 0; a11y 100 |

### Self-review (Phase 7 row; spec 7.2 gate mechanics, 9.1A, 9.1, 9.2, 9.3, 12, 14)
| Item | Status |
|---|---|
| Email verification: 6-digit inline code, 10-min expiry, 5 attempts, resend after 30 s, change email, spam hint | Done |
| Lead via `lead_intake()` only after verification; exactly once; duplicate phone handled by `lead_intake` | Done (SQL + e2e) |
| Phone validated, E.164, not OTP-verified; phone-OTP adapter built and disabled (`require_phone_otp` off) | Done (`disabledPhoneOtp`; S-25) |
| Turnstile, rate limits per IP / device / email, disposable list, honeypot, block list, junk score | Done (D-050, D-052, D-053) |
| Consent versioned and stored (ledger + lead stamps); withdrawal; deletion / opt-out / export requests | Done |
| Drop-offs recorded in `web_gate_attempts`; `push_unverified_gate_leads` (default off) | Done (worker calls `web_push_unverified`) |
| Sessions: verified users stay signed in; sign in again with an email code | Done (own sessions, D-005) |
| Account pages: profile, shortlist (synced), saved comparisons, applications, consent, opt-out / deletion | Done; chat history arrives with Phase 8 |
| Built-in application form: steps 2–4 enrich the same lead, save on Next, submit = application request, reference, confirmation email | Done |
| Signed-in users skip verification and get pre-filled fields | Done |
| Short enquiry form via `lead_intake` with page context | Done |
| Attribution (UTM, click ids, referrer, landing, creator code) on every lead | Done (cookies → `attributionToLead`) |
| Creator pages with a typed provider + mock; code attached, never gates | Done (D-018, D-051; S-43) |
| Server-side conversion events on a verified lead (CAPI Lead) and on submit (SubmitApplication) | Done via outbox (D-047; S-17) |
| Document upload behind `document_upload_enabled` (off) | Deferred — owner decision on storage, retention and legal text (D-054) |
| Form fields configurable in the admin | Deferred to Phase 10 (the form already reads a `config` of hidden/optional fields) |
| Witty gate UI (before the first message) | Phase 8 (reuses `startVerification` with `surface = 'gate'`) |

### Phase 7 summary
Students verify their email inline; only then is a lead written through `lead_intake` (once, de-duplicated by phone, with
attribution, creator code and versioned consent). The application form enriches the same lead step by step and ends as
an application request with a reference and a confirmation email; the enquiry form and creator pages use the same flow.
Students can sign in, see their applications, sync their shortlist, save comparisons, withdraw consent and request
deletion. Conversions API events wait for marketing consent and a token.

## Phase 8 — Witty on the website (`web_advisor`) ✅ `website-phase-8-done` (ships OFF until A-AGENT-1)

### Plan
1. `web8_advisor`: sessions, transcript in the `w2_messages` shape, feedback, callbacks; read-only wrappers of Witty's
   prompts, catalogue and knowledge functions; turn commit with the lead through `lead_intake`.
2. `lib/witty-core`: Witty's published contract as a channel-agnostic module (engine, verifier, placeholders, texts).
3. Model providers (Claude with prompt caching; scripted provider without a key), `/api/witty` (SSE, budget, timeout,
   circuit breaker, verifier rewrite + fallback, metrics).
4. Chat UI (gate, streaming, cards, chips, feedback, callback, restart, retry), `/witty`, hero, account chat history.
5. Tests, docs, gate.

### Step log
- 8.1 ✅ Plan; spec 7 / 3A re-read; `docs/AGENT_ARCHITECTURE.md` followed.
- 8.2 ✅ `20261017100700_web8_advisor.sql` (4 tables, 8 functions) + `supabase/tests/70_web_advisor.test.sql` (24 checks);
  local seed mirrors Witty's two prompts (md5 = production, D-056); course names normalised to Witty's catalogue keys.
- 8.3 ✅ `web/lib/witty-core/` (contract, normalise, language, fixed-texts, engine, placeholders, verifier) + 47 tests
  (`happy_path_mba`, `hinglish_parent`, `general_questions`, `fee_check`, `alternatives_and_complaints`, eligibility,
  hand-off, opt-out, fact rules, classification table, lead payload keys) — D-060.
- 8.4 ✅ `lib/server/web-advisor/{model,mock,prompts,breaker,turn}.ts`, `lib/web-advisor/{stream,events}.ts` (+ tests),
  `app/api/witty/route.ts`, `app/actions/witty.ts`; Anthropic SDK pinned to 0.131.0.
- 8.5 ✅ `components/witty/{WittyChat,WittyGate,RichText}.tsx`, `/witty`, hero ask box (D-057), account "Chats with
  Witty"; fixed the `[slug]` 500 after cache-tag expiry (D-058) with a regression test.
- 8.6 ✅ `e2e/witty.spec.ts` (gate → no lead before the code → streamed DIRECTIONAL → PROGRAMS with cards → lead with
  Witty's fields, transcript, feedback, callback; returning user resumes; same phone one lead; erasure → opt-out; flag
  off fallback). Docs: D-055–D-061, A-AGENT-1 "ready" note, S-14.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 165 unit tests incl. 47 witty-core, copy check) | ✅ |
| `npm run db:gate` (web1–8 on the replica: 877+18+15+48+42+1+42+24 checks, shared unchanged, s03; local + 31 quality) | ✅ |
| `npm run build` | ✅ |
| Playwright | ✅ 126 passed (laptop + Pixel 7), incl. 4 Witty flows (laptop; the flag is global state) and the cache-expiry regression test |
| Lighthouse CI mobile (2 runs) | ✅ all 13 paths on performance ≥ 0.9, LCP ≤ 1.9 s, CLS ≤ 0.07, a11y 100, SEO 100 on indexable pages — except TBT on `/programmes/online-mba` (355–365 ms in that run). Re-measured 3× on the same build: 234 / 263 ms (budget 300); `/universities/nmims` 170–198 ms; `/` 210–293 ms. Treated as run-to-run noise; Phase 9 moves Lighthouse to 3 runs (median) and does the performance pass |

### Self-review (Phase 8 row; spec 7.0–7.5, 3A Witty path)
| Item | Status |
|---|---|
| Public name Witty everywhere; `web_advisor` only internal | Done (UI, URLs `/witty`, page text; code, DB, env, flags use `web_advisor`) |
| Shared agent core per `AGENT_ARCHITECTURE.md` (prompts by reference, same tools, same contract, lead keys and events) | Done; the engine is a contract implementation until A-AGENT-1 — **advisor ships OFF** (spec 7.3 allows launch without it) |
| Ask before suggesting; HOT/WARM/COLD; hand-off; no hallucination (placeholders + verifier) | Done (D-060; verifier rewrite then safe fallback) |
| Tools: search_programmes, get_offering_details, compare_offerings, check_eligibility, get_university_details, save_lead_fields | Done as engine-invoked functions (search via Witty's own function, cards from the read model, compare page, engine eligibility, lead via `lead_intake`); university details are not part of Witty's engine flow |
| Gate before the first message (7.2) with inline code; lead only after verification; existing user → no duplicate, history restored | Done (e2e) |
| Streaming chat UI: hero + full screen, markdown, programme cards with shortlist/compare/open panel, quick replies, typing indicator | Done (hero hands off to `/witty`, D-057). Comparison opens `/compare`; fee breakdown and eligibility are on the cards and in the detail panel |
| Talk to a counsellor, Book a callback (writes to the lead), restart, thumbs up/down, history in the account | Done |
| Edge cases: network loss (retry with the same message id, replay), long replies (max words + verifier), off-topic/abusive (Witty's own rules + rate limits), deletion request → opt-out flow | Done |
| Storage (7.5): every message with channel web, session, tool calls in meta; lead fields via the approved function | Done in `web_advisor_messages` (exact `w2_messages` shape) pending A-AGENT-2/3 |
| Circuit breaker, token budget, turn timeout, prompt caching, metrics (TTFT, total, tool latency, tokens, cost, hand-off) | Done; real latency and cost need the API key (S-14). Admin "Advisor insights" in Phase 10 |
| Feature flag `web_advisor_enabled` without redeploy; hero fallback | Done (e2e) |
| Accessibility: live region, keyboard, reduced motion | Done (axe on `/witty`) |

### Phase 8 summary
Witty runs on the website end to end — gate, streamed replies with programme cards, storage, leads with Witty's fields,
feedback, callbacks, history — through Witty's own prompts and catalogue function, with the decision rules implemented
from Witty's published contract. It stays switched off until Witty's ENGINE is shared or proven equivalent (A-AGENT-1)
and an API key is supplied (S-14). Also fixed: `[slug]` pages returned 500 whenever a cache tag expired (D-058).

## Phase 9 — Technical SEO and analytics ✅ `website-phase-9-done`

### Plan
1. robots, sitemap index by type, OG/Twitter images, `WebSite` + `SearchAction`.
2. Indexing and canonical rules (curated views only; panels noindex); admin title/description overrides.
3. Redirects tested in CI entry by entry (301).
4. Analytics: events per spec 13.3, Pixel ↔ Conversions API de-duplication, standard `SubmitApplication`.
5. Performance pass and JS budgets in Lighthouse CI; docs.

### Step log
- 9.1 ✅ `app/robots.ts`, `app/sitemap.xml/route.ts`, `app/sitemaps/[file]/route.ts` (`lib/server/sitemap.ts` + tests),
  `lib/og/card.tsx` with OG + Twitter images for the site, universities, curated views and guides; `websiteLd` on the home.
- 9.2 ✅ `lib/search/seo.ts` rewritten (D-062) + tests; `?offering=` / `?group=` noindex; `lib/server/page-meta.ts`
  (`web_pages` overrides) on every indexable page.
- 9.3 ✅ Legacy redirects send 301 and `e2e/content.spec.ts` checks every entry and its destination.
- 9.4 ✅ Event ids aligned (D-063); `filter_apply`, `programme_view`, `counsellor_click` (delegated listener for WhatsApp
  and phone links), `callback_booked` and `advisor_message` with parameters.
- 9.5 ✅ `docs/PERFORMANCE.md`; Lighthouse CI: median of 3, JS budget ≤ 250 KB per route, SEO budget skips filtered
  finder URLs. Tooling hardened after the `npx lhci` incident (D-065). `e2e/seo.spec.ts` (robots, sitemaps, indexing,
  structured data, OG images).

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 169 unit tests, copy check) | ✅ |
| `npm run db:gate` | ✅ (no schema change in Phase 9; web1–8 as Phase 8) |
| `npm run build` | ✅ (robots, sitemap index, OG images prerendered or per request) |
| Playwright | ✅ 132 passed (laptop + Pixel 7), incl. `seo.spec.ts`, every legacy redirect, cache-expiry regression |
| Lighthouse CI mobile, median of 3, 13 paths | ✅ all assertions: performance 92–99, LCP ≤ 1.9 s, TBT median ≤ 242 ms, CLS ≤ 0.07, JS 175–232 KB (budget 250 KB), a11y 100, SEO 100 on indexable pages |

### Self-review (Phase 9 row; spec 13.1–13.3)
| Item | Status |
|---|---|
| Unique titles, descriptions, H1s from templates with admin overrides | Done (`web_pages` overrides; editing UI in Phase 10) |
| Structured data: EducationalOrganization (Eduwit, universities), ItemList of Course, BreadcrumbList, FAQPage, Organization, WebSite + SearchAction | Done |
| `?offering=` deep links noindex, canonical to the finder view | Done |
| Sitemap index split by type; robots; canonical URLs; OG and Twitter images via `next/og` | Done (D-064) |
| Indexable filter combinations only from curated views | Done (D-062) |
| Migration: 301 map, `/about` and `/legal/*` identical, redirects tested in CI | Done for the known URLs; the full crawl-based inventory is blocked on S-01 (`scripts/crawl-legacy-site.mjs` fills `content/redirects.ts`) |
| Internal linking: curated views, university pages, resources → finder views, breadcrumbs, footer hubs | Done (engine for resource links in Phase 11) |
| Performance: LCP/INP/CLS budgets on home, finder (incl. panel), university pages; hero static first; chat loads on interaction; JS budget per route in CI | Done (`docs/PERFORMANCE.md`) |
| Consent manager gates GA4, Pixel, Clarity | Done (Phase 2 loader, verified) — IDs needed (S-16–S-18) |
| Events (no PII) per 13.3 | Done |
| Conversions API `Lead` on verified lead, hashed identifiers, de-duplicated with the Pixel via event id, consent respected | Done (D-047, D-063) — token needed (S-17) |

### Phase 9 summary
Search engines see only deliberate pages: the home, hubs, curated views, universities and guides, each with structured
data, a canonical URL and a social image, listed in a sitemap index by type. Everything else is noindex with the right
canonical. Analytics events match the spec, and browser and server conversion events share ids. Performance budgets,
including JavaScript per route, are enforced in CI.

## Phase 10 — Admin ✅ `website-phase-10-done`

### Plan
1. `web9_admin`: entity allow-list, audited save/delete, settings with role checks, dashboards (overview, funnels, Witty
   insights, outbox, audit, taxonomy options, privacy requests).
2. Admin UI: shell and navigation, dashboard, generic content list/edit for 12 content types, flags and settings,
   funnels and insights, data quality, taxonomy mapping, outbox with retries, privacy requests, audit log.
3. Revalidate on publish; application form configuration (deferred from Phase 7).
4. Tests, docs, gate.

### Step log
- 10.1 ✅ `20261017100800_web9_admin.sql` (1 table, 15 functions) + `supabase/tests/80_web_admin.test.sql` (25 checks).
- 10.2 ✅ `web/lib/admin/entities.ts` (+ tests), `app/admin/content-actions.ts`, `components/admin/*`, pages under
  `app/admin/{content,settings,insights,data-quality,taxonomy,outbox,audit,privacy}`; dashboard replaced.
- 10.3 ✅ Saves expire cache tags (`settings`, `content`, `pages`, `redirects`, `catalog`); university and synonym edits refresh
  the read model; `application_form` setting read by the form (D-069). Rejected saves keep the editor's input.
- 10.4 ✅ `e2e/admin.spec.ts`: curated view created → live at `/programmes/<slug>` → audited → deleted; testimonial consent
  rule; announcement bar live; every dashboard loads; axe on admin screens; viewer is read-only.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 174 unit tests, copy check) | ✅ |
| `npm run db:gate` (web1–9 on the replica: 930 security + 18+15+48+42+1+42+24+25 checks, shared unchanged, s03; local + 31 quality) | ✅ |
| `npm run build` | ✅ |
| Playwright | ✅ 138 passed (laptop + Pixel 7), incl. 6 admin flows and axe on admin screens |
| Lighthouse CI mobile, median of 3, 13 paths | ✅ after a quiet re-run. The first run overlapped with typechecks on the same machine and put `/`, `/programmes/online-mba` and one filtered finder URL 5–60 ms over the TBT budget; re-measured alone: 235–246, 180–285, 194–269 ms (budget 300). Rule added to `docs/PERFORMANCE.md`: measure only on an idle machine |

### Self-review (Phase 10 row; spec 11)
| Item | Status |
|---|---|
| Auth: Supabase Auth (Google or email) + email-code 2FA after Google; roles Super Admin, Content Editor, Viewer | Done (Phase 2) + role enforcement in pages and database (D-067) |
| Manage testimonials, FAQs, homepage sections and banners | Done (entities + settings: sections, announcement) |
| Popular searches, resources, curated finder views, university editorial | Done |
| SEO overrides, redirects | Done |
| Announcement bar, feature flags, consent text versions | Done (consent texts never reworded) |
| Taxonomy mapping tool + synonym management | Done |
| Data quality dashboard | Done (missing fees, minimum %, duration, approvals, unmapped, zero-result searches) |
| Advisor insights: conversations, gate and form funnels, top questions, thumbs-down; no prompt editing | Done (D-068) |
| Outbox and dead-letter monitor | Done (retry for super admins) |
| Revalidate on publish; audit log for every change | Done |
| Programme data not edited here | Done (read-only; university pages edit editorial fields only) |
| Application form fields configurable (from 9.1A) | Done (D-069) |

## Phase 11 — SEO toolkit ✅ `website-phase-11-done`

### Plan
1. `web10_seo_toolkit`: Search Console rows, sync log, keywords, 404 log, on-page check results, link suggestions, local
   SEO tasks; dashboard, keyword, opportunity, 404 and link functions (all audited through the admin save path).
2. Libraries: Search Console client (service account; labelled sample rows outside production, D-070), on-page checker
   (D-072), internal-link suggester (D-073), brief/draft generator grounded in catalogue facts (D-071).
3. Admin: SEO dashboard, opportunities → draft curated view / guide idea, keyword list with cannibalisation flags,
   content planner (Idea → Brief → Draft → Review → Published → Refresh due), on-page checks, internal links, 404
   monitor, local SEO checklist. Daily job `/api/internal/seo-daily`.
4. Site: 404 beacon, approved "Related" links on guides, `LocalBusiness` structured data with owner-set hours (D-074),
   related-link blocks on curated views and university pages (D-075).
5. SEO checks in CI; tests, docs, gate.

### Step log
- 11.1 ✅ `20261017100900_web10_seo_toolkit.sql` (7 tables, 13 functions, 7 local SEO tasks) + `supabase/tests/90_web_seo.test.sql` (16 checks).
- 11.2 ✅ `web/lib/seo/{onpage,links,related}.ts` (+ tests), `web/lib/server/seo/{gsc,toolkit}.ts` (+ test),
  `app/admin/seo-actions.ts`, pages under `app/admin/seo/*`, `components/admin/SeoNav.tsx`.
- 11.3 ✅ 404 beacon (`components/site/NotFoundBeacon.tsx` → `/api/events/404`), guide "Related" block,
  `organizationLd` with `LocalBusiness` + `business_hours` setting, Vercel cron `30 21 * * *` (03:00 IST).
- 11.4 ✅ First checker run scored our own pages 80: fixed the checker (streamed Suspense content, intro after the H1,
  inbound links from header/footer/hubs) and the pages (related-link blocks; shorter titles for long university
  names). Local average now 95; remaining warnings are content work (S-53 university intros, 6 very long names).
- 11.5 ✅ Planner "Refresh due" also flags guides losing Search Console clicks (spec 13.4), with the reason shown; the
  coverage/Core Web Vitals card links to the Search Console reports instead of promising data the API cannot export.
- 11.6 ✅ `e2e/seo-toolkit.spec.ts` (5 flows) and an on-page error gate in `e2e/seo.spec.ts` (fails CI on any
  error-level finding on a sitemap curated view or university page). JSON imports carry `with { type: "json" }` so
  Playwright's ESM loader can import the checker.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 183 unit tests, copy check) | ✅ |
| `npm run db:gate` (web1–10 on the replica: 1046 security + 18+15+48+42+1+42+24+25+16 checks, shared unchanged, s03; local + 31 quality) | ✅ |
| `npm run build` | ✅ |
| Playwright | ✅ 142 passed in the full run; the one failure (home JSON-LD now `["EducationalOrganization","LocalBusiness"]`) was the test's expectation, updated; `seo.spec.ts` + `seo-toolkit.spec.ts` re-run on the final build: 10/10 |
| Lighthouse CI mobile, median of 3, 13 paths (idle machine) | ✅ all assertions on the first run (machine otherwise idle). Medians: performance 0.94–0.98, accessibility 1.00, SEO 1.00 on every indexable page, LCP 1.65–1.80 s, TBT 110–252 ms, CLS ≤ 0.066 |

### Self-review (Phase 11 row; spec 13.4)
| Item | Status |
|---|---|
| Search Console integration: daily queries, impressions, clicks, CTR, position into `web_seo_*` | Done (service account; sample data until S-20, D-070) |
| Dashboard: trends, top queries, top pages, rising/falling pages, low-CTR candidates | Done |
| Index coverage and Core Web Vitals "where the API exposes them" | Done as far as the API allows: the Search Console API exports neither report (URL Inspection is per URL and quota-bound), so the dashboard links straight to both; lab Core Web Vitals are budgeted in CI |
| Opportunity finder → one-click draft curated view; question queries → guide ideas | Done |
| Keyword list: priority, mapped page, position tracking, cannibalisation flag | Done |
| Content planner Idea → Brief → Draft → Review → Published → Refresh due | Done |
| Claude-assisted briefs and drafts grounded in catalogue facts and approved claims | Done (template without S-14; Claude drafts rejected on banned claims, D-071) |
| Named human author and reviewer before publishing; no mass-generated pages | Done (database constraint; drafts never self-publish) |
| Refresh-due reminders (age or losing rankings) | Done (past refresh date, clicks down ≥30% from ≥5, or older than 9 months; reason shown per guide; `lib/seo/refresh.ts`) |
| On-page checker on every curated view, university page, resource; before publish and on a schedule; score + fixes | Done (daily + on demand; "before publish" = editor preview + next run, D-072) |
| Internal linking engine with editor approval; related-content blocks kept fresh | Done (D-073, D-075) |
| Redirects and 404 monitor with one-click redirect, redirect-chain detection | Done |
| Local SEO: `LocalBusiness`/`EducationalOrganization` with Indirapuram address, phone, hours; GBP/directory checklist | Done (hours once set, S-51; checklist tracked in admin, S-52) |
| SEO checks in CI: structured data, sitemaps, canonical/robots, redirect map, Lighthouse SEO and performance budgets; fail on regressions | Done (`seo.spec.ts` incl. on-page gate, redirects in e2e, LHCI budgets in `website-ci.yml`) |

### Phase 11 summary
The SEO operation runs from the admin: Search Console data (sample until S-20), opportunities that become draft curated
views or guide ideas, a keyword list with cannibalisation flags, a content planner whose briefs and drafts use catalogue
facts only and can never publish without a named author and reviewer, a daily on-page checker, an approval-based
internal-link engine, a 404 monitor with one-click 301s, and a local SEO checklist. CI fails on on-page errors. Owner
items: S-20 (Search Console), S-50 (authors and reviewers), S-51 (hours), S-52 (Business Profile), S-53 (university intros).

## Phase 12 — Hardening and go-live prep ✅ `website-phase-12-done`

### Plan
1. Security review (`docs/SECURITY_REVIEW.md`): independent read-only review done (no high findings; 4 medium, 13 low).
   Fix every medium and every low that is cheap and safe; record the rest with reasons. `npm audit`.
2. Accessibility audit (`docs/ACCESSIBILITY.md`): axe on every page type in both themes and on phone + laptop,
   keyboard-only and screen-reader walkthrough of the gate, finder, panel, form, Witty and admin.
3. Full end-to-end suite on the final build.
4. Load tests (`docs/LOAD_TESTS.md`, spec 3A): 10,000+ offerings (synthetic catalogue on a local copy), 1,000
   concurrent visitors on cached pages and search, 200 concurrent Witty conversations (mock model provider).
5. Production migration dry-run (`docs/GO_LIVE_DRY_RUN.md`) on the production-schema replica: every web migration in
   order, every APPROVALS item (s01, s02, s03, data/cron proposals), smoke tests, timings, locks; rollback scripts for
   web_ objects and for each shared proposal.
6. `docs/RUNBOOK.md` (operations, incidents, flags, rollbacks), DNS cut-over plan Hostinger → Vercel with rollback,
   go-live checklist.
7. Final report; **stop** for the owner's go-live approval (no production apply, deploy or DNS change).

### Step log
- 12.1 ✅ Security review: 4 medium + 13 low findings, 16 fixed, L12 accepted (D-076). `docs/SECURITY_REVIEW.md`,
  migration `20261017101000_web11_hardening.sql`, D-076–D-079. `npm audit`: production 0; 22 dev-only (Lighthouse CI
  chain, eslint-config-next). Full e2e on the hardened build: 144 passed, 0 failed.
- 12.2 ✅ Accessibility audit: `e2e/a11y.spec.ts` (30 checks: remaining pages, cookie banner, application form states,
  signed-in account, Witty gate and conversation, keyboard). Two focus bugs fixed (panel focus return, banner focus).
  `docs/ACCESSIBILITY.md`.
- 12.3 ✅ Load tests (`docs/LOAD_TESTS.md`, scripts in `scripts/load/`): 10k offerings (search 29–145 ms, zero-result
  255–287 ms; 56 uncached searches/s on 4 vCPU), 1,000 visitors (edge stand-in, ad mix: 359 req/s, pages p95 10 ms,
  0.74% fast 503 on search misses), 200 Witty conversations (800/800 turns, TTFT p50 1.31 s incl. 800 ms model).
  Found and fixed: shared connection pool exhaustion → per-instance DB concurrency cap, batched search log,
  `use cache: remote` for search, optional read replica (D-080, S-54, S-55).
- 12.4 ✅ Production migration dry run (`scripts/db/go-live-dry-run.sh`, report `docs/GO_LIVE_DRY_RUN.md`): fresh
  replica (42/42 rows = production), web1–web11 in 1.24 s with no strong locks on shared tables, all suites green,
  every APPROVALS item applied in go-live order (s01–s07; s04–s07 and the s03 rollback written this phase) with smoke
  tests, full reverse rollback (proposal rollbacks + `scripts/db/rollback-web.sql`) back to the exact baseline.
  `check-shared-proposals.sh` now applies, smoke-tests and rolls back each proposal to an identical state on every
  build. Lead payload already sends `email_verified_at`, `final_program_id/name`, `junk_risk_score` (dropped by
  production until s01 is approved).
- 12.5 ✅ `docs/RUNBOOK.md` (operations, flags, go-live procedure, DNS cut-over Hostinger → Vercel with rollback,
  database rollback, incidents), `docs/GO_LIVE_CHECKLIST.md`, `docs/FINAL_REPORT.md`; Staff management in the admin
  (super admins; last super admin protected); `scripts/db/make-s01.py`; `.env.example` completed.

### Phase gate (17 Oct 2026)
| Check | Result |
|---|---|
| `npm run check` (typecheck, lint, 187 unit tests, copy check) | ✅ |
| `npm run db:gate` (fresh replica 42/42 = production; web1–11: 1,051 security + 18+17+48+43+1+43+26+29+18 checks; shared unchanged; s01–s07 applied, smoke-tested, rolled back to the identical state; local + 31 quality) | ✅ |
| `scripts/db/go-live-dry-run.sh` | ✅ DRY RUN PASSED |
| `npm run build` | ✅ |
| Playwright (laptop + Pixel 7, incl. the new accessibility audit) | ✅ 174 passed, 0 failed (32 skipped by design) |
| Lighthouse CI mobile, 13 paths | ◐ full run: TBT over budget on 3 paths (322–433 ms) on this noisy container; re-run of the four heaviest paths passed (medians 215–285 ms; single runs 172–487 ms). Accessibility 1.00, SEO 1.00 on indexable pages, LCP ≤ 1.84 s, CLS ≤ 0.067 (`PERFORMANCE.md`) |

### Self-review (Phase 12 row; spec 17)
| Item | Status |
|---|---|
| Security review | Done (`SECURITY_REVIEW.md`; 16 of 17 findings fixed, L12 accepted D-076; npm audit production 0) |
| Accessibility audit | Done (`ACCESSIBILITY.md`; 2 focus bugs fixed; manual screen-reader pass recommended) |
| Full end-to-end suite | Done (174 passed) |
| Load tests (3A: 10k offerings, 1,000 visitors, 200 Witty conversations) | Done on this environment (`LOAD_TESTS.md`); found and fixed shared-pool exhaustion (D-080). Production-like repeat is S-55 |
| `docs/RUNBOOK.md` | Done |
| DNS cut-over plan Hostinger → Vercel with rollback | Done (RUNBOOK §6; zone export first, only `@`/`www` change, TTL 300 s, 14-day rollback window) |
| Production migration dry run incl. every APPROVALS item | Done (`GO_LIVE_DRY_RUN.md`; s01–s07, rollbacks for each and for all web_ objects) |
| Final report | Done (`FINAL_REPORT.md`) |
| STOP before go-live | Stopped: nothing applied to production, deployed or changed in DNS |

### Phase 12 summary
The site is hardened (security and accessibility findings fixed), load-tested with protections for the shared
database, and its production rollout is rehearsed end to end on a production-schema replica with a full rollback.
Go-live now waits on the owner: approval itself, the two blocking approvals (A-B2B-1, A-CONSENT-1 after S-44), the
legal texts (S-01) and the go-live setup items.

## After Phase 12 — catalogue sync (owner request, 17 Oct 2026)
- Found: direct catalogue edits (table editor, CRM screens, synonym re-mapping) never reached the website, because the
  change detector trusted `updated_at`/`catalog_version`; university renames were masked by copied display names; brand-new
  courses were hidden silently.
- Fixed in `20261017101100_web12_catalog_sync.sql` (content fingerprint, university-name sync, unmapped alert, health
  fields) + alert email, health `checks.catalog`, dashboard "Programme list sync" card (D-081).
- Tests: `40_web_search` (+4 checks), `e2e/catalog-sync.spec.ts` (direct edit → API and university page), email unit
  test. Gate: check ✅ (188 tests), db:gate ✅, dry run ✅ (web12 74 ms, no shared locks).

## Scheduled jobs moved to Supabase pg_cron (owner decision, 17 Oct 2026)
- Owner chose pg_cron over Vercel Pro. `20261017101200_web13_scheduled_jobs.sql`: `web_job_call(path)` (address from
  `web_settings.internal_base_url`, key from Vault `web_internal_key`, sends nothing until both exist; only
  `/api/internal/*` paths), jobs `web_outbox_worker` (every minute) and `web_seo_daily` (03:00 IST) next to
  `web_catalog_poll`. `vercel.json` has no crons; health and the admin dashboard flag a stalled worker. D-082.
- Production checked read-only: pg_cron 1.6.4, pg_net 0.20.3, Vault present; ~50 CRM jobs already run there.
- Gate: check ✅ (188), db:gate ✅, dry run ✅ (web13 56 ms; jobs scheduled on the replica and removed by the rollback).
