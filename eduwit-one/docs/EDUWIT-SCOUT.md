# Eduwit Scout (the catalogue engine) in Eduwit One

Eduwit Scout is Eduwit's sixth app, the catalogue engine: it builds a clean, versioned catalogue of every paid
programme (first from degreepartner.com, then other partners) that Witty, the two CRMs, the website and the influencer
portal are meant to read instead of the legacy `public.catalog_*` tables. It lives in its own repository
(`connect289/eduwit-catalogue-engine`; schemas `ce`, `ce_pub`, `ce_admin`; role `ce_worker`; cron jobs `ce-health`,
`ce-prune`, `ce-prune-claims`; workers on GitHub Actions; a dashboard on Vercel; three Edge Functions). Its design stays
there (`docs/decisions.md`, O-* and T-*). This file is Eduwit One's side: what it reads, how, and what is still open.

History: drafted on 29 Oct 2026 (D-095) while Scout was being prepared for production; PR #29 (D-096, D-097) merged
on 30 Oct and its migrations 0022 to 0024 went to production the same day at 09:50 UTC; the owner validated the Setup
item on 2 Nov; trimmed to what is live on 3 Nov (D-131).

## 1. Principles, the same as for the other five apps

- **Read only.** Eduwit One writes nothing into `ce*`; the engine's dashboard and workers stay the only writers.
- **Detection is deterministic SQL**; the AI only explains. A check fails on a fact, never on a model's opinion.
- **Fixes come last and prove themselves first** (D-084). Scout exposes no fix function yet, so there are none.
- **Test identities** follow the engine's convention once it states one (it has no test partners on production).

## 2. What is live

- **The app** `catalogue_engine`, label Eduwit Scout (0022). Its event log (`ce.events`) is copied into `one.events`
  like the other sources: 17 events in the week to 3 Nov. Ask's `app_status` accepts the app and lists its three `ce-*`
  cron jobs.
- **The checks** (`supabase/checks/catalogue_engine.sql`, seeded by 0023), every 15 minutes, on since the owner
  validated `setup:catalogue_engine` on 2 Nov. `one.run_check` executes every check as the database owner, so no grant to
  `eduwit_one_reader` on `ce` or `ce_pub` exists or is needed.

  | Check | Reads                              | Fails when                                                                                     |
  | ----- | ---------------------------------- | ---------------------------------------------------------------------------------------------- |
  | CE-01 | `ce.heartbeat`                     | a component has had no good report for 3 × its interval, or was never once ok                  |
  | CE-02 | `ce.job`                           | a job is `dead` (failed `max_attempts` times)                                                  |
  | CE-03 | `ce.health`                        | a metric's latest row in 24 h has status `alert` (Scout's own alerts, such as `session.expired`) |
  | CE-04 | `ce.job`                           | queued 3 days past `next_run_at`, or running with its lease expired over an hour ago            |
  | CE-05 | `ce.run`                           | a run is `held` (a crawl health gate stopped it before publishing)                             |

  Their first day (2 Nov) opened three true incidents: CE-01 (a worker silent, 16:06 to 17:25 UTC) and CE-04 (the
  queue stuck, 16:40 to 21:10) during the database slowdown, and CE-03, open since 13:43 UTC on the degreepartner
  login's expiries (a real logout at 13:30, a false expiry at 21:04 that Scout's T-113 removed, a real one at 01:52
  on 3 Nov).
- **The panels** on the Apps page (0024): status, versions and queue, read by `one.embed_data` as the database owner
  from `ce_pub.programmes_v1`, `ce_pub.catalogue_versions_v1`, `ce_pub.changes_v1` and `ce.job`, with deep links to
  Scout's dashboard.
- **Heartbeats**: Scout's own, read by CE-01: `worker:<stages>` and `worker:check` (one report per workflow run; their
  expected interval is monthly, the nightly schedule aside) and `db:health_collect` (every 15 minutes).

## 3. What Scout provides, against the first draft's asks

| Ask of 29 Oct                       | What exists on 3 Nov                                                                                                                                                         |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. `ce.health()` returning jsonb     | `ce_pub.engine_status()` (server keys only, Scout T-111, D-125) and the `ce.health` table (one row per metric and partner, status `ok` or `alert`), which CE-03 reads.  |
| 2. Grants to `eduwit_one_reader`    | Not needed: checks and panels run as the owner. `ce_pub` is readable by `service_role` only; signed-in accounts are refused (T-111).                                          |
| 3. Publication and programme views  | `ce_pub.catalogue_versions_v1`, `programmes_v1`, `institutions_v1`, `programme_document_v1`, `changes_v1`, `partners_v1`; functions `catalogue()`, `catalogue_changes_since()`, `engine_status()`. |
| 4. The worker heartbeat table       | `ce.heartbeat` (`component`, `last_ok_at`, `last_error_at`, `last_error`, `expected_interval_s`).                                                                             |
| 5. Stable statuses                  | `ce.job.status`: `queued`, `running`, `succeeded`, `failed`, `dead`, plus `paused` (a job waiting for a portal login, T-54) and `cancelled`; `ce.run.status` includes `held`. |
| 6. Test rows                        | None on production; `ce.partner.pilot` marks pilots. Open until Scout states a convention.                                                                                   |
| 7. Dashboard `/api/health`          | Not present. See §4.                                                                                                                                                         |

## 4. Open

- **A heartbeat for Scout's dashboard.** No `/api/health` route exists. The Vercel heartbeat pattern of D-129
  (`vercel:one`, `vercel:website`: the newest built production deployment) would cover Scout's dashboard without any
  change in Scout, once the owner adds Scout's Vercel project to the token Eduwit One holds. An ask to the owner.
- **CE-06 to CE-08**, proposals only: an approved trusted source whose fetch keeps failing (`ce.trusted_source`),
  Scout's three cron jobs checked by name (today a failure of any cron job surfaces through the PLAT checks over
  `cron.job_run_details`, not by Scout's name), and a published-catalogue sanity check (an active offer with no fee or
  duration, or two values for one concept). Each is one row in `catalogue_engine.sql` when wanted.
- **Consumer switch-over checks** (`setup:catalogue_switchover`): nothing reads `ce_pub` yet, so none exist. CAT-01 to
  CAT-04 stay the truth for the legacy catalogue. `catalog.changes` holds no rows (the legacy list is frozen, Scout's
  O-6), so CAT-02 and CAT-03 are idle, not blind: checked on 3 Nov, the owner role reads the table and its newest row is
  null. When a consumer moves to `ce_pub`, its check compares that consumer's version marker with
  `ce_pub.catalogue_versions_v1`.
- **Fixes on the engine**: none. When Scout exposes a safe function (re-queue a dead job, re-run a stage), it enters
  under the proof-before-power rules (D-084): dry-run first, one row until a run holds.

Nothing else: no calls from the engine into Eduwit One, no shared secrets, no `one_*` names in the engine.
