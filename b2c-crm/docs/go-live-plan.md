# Eduwit Spark: go-live plan

Version 16 October 2026. Vikas asked on 15 October for everything to go to production once the design, the features
and every test passed; steps 0, 2 and 4 are the developer's and are carried out under that instruction, the others
wait for him. Live mode stays off until step 9. The hard limits stand: `student_leads_v2_rename.sql` is never run; Witty's `w2_*`
objects, `lead_intake()`, the n8n workflows and the B2B CRM are never changed by Spark's work.

## What "live" means

- Spark's own schema `b2c` exists in the **production** Supabase project `xlseqwgyjuqhktrguhyc`, next to Witty's
  tables and `student_leads`. Spark reads `student_leads` and the catalogue through views and writes nothing into
  them directly: every lead change goes to the B2B CRM's write API, which owns `student_leads`.
- A production Vercel site (`eduwit-spark`, Mumbai), on production keys, with `LIVE_MODE=on` only at the very end.
- The B2B CRM's Addendum 4 deployed, so hand-offs flow in and every assignment flows back.

## Order, with the check after each step and the way back

| # | Step | Who | Check | Way back |
| --- | --- | --- | --- | --- |
| 0 | Freeze: no further migrations after `b38` without a re-run of every suite; tag the branch | developer | tag exists | — |
| 1 | **Backup production** (Supabase point-in-time or a manual backup) | Vikas | backup listed | the backup |
| 2 | Apply `b1`…`b38` to production in order through the Supabase connector (the same chunks as on staging; `b4` without `pool_save`/`calendar_save`), then the two manual files (`staging_b4_pool_calendar.sql`, `staging_phase3_ledger_guards.sql`: they hold DELETE statements the connector refuses) in the SQL editor | developer + Vikas | the fingerprint query matches staging and the local build (functions, hash, tables, policies, `anon_exec` 0); `test_phase1`, `test_phase2`, `test_support_phones`, `test_walkthrough_fixes`, `test_features` pass in the SQL editor (they roll back) | drop schema `b2c` cascade (it holds nothing of Witty's); restore the backup if anything outside `b2c` looks touched |
| 3 | Expose `b2c` in production's Data API; enable Google sign-in with a **production** OAuth client (redirect `https://xlseqwgyjuqhktrguhyc.supabase.co/auth/v1/callback`); site URL and redirect URLs | Vikas | sign-in page loads against production | turn the provider off |
| 4 | Production Vercel project from the same branch, root `b2c-crm/web`, production keys (service role, publishable, SMTP, VAPID, `LINK_SECRET`, `B2C_INTERNAL_KEY`), `LIVE_MODE=off`; `app_deploy_set` points the timers at it. `web/scripts/deploy-production.mjs` does all of it and needs `PRODUCTION_SERVICE_ROLE_KEY` in the environment (it refuses a staging key) | developer (key from Vikas) | `/login` 200; the timers' calls return 200 (`net._http_response`) | delete the project; `app.base_url` back to null |
| 5 | First Admin (connect@eduwit.in) and the real team under Teams, with work mobiles; test users marked as such | Vikas | every person signs in once | — |
| 6 | Connect services one at a time, each tested with test leads: SMTP (done at 4), Google Workspace delegation, the WhatsApp Cloud API number and its approved templates, Exotel if wanted, Claude | Vikas + developer | the Setup checklist on Home shows each as connected; the browser flows pass against production with the `9190000000NN` test leads | unset the variable |
| 7 | B2B CRM: Addendum 4 deployed, endpoint registered, key and secret issued; `npm run mock-b2b` against production | B2B developer + ours | a test hand-off is allocated within 3 s and recorded back in the B2B CRM | switch the endpoint off in the B2B CRM |
| 8 | End-to-end with test leads only: hand-off → allocation → call → follow-up → application → enrolment → verification → commission | Vikas + a counsellor | the Phase 1 exit test list in the spec (B19.2) | — |
| 9 | **Live**: `LIVE_MODE=on` and Settings → live mode on; journeys un-paused one by one | Vikas | the first real lead reaches a counsellor; the first real WhatsApp opener goes out from the B2C number | `LIVE_MODE=off` stops every message at once |
| 10 | Clean up: delete the test leads and test users from production, keep staging as is | developer | no `is_test` leads left in production | — |

## What is not yet proven on staging (and why it waits for the real services)

- Real email delivery of sign-in codes (sent, not independently verified from here), WhatsApp on the B2C number,
  Gmail for counsellors, Google Calendar, Exotel calls, Claude briefs and classification, the B2B link: each needs its
  service connected (step 6 and 7). The code paths are covered by unit tests and mocks.

## Decisions for Vikas before step 2

1. The production address: `spark.eduwit.in` (a DNS record) or the free `*.vercel.app` address.
2. Whether the three inactive accounts from July 2026 stay inactive (the spec says yes).
3. The commission settings the CA must confirm (Settings → money, `ca_confirmed`).
