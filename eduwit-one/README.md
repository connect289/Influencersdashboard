# Eduwit One

The sixth app in Eduwit's stack. It monitors, tests, alerts on, partly repairs and proposes improvements for Witty, the
B2B CRM, Spark, the website and the influencer portal, and gives one UI over their admin, marketing and analytics
screens. The specification and the prerequisites doc are binding; this folder's `docs/` hold the build's state.

| Path | What |
| --- | --- |
| `config/defaults.json` | Non-secret hosts, ids and identities: the single source that seeds `one.settings` |
| `config/setup-items.json` | The Setup checklist: every deferrable item and what it unblocks |
| `scripts/preflight.ts` | Re-runnable access preflight (`npm run preflight`; in the cloud build environment prefix `NODE_USE_ENV_PROXY=1`) |
| `supabase/` | Schema `one`: migrations with rollbacks, the seed, `tests/local/` fixture tests and `tests/smoke.sql` |
| `scripts/db/` | `local-test.sh` (throwaway cluster), `rehearse.sh` (staging), `dump.sh` and `apply.sh` (production), `guards.ts` |
| `.env.example` | Every environment variable name the scripts read, no values |
| `web/` | The Next.js app (from phase 2; brand assets in `web/public/brand/`) |
| `docs/DECISIONS.md` | Decision log and the database survey: the resumable state |
| `docs/PHASES.md` | Phase acceptance criteria and their status |
| `docs/PREFLIGHT.md` | Access preflight findings |
| `docs/CHANGES.md` | Change log |
| `docs/REHEARSALS.md` | Passed rehearsals by migration-set hash; `apply.sh` requires a row |

Never run anything in this folder against production except the read-only preflight, `scripts/db/dump.sh`, and
`scripts/db/apply.sh` after a dump and a passed rehearsal (D-010). Order: `npm run db:local-test` →
`scripts/db/rehearse.sh` → `scripts/db/dump.sh` → `scripts/db/apply.sh <file>…` → inspect the tick report.
