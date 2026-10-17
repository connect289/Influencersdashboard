# Discovery: the production-schema replica (`prod-replica`)

A local Postgres with the **schema** of the production Supabase project `xlseqwgyjuqhktrguhyc` (no production rows). Use
it to test the website's migrations against what production really has. Built 17 Oct 2026. Production was only read:
catalog and `supabase_migrations.schema_migrations` SELECTs through the Supabase connector.

## Build it

```bash
website/scripts/db/build-replica.sh          # about 50 s; drops and recreates the container every time
psql postgresql://postgres:postgres@localhost:54330/postgres
```

- Needs Docker and the images `supabase/postgres:17.11.0.004`, `supabase/gotrue:v2.197.0` and
  `supabase/storage-api:v1.82.1` (the website's local stack already pulled all three). No host `psql` needed: the script
  runs `psql` inside the container.
- The container is `prod-replica` on port 54330 (override with `NAME=` and `PORT=`). It is separate from the website's
  local stack (`supabase_*_website`, ports 54321-54324), which the script never touches.
- Every step runs with `psql -v ON_ERROR_STOP=1`. The first failure stops the build and prints the end of the log.
- At the end the script runs `fingerprint.sql` on the replica, compares it with `fingerprint.prod.txt` (production's
  output) and prints `all 42 rows match production` or the rows that differ.

| File | What it is |
|---|---|
| `website/scripts/db/build-replica.sh` | The build. |
| `website/scripts/db/manifest.txt` | Production's migration order: one line per row of production's `supabase_migrations.schema_migrations` (229 rows), plus the steps production ran without recording them. Each line points to a repo file or to a section of `replica-extras.sql`. |
| `website/scripts/db/fingerprint.sql` | One read-only query: per schema (public, b2b, b2c, catalog) and kind, the object count and an md5. Safe to run on production. |
| `website/scripts/db/fingerprint.prod.txt` | Production's fingerprint on 17 Oct 2026. |
| `website/supabase/prod-snapshot/replica-extras.sql` | What production has that no repo file creates, in `-- @section <name>` blocks (see below). |

## What is applied, in order

1. **Supabase's own schemas.** The image's init scripts create the roles (`anon`, `authenticated`, `service_role`,
   `supabase_admin`, ...) and the `auth`, `storage`, `extensions`, `vault` schemas. These are empty shells, so the script
   then runs GoTrue's migrations (`gotrue migrate`, 27 auth tables, the same count as production) and storage-api's
   migrations (a throwaway container that starts, migrates and is removed). Both join the replica's network namespace,
   so they publish no ports.
2. **Prelude.** The extensions production has: `pg_cron` (in `pg_catalog`), `pg_net`, `pgmq`, `vector` and `pg_trgm`
   (in public), plus `supabase_migrations.schema_migrations` with production's columns.
3. **`00000000000000_baseline.sql`.** Production's `public` schema on 6 Oct, never applied to production itself.
4. **`n8n_internal`** (extras): n8n's 109 tables in public, which the baseline left out (see below).
5. **The 83 migrations of 6-7 Oct** (`b2b-crm/supabase/migrations/2026100*`), ending with `w1_witty_addendum3`. Then
   `witty_backup_20261007` (extras), a table made by hand with W1.
6. **M24 to M31p**, applied by `deploy.mjs` on 8 Oct. Production's history includes the five `pending/` files
   (`m25d_ml_training_rows_prune`, `m30b_fact_views`, `m31a_guards`, `m31i_dispute_index`, `m31n_facts`), so they are
   applied. `pending/drop_tmp_transfer.sql` is not in production's history and is not applied.
7. **`w2_witty_b2c`** (extras, 14 Oct).
8. **B2C `b1` to `b38`** (15 Oct). Production recorded them as connector chunks (`b1_access_part0`, `b1_access_part1`,
   ...). Each repo file is applied once, at its `part0` version, and every chunk's row is recorded. Then
   `phase3_ledger_guards` = `b2c-crm/supabase/manual/staging_phase3_ledger_guards.sql`.
9. **M32a to M33f** (15 Oct), then `m33f_cron_history_performance_runid_window` and `m33f_cron_history_prune`
   (extras: run on production, not in the repo).
10. **Unrecorded, 16 Oct, SQL editor:** `manual/staging_b4_pool_calendar.sql`, then `b39` to `b43` (the developer
    handover says so; production's history has no rows for them). They go before `spark_b44`.
11. **`spark_b44_programme_facets`, `spark_b45_pipeline_test_users`** (= `b44_*.sql`, `b45_*.sql`).
12. **Witty W3 and W3b** (extras, 10 migrations), **`spark_b46_health_timer_calls`** (extras).
13. **End of build:** `b2b_tmp_transfer`, `backup_tables`, `catalog_drift` (extras, unrecorded), then the stubs.

**CRLF.** Production received two groups of files with Windows line endings, so their function bodies (`prosrc`) contain
`\r`: the 8 Oct `deploy.mjs` batch (M24 to M31p, 288 b2b functions) and the 16 Oct SQL-editor files (167 b2c functions).
The manifest marks these lines `crlf`, and the script feeds those files with CRLF line endings. Behaviour is the same
either way, but without CRLF the function hashes would not match.

## `replica-extras.sql`

| Section | Source | Contents |
|---|---|---|
| `w2_witty_b2c`, `m33f_*_runid_window`, `m33f_*_prune`, `w3_*` (8), `w3b_*` (2), `spark_b46_*` | Production's recorded SQL (`schema_migrations.statements`), copied exactly. Each section's md5 equals production's `md5(array_to_string(statements, E'\n'))`. | Witty function changes (`w2_try_claim`, `w2_crm_payload`, `w2_redeem_code`, `w2_inbox_add`, `w2_agent_pause`, `w2_blocks_sweep`, `w2_health_digest`, `w2_health_alerts`, `w2_send_failed`, `w2_search_programs`, `w2_nurture_due`), `w2_inbox.referral`, `b2b.witty_backup_20261015/16`, `b2c.job_calls`, `b2c.job_call`, `b2c.system_health`, `b2b.health_check`, `b2b.system_overview`, the `b2b-cron-prune` job. |
| `w3_witty_extractor_prompt_v6` | `-- @skip`: recorded, not run | Data only: it rewrites the `w2_prompts` extractor row from version 5 to 6, and it raises an error on an empty table. |
| `n8n_internal` | Rebuilt from production's catalog | 109 n8n tables (`workflow_entity`, `execution_entity`, `credentials_entity`, `user`, `settings`, `migrations`, `project`, ...), 17 sequences, every constraint and index, `increment_workflow_version()` and its trigger, RLS on. 18 CHECK constraints and one partial index are written as n8n wrote them (`col IN (...)`). Re-parsing `pg_get_constraintdef`'s output would store a different expression that means the same thing. |
| `witty_backup_20261007`, `b2b_tmp_transfer` | Rebuilt from production's catalog | Tables (and `b2b_tmp_transfer_get()`) made by hand, with production's grants. |
| `backup_tables` | Rebuilt from production's catalog | The 19 `public.*_backup_2026100N` copies. Each is an ordered column subset of today's source table (checked on production), so each is rebuilt empty with `CREATE TABLE ... AS SELECT <cols> ... WITH NO DATA`. |
| `catalog_drift` | Repo function bodies made byte-identical to production's | 33 functions whose production body differs **only in comments or line endings**. On 15 Oct the connector chunks (b1-b38 parts, m32a-c) dropped comment lines. Four baseline functions in public were saved with CRLF. One comment in `b2b.b2c_sync_lead` reads "treat" instead of "drop". Each body's md5 was checked against production's. |

## Stubs (nothing leaves the machine)

- **pg_net:** the container starts with `http_proxy`/`https_proxy`/`ALL_PROXY` pointing at `127.0.0.1:9`. A test
  `net.http_get('https://example.com/…')` came back "Couldn't connect to server". Code that calls `net.http_post`
  (`b2c.job_call`, the b2b outbox and push senders) runs, and its request fails locally.
- **pg_cron:** all 47 jobs exist with production's names, schedules and commands (md5 identical), all set to
  `active = false`. Run one by hand with its command if a test needs it.
- **Vault:** production has 3 secrets (`b2b_email_api_key`, `b2b_webhook_1`, `b2b_whatsapp_token`) that were set through
  the CRM admin screens. The replica has none, so code that needs them returns early (for example, `b2c.job_call`
  returns null without the `b2c_internal_key` secret). Create a dummy secret with `vault.create_secret` if a test needs
  one.
- **Data:** no production rows. The only rows are the seed rows the migrations insert (settings, guides, stages, buckets,
  the `b2c.job_calls` singleton, and the `witty_backup_*` rows, which hold the replica's own function definitions).

## Fidelity result (17 Oct 2026)

`fingerprint.sql` returns 42 rows per side (11 kinds for b2b, b2c and public, and 9 for catalog, which has no
functions or triggers). Kinds: tables + column definitions, column order, functions (signature, result, language,
security, volatility, config, md5 of the body), views, policies, triggers (with enabled state), indexes, constraints,
sequences, grants (ACL), RLS flags. **All 42 rows match production**, including the n8n tables.

| Schema | Tables | Functions | Views | Policies | Triggers | Indexes | Constraints |
|---|---|---|---|---|---|---|---|
| public | 199 | 192 (extension-owned excluded) | 9 | 37 | 7 | 403 | 432 |
| b2b | 106 | 626 | 10 | 97 | 18 | 262 | 413 |
| b2c | 116 | 510 | 3 | 72 | 22 | 257 | 358 |
| catalog | 1 | 0 | 4 | 1 | 0 | 2 | 2 |

Also checked and identical: the migration history (229 rows, md5 of `version name`), the 5 storage buckets with their
limits and MIME types, and the cron jobs (names, schedules, commands, owner).

**Remaining differences, and why they don't matter:**
- Postgres 17.11 locally, 17.6 on production. pg_net 0.20.4 vs 0.20.3, vector 0.8.2 vs 0.8.0 (image versions). None of
  these shows in the four schemas.
- `auth` and `storage` come from the local GoTrue v2.197 and storage-api v1.82 migrations, not from production's
  versions: auth has 27 tables on both sides, and storage has 10 locally vs 8 on production (newer storage-api). They are
  outside the fingerprint and the website doesn't write to them.
- Cron jobs are inactive, there are no vault secrets and pg_net is black-holed (the stubs above).
- The n8n tables are a snapshot: n8n changes them on every upgrade. When a later fingerprint differs only in public n8n
  tables, extract `n8n_internal` again.
- `fingerprint.sql` doesn't cover comments (`COMMENT ON`), column-level grants, or the `graphql`, `realtime`, `net`,
  `pgmq` and `supabase_functions` schemas.

## Keeping it current

When production gains a migration:
1. Run `list_migrations`, read-only. If the migration is a repo file, add a manifest line with production's version
   and name. Otherwise copy its `statements` from `supabase_migrations.schema_migrations` into a new `-- @section` of
   `replica-extras.sql`, check the md5 against production's, and point a manifest line at it.
2. Run `fingerprint.sql` on production (read-only) and replace `fingerprint.prod.txt`.
3. Rebuild. The script reports any row that differs.
4. To find a difference, swap the final SELECT of `fingerprint.sql` for a per-item listing (the file's header shows
   it), or compare hashes per bucket (`left(md5(key),1)`) to narrow down which object differs.

## Production migration history (latest 20 of 229)

| Version | Name |
|---|---|
| 20261016124923 | spark_b46_health_timer_calls |
| 20261016051344 | w3b_nurture_due_context |
| 20261016045831 | w3b_search_programs_emi_fields |
| 20261016044702 | w3_witty_send_failed |
| 20261016044500 | w3_witty_health_digest |
| 20261016044406 | w3_witty_extractor_prompt_v6 |
| 20261016043613 | w3_witty_soft_gate_e_ctwa_is_influencer |
| 20261016042749 | w3_witty_soft_gate_d_referred_by_fix |
| 20261016042526 | w3_witty_soft_gate_c_payload_sweep |
| 20261016042454 | w3_witty_soft_gate_b_try_claim |
| 20261016042407 | w3_witty_soft_gate_a_backup_inbox_redeem_agentpause |
| 20261016004420 | spark_b45_pipeline_test_users |
| 20261015210806 | spark_b44_programme_facets |
| 20261015210250 | m33f_cron_history_prune |
| 20261015210224 | m33f_cron_history_performance_runid_window |
| 20261015210000 | m33f_cron_history_performance |
| 20261015204807 | m33e_email_partner_adapter |
| 20261015204616 | m33d_referral_outcomes |
| 20261015204503 | m33c_data_protection_audit |
| 20261015204359 | m33b_lead_workspace |

The full history in brief: 83 migrations on 6-7 Oct (`disable_crm_auto_assign` to `w1_witty_addendum3`), 36 on 8 Oct
(M24 to M31p, with the five `pending/` files), `w2_witty_b2c` on 14 Oct, 84 B2C chunks plus `phase3_ledger_guards` on
15 Oct, M32a to M33f on 15 Oct, and Spark b44 to b46 with Witty W3/W3b on 15-16 Oct. Not in production's history but
applied there by hand (per `b2c-crm/docs/developer-handover.md`): `b39` to `b43` and `staging_b4_pool_calendar.sql`.
Note: `docs/HANDOVER.md` still says `m33a` to `m33e` are not applied. Production's history shows that they are (15 Oct).
