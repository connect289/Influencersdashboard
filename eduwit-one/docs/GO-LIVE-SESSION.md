# Eduwit One go-live from the owner's computer: staging rehearsal, production dump, production apply

Instructions for a Claude session running on the owner's computer (Claude Desktop), written so the owner only has to say
"read `eduwit-one/docs/GO-LIVE-SESSION.md` and do what it says". The build sessions in the cloud cannot do this work:
they have no database connection and no durable disk for the dump (D-041, D-089), and the Supabase connector's
confirmation prompts for destructive statements never reached the owner (24 Oct, four attempts).

You are a Claude session running on the owner's own computer. The owner is not technical: do every step yourself, explain in one line what each step is before you run it, and ask only for the approvals the computer requires. The repository is `connect289/influencersdashboard` (clone it if it is not here yet), folder `eduwit-one/`, branch `claude/festive-babbage-7yhhx8`. The procedure is `eduwit-one/docs/RUNBOOK-database.md` §1 to §4, with the notes below; `docs/DECISIONS.md` D-089 says why it has to run from a computer with a database connection.

## The two connection strings, without a chat

The scripts need `ONE_STAGING_DB_URL` (project `mplbspysxmtohnlwpbti`) and `ONE_PROD_DB_URL` (project `xlseqwgyjuqhktrguhyc`) in the environment. They must never be pasted into this chat, printed, logged or committed. Do it this way:

1. Create an empty file outside the repository, readable only by the owner: `mkdir -p ~/.config/eduwit-one && touch ~/.config/eduwit-one/env && chmod 600 ~/.config/eduwit-one/env`, then open it in the system's text editor (`open -e` on macOS, `notepad` on Windows, `xdg-open` on Linux).
2. Tell the owner, in plain words: in the Supabase dashboard open the staging project, press **Connect**, choose **Session pooler**, copy the URI, replace `[YOUR-PASSWORD]` with the database password, and paste it into the editor as the line `ONE_STAGING_DB_URL=postgresql://…`; then the same for the production project on a second line `ONE_PROD_DB_URL=postgresql://…`; save and close the editor; then say "done".
3. Load the file into each command that needs it, in the same shell call, never echoing it: `set -a; . ~/.config/eduwit-one/env; set +a; <command>`. Check with `node scripts/db/with-db.ts ONE_STAGING_DB_URL psql -X -At -c "select 1"` (it prints `1`, nothing else); `with-db.ts` refuses a URL that reaches the wrong project.
4. When everything is done, offer to delete the file; if the owner agrees, `rm ~/.config/eduwit-one/env`.

## Rules

- Only schema `one`, the roles `eduwit_one_reader` and `eduwit_one_fixer`, default privileges naming them, the fixer's grants and the cron jobs `one-tick` and `one-nightly` may change on either project; the fingerprint wrapper in the scripts refuses anything else. Never touch the five apps' tables, functions, triggers or cron jobs.
- Never run the local tests, the smoke test on its own, or Playwright against staging or production; never `supabase db push`, `migration up` or `db reset`.
- The production dump stays on this computer outside the repository (default `~/eduwit-one-dumps`); it holds personal data and is never uploaded anywhere.
- Commit only `docs/REHEARSALS.md`, `docs/DECISIONS.md`, `docs/CHANGES.md` and `docs/PHASES.md`; push only to `claude/festive-babbage-7yhhx8`; open no pull request.
- If a step fails, stop, keep the output and report it; do not improvise on production.

## Steps

1. **Tools** (runbook §1). Node 22.18 or later and the PostgreSQL 17 client tools (`psql`, `pg_dump`, `pg_restore`); both projects run Postgres 17 and `scripts/db/dump.sh` refuses an older `pg_dump`. Install what is missing (Homebrew `postgresql@17` and `node@22` on macOS; the PostgreSQL apt repository and `postgresql-client-17` on Ubuntu; the EDB installer on Windows), asking for the approvals the system needs. Then `git fetch origin claude/festive-babbage-7yhhx8 && git checkout claude/festive-babbage-7yhhx8 && git pull`, and in `eduwit-one/`: `npm ci`, `node scripts/db/guards.ts` (must print "guards passed"), `node scripts/db/guards.ts --hash` (note the hash).

2. **Clean staging** (runbook §2, first block). Staging holds an older version of the first three migrations (25 tables, 16 functions, the two roles, no cron jobs). Run the three rollbacks as the runbook shows (`0003_functions_core`, `0002_core_tables`, `0001_schema_and_roles`). Then `node scripts/db/with-db.ts ONE_STAGING_DB_URL psql -X -At -f scripts/db/leftovers.sql` must print `0`. If not, list what remains in schema `one` (`pg_proc`, `pg_class`, `pg_roles`, `pg_default_acl`, `cron.job`), drop exactly those objects by their actual signatures (a stale function may hold `one.severity`), and re-check until it prints `0`.

3. **Rehearse** (runbook §2, second block): `scripts/db/rehearse.sh`. It must end with `REHEARSAL PASSED (<hash>)` and appends a row to `docs/REHEARSALS.md`; commit and push that file. Staging keeps schema `one` afterwards; that is intended.

4. **Dump production** (runbook §3): `scripts/db/dump.sh` must print `DUMP OK <path> (...)`. Write the path and date in `docs/DECISIONS.md` under D-010.

5. **Apply to production** (runbook §4), within 24 hours of the dump: `scripts/db/apply.sh $(cd supabase/migrations && ls 0*.sql | grep -v '\.rollback\.sql$' | sort)` (0001 to 0020). The tick report it prints must have no key ending in `_error`, and `cron` must list `one-tick` and `one-nightly`. A refusal "this migration changed an object outside schema one" is stop-and-report.

6. **Record it**: a new decision in `docs/DECISIONS.md` (after D-089) with the rehearsal row, the dump path and time, the apply time and the tick report's `checks` counts; a top entry in `docs/CHANGES.md` naming the dump; the matching rows in `docs/PHASES.md`. Commit and push.

## Done looks like

A `REHEARSAL PASSED` row for the current hash; production has schema `one`, the two roles and the two cron jobs; the smoke test passed there and the tick report had no `_error` key; the dump exists on this computer with its `.sha256`; the docs are updated and pushed. Tell the owner in plain words what happened at each step, and that the next step is deploying the app (RUNBOOK.md, "Setup").
