# Eduwit One — database runbook (rehearse, dump, apply)

The database scripts need a direct Postgres connection. The Claude build environment cannot open one (it only
reaches the internet over HTTPS), and the Supabase connector holds every DROP or DELETE for an approval this app
cannot show (D-031, D-041). Run these steps from a machine that can reach Supabase on port 5432: your laptop, or the
Lightsail server that runs n8n (same region as the database), or follow §5 from a cloud session whose environment
allows `api.supabase.com` (D-090).

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

**Without a dump.** On 24 Oct 2026 the owner waived the dump for the phase 1 apply (D-090). `apply.sh` and `api-apply.sh`
then need `ONE_APPLY_WITHOUT_DUMP=owner-accepted` in front of the command, set on purpose for every run; without it they
refuse as before. What stands in for the dump: every file runs in one transaction between two catalogue fingerprints,
so nothing outside schema `one` can change; every file has a rollback; the staging rehearsal ran the same set; and
Supabase's own backups, which the owner checks in the dashboard (Database → Backups) before the apply.

## 4. Apply to production

Within 24 hours of the dump, one file at a time:

```sh
scripts/db/apply.sh $(cd supabase/migrations && ls 0*.sql | grep -v '\.rollback\.sql$' | sort)
```

That is every migration in order, 0001 to 0024 today, for an empty database; the rehearsal vouches for the same set.
Production already holds 0001 to 0020 (D-092): after a rehearsal of the whole set, apply only the files that are new
there, today `scripts/db/apply.sh 0022_catalogue_engine.sql 0023_seed_catalogue_engine_checks.sql` (D-096). Do not
apply 0007 there again: its seed of `fixes` is refused once the observation window has started.

Each file runs in one transaction between two fingerprints of everything outside schema one; if a file changed any
app object, it is rolled back whole and the run stops with "refused: this migration changed an object outside schema
one" (D-057). It stops at the first failure, runs the smoke test, and prints the first tick report and the two cron
jobs. The report must have no key ending in `_error`, and `cron` must list `one-tick` and `one-nightly`.

## 5. From a cloud session, through the Management API

For a machine that has HTTPS to `api.supabase.com` but no Postgres connection (D-090). The scripts here post each
file to the Management API's query endpoint, the same executor the Supabase connector uses, as `postgres`, without the
connector's confirmation gate; every guard of §2 to §4 stays (the target rule, the fingerprint wrapper around each file,
the rehearsal row, the smoke test).

1. In the Supabase dashboard, create a personal access token (Account → Access tokens). Store it as the secret
   `SUPABASE_ACCESS_TOKEN` of the cloud environment (cloud environment menu → Edit → Network secrets, or an
   environment variable), add `api.supabase.com` under Network access → Allowed domains, and start a new session.
   Never paste the token into a chat or a file in the repository; revoke it when the apply is done.
2. Clean staging (its partial apply of 23 Oct), each stale file as one wrapped transaction:
   ```sh
   for f in 0003_functions_core 0002_core_tables 0001_schema_and_roles; do
     node scripts/db/wrap.ts supabase/migrations/$f.rollback.sql > /tmp/payload.sql && node scripts/db/with-api.ts staging /tmp/payload.sql
   done
   node scripts/db/with-api.ts staging scripts/db/leftovers.sql   # must print 0
   ```
   The stale functions have older signatures than today's rollbacks name; what the count still shows, drop by its actual
   signature (`pg_proc`, `pg_class`, `pg_roles`, `pg_default_acl`, `cron.job`), through `with-api.ts --sql`, nothing else.
3. Rehearse: `scripts/db/api-rehearse.sh` (the sequence of §2; ends with `REHEARSAL PASSED (<hash>)` and adds the row).
   Commit and push `docs/REHEARSALS.md`.
4. Apply: `ONE_APPLY_WITHOUT_DUMP=owner-accepted scripts/db/api-apply.sh $(cd supabase/migrations && ls 0*.sql | grep -v '\.rollback\.sql$' | sort)`.
   Same checks as §4; no dump is taken on this route. On production, which holds 0001 to 0020, name only the new files
   (today `0022_catalogue_engine.sql 0023_seed_catalogue_engine_checks.sql`, §4).

`with-api.ts` never prints the token (it reaches curl through a config on stdin) and names projects by target only.
Session settings do not carry between calls, so `smoke.sql`'s `call one.tick_job()` runs as its own top-level call and its
`set`/`reset` lines are left out; the API's own request timeout applies to each file.

## Undo

Each migration has a `.rollback.sql`; `RUNBOOK.md` → "Rolling back a migration" says what each one removes and what to
check first. To remove everything from a database, run the rollbacks newest first with the same `with-db.ts ... psql
-1 -f` line as in step 2 (on production between `scripts/db/fp-before.sql` and `fp-after.sql`, as the runbook shows).
They touch only schema `one`, its two roles, its two cron jobs and the fixer's grants.

`0006_seed_checks.rollback.sql` deletes incidents, proposals and actions, which are kept forever (spec §13), so it
refuses while any exist. On production, export them first (`pg_dump -n one`), then run it with
`PGOPTIONS="-c one.rollback_discards_history=on"` in front of the psql command. The staging rehearsal and the local
test set this themselves.
