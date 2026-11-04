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

Run on 24 Oct 2026 at 10:36 UTC, read only, through the build session's Supabase connector again: this environment still
has no Postgres connection (D-041, checked again today), so `scripts/db/with-db.ts` could not carry it. The SQL is what
`node scripts/db/try-checks.ts --ids=B2B-05,B2B-10,INT-07,B2C-05,B2C-09,WEB-06` prints, run one check per
`begin transaction read only … rollback`. The timing is `explain (analyze, buffers)` on the same statement in the same
kind of transaction: the first production timing for these six (the 23 Oct trial measured none), so the comparison with
23 Oct is on the values.

| Check | Result | Value | Planning / execution | What the plan used | 23 Oct |
| --- | --- | --- | --- | --- | --- |
| B2B-05 | ok | stuck `[]`, failing_streaks `[]` | 2.5 ms / 0.45 ms, 6 buffers | `allocations_push_due_idx` and `allocations_lead_status_idx` for the candidates; `push_requests_alloc_idx` for the streaks, not reached (no candidate rows) | ok |
| B2B-10 | ok | decided_today 0, breached_today 0, late_run_partners `[]` | 3.6 ms / 0.34 ms, 1 buffer | sequential scans of `sla_checks` and `partners`, both empty on production; `sla_checks_partner_idx` for the per-partner runs, not reached | ok |
| INT-07 | ok | shared_without_consent 0, marketed_without_consent 0 | 4.2 ms / 0.40 ms, 12 buffers | `allocations_one_open_per_cycle` (7 index rows, none after the filter), `wa_messages_lead` with the IST day as the index condition, `student_leads_pkey` | ok |
| B2C-05 | ok | count 0, lead_ids `[]` | 1.1 ms / 0.16 ms, 4 buffers | `leads_state_owner` index scan with the IST day as a filter (small table) | ok |
| B2C-09 | ok | spent_inr 0, cap_inr 500 | 2.4 ms / 0.28 ms, 6 buffers | `ai_calls_at` with the IST day as the index condition; `settings_pkey` | ok |
| WEB-06 | ok | spent_usd_today 0, escalations_without_callback 0 | 1.6 ms / 0.36 ms, 5 buffers | `web_advisor_sessions_student_idx` with the IST day as the index condition; hash anti join on `web_callback_requests` for the escalations | ok |

Every check compiled, returned one row and reported ok, as on 23 Oct; none took more than 5 ms to plan or 0.5 ms to
run. Nothing was written. Nothing stands in the way of the apply on this account.

B2B-01's new SQL (it now also fails on dead deliveries and deliveries waiting over an hour, D-080) was run on production
at 06:49 UTC, read only: **ok**. `health_check()` ok, 0 dead deliveries in 7 days, 0 waiting over an hour, B2C sync
cursor 2 s old.
