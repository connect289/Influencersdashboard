# Eduwit One — production trial of the SQL checks

Run on 23 Oct 2026, around 19:35 to 19:40 UTC, on production (`xlseqwgyjuqhktrguhyc`) through the build session's Supabase connector.
Each batch ran inside `begin transaction read only`; nothing was written. Generated with `node scripts/db/try-checks.ts`,
which replaces `one.*` references with the configured threshold and setting values or empty stand-ins (schema `one`
does not exist on production yet). Heartbeat and ONE-01 checks read only schema `one`, so the local test covers
them. App-run checks (http) are not SQL and are not in this table.

| Check | Result | What it saw |
| --- | --- | --- |
| PLAT-01 | ok | after excluding b2c-capacity, which B2C-10 reports (first run listed it) |
| PLAT-01B, PLAT-02, PLAT-04, PLAT-07, PLAT-08 | ok | no startup timeouts, no silent frequent job, no bad job call |
| PLAT-03 | ok (seeded off) | return message is "1 row", as D-007 says |
| PLAT-05 | **fail** | Spark base_url null; Vault lacks b2c_internal_key and one_internal_key |
| PLAT-06 | ok | after limiting it to app schemas readable by the API roles (first run counted Supabase's own schemas) |
| PLAT-09 | ok | 249 MB, 25 connections, slowest query mean 865 ms (first day: no comparison) |
| WITTY-01, 03, 04, 06, 07 | ok | no health alerts; outside Witty's hours; no replies in the last 15 min |
| B2B-01, 02, 03, 05 to 10, 12 to 14 | ok | health_check ok, no stuck intake, no partners configured yet |
| B2B-04 | **fail** | lead 1218 is sales-ready with no allocation |
| B2B-11 | **fail** | one `ml.model_failed` event on 22 Oct at 20:30 UTC |
| B2C-01 to 09 | ok | 15 timers healthy; queues empty (Spark not live) |
| B2C-10 | **fail** | b2c-capacity failed at 04:15 UTC: "cannot extract elements from a scalar" in `b2c.capacity_tick()` |
| WEB-01, 03 to 06 | ok | web_health ok, catalogue checked 18 s ago |
| INF-01 to 03, 05 | ok | inf.health db and queue ok |
| INF-06 | **fail** | 3 active legacy influencer accounts (D-019) |
| CAT-01 to 03 | ok | cache current; no catalogue change pending |
| CAT-04 | **fail** | 86 active programmes with no fee and no fee_on_request flag |
| INT-01 to 07 | ok | no leads in a partner allocation yet; money tables empty |

## Re-run, 24 Oct 2026

Before go-live, re-run read-only (`scripts/db/try-checks.ts`) the checks D-088 rewrote for the apps' indexes without a
production timing: B2B-05 (candidate allocations and their last pushes), B2B-10 (per-partner last decided SLA checks by
due date), INT-07 (from the open partner allocations), and the five on a sargable IST day (B2B-10, INT-07, B2C-05,
B2C-09, WEB-06). Compare each value with the previous trial's.


B2B-01's new SQL (it now also fails on dead deliveries and deliveries waiting over an hour, D-080) was run on production
at 06:49 UTC, read only: **ok**. `health_check()` ok, 0 dead deliveries in 7 days, 0 waiting over an hour, B2C sync
cursor 2 s old.
