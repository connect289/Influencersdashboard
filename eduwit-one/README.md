# Eduwit One

The sixth app in Eduwit's stack. It monitors, tests, alerts on, partly repairs and proposes improvements for Witty, the
B2B CRM, Spark, the website and the influencer portal, and gives one UI over their admin, marketing and analytics
screens. The specification and the prerequisites doc are binding; this folder's `docs/` hold the build's state.

| Path | What |
| --- | --- |
| `config/defaults.json` | Non-secret hosts, ids and identities: the single source that seeds `one.settings` |
| `config/setup-items.json` | The Setup checklist: every deferrable item and what it unblocks |
| `scripts/preflight.ts` | Re-runnable access preflight (`npm run preflight`; in the cloud build environment prefix `NODE_USE_ENV_PROXY=1`) |
| `supabase/` | Schema `one`: migrations with rollbacks, seeds, SQL tests (from phase 1) |
| `web/` | The Next.js app (from phase 2; brand assets in `web/public/brand/`) |
| `docs/DECISIONS.md` | Decision log and the database survey: the resumable state |
| `docs/PHASES.md` | Phase acceptance criteria and their status |
| `docs/PREFLIGHT.md` | Access preflight findings |
| `docs/CHANGES.md` | Change log |

Never run anything in this folder against production except the read-only preflight and the documented apply script
after a dump (see `docs/DECISIONS.md` D-010).
