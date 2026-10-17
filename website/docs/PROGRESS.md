# Build progress

**Current phase: 0 — Discovery. Current step: 0.2 (discovery reports in progress).**

Resume rule: read this file top to bottom, then continue from the current step. Each phase has a plan, a step log and a
self-review table (Done / Partial / Deferred-with-reason). Tags: `website-phase-N-done`.

## Environment state (17 Oct 2026)
- Docker daemon started manually (`dockerd`), registry mirror `mirror.gcr.io` in `/etc/docker/daemon.json`.
- Supabase CLI 2.121 local stack running from `website/` (ports 54321–54324; studio, imgproxy, edge-runtime, logflare,
  vector and supavisor excluded with `-x`).
- `prod-replica` container (port 54330): production-schema replica (see `docs/discovery/replica.md`).
- `eduwit.in` is blocked by the environment's network policy (D-006, S-01).

---

## Phase 0 — Discovery (read-only)

### Plan
1. Set up `website/` (spec copy, logo), local Supabase stack, state docs (`CLAUDE.md`, this file, `DECISIONS.md`,
   `SETUP_CHECKLIST.md`, `APPROVALS_NEEDED.md`).
2. Discovery tracks (parallel, read-only): production database (`catalog_*`, `student_leads`, `lead_intake()`, messages,
   `w2_*`), Witty's agent (prompts, tools, contract), CRM code conventions, production-schema replica.
3. Crawl the current site → blocked; crawler script prepared (D-006).
4. Write `PHASE0_FINDINGS.md`, `TAXONOMY_PROPOSAL.md`, `SCHEMA_PLAN.md`, `ARCHITECTURE.md`, `AGENT_ARCHITECTURE.md`,
   `URL_REDIRECT_MAP.md`, `TECH_DECISIONS.md`, `RISKS.md`; answer Section 18 questions.
5. Phase gate, self-review, summary, tag `website-phase-0-done`.

### Step log
- 0.1 ✅ `website/` created; spec copied to `docs/WEBSITE_SPEC.md`; logo saved to `web/public/brand/` source; Supabase CLI
  stack running; Next 16 app dependencies installed in `web/`; crawler written; `CLAUDE.md`, `DECISIONS.md`,
  `SETUP_CHECKLIST.md` started.
- 0.2 ⏳ discovery reports: CRM conventions ✅ (`docs/discovery/crm-conventions.md`); database, Witty, replica in progress.
