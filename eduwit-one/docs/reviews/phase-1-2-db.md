# Phase 1 and 2 (database layer) review

Second fresh, adversarial review of the Eduwit One database layer at HEAD `7c1b14f` on `claude/festive-babbage-7yhhx8`,
after the builder fixed B1 and M1 to M8 of `docs/reviews/phase-1.md`. The first review was not used as a guide; its
findings are referred to only where a fix is incomplete.

Scope: `supabase/migrations/*.sql` and every `.rollback.sql`, `supabase/checks/*.sql` (the sources of the generated
migration 0006), `supabase/tests/local/*.sql`, `supabase/tests/smoke.sql`, `scripts/db/*` and their tests,
`config/settings.json`, `config/defaults.json`. Rubric: spec §2, §5, §6, §7, §9, §13, §16, §17, D-001..D-046.

How it was checked, offline only: reading the code; `scripts/db/local-test.sh`, `npm test`, `npm run typecheck`,
`node scripts/db/guards.ts`, `node scripts/db/gen-checks.ts --check`; and probe scripts on throwaway local clusters
built the way `local-test.sh` builds its own (same stubs, same migrations, local PostgreSQL 16). App object shapes were
read from `b2b-crm/`, `b2c-crm/`, `influencer-portal/` and the website branch's production snapshot where needed. No
remote database, connector or network tool was used. A finding marked "verified" was reproduced on a local cluster or
traced through the code path end to end; anything else says "unverified" and why.

Severity: blocker = must be fixed before the production apply; major = a real failure on production that the phase
criteria would not catch; minor = a defect with limited reach or an unlikely trigger.

## Findings

| ID | Severity | File:line | Finding | Failure scenario |
| --- | --- | --- | --- | --- |
