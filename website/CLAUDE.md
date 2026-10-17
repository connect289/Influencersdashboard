# eduwit.in website — working notes for Claude Code

**To resume: read `docs/PROGRESS.md` and continue from the current step.** The spec is `docs/WEBSITE_SPEC.md` (source of
truth). Decisions made without the owner are in `docs/DECISIONS.md`; shared-object changes awaiting approval in
`docs/APPROVALS_NEEDED.md`; credentials and accounts needed in `docs/SETUP_CHECKLIST.md`.

## Hard rules (never break)
- Production Supabase `xlseqwgyjuqhktrguhyc` is LIVE and shared with Witty, the B2B CRM, the B2C CRM (Spark) and the
  Influencer Portal. **Only read it** (SELECT / catalog inspection). Never apply migrations, never write, never deploy,
  never change DNS until the owner approves go-live.
- Never modify `../b2b-crm`, `../b2c-crm`, Witty's n8n workflows or Chatwoot.
- Website-owned objects use the `web_` prefix (tables, functions) and live in schema `public` unless noted in
  `docs/SCHEMA_PLAN.md`. Migrations are additive only. Any change to a shared object goes in its own migration file under
  `supabase/migrations-shared/` (dev only) and is listed in `docs/APPROVALS_NEEDED.md`.
- Leads are created/updated only through the approved path (see `docs/SCHEMA_PLAN.md` §Leads). Never write
  `student_leads` directly.
- No invented facts: fees, approvals, durations, eligibility come only from the catalogue. Missing → show nothing or
  "Ask an advisor". Never expose partner commission or internal fields.
- No PII in URLs, logs or analytics events.
- Public name of the website agent is **Witty**; internal code name is **`web_advisor`** (code, DB, env, flags, logs).
  Never show `web_advisor` to students.

## Layout
- `web/` — Next.js 16 app (App Router, RSC, Server Actions, Cache Components), TypeScript strict, Tailwind 4.
  Vercel root directory = `website/web`, region `bom1`.
- `supabase/` — `config.toml` (local stack), `migrations/` (website migrations; `00000000000000_prod_snapshot.sql` is the
  read-only snapshot of the shared objects the site depends on and is **never applied to production**),
  `migrations-shared/` (proposed shared changes, dev only), `tests/` (SQL tests, run in `begin … rollback`),
  `seed/` (catalogue export + website seed content), `prod-snapshot/` (raw read-only snapshots).
- `scripts/db/` — `build-replica.sh` (full production-schema replica on port 54330), `fingerprint.sql`.
- `docs/` — spec, progress, decisions, plans, runbook.

## Commands (run from `web/`)
- `npm run dev` · `npm run build` · `npm run typecheck` · `npm run lint` · `npm test` (Vitest) · `npm run e2e` (Playwright)
- `npm run check` = typecheck + lint + unit tests (run after every step).
- Local Supabase (from `website/`): `npx supabase start` / `npx supabase db reset` (applies `supabase/migrations` + seed).
  Local URLs: API http://127.0.0.1:54321, DB postgresql://postgres:postgres@127.0.0.1:54322/postgres,
  Mailpit http://127.0.0.1:54324.
- Docker: if the daemon is not running, start it with `dockerd > /tmp/dockerd.log 2>&1 &` (registry mirror
  mirror.gcr.io is configured in /etc/docker/daemon.json because Docker Hub rate-limits this environment).
- SQL tests: `npm run db:test` (runs every `supabase/tests/*.sql` against the local DB and the replica).

## Conventions (match the CRMs where sensible)
- `lib/` holds pure, tested logic (`*.test.ts` next to it); `lib/server/` holds server-only code (`import "server-only"`).
- Supabase service-role client only on the server; the browser never sees a service key.
- DB functions: `SECURITY DEFINER`, `set search_path = ''`, fully-qualified names, `p_*` params or a single `p jsonb`,
  no `anon` execute unless explicitly a public read.
- Env via `lib/server/env.ts`; `siteUrl()` from `NEXT_PUBLIC_SITE_URL`, never request headers.
- Copy lives in `content/` constants or `web_` tables (admin), not scattered inline.
- Commit after every completed step; tag phases `website-phase-N-done`.
