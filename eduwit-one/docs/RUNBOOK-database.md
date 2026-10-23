# Eduwit One — database runbook (rehearse, dump, apply)

The database scripts need a direct Postgres connection. The Claude build environment cannot open one (it only
reaches the internet over HTTPS), and the Supabase connector holds every DROP or DELETE for an approval this app
cannot show (D-031, D-041). Run these steps from a machine that can reach Supabase on port 5432: your laptop, or the
Lightsail server that runs n8n (same region as the database).

Nothing here is run by the build automatically. Each step prints what it did; stop at the first error and send the
last 20 lines (they never contain the password).

## 1. Once per machine

1. Install Node 22 and the PostgreSQL 17 client tools (`psql`, `pg_dump`, `pg_restore`).
   On Ubuntu (Lightsail): add the PostgreSQL apt repository (https://www.postgresql.org/download/linux/ubuntu/), then
   `sudo apt install postgresql-client-17`. Check: `pg_dump --version` prints 17 or later.
2. Get the code: `git clone https://github.com/connect289/influencersdashboard.git && cd influencersdashboard/eduwit-one`
   then `git checkout claude/festive-babbage-7yhhx8`.
3. Get the two connection strings from the Supabase dashboard: open the project, press **Connect**, choose
   **Session pooler**, and copy the URI. Replace `[YOUR-PASSWORD]` with the database password.
   - Staging: project `mplbspysxmtohnlwpbti`.
   - Production: project `xlseqwgyjuqhktrguhyc`.
4. Put them in your shell only, never in a file in the repository and never in a chat:
   ```sh
   read -rs ONE_STAGING_DB_URL && export ONE_STAGING_DB_URL   # paste, press Enter (nothing is shown)
   read -rs ONE_PROD_DB_URL && export ONE_PROD_DB_URL
   ```

## 2. Rehearse on staging

Staging holds a partial apply from 23 Oct (0001, 0002 and 0003 core). Remove it first, then rehearse:

```sh
for f in 0003_functions_core 0002_core_tables 0001_schema_and_roles; do
  node scripts/db/with-db.ts ONE_STAGING_DB_URL psql -X -q -1 -v ON_ERROR_STOP=1 -f supabase/migrations/$f.rollback.sql
done
scripts/db/rehearse.sh
```

It must end with `REHEARSAL PASSED (<hash>)` and adds a row to `docs/REHEARSALS.md`. Commit that file
(`git add docs/REHEARSALS.md && git commit -m "docs: staging rehearsal passed" && git push`); production refuses to
apply without the row.

## 3. Dump production

```sh
scripts/db/dump.sh
```

It must print `DUMP OK <path> (...)`. The file stays on this machine (default `~/eduwit-one-dumps`, outside the
repository); it holds personal data, so never upload it anywhere. Write the path and the date in `docs/DECISIONS.md`
under D-010.

## 4. Apply to production

Within 24 hours of the dump, one file at a time:

```sh
scripts/db/apply.sh 0001_schema_and_roles.sql 0002_core_tables.sql 0003_functions_core.sql 0003_functions_runner.sql \
  0004_events_union.sql 0005_cron.sql 0006_seed_checks.sql 0007_seed_settings.sql
```

It stops at the first failure, runs the smoke test, and prints the first tick report and the two cron jobs. The
report must have no key ending in `_error`, and `cron` must list `one-tick` and `one-nightly`.

## Undo

Each migration has a `.rollback.sql`. To remove everything from a database, run the rollbacks newest first with the
same `with-db.ts ... psql -1 -f` line as in step 2. They touch only schema `one`, its two roles and its two cron jobs.
