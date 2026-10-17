import type { Guide } from "../types";

export const DEVELOPER: Guide = {
  slug: "developer",
  audience: "developer",
  title: "Developer guide",
  summary: "Architecture, local set-up, conventions, testing, background jobs, and how deployment and go-live work.",
  sections: [
    {
      id: "architecture",
      title: "Architecture",
      blocks: [
        {
          list: [
            "**Next.js 16** (App Router, React 19, TypeScript strict) with three portals: `app/(admin)`, `app/(creator)`, `app/(agency)`, plus `app/(auth)` and the public media kit `app/m`.",
            "**Supabase Postgres** is shared with Witty and both CRMs. Every portal object lives in schema `inf`; the shared objects the portal reads are reproduced locally from a read-only baseline.",
            "Authorisation is enforced in the database: RLS on every `inf` table, `SECURITY DEFINER` functions that check `inf.has_perm()`, the creator's identity or an agency grant. The UI hides what a role cannot use but never relies on hiding.",
            "Student phone numbers and emails never reach creators or agencies: they read lead data only through functions that mask it in the database.",
            "**Compensation** is a pure TypeScript engine (`lib/compensation`): a deterministic replay of a deal's versions and events that returns the ledger it should have, with stable keys. The runner (Phase 7) diffs it against posted entries; the dry-run and simulator reuse it.",
            "Background work runs through `inf.jobs` (claimed with SKIP LOCKED by `/api/internal/jobs`, called every minute by pg_cron with an internal key).",
          ],
        },
      ],
    },
    {
      id: "setup",
      title: "Local set-up",
      blocks: [
        {
          steps: [
            "Install Node 20.9 or later and Docker.",
            "In `influencer-portal/`: `npm ci`.",
            "Start the local database: `node scripts/db.mjs start`, then `node scripts/db.mjs reset` (shared baseline + every `inf` migration).",
            "Copy `.env.example` to `.env.local` and fill the local URL and keys from `npx supabase status`.",
            "Seed demo data: `npm run seed` (staff password `Local-Demo-Password-2026`; emails land in Mailpit on port 54424).",
            "Run `npm run dev` and open http://localhost:3200. Staff sign in at /login/staff, creators at /login.",
          ],
        },
        {
          warning:
            "Never point local tools at the live Supabase project. Scripts refuse remote targets, and `lib/env.ts` refuses a service key that does not belong to the configured project.",
        },
      ],
    },
    {
      id: "commands",
      title: "Commands",
      blocks: [
        {
          table: {
            head: ["Command", "What it does"],
            rows: [
              [
                "`npm run typecheck` · `npm run lint` · `npm run format`",
                "Static checks (no `any`, strict type-checked lint, Prettier)",
              ],
              ["`npm test`", "Vitest: engine, simulator, schemas, codegen drift, message keys, guides, contrast"],
              ["`npm run test:db`", "pgTAP files in `supabase/tests` (RLS per role, masking, workflows)"],
              ["`npm run e2e`", "Playwright journeys against a production build; resets and seeds the local DB first"],
              [
                "`npm run gen:sql`",
                "Regenerates migrations from the permission matrix, settings registry, compensation schema and system presets",
              ],
              ["`node scripts/db.mjs types`", "Regenerates `lib/database.types.ts` after a schema change"],
            ],
          },
        },
      ],
    },
    {
      id: "conventions",
      title: "Conventions",
      blocks: [
        {
          list: [
            "**Migrations**: new files only, never edit an applied one. Every function sets `search_path = ''`. Grants go into `inf.client_grants` and are applied with `call inf.apply_client_grants();`.",
            "**Ownership checks** must be null-safe: `coalesce(p_creator = inf.current_creator_id(), false)`.",
            "**Generated SQL**: permissions, settings, the compensation JSON Schema and system presets come from TypeScript via `npm run gen:sql`. A test fails if a generated migration is stale.",
            "**Server actions**: zod schema in `lib/<domain>/schemas.ts` → one RPC → map database errors to message keys → `ActionResult`. Client components call them with `useAction()`.",
            "**Money** is integer paise; percentages become basis points; banker's rounding once per line. Store UTC, display IST and Indian formats.",
            "**PII**: PAN and bank numbers through `inf.pii_encrypt/decrypt` (Vault key `inf_pii_key`); only audited reveal functions return them.",
            "**Text**: UI strings live in `messages/en.json` (a test checks every key used in code exists). Guides live in `lib/guides/content`.",
            "**No placeholders**: a screen ships only when its feature works; mock data only in the seed.",
          ],
        },
      ],
    },
    {
      id: "deals",
      title: "Deals and the compensation engine",
      blocks: [
        {
          list: [
            "`lib/compensation/schema.ts`: the zod schema of a deal version's config (fixed fees, commission, floors, recoupment, bonuses, penalties, fees, non-cash). Stored as JSONB and checked again by `inf.comp_config_valid()`.",
            "`engine.ts`: `computeLedger()` replays versions + events to `as_of`. Ledger keys are `<version>:<rule>:<subject>:<kind>`; `diff.ts` turns desired vs posted into new lines, confirmations and reversals.",
            "`simulator.ts` builds a synthetic event stream from a scenario; `tax.ts` estimates TDS and GST from the section table.",
            "Deal versions are immutable rows; a change after agreement is a new proposed version (amendment).",
          ],
        },
      ],
    },
    {
      id: "contracts",
      title: "Contracts",
      blocks: [
        {
          list: [
            "Document model (`lib/contracts/doc.ts`): a whitelisted subset of the Tiptap JSON (paragraphs, headings 2–4, lists, bold/italic/underline; tables only from deal data). We render it ourselves (`html.ts`, `pdf.tsx`, `components/contracts/doc-view.tsx`); stored HTML is never trusted.",
            "Templates (`template.ts`): `{{path}}` variables from the catalogue in `variables.ts`, block and inline `{{#if}}…{{else}}…{{/if}}` / `{{#unless}}`. `assemble.ts` builds a version's content from a template, the clause versions and the deal context; `build.ts` adds the HTML. Pure and unit-tested.",
            "Generation (`generate.ts`): loads `inf.contract_source(deal)` and `inf.template_source`, keeps agreed overrides of negotiable clauses, and calls `inf.contract_version_add`, which hashes the HTML (SHA-256) in the database. Missing values are stored on the version and block sending.",
            "Counter-offers (`counter.ts`): stable keys for every number in a config; `applyCounter` returns a validated new config that becomes a deal version (`origin = counter_offer`).",
            "Signing (`lib/actions/signing.ts`): the action authenticates the person and calls `contract_sign_code_issue` / `contract_sign` as the service role with that person's id, IP and user agent. Codes are hashed with a per-code salt; 5 attempts, 10-minute expiry, resend cooldown and an hourly cap.",
            "After the countersignature `finalize.ts` renders the PDF with a signature certificate, uploads it write-once to the `inf-contracts` bucket and records its hash (`contract.finalize` job as the safety net). `/api/contracts/[id]/pdf` re-verifies both hashes on every download and flags the contract on a mismatch.",
            "Clause seeds: `lib/contracts/library.ts` → `npm run gen:sql` (insert-only migration).",
          ],
        },
      ],
    },
    {
      id: "content",
      title: "Briefs, deliverables and compliance",
      blocks: [
        {
          list: [
            "`lib/content/workflow.ts` is the deliverable state machine (stages can be switched off). The database mirrors it in `inf.deliverable_next` / `inf.deliverable_pending`; `supabase/tests/017_workflow_matrix.sql` is generated from the TypeScript (`npm run gen:sql`) and checks every status × action × stage combination, and a unit test fails if it is stale.",
            "Every move goes through `inf.deliverable_apply` (transition row, event, timestamps). Submissions are immutable except their decision; file paths must sit under `<deliverable id>/`.",
            "Compliance (`compliance.ts`): banned-claim scan with safe regex checks and the disclosure check. The server records results with the service role (`inf.compliance_record` refuses anyone else) so a client cannot report a clean scan.",
            "Uploads (`components/content/uploader.ts`): one-time signed uploads to the private `inf-deliverables` bucket; files over 6 MB use Supabase's resumable (TUS) endpoint with the signed token. Links are signed for an hour after an `inf.*_allowed` check.",
            "Penalties: going live, cancelling or failing the disclosure check enqueues `penalties.refresh`, which runs the compensation engine (`lib/content/events.ts`) and syncs `inf.penalty_proposals`. Approval is manual; the ledger posts approved ones (Phase 7).",
            "Nightly: `inf.content_remind()` (due, overdue, escalation and metrics reminders) runs inside `inf.nightly_prune()`.",
          ],
        },
      ],
    },
    {
      id: "jobs",
      title: "Background jobs and notifications",
      blocks: [
        {
          list: [
            "Enqueue with `inf.job_enqueue(kind, payload, run_at, idem_key)`; handlers are registered in `lib/jobs/registry.ts` and must be idempotent.",
            "Notifications: `inf.notify()` writes the in-app row and queues email/WhatsApp copies. Providers are adapters (SMTP, Resend, Brevo, Meta Cloud, mock); nothing leaves the system unless `LIVE_MODE=on`.",
            "[System status](/admin/system) shows the queue, scheduled tasks and providers.",
          ],
        },
      ],
    },
    {
      id: "deploy",
      title: "Deployment and go-live",
      blocks: [
        {
          p: "Go-live is a controlled, owner-approved step. `docs/RUNBOOK.md` holds the checklist: marking the shared baseline as already applied (never running it), exposing schema `inf` to the Data API, Vault secrets (back up `inf_pii_key` immediately), auth settings, legal and CA sign-offs, then applying only the `inf` migrations, deploying, and connecting attribution.",
        },
        {
          list: [
            "Hosting: a Next.js host (Vercel planned) with the variables from `.env.example`.",
            "Providers: email (Resend, Brevo or SMTP), WhatsApp (Meta Cloud API), Sentry, a domain. Until they are supplied the app runs on mock adapters.",
            "Every change to production is preceded by a dry-run report and has a rollback script.",
          ],
        },
      ],
    },
    {
      id: "docs",
      title: "Where to find more",
      blocks: [
        {
          list: [
            "`CLAUDE.md` (repo root): conventions, commands and how to resume work.",
            "`docs/PROGRESS.md`: the phase plan and requirement checklists; `docs/DECISIONS.md`: every design decision with its reason.",
            "`docs/INFLUENCER_PORTAL_SPEC.md`: the product spec; `docs/ERD.md`, `docs/INTEGRATION_CONTRACTS.md`, `docs/SHARED_CHANGES.md`: data model and shared-database contracts.",
          ],
        },
      ],
    },
  ],
};
