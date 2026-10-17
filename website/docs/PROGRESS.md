# Build progress

**Current phase: 7 — Gate, email verification, accounts, forms. Current step: 7.1 (plan).**

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
