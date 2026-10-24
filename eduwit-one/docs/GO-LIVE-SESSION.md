# Eduwit One go-live from the owner's computer: staging rehearsal, production dump, production apply

Instructions for a Claude session running on the owner's computer (Claude Desktop), written so the owner only has to say
"read `eduwit-one/docs/GO-LIVE-SESSION.md` and do what it says". The build sessions in the cloud cannot do this work:
they have no database connection and no durable disk for the dump (D-041, D-089), and the Supabase connector's
confirmation prompts for destructive statements never reached the owner (24 Oct, four attempts). On 24 Oct the owner
waived the production dump for this apply (D-090): step 4 is offered, not required, and step 5 says how to apply without it.

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

1. **Tools** (runbook §1). Node 22.18 or later and the PostgreSQL client tools: `psql` always; `pg_dump` and `pg_restore` 17 if a dump is taken (both projects run Postgres 17 and `scripts/db/dump.sh` refuses an older `pg_dump`). Install what is missing (Homebrew `postgresql@17` and `node@22` on macOS; the PostgreSQL apt repository and `postgresql-client-17` on Ubuntu; the EDB installer on Windows), asking for the approvals the system needs. Then `git fetch origin claude/festive-babbage-7yhhx8 && git checkout claude/festive-babbage-7yhhx8 && git pull`, and in `eduwit-one/`: `npm ci`, `node scripts/db/guards.ts` (must print "guards passed"), `node scripts/db/guards.ts --hash` (note the hash).

2. **Clean staging** (runbook §2, first block). Staging holds an older version of the first three migrations (24 tables, 16 functions with older signatures, the two roles, no cron jobs; measured 24 Oct). Run the three rollbacks as the runbook shows (`0003_functions_core`, `0002_core_tables`, `0001_schema_and_roles`). Then `node scripts/db/with-db.ts ONE_STAGING_DB_URL psql -X -At -f scripts/db/leftovers.sql` must print `0`. If not, list what remains in schema `one` (`pg_proc`, `pg_class`, `pg_roles`, `pg_default_acl`, `cron.job`), drop exactly those objects by their actual signatures (a stale function may hold `one.severity`), and re-check until it prints `0`.

3. **Rehearse** (runbook §2, second block): `scripts/db/rehearse.sh`. It must end with `REHEARSAL PASSED (<hash>)` and appends a row to `docs/REHEARSALS.md`; commit and push that file. Staging keeps schema `one` afterwards; that is intended.

4. **Dump production** (runbook §3), offered, not required: the owner waived it for this apply on 24 Oct 2026 (D-090). If the computer has `pg_dump` 17 and the owner wants one, `scripts/db/dump.sh` must print `DUMP OK <path> (...)`; write the path and date in `docs/DECISIONS.md` under D-010. Otherwise skip this step.

5. **Apply to production** (runbook §4): `scripts/db/apply.sh $(cd supabase/migrations && ls 0*.sql | grep -v '\.rollback\.sql$' | sort)` (0001 to 0020), within 24 hours of the dump when one was taken; without a dump, put `ONE_APPLY_WITHOUT_DUMP=owner-accepted` in front of the command (D-090), otherwise `apply.sh` refuses. The tick report it prints must have no key ending in `_error`, and `cron` must list `one-tick` and `one-nightly`. A refusal "this migration changed an object outside schema one" is stop-and-report.

6. **Record it**: a new decision in `docs/DECISIONS.md` (after D-090) with the rehearsal row, the dump path and time or that none was taken (D-090), the apply time and the tick report's `checks` counts; a top entry in `docs/CHANGES.md` naming the dump or its absence; the matching rows in `docs/PHASES.md`. Commit and push.

## After the apply: deploy the app (WALKTHROUGH steps 3 to 6)

> Status 24 Oct, 16:30 UTC (D-093): steps 8, 9 (the Vercel half), 10 (the redirect URL), 11 (the domain, verified) and
> the `base_url` of step 12 are done from the build session; so are the Vault copy of the internal key and the exposed
> schema `one` (16:50 UTC). Left: `npx vercel --prod` once Vercel's daily deployment limit resets or the team is on
> Pro, then step 12's first sign-in and Setup.

The Vercel project **eduwit-one** already exists in the Eduwit team (region `bom1`, created 24 Oct from the build
session), with `ONE_SUPABASE_URL` and `ONE_SUPABASE_ANON_KEY` set for Production (both public values). It needs two
secrets, two dashboard settings and a deploy. On this computer, in `eduwit-one/web`, after `npx vercel login` (the
developer's own Vercel account, a member of the Eduwit team) and `npx vercel link --project eduwit-one --scope eduwit`:

8. **The service key.** In the Supabase dashboard, production project → Project settings → API keys → create a new
   _secret_ key named `eduwit-one`. Then `npx vercel env add ONE_SUPABASE_SERVICE_KEY production` and paste the key at
   the prompt (nothing is shown). Never the project's generic `service_role` key, and never in this chat.
9. **The internal key**, the same value in two places, generated here and never displayed:
   `openssl rand -hex 32 > ~/.config/eduwit-one/internal.key && chmod 600 ~/.config/eduwit-one/internal.key`, then
   `npx vercel env add ONE_INTERNAL_KEY production < ~/.config/eduwit-one/internal.key`, then into Vault on production:
   `set -a; . ~/.config/eduwit-one/env; set +a; node scripts/db/with-db.ts ONE_PROD_DB_URL psql -X -q -v ON_ERROR_STOP=1 -v k="$(cat ~/.config/eduwit-one/internal.key)" -c "select vault.create_secret(:'k', 'one_internal_key')"`
   (if a secret of that name already exists, `vault.update_secret(id, :'k')` for its id). Then delete the key file.
10. **Two dashboard settings** (owner or developer): Supabase → Project settings → Data API → Exposed schemas: add `one`
    (Setup item `supabase_api_schema`); Supabase → Authentication → URL configuration → Redirect URLs: add
    `https://one.eduwit.in/auth/callback` (Setup item `one_app_env`). Keep sign-ups disabled or the Google provider
    limited to the eduwit.in domain (RUNBOOK.md, "Signing in").
11. **Deploy**: in `eduwit-one/web`, `npx vercel --prod`. Then the domain: `npx vercel domains add one.eduwit.in` and the
    DNS record it asks for (a CNAME at the DNS provider of eduwit.in). The team is on the Hobby plan: its 300-second
    function limit fits the AI route, but Hobby is for non-commercial use, so the owner should move the team to Pro.
    If the project is later connected to GitHub for automatic deploys, its Root Directory must be `eduwit-one/web` and
    its production branch `claude/festive-babbage-7yhhx8` until the work is merged.
12. **First sign-in and Setup**: the owner signs in at https://one.eduwit.in with their eduwit.in Google account, enters
    the emailed code, then Settings → App → `base_url` = `https://one.eduwit.in`, and fills Settings → Setup starting
    with `email` (alerts) and `ai_key` (RUNBOOK.md, "Setup"). Settings → Setup shows what each remaining item unblocks.

## Done looks like

A `REHEARSAL PASSED` row for the current hash; production has schema `one`, the two roles and the two cron jobs; the smoke test passed there and the tick report had no `_error` key; the dump, if one was taken, exists on this computer with its `.sha256`; the docs are updated and pushed; https://one.eduwit.in answers and the owner can sign in. Tell the owner in plain words what happened at each step.
