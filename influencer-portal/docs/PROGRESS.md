# Progress

## Now

- **Current phase:** Phase 0 (Discovery and design): **complete, at HARD STOP 1**, waiting for the owner's approval.
- **Current step:** none. Waiting for answers to the open questions in `PHASE0_FINDINGS.md` §7 and approval of
  `ERD.md`, `SHARED_CHANGES.md`, `LEAD_FIELD_WHITELIST.md`, `STAGE_MAPPING.md` and `INTEGRATION_CONTRACTS.md`.
- **Next:** Phase 1 (Foundation), plan in `PHASE0_FINDINGS.md` §8. Starts only after approval.
- **Blockers:** owner approval (HARD STOP 1). Provider credentials, domain, Vercel and Sentry are needed later (HARD STOP 4)
  but don't block Phase 1, which uses mocks.

## Phase 0: Discovery and design

### Plan

| Step | What | Output |
| --- | --- | --- |
| 0.1 | Inspect the production database read-only: tables, columns, functions (`lead_intake`), triggers, RLS, grants, catalogue, Witty's code storage, CRM status sources, commission data, cron, storage, auth, advisor | Findings §2–§3 |
| 0.2 | Inspect the B2B and B2C apps for conventions | Findings §4 |
| 0.3 | Proposed ERD | `ERD.md` |
| 0.4 | Shared-object changes with justification | `SHARED_CHANGES.md` |
| 0.5 | Creator-visible lead field whitelist | `LEAD_FIELD_WHITELIST.md` |
| 0.6 | Stage mapping proposal | `STAGE_MAPPING.md` |
| 0.7 | Integration contracts | `INTEGRATION_CONTRACTS.md` |
| 0.8 | Tech decisions, risk register, open questions | Findings §5–§7 |
| 0.9 | State files: `PROGRESS.md`, `DECISIONS.md`, root `CLAUDE.md` | |

No migrations, no app code and no tests in Phase 0 (the spec says "no app code yet"). The phase gate items that need code
(migrations, typecheck, lint, tests, seed) start in Phase 1. The Mermaid diagrams were parse-checked with `mermaid@11.4.1`.

### Requirement checklist (spec Section 22, Phase 0, and Section 23)

| Requirement | Status | Where / note |
| --- | --- | --- |
| Inspect all tables, columns | Done | Findings §2; 141 `student_leads` columns in the whitelist |
| Inspect functions, especially `lead_intake()` | Done | Findings §3.1 (full source read) |
| Inspect triggers | Done | Findings §3.2 |
| Inspect RLS (and grants) | Done | Findings §3.3, `SHARED_CHANGES.md` §E |
| Inspect the `catalog_*` structure | Done | Findings §2; `catalog.*` views including `partner_rates_v` |
| How Witty stores source and referral codes | Done | `INTEGRATION_CONTRACTS.md` §1.1 |
| Where CRM and partner lead statuses live | Done | `STAGE_MAPPING.md` §1 |
| Whether Eduwit commission received per enrollment is recorded | Done | `INTEGRATION_CONTRACTS.md` §3 |
| Inspect existing Next.js apps for conventions | Done | Findings §4 |
| `PHASE0_FINDINGS.md` | Done | |
| Proposed ERD (Mermaid) | Done | `ERD.md` (8 diagrams, parse-checked) |
| Full list of shared-object changes with justification | Done | `SHARED_CHANGES.md` |
| Creator-visible lead field whitelist | Done | `LEAD_FIELD_WHITELIST.md` (5 ASK rows for the owner) |
| Stage-mapping proposal | Done | `STAGE_MAPPING.md` |
| Integration contracts (Witty code format, CRM stage events, commission receipts) | Done | `INTEGRATION_CONTRACTS.md` |
| Final tech decisions list | Done | Findings §5 |
| Risk register | Done | Findings §6 |
| Ask every open question the codebase can't answer (Section 23) | Done | Findings §7: Q1, Q3, Q4 answered; Q10 recommended; Q2, Q5–Q9, Q11–Q20 asked |
| Justify `inf_` prefix vs dedicated schema (spec 2.1) | Done | D-01 |
| Pull the production schema into a local or branch database (build prompt, environment rule 1) | Deferred to Phase 1 step 2 | It is part of setting up the dev database, which is Phase 1 work; approach needs Q13 |

### Phase 0 summary

- **Built:** the eight Phase 0 documents, the decisions log, this file, the root `CLAUDE.md`, the brand palette and the
  logo file. Nothing was changed in any database.
- **Key decisions (pending approval):** schema `inf`; Next.js 16; read-only sweeps instead of a trigger on
  `student_leads`; Route A (portal calls Witty's own code issuer) plus Route B (Witty recognises typed codes);
  commission receipts derived from both CRMs.
- **Known issues found:** legacy influencer objects expose students' full rows to 3 legacy accounts and store plain-text
  passwords (`SHARED_CHANGES.md` §E); leaked-password protection is off; shared Supabase Auth means creators will hold
  `authenticated` JWTs on the same project as every other product (RK-2).
