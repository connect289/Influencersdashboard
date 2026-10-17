# Build progress

**Current phase: 2 — Foundation. Current step: 2.1 (plan).**

Resume rule: read this file top to bottom, then continue from the current step. Each phase has a plan, a step log and a
self-review table (Done / Partial / Deferred-with-reason). Tags: `website-phase-N-done` (D-002).

## Environment state (17 Oct 2026)
- Docker daemon started manually (`dockerd`), registry mirror `mirror.gcr.io` in `/etc/docker/daemon.json` (Docker Hub
  rate-limits this environment). Containers do not survive a new session: restart dockerd, then `npx supabase start`.
- Supabase CLI 2.121 (`npm i supabase` in a scratch dir; Phase 2 adds it as a dev dependency) local stack from
  `website/` (ports 54321–54324; started with `-x studio,imgproxy,edge-runtime,logflare,vector,supavisor`).
- `prod-replica` container (port 54330): production-schema replica, built by `scripts/db/build-replica.sh` (~50 s);
  **all 42 fingerprint rows match production** for public, b2b, b2c, catalog (report: `docs/discovery/replica.md`).
- Video recording: Playwright 1.64 wants ffmpeg-1013; use `PLAYWRIGHT_BROWSERS_PATH=<dir>` with
  `ffmpeg-1013/ffmpeg-linux -> /usr/bin/ffmpeg` (apt `ffmpeg` installed) — see `web/scripts/record-concepts.mjs`.
- Stopping the prod server: `fuser -k 3100/tcp` (never `pkill -f "next …"` — it matches the calling shell).
- Chromium for Playwright: `/opt/pw-browsers/chromium` (pass `executablePath`; do not run `playwright install`).
- `eduwit.in` is blocked by the environment's network policy (D-006, S-01).

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
- Offering deep link: `/programmes?…&offering=<catalog_programs.id>` (numeric id; `program_key` fallback resolves renamed
  rows).
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

## Phase 2 — Foundation

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
- 2.1 ⏳ plan written.
