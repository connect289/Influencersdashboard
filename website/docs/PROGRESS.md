# Build progress

**Current phase: 1 — Design system and concepts. Current step: 1.1 (plan written; scaffold + tokens next).**

Resume rule: read this file top to bottom, then continue from the current step. Each phase has a plan, a step log and a
self-review table (Done / Partial / Deferred-with-reason). Tags: `website-phase-N-done` (D-002).

## Environment state (17 Oct 2026)
- Docker daemon started manually (`dockerd`), registry mirror `mirror.gcr.io` in `/etc/docker/daemon.json` (Docker Hub
  rate-limits this environment). Containers do not survive a new session: restart dockerd, then `npx supabase start`.
- Supabase CLI 2.121 (`npm i supabase` in a scratch dir; Phase 2 adds it as a dev dependency) local stack from
  `website/` (ports 54321–54324; started with `-x studio,imgproxy,edge-runtime,logflare,vector,supavisor`).
- `prod-replica` container (port 54330): production-schema replica, built by `scripts/db/build-replica.sh`
  (report: `docs/discovery/replica.md`, being finalised by a background task during Phase 1).
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
- 1.1 ⏳ plan written.
