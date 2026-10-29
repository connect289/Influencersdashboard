# Eduwit Scout (the catalogue engine) in Eduwit One

Eduwit Scout is Eduwit's sixth app, the catalogue engine: it builds a clean, versioned catalogue of every paid
programme (first from degreepartner.com, then other partners) that Witty, the two CRMs, the website and the influencer
portal are meant to read instead of the legacy `public.catalog_*` tables. It is designed and built in its own repository
(`connect289/eduwit-catalogue-engine`, a repository named before the product was; schemas `ce`, `ce_pub`, `ce_admin`;
role `ce_worker`; cron jobs `ce-health`, `ce-prune`, `ce-prune-claims`; workers on GitHub Actions; a dashboard on
Vercel; three Edge Functions). On 29 Oct 2026 it is applied to staging and prepared for production; nothing of it exists
on production yet.

This file is Eduwit One's side of the integration: what it will watch and operate, how, and the few stable names it
needs from Scout ("the engine" below). It changes nothing in the engine and nothing in the five apps. The engine's own
design stays in its repository (`docs/decisions.md`, O-1 to O-28 and T-1 to T-103 there).

> **Name (29 Oct 2026, D-100).** The owner named the product **Eduwit Scout**. In Eduwit One the name is what people
> see: the app's label, its Setup item, its Apps page entry, the checks' app name and these docs. The technical
> identifiers stay as they are unless Scout's own session changes them: schemas `ce`, `ce_pub` and `ce_admin`, the check
> ids `CE-01` onwards and the app key `catalogue_engine` of PR #29. Nothing in production carries either name yet.

> **Status, 29 Oct 2026 (D-095).** Scout's design session had already built part of this on branch
> `claude/jolly-hopper-hrwqbd` (26 Oct): the app `catalogue_engine` with five checks off until a Setup item, an event
> source, three Apps page panels and runbook sections. It is PR #29, renumbered to migrations 0022, 0023 and 0024 and
> decisions D-096 and D-097 after the production branch took 0021 for the command centre. Its labels still read
> "Catalogue Engine" until that session renames them (it was told on 29 Oct). When it merges, this file is trimmed to
> what it does not cover: the heartbeats, the switch-over checks and the asks in §3 that Scout has not decided.

## 1. Principles, the same as for the other five apps

- **Read only, by Eduwit One's own role.** `eduwit_one_reader` gets `USAGE` on `ce` and `ce_pub` and `SELECT` on the
  relations the checks name, granted by Eduwit One's own migration (the fingerprint allow-list permits exactly that).
  Nothing is written into `ce*`; the engine's dashboard stays the only writer.
- **Detection is deterministic SQL**; the AI only explains. A check fails on a fact (a job dead, a publication older than
  its cadence, a consumer behind), never on a model's opinion.
- **Gated until the engine is live.** Every CE check carries `disabled: setup:catalogue_engine`, a Setup item the owner
  validates once the engine's production go-live (its `docs/go-live.md`, nine steps) is done. Until then the checks are
  off, so a missing `ce` schema opens nothing.
- **Fixes come last and prove themselves first** (D-084): a fix on the engine (re-queue a dead job, re-run a stage) is a
  later phase, dry-run for two weeks, one row until a run holds, and only if the engine exposes a safe function for it.
- **Test identities** follow the engine's convention once it states one; until then Eduwit One's tests do not touch the
  engine (no synthetic claims, no test partner).

## 2. What Eduwit One will add

This draft had Scout's checks join the app `catalogue` (CAT-01 to CAT-04, the legacy catalogue and the consumers'
caches). PR #29 registers Scout as its own app instead, key `catalogue_engine`, label Eduwit Scout; that choice wins
when it merges, and the Operate page then shows the chain across the two apps: the engine, the published catalogue,
each consumer's sync.

### Checks (new, gated by `setup:catalogue_engine`)

| Check                            | Reads                                                   | Fails when                                                                                                                 |
| -------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| CE-01 Engine health              | `ce.health()` (rpc; see §3)                             | `ok` is false: a dead job, a worker silent, a stage stuck, a publication rollback pending                                  |
| CE-02 Dead or stuck jobs         | `ce.job`                                                | a job `dead`, or `running` longer than `ce_job_max_min` (60), or `queued` longer than `ce_queue_max_min` (180)             |
| CE-03 Publication freshness      | `ce_pub` publication view                               | the latest publication for an active partner is older than `ce_publish_max_days` (14) while unpublished facts exist        |
| CE-04 Conflicts waiting          | `ce.conflict`                                           | open conflicts older than `ce_conflict_max_days` (7)                                                                       |
| CE-05 Facts expiring unsupported | `ce.fact`                                               | published facts closed by `ce.facts_expire` in the last day above `ce_expired_max` (20)                                    |
| CE-06 Trusted source failing     | `ce.trusted_source`                                     | an approved source whose last fetch failed for `ce_source_fail_days` (3) (NIRF's 403 is the first case)                    |
| CE-07 Engine cron jobs           | `cron.job`, `cron.job_run_details`                      | `ce-health`, `ce-prune` or `ce-prune-claims` missing, inactive, or last run failed                                         |
| CE-08 Published catalogue sanity | `ce_pub` programme view                                 | an active offer with no fee, no duration, or two values for one concept (the Excel's "one concept, one column" rule, O-27) |
| HB-ce:worker                     | `ce` worker heartbeat (see §3)                          | no `beat()` within its expected interval                                                                                   |
| HB-ce:dashboard                  | the dashboard's `/api/health` (HTTP probe from the app) | not answering; expected every 300 s                                                                                        |

Thresholds live in `config/settings.json` → `thresholds` (engineer-editable) like the others. Severities: CE-01, CE-07,
HB-ce:worker P2 (the catalogue is not a lead path; nobody is paged at night for it); the rest P3; the owner can raise
them.

### Consumer checks (the switch-over, gated by `setup:catalogue_switchover`)

Once a consumer reads `ce_pub` instead of `public.catalog_*`, CAT-01 to CAT-03 get a sibling comparing that consumer's
version marker with `ce_pub`'s latest publication (Spark's `programme_cache.catalog_updated_at`, the website's
`web_catalog_state.fingerprint`, Witty's catalogue import version, the influencer portal's `inf.campaign_programmes`
programme ids still existing). The owner validates the item when the switch-over is done; until then the legacy checks
stay the truth.

### Heartbeats, events, Setup, Operate, Ask

- **Heartbeats**: `ce:worker` read from the engine's own beat table; `ce:dashboard` written by Eduwit One's HTTP probe.
- **Events**: one source, `ce.job` transitions (queued, running, succeeded, failed, dead) and publications, copied by the
  events union like the other 17 sources; payloads carry ids and counts only.
- **Setup items**: `catalogue_engine` (the dashboard URL and "production go-live done": validate = `ce_pub` reachable and
  `ce.health()` answering); `catalogue_switchover` (owner: which consumers read `ce_pub`).
- **Operate page**: the engine's needs (Supabase Pro, the GitHub Actions secrets, the Edge Functions, the Sources to
  approve), first-time steps (its go-live list), live state (jobs by status, last publication per partner, open
  conflicts, sources failing), every-day checks, where to look first per check, links to the dashboard.
- **Ask**: `app_status('catalogue')` already exists; a `catalogue` tool answers "what is published for partner X",
  "which programmes changed this week", "which sources are failing" from `ce_pub` and `ce.job`, read only.

## 3. What Eduwit One needs from Scout (the asks)

Stable names, so the checks are written once. Each is small; the engine's own patterns already have most of them.

1. **`ce.health()` returning jsonb** `{ok, jobs: {queued, running, dead, failed_24h}, workers: {last_beat_at}, publications:
{latest_at, partners_without_publication}, conflicts_open, sources_failing}` — the same shape of contract as
   `b2b.health_check()`, `b2c.health()` and `public.web_health()`, `SECURITY DEFINER`, `EXECUTE` to `eduwit_one_reader`
   in `ce.apply_grants()`.
2. **Grants in `ce.apply_grants()`**: `USAGE` on `ce` and `ce_pub` and `SELECT` on `ce.job`, `ce.conflict`, `ce.fact`,
   `ce.trusted_source`, the worker heartbeat table and every `ce_pub` relation, to `eduwit_one_reader`. (Eduwit One can
   also grant these itself; doing it in the engine's `apply_grants` keeps one owner per schema.)
3. **A publication view in `ce_pub`** with `partner_id`, `version` (or `publication_id`), `published_at`, `programme_count`,
   `rolled_back_at`, so "latest publication per partner" is one query, and a programme view with `fee`, `duration`,
   `mode`, `level`, `offer_status`, one value per concept.
4. **The worker heartbeat**: the table (or view) `beat()` writes, with `worker`, `at`, `stage`; one row per worker.
5. **Stable statuses**: `ce.job.status` in `queued, running, succeeded, failed, dead`; `ce.offer.status` including
   `possibly_dropped`; `ce.conflict` with an open/closed marker.
6. **Test rows**: if the engine ever carries test partners or fixture sites on production, an `is_test` column on
   `ce.partner` (and offers through it), so Eduwit One's checks leave them out as they do elsewhere.
7. **The dashboard health route**: `/api/health` answering `{"ok": true}` without sign-in, for the HTTP probe.

Nothing else: no calls from the engine into Eduwit One, no shared secrets, no `one_*` names in the engine.

## 4. Sequence

1. Scout's design session confirms or amends the names in §3 (one message; whichever it already has, it keeps).
2. Eduwit One: a migration after PR #29's 0024 (grants for the reader, the `catalogue_engine` and `catalogue_switchover` Setup items,
   thresholds), the CE checks in `supabase/checks/catalogue.sql` (regenerated into 0006 and `docs/CHECKS.md`), the two
   heartbeats, the events source, the Operate page section, the Ask tool, local tests on stubs of the named `ce`
   relations, the click-through. Rehearsed on staging, which already holds the engine, then applied to production as
   phase 1 was.
3. The owner validates `catalogue_engine` on Settings → Setup after the engine's production go-live; the checks switch
   on; the first tick reports them.
4. Later, with the switch-over: the consumer checks and, when the engine exposes safe functions, the first fixes under
   the proof-before-power rules.
