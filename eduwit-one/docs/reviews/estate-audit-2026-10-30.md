# Estate audit, 30 Oct 2026

The owner asked: "Audit each of the apps ... Look for bugs and security gaps and fix them all. Make sure that all the
functionalities of all the apps work and fix any anomaly." This file is the coordinator's record: the findings that cut
across the apps (verified read-only on production unless stated), then one section per app from its auditor, verified
by the coordinator before any fix was merged. Severity: critical (exploitable now or an outage within days), high,
medium, low. Production changes wait for the owner's go; nothing in this file was applied to production unless it
says so.

This repository is public. A finding that is still open in production is described here only by what it is, who acts
and what the fix is; its technical detail stays out of the repository until the fix is live (D-109).

## The estate on 30 Oct

| App                                    | Code                                                   | Live at                       | Database                           |
| -------------------------------------- | ------------------------------------------------------ | ----------------------------- | ---------------------------------- |
| Witty (WhatsApp)                       | n8n workflow "Eduwit Witty" + `public.w2_*`            | n8n.eduwit.in, chat.eduwit.in | `public.w2_*`                      |
| B2B CRM                                | `b2b-crm/`                                             | crm.eduwit.in                 | `b2b`, legacy `public.crm_*`       |
| Spark (B2C CRM)                        | `b2c-crm/`                                             | spark.eduwit.in               | `b2c`                              |
| Website                                | `website/` on branch `claude/inspiring-babbage-8asj1y` | www.eduwit.in                 | `public.web_*`                     |
| Influencer portal (+ legacy dashboard) | `influencer-portal/`                                   | influencer.eduwit.in          | `inf`, legacy `public.influencer*` |
| Eduwit One                             | `eduwit-one/`                                          | one.eduwit.in                 | `one`                              |
| Eduwit Scout                           | repository `connect289/eduwit-catalogue-engine`        | Edge Functions, dashboard     | `ce`, `ce_pub`, `ce_admin`         |

One Supabase project serves all of them (ref `xlseqwgyjuqhktrguhyc`, Postgres 17, ap-south-1), on the organisation's
FREE plan with Micro compute. API-exposed schemas: public, graphql_public, b2b, b2c, catalog, inf, one. Supabase Auth
sign-ups are open (email + password with confirmation, Google). Four sign-in accounts exist. n8n keeps its own data in
the same database's public schema.

## Cross-app findings

| #   | Severity | Finding                                                                                                                                                                                          | State                                      |
| --- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------ |
| X1  | critical | A legacy CRM function in `public` can be run by any signed-in user without a role check, and sign-ups are open                                                                                   | fix ready (B2B `m33g`), not applied        |
| X2  | critical | Free plan: the whole database turns read-only above 500 MB; it held 394 MB, Eduwit One growing it fastest                                                                                        | fix ready (Eduwit One `0029`), not applied |
| X3  | high     | pg_cron's history pruning runs inside the nightly stall window and failed two nights running (131 MB)                                                                                            | proposal (owner)                           |
| X4  | high     | n8n's only account has no two-factor sign-in                                                                                                                                                     | owner action                               |
| X5  | high     | Free plan: no daily backups of production at all                                                                                                                                                 | owner decision (Pro plan)                  |
| X6  | medium   | Sign-in policy: passwords of 6 characters, no character rules, no CAPTCHA, with open sign-ups; redirect allow list holds `http://localhost:3000` and old Vercel preview domains                  | owner decision                             |
| X7  | medium   | The main GitHub repository is public (all code and security logic readable); no secrets or student data found in any branch's history                                                            | owner decision                             |
| X8  | medium   | Eduwit One's checks used about 9.5 s of database time a minute, over half in one check (B2C-01)                                                                                                  | fixed in `0029` (not applied)              |
| X9  | medium   | The B2B CRM has no CI workflow                                                                                                                                                                   | proposal                                   |
| X10 | low      | n8n's internal tables sit in the API-exposed public schema with full grants to anon/authenticated, protected only by row security with no policies (and the `ensure_rls` trigger for new tables) | proposal (move n8n to its own schema)      |
| X11 | low      | Copies of student data in old backup tables (`public.student_leads_backup_2026100x`, `w2_*_backup_*`, `b2b.witty_backup_*`), not exposed                                                         | owner decision (drop when not needed)      |

Details:

- **X1.** The fix withdraws the signed-in users' grant on that function; its two internal callers keep working without
  it. No trace of use was found. Fix: `b2b-crm/supabase/migrations/m33g_revoke_legacy_stage_function.sql` with
  `b2b-crm/supabase/tests/test_m33g_legacy_stage_function.sql`. The safety layer refused the coordinator's write to the
  shared staging project for this one, so it is not rehearsed; it is a single revoke, re-appliable, with its inverse in
  the file. The detail stays with the owner until the fix is live (D-109).
- **X2.** Supabase docs (Understanding Database and Disk Size, Free Plan behavior): "Free Plan projects enter read-only
  mode when your database size exceeds 500 MB." Sizes on 30 Oct: cron 131 MB, one 107 MB, public 72 MB (catalogue
  embeddings 48 MB), pg_catalog 46 MB, every app schema under 7 MB. Eduwit One kept every check result (about 40,000 rows
  a day) 14 days when ok and 90 when failed, one tick report a minute for 30 days and copied events 180 days; it would have
  settled near 590 MB on its own. `0029` (D-103) brings it to roughly 120 MB, adds PLAT-10 (size against the plan's
  limit: P2 at 80 %, P1 at 90 %), and also rewrites B2C-01 (X8).
- **X3.** `b2b-cron-prune` deletes `cron.job_run_details` older than 7 days at 22:15 UTC, inside the stalls of 28 and 29
  Oct; its last run ended "job startup timeout", so 10 days (669,000 rows) are kept. Move it to a quiet hour and shorten
  the window; see the B2B section.
- **X4.** Turn on two-factor sign-in for the n8n account (n8n: Settings, Personal, two-factor) and keep n8n updated. The
  detail stays with the owner until it is done (D-109).
- **X5.** The Free plan has no automated backups. Pro (USD 25 a month) has daily backups kept 7 days, an 8 GB database,
  leaked-password protection and lets the compute be upgraded (the stalls; `db-stalls-2026-10-30.md`).
- **X6.** Auth settings now: `password_min_length` 6, no required characters, `password_hibp_enabled` false (needs Pro),
  `security_captcha_enabled` false, `uri_allow_list` includes `http://localhost:3000/auth/callback`,
  `https://dashboard-eduwit.vercel.app/auth/callback`, `https://web-five-gray-cxilbo6ue2.vercel.app/**` and
  `https://eduwit-spark.vercel.app/**`. Proposal: minimum length 10, drop the localhost and retired entries after
  checking which apps still use them, CAPTCHA (Cloudflare Turnstile) once the sign-up forms carry it. Checked by GET:
  `web-five-gray-cxilbo6ue2.vercel.app` is the B2B CRM's own Vercel address and `eduwit-spark.vercel.app` Spark's (both
  live, keep them); `dashboard-eduwit.vercel.app` (the legacy influencer dashboard) answers 404, so its entry can go
  with `http://localhost:3000/auth/callback`.
- **X7.** A history scan of every branch found only test fixtures (sample JWT, fake keys, a TOTP test vector) and
  Eduwit's own public phone numbers. Making the repository private keeps the code and the security design to the team;
  Vercel deploys private repositories of a personal account on the Hobby plan.
- **X8.** Five hours of production results: B2C-01 1,621 s (median 9.2 s a minute), PLAT-01 575 s, the rest small; the
  per-job lookups in B2C-01 walked up to 100,000 rows of pg_cron history once per Spark job. One pass gives the same
  answer job by job in 0.08 s warm and 0.14 s cold.
- **Checked and sound:** every other public-schema definer function callable by signed-in users checks its caller
  (`crm_require`, `crm_role`) or is scoped to the caller's own id; new sign-ups get an inactive legacy CRM row with role
  viewer (no access); no access rule or function trusts user-editable metadata; no view exposes `auth.users`;
  materialized views and the `catalog` schema grant nothing to clients; storage buckets are private (one public avatar
  bucket) with no client policies; GitHub workflows run on `pull_request` with a read-only token and no secrets; the four
  Vercel apps send strict security headers (HSTS, CSP with nonces, framing denied).
- **Eduwit Scout:** 46 of its 49 signed-in-callable `ce_admin` functions call `ce.require_admin()` first and the other
  three are safe as written; its Edge Functions authenticate with a single-use 15-minute code. One low finding sent to its
  session: refused admin sign-ins each write an audit row with no rate limit (unbounded growth reachable by strangers once
  `ce_admin` is exposed).

## Per-app findings

(Filled from each auditor's verified report.)

### Website (www.eduwit.in)

Verified by the coordinator: robots.txt, the canonical link, the sitemap, the apex redirect and the sample creator page
fetched live; verification attempts, students, chats and the website's settings read on production (read-only).

| ID      | Severity | Finding                                                                                                                                                                                                           | State                                               |
| ------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| SITE-01 | high     | The live domain runs the preview configuration: robots.txt disallows every page, canonical links and the sitemap name the vercel.app address, enquiries would be stored as tests, a sample creator page is public | owner: the go-live decision, then Vercel settings   |
| SITE-02 | high     | No email code reaches students: since 22 Oct, 3 attempts, 0 verified, 0 leads, 0 chats                                                                                                                            | owner: Vercel email settings; code makes it visible |
| SITE-03 | medium   | A deployed site without an email provider printed addresses and codes to the hosting logs and told students a code was sent                                                                                       | fixed `63d0835`, not deployed                       |
| SITE-04 | medium   | The forms have no robot check and codes go out from the main mailbox                                                                                                                                              | owner: Turnstile keys, a dedicated sender           |
| SITE-05 | medium   | An enquiry can update an existing lead matched only by a phone number the site does not verify                                                                                                                    | owner decision (recommendation with the owner)      |
| SITE-06 | low      | The code check returned the CRM lead id to the browser                                                                                                                                                            | fixed `f75dd30`, not deployed                       |
| SITE-07 | low      | Student cookies were not `Secure` on preview deployments (which the live site is today)                                                                                                                           | fixed `a95d842`, not deployed                       |
| SITE-08 | medium   | While the database was unreachable every page waited up to 1.5 s for the redirect list                                                                                                                            | fixed `990b253`, not deployed                       |
| SITE-09 | low      | Creator page links could point to another site                                                                                                                                                                    | fixed `97071bb`, not deployed                       |
| SITE-10 | low      | nodemailer 10.1.2 advisories                                                                                                                                                                                      | fixed `ee90166` (10.1.7), not deployed              |
| SITE-11 | medium   | `typecheck`, and so CI, failed on a clean checkout; production deploys from a branch CI does not run on                                                                                                           | fixed `78b3dc0`; CI branch: owner                   |
| SITE-12 | low      | The harness test phone is refused by the phone check, so a test enquiry cannot be made                                                                                                                            | proposal (a signed test route)                      |
| SITE-13 | low      | `HB-vercel:website` is never written: Eduwit One has no Vercel token                                                                                                                                              | owner: Eduwit One Setup                             |
| SITE-15 | low      | The website's jobs run every minute whether or not there is work, and ran for minutes during the stalls                                                                                                           | proposal                                            |
| SITE-16 | low      | `format:check` fails on 197 files (before the audit)                                                                                                                                                              | reported                                            |
| SITE-17 | low      | Witty's extractor sends the student's email address to the model                                                                                                                                                  | owner decision                                      |
| SITE-18 | low      | No site-wide daily AI spending cap                                                                                                                                                                                | proposal                                            |
| SITE-19 | low      | The apex redirects to www, the reverse of the runbook                                                                                                                                                             | owner: pick the primary host                        |

SITE-14 lists what Eduwit One's T-WEB tests need from the website (a signed test route); not built. Checked and sound:
no website function, `lead_intake` or `crm_verify_*` can be run by browser roles; all 62 `web_*` tables have row
security and no browser grants; the search functions build no SQL from input; 110 of 119 live functions match the
repository (the other 9 differ in whitespace only).

Delivery: the eight commits (base `615ee72`, the head of `claude/inspiring-babbage-8asj1y`) are saved as
`estate-audit-2026-10-30/website-fixes.mbox`. They pass typecheck, lint, 210 of 210 unit tests, the copy check, the build
and `npm audit --omit=dev`; each new test fails on the old code. Applying them is `git am` on that branch, whose pushes
deploy www.eduwit.in, so it waits for the owner's go. No database change.

### Spark (B2C CRM, spark.eduwit.in)

Verified by the coordinator: the live definitions of `b2c.qualify_record`, `b2c.my_role` and `b2c.is_staff` and the
grants of the six functions named below (read-only); the four migrations read against them; typecheck and 174 of 174
unit tests re-run. Spark holds no student data in production yet (0 leads, 0 tickets, 1 user), so nothing was exposed;
the fixes must be live before its first lead.

| ID     | Severity | Finding                                                                                                    | State                                   |
| ------ | -------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| SPK-01 | critical | The details step for leads let signed-in people who are not staff through its permission check             | fixed `b47`, not applied                |
| SPK-02 | high     | The support-ticket permission check had the same gap                                                       | fixed `b47`, not applied                |
| SPK-03 | medium   | A sales head's Follow-ups list showed every team's leads, not only their team's                            | fixed `b48`, not applied                |
| SPK-04 | low      | Saved views opened for people who are not staff (no lead data in them)                                     | fixed `b47`, not applied                |
| SPK-05 | low      | The insights job's function was callable by signed-in users                                                | fixed `b47` (service role only)         |
| SPK-06 | low      | The emailed sign-in code came from `random()`                                                              | fixed `b50` (`gen_random_bytes`)        |
| SPK-07 | low      | B2C-10: `b2c-capacity` failed every day while nobody takes leads                                           | fixed `b49`, not applied                |
| SPK-08 | medium   | PLAT-05: Spark's base URL and Vault key `b2c_internal_key` are missing, so its four HTTP timers do nothing | owner: Vault key, then the base URL     |
| SPK-09 | medium   | B2C-01 took 10 to 30 s and was killed                                                                      | fixed in Eduwit One `0029`, not applied |
| SPK-10 | low      | Rows a person owns (tasks, notifications) are readable before the second sign-in step                      | proposal                                |
| SPK-11 | low      | Staff can read each other's push subscriptions                                                             | proposal                                |
| SPK-12 | low      | Three money tests use September fixtures and fail since 16 Oct (test data, not code)                       | proposal                                |
| SPK-13 | low      | nodemailer advisories                                                                                      | fixed (10.1.7)                          |
| SPK-14 | low      | `b2c-money` and `b2c-anomalies` hit "job startup timeout" on 29 and 30 Oct                                 | platform capacity (Pro plan, compute)   |
| SPK-15 | low      | Two server-side fetches go to configured hosts without a host allow list                                   | proposal                                |
| SPK-16 | low      | The leads export starts on a GET request                                                                   | proposal                                |

Commits on this branch: `f2e08f4` (b49), `15c30a9` (b47), `d6108bb` (b48), `d14ac00` (b50), `aa931aa`
(`b2c-crm/supabase/tests/test_audit_2026_10.sql`, 32 checks; 16 of the first 29 fail before the fixes), `a4749fc`
(nodemailer). Each migration is idempotent, has no DELETE and ends with its rollback; the auditor's local run of every
Spark suite: 590 checks pass (the 3 of SPK-12 fail before and after). Applying b47 to b50 to production waits for the
owner's go and a staging rehearsal.

### Influencer portal (influencer.eduwit.in) and the legacy dashboard

Verified by the coordinator: the live `inf.change_request_withdraw` and `inf.contract_side` (the guard passes when the
caller has no side, as reported); the vercel.app address compiled into the live portal's scripts (INF-A5); typecheck and
3,676 of 3,676 unit tests re-run with the fixes. The auditor's pgTAP run: 916 of 916 (884 before), and the new file
fails 23 of its 32 assertions without the migration.

| ID      | Severity | Finding                                                                                                         | State                                           |
| ------- | -------- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| INF-A1  | high     | The legacy dashboard's access rule on `student_leads` still exposes full lead rows                              | proposal ready, owner decision                  |
| INF-A2  | medium   | The legacy dashboard's sign-in function is still open and keeps its passwords unhashed                          | proposal ready, owner decision                  |
| INF-A3  | medium   | INF-06: the three legacy accounts are still active                                                              | proposal ready, owner decision                  |
| INF-A4  | medium   | Seven portal functions let a caller with no side on the deal past their check (effective in two)                | fixed `20261030000100_inf_audit_guards.sql`     |
| INF-A5  | medium   | The live portal is built with the vercel.app address as its site address, not influencer.eduwit.in              | owner: Vercel setting, then redeploy            |
| INF-A6  | low      | `inf.eligibility_gaps` was callable by signed-in users                                                          | fixed (client grant withdrawn)                  |
| INF-A7  | low      | Profile updates accepted any avatar path                                                                        | fixed                                           |
| INF-A8  | low      | KYC proofs could point outside the creator's own folder                                                         | fixed                                           |
| INF-A9  | low      | Message attachments were checked by prefix only                                                                 | fixed                                           |
| INF-A10 | low      | The tier list answered any signed-in account of the shared project                                              | fixed                                           |
| INF-A11 | low      | Some malformed short links answered 500                                                                         | fixed (`decodeCodeSegment`)                     |
| INF-A12 | low      | nodemailer and fast-uri advisories                                                                              | fixed                                           |
| INF-A13 | low      | Payout batches take their GST and TDS amounts from the caller (gross is checked against the ledger)             | owner decision (money logic)                    |
| INF-A14 | low      | Campaign message threads skip the campaign-visibility check                                                     | proposal                                        |
| INF-A15 | low      | Supabase sends 8-digit email codes valid 1 hour; the portal's texts say 6 digits and 10 minutes                 | owner: Auth setting (the code field takes both) |
| INF-A16 | low      | `authenticated` holds write and TRUNCATE privileges on four shared `public` tables (row security blocks writes) | cross-app proposal                              |

Commits on this branch: `96bf262` (the migration, pgTAP `025_audit_guards.sql`, portal D-192, security review rows 11 to
18), `8851f39` (short links), `f135ca5` (dependencies), `7c658d3` (the legacy retirement proposal in
`influencer-portal/supabase/proposals/`, outside the migration chain, with its rollback; rehearsed by the auditor with
fake accounts, 14 of 14). The portal's migration and the legacy proposal wait for the owner's go and a staging rehearsal
(project rule: hard stop 6 for migrations to the live project).
