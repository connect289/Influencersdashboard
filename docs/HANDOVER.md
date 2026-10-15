# Eduwit B2B Partner CRM: developer handover and go-live guide

For the developer who takes the CRM live and switches on each function. Everything is built and in the repository
(`connect289/Influencersdashboard`, folder `b2b-crm/`). This guide is the order of work; the per-screen detail lives in
`docs/go-live-setup.md` (referenced as "Go-live §n"), the daily operation in `docs/operations.md`, the design history in
`docs/b2b-design.md`. Where a step needs the owner (Vikas, connect@eduwit.in) it is marked **[Vikas]**.

Never paste a password, API key or token into a chat, ticket or document. Keys go into Supabase Vault through the CRM's
screens, or into Vercel's environment variables; the database connection string stays in your own shell.

## 0. What you are taking over

| Part | Where | State on 15 Oct 2026 |
|---|---|---|
| Web app | Vercel project `web`, root `b2b-crm/web`, Next.js 15, deploys branch `main`, host `https://crm.eduwit.in` | `main` is at commit c6d8d29 (Addendum 3). Addendum 4 and M33 (five commits) are on branch `claude/friendly-darwin-w7cuye`, pull request open, **not merged** |
| Database | Supabase project `xlseqwgyjuqhktrguhyc` (Mumbai), schema `b2b` plus `student_leads` in `public` (shared with Witty and the B2C CRM) | Migrations through `m32c_a4_catalog` applied. `m33a` to `m33e` **not applied** (the Supabase connector refuses their `drop constraint` lines; apply from a shell, step 1) |
| Staging | Supabase `mplbspysxmtohnlwpbti` (free plan, pauses when idle) | Has migrations only up to `m30a`: missing all of Addendum 3 and later. Catch up with the same deploy script before using it |
| Witty | n8n workflow "Eduwit Witty" `PKPs7tXg9bej8AgX` on VM `n8n-vm`, WhatsApp +91 96439 77407 | Database half of release W1 live; **workflow half not applied** (`b2b-crm/witty/WITTY_CHANGES_PROMPT.md`) |
| B2C CRM | Separate product, same database (schema `b2c`, its own migrations b1 to b38) | Built by another developer; connected to B2B through `docs/b2c-contract.md` version 4 once step 8 is done |
| Routing | Live switch `routing` | **Off.** Leads collect in the pre-routing pool. Every outbound channel (WhatsApp, email, CAPI, each partner) is off |

Accounts you need: GitHub (the repository), Vercel (project `web`), Supabase (both projects; the owner adds you as a
member), Meta Business (WhatsApp, Lead Ads, Events Manager), Google Ads, the email provider (Resend or Brevo), n8n
(`https://n8n.eduwit.in`) and Chatwoot (`https://chat.eduwit.in`) for the Witty step.

## 1. Finish the deployment (day 1)

1. **Apply the pending migrations.** On your machine, with the repository cloned and Node 20+:
   ```
   cd b2b-crm/supabase
   export DATABASE_URL='postgresql://postgres:<password>@db.xlseqwgyjuqhktrguhyc.supabase.co:5432/postgres'
   node deploy.mjs
   ```
   The password is in Supabase → Project Settings → Database (reset it there if you cannot see it; the owner has pasted
   it into a chat before, so a reset is due anyway **[Vikas]**). The script pauses the `b2b-*` cron jobs, skips every
   migration already recorded, applies `m33a_access_api_hardening`, `m33b_lead_workspace`, `m33c_data_protection_audit`,
   `m33d_referral_outcomes`, `m33e_email_partner_adapter` in order, each in its own transaction, records them, and resumes
   the jobs. It stops on the first error and leaves the earlier files applied; fix and rerun.
   Check: `select name from supabase_migrations.schema_migrations order by version desc limit 5;` ends with `m33e_email_partner_adapter`;
   `select count(*) filter (where active), count(*) from cron.job where jobname like 'b2b-%';` shows every job active (29 after M33).
2. **Merge the pull request** `claude/friendly-darwin-w7cuye` → `main` on GitHub. Vercel builds and deploys in about two
   minutes. Do this only after step 1: the new screens call the M33 functions.
   Check: Vercel → Deployments → latest is Ready; `https://crm.eduwit.in/api/health` answers `200 {"ok": true, …}`;
   `/login` loads; sign in as the Admin; System health → Health shows every job with a recent run.
3. **Vercel environment variables** (production scope; redeploy after a change): `NEXT_PUBLIC_SUPABASE_URL`,
   `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SITE_URL=https://crm.eduwit.in`;
   later `ANTHROPIC_API_KEY` and `AI_WORKER_KEY` for the AI Optimiser (step 11). Go-live §1.1 has the table.
4. **Vercel plan [Vikas].** Hobby forbids commercial use; move the project to Pro before students' data flows.
5. **Post-deploy once-offs:** on `/b2c` press **Resend every lead** (the B2C CRM's copies gain the version-4 fields);
   on System health → Data protection set the retention rules (step 12).
6. **Staging catch-up (recommended before any further migration):** run the same `node deploy.mjs` with staging's
   connection string; it applies `m30b` to `m33e` there. Then run the SQL test files (`b2b-crm/supabase/tests/`) that
   matter for a change in the staging SQL editor: every row of the final select must say `ok`.

## 2. Access, security and monitoring (day 1)

1. **Supabase Auth.** Authentication → Providers: Google (redirect `https://crm.eduwit.in/auth/callback`) and Email on;
   Multi-factor: TOTP on; Settings: leaked-password protection on. Go-live §1.2 step 2.
2. **Team.** Settings → Team: invite each colleague as **Admin** or **Viewer** (viewers see everything, change nothing).
   The invite is used up at the person's first Google or magic-link sign-in with that address and expires after 14 days.
   Every Admin enrols two-factor at first sign-in. You cannot remove the last Admin or change your own role.
3. **Uptime monitor.** Point UptimeRobot, Better Stack or Cronitor at `GET https://crm.eduwit.in/api/health` every 5
   minutes, alert on anything but 200. No key, no personal data in the answer.
4. **API limits.** Setting `api_limits` (per minute by scope: intake 120, referrals 60, events 300, b2c 600, ai_worker
   600, default 300). Raise a scope only when a caller reports `429`. New keys default to a 90-day expiry.
5. **Backups.** Supabase → Database → Backups: daily backups exist on Pro; switch on point-in-time recovery before the
   first paying partner. Do the quarterly restore test in `docs/operations.md` §6 once now to learn the procedure.

## 3. Email and WhatsApp providers (week 1; needed by steps 6, 9 and 10)

1. **Email.** Notifications (`/notifications`) → Providers: provider `resend` or `brevo`, API key (stored in Vault),
   sender on an Eduwit domain, sender name, reply-to. Add SPF, DKIM and DMARC for that domain at the provider. The same
   provider sends student messages, Admin alerts, scheduled reports and the leads for **email partners**.
   Check: the provider dashboard shows the domain verified; the screen shows "API key (stored)".
2. **WhatsApp.** Same screen: Phone number ID, permanent system-user token, Graph API version. **Which number [Vikas]:**
   Witty's (+91 96439 77407, replies land in Chatwoot) or a separate one.
3. **Templates.** Submit the utility templates in WhatsApp Manager (wording in Go-live §8 step 2 and §9 step 2), then
   Notifications → Templates: enter the approved names and set the `accepted` templates active (English and Hindi).
4. **Quiet hours and support contact** (Go-live §8 step 4), then the `whatsapp` and `email` live switches only after a
   test message succeeded. A message due while a switch is off is cancelled, never sent late.

## 4. Consent wording (blocks routing; start now, it depends on the lawyer)

1. **Lawyer-approved texts [Vikas].** Every consent line must name "our admission partners (edtech companies)":
   Witty's first reply, the website agent's sign-up, every website and landing-page form, the Meta and Google form
   disclaimers, and the one-tap request ("may we share your details with our admission partner? Reply YES or NO").
2. **Register them** on Intake → Consent texts (`version`, channel, purposes, body, covers admission partners, active,
   lawyer-approved date). `witty-notice-2026-10-v2`, `witty_partner_consent_v1` and `wa_partner_consent:v1` are seeded
   without a lawyer date.
   Check: `select version, channel, covers_admission_partners, active, lawyer_approved_at from b2b.consent_texts order by 1;`
3. Every source stamps `consent_partner_share_at` and `consent_text_version` (Go-live §4 step 3). A lead whose version
   is not registered or not lawyer-approved counts as not consented and goes to B2C, never to a partner.

## 5. Lead sources (week 1 to 2)

In order of value: the website Intake API, Meta Lead Ads, Google lead forms, imports, manual entry. Details Go-live §7;
contract `docs/intake-api.md`.

1. **Website forms.** The site's server posts to `POST https://crm.eduwit.in/v1/leads` with an API key of scope
   `intake` (System health → Webhooks and API keys), an `Idempotency-Key` per submission, the consent fields and the
   click IDs (`gclid`, `fbclid`) for attribution. Move the forms off the old CRM's `/api/v1/leads`.
   Check: the curl in `intake-api.md` §3 with a `910000…` phone returns 201 with `"is_test": true`.
2. **Meta Lead Ads.** Intake → Connections → Meta (verify token, app secret, Page token, API version); Meta app →
   Webhooks → `leadgen` → `https://crm.eduwit.in/v1/webhooks/meta/leadgen`. Map each form on Intake → Lead forms
   (fields, consent text, version, purposes including `partner_share`).
3. **Google lead forms.** Intake → Connections → Google (a key); in the form asset, webhook
   `https://crm.eduwit.in/v1/webhooks/google/leadform` with that key; **Send test data** creates a test lead.
4. **Imports and manual entry.** Intake → Import a file (`.xlsx`/CSV, template saved per source, consent basis step,
   rollback 24 h) and Intake → New lead.
5. **Test leads** use phones `910000…` or `9190000000NN`: never routed live, never messaged, never sent to CAPI.
   Delete them after each test (one row at a time: the bulk-delete guard blocks more than 5).
6. **Switch off the old path [Vikas]:** the n8n workflow **Meta Leads to WhatsApp Alert** `M4WnPdy9MEXsj30d`, once Meta
   leads have arrived through the CRM for a few days. Workflows **Eduwit CRM · Jobs** and **Partner Sync Worker** must
   stay unpublished (they call functions that no longer exist).

## 6. Partners (per partner, week 2 onward)

The go-live checklist on each partner's page (agreement, programmes, credentials, duplicates, mapping, SLA hours,
branding, test leads) must be complete before its live switch accepts. Detail: Go-live §3; adapters
`docs/partner-adapters.md`; the generic contract `docs/partner-api.md`.

1. **Create** (Partners → New): name, slug, student-facing display name, logo, brand colour, **CRM type**: `leadsquared`,
   `zoho`, `salesforce`, `hubspot`, `meritto`, `inhouse`, `generic_rest`, `webhook`, or **`email`** for a partner with no
   API at all (step 6.4).
2. **Settings:** duplicate handling (`sync` when their CRM refuses duplicates on create, else `async` with the 30-minute
   hold), caps, minimum monthly, lead criteria, working hours, holidays, SLA, whether the student is told the partner's
   name. **Agreement:** sign outside the CRM, then Confirm agreement with the document's location.
3. **Connection** (Sandbox first, then Live): the partner's API user and keys (Vault), the reference field they created
   in their CRM, the inbound signing secret you generate and hand over once. **Preview a push** and **Fetch fields**.
   Then **Programme sheet** (Programme Repository → upload or Google Sheet → map → Publish; sets the routing candidates and
   the commission rates), **Mapping studio** (their stages to Eduwit stages; a mapped `lost` starts the 7-day grace),
   **Branding**, ten **sandbox test pushes** from Routing → Simulate (one forced duplicate, one through every stage).
4. **Email partners (no API):** Connection tab → to-address, optional cc and subject prefix, live and sandbox addresses
   apart. Needs step 3.1 done. Each allocated lead is emailed as a table with the reference in the subject and accepted
   after the hold window. What they report back by phone or email goes in from the lead's Routing tab → **Record
   partner's report** (stage, sub-stage, note, lost reason); the engine applies it like a synced stage.
5. **Activate and switch live:** Settings → status active, then the live switch. **Billing details** (Commission &
   Finance → Partner billing details) before the first invoice.

## 7. Witty (release W1, workflow half) [Vikas's machine]

Witty is the live WhatsApp bot; its workflow half of release W1 is not applied, so students still hear "one of our
Academic Counselors" and no partner-sharing consent is stamped. Procedure, harness, publish and rollback:
`b2b-crm/witty/WITTY_CHANGES_PROMPT.md` (run as a Claude Code session in the Eduwit CRM folder with the n8n and Supabase
connectors) or by hand per `b2b-crm/witty/README.md`. Prerequisites: the editor lock (nobody else edits the workflow;
the published version is `1f79392c-ec02-4daf-a090-1d9d9dbb0a60`), the lawyer-approved wording from step 4, and the
harness at 20/20 before and after. Afterwards copy the four changed functions into the old CRM's `crm/sql/001_lead_intake.sql`
so a rerun cannot revert them. Decisions Witty still needs are in Go-live §6 step 5 **[Vikas]**.

## 8. The B2C CRM connection (with the B2C developer)

Give them `docs/b2c-contract.md` (version 4). Detail: Go-live §5.

1. **Keys and endpoint.** System health → Webhooks and API keys: an API key with scopes `b2c`, `events`, `intake` (90-day
   expiry; they rotate it on their side) and a webhook endpoint with consumer `b2c_crm`, their HTTPS URL, events `b2c.*`
   plus `b2b.lead_routed_to_partner`; Generate secret, Send test (`ping`), switch on once their signature check passes.
2. **Database user for the catalogue.** In the Supabase SQL editor (pick the password there):
   `create role b2c_server login password '…' in role b2c_app;` It reads `catalog.*` only; nothing on `student_leads`,
   `b2b` or `w2_*`.
3. **Settings** on `/b2c`: scope `held` (default) or `all`, writable fields; delivery is always real time.
4. **Their side:** the welcome WhatsApp template on the B2C number (nurture hand-offs), the 15-minute batch of their writes
   (`POST /v1/b2c/leads/batch`), the five immediate calls, round robin for duplicate-cascade and partner-lost leads, and
   moving off direct `student_leads` writes (contract §5).
5. **Test** with `9190000000NN` phones in the order of contract §6 (routing must be on for a hand-off: do it on staging or
   right after step 10).

## 9. Admin alerts and reports (before routing)

Dashboards → Alerts and e-mails → Where alerts go: enable, recipients (email and WhatsApp), digest interval, types.
WhatsApp alerts need their own one-parameter Meta template. Press **Send a test**. Add metric alerts for duplicate rate,
SLA compliance, failed pushes, failed CAPI. Scheduled e-mails of dashboards and reports as wanted. Go-live §9.

## 10. Routing go-live

Only when at least one partner is live, consent texts are approved, the B2C endpoint is subscribed and the providers of
step 3 are on. Rulebook `docs/B2B_CRM_ADDENDUM_3.md`; detail Go-live §11.

1. **Engine settings** (Routing → Engine settings): review `witty_unqualified_idle_hours` (18), `consent_policy` (`ask`),
   effort and SLA factors, spam rules, re-enquiry quiet hours, `lost_nurture_delays`. Every save needs a reason.
2. **Go-live checklist** on Routing → Overview (`routing_golive_check`): consent texts approved, Witty W1 consent line
   (acknowledge with a reason if Witty's half is still pending), B2C endpoint subscribed to `b2c.consent_requested`,
   Witty W2 one-tap request (acknowledge: the B2C number sends it until W2 exists), at least one live partner (warning).
3. **Switch on:** Routing → Overview → Turn on automatic routing, with a reason. Refused while a blocking item fails.
4. **Watch 48 hours:** Command Center, Pre-routing pool (a growing `due` group means the sweep fails), the decision log
   (spot-check ten decisions against the rulebook), pushes per partner, Send log, webhook deliveries, Not passed and the
   review queue, `select type, count(*) from b2b.events where created_at > now() - interval '48 hours' and type like 'alert.%' group by 1;`.
5. **Pause:** Routing → Overview → Turn off automatic routing; one partner: its Pause or live switch; one channel: its
   switch; emergency from SQL as the Admin: `select b2b.set_live_switch('routing', false, 'incident <ref>');`.

## 11. Later functions (each switched on when wanted)

- **Conversions (CAPI):** Conversions → Setup: Meta dataset and token, Google conversion actions and OAuth; consent
  basis; switches `capi_meta`, `capi_google`. Needs click IDs from the website. `docs/capi-setup.md`, Go-live §10.
- **Money:** Commission & Finance → Settings: GST, SAC, TDS (confirmed by the CA **[Vikas]**), invoice prefix, close
  day, Eduwit's legal details; partner billing details. Flow: enrolment to verify → verify with proof → month close →
  approve invoice → send PDF yourself → receipt. `docs/money.md`, Go-live §13.
- **AI Optimiser (costs money):** Vercel `ANTHROPIC_API_KEY`, an `ai_worker` API key in `AI_WORKER_KEY`, worker URL
  `https://crm.eduwit.in`, daily budget; advisory mode; Autopilot stays locked for at least two months. `docs/ai-optimiser.md`.
- **Sync cadence:** after the end-to-end tests, partner polling intervals per partner (Connection → Fields and polling;
  off for partners that send webhooks). The B2C CRM is always real time (Addendum 4).
- **Referral outcomes** for the influencer dashboard: an API key with scope `referrals` only; `docs/referral-api.md`.

## 12. Data protection (DPDP)

- **Retention:** System health → Data protection: erase leads idle for N months (empty keeps them; 24 months is a common
  choice) and delete test leads after N days (30). Nightly at 02:15 IST, with a reason kept in the audit log.
- **Erasure:** requests from the B2C CRM appear on the same tab; direct requests from the lead → **Erase**. The CRM's
  copies are removed at once; then tell each partner the alert names and ask the Witty maintainer to delete the chat
  (`docs/operations.md` §5, 72 hours).
- **Audit log:** System health → Audit log: every settings change, live switch, route, merge, erasure, team and key change.

## 13. Decisions and actions only the owner can take [Vikas]

1. Reset the production database password (it was shared in a chat) and give the developer the new one directly.
2. Vercel Pro plan. 3. Lawyer approval of the consent texts. 4. Which WhatsApp number sends student messages.
5. Partner agreements and data-processing terms, signed. 6. CA confirmation of GST, SAC and TDS.
7. Witty decisions (Go-live §6 step 5) and the editor lock while W1 is applied.
8. Deactivate n8n **Meta Leads to WhatsApp Alert** after the Meta webhook is proven.
9. Delete Google Cloud SQL `n8n-db` and its IAM grant (not Cloud Run service `n8n`, which forwards the old webhook address).
10. Keep or drop the `*_backup_2026100x` tables after 12 Nov.

## 14. Verification queries (read-only, Supabase SQL editor)

```sql
select name from supabase_migrations.schema_migrations order by version desc limit 8;          -- ends with m33e
select jobname, active from cron.job where jobname like 'b2b-%' order by 1;                     -- all active
select scope, live from b2b.live_switches order by 1;                                            -- routing and channels
select b2b.health_check();                                                                       -- ok true
select version, lawyer_approved_at, covers_admission_partners from b2b.consent_texts where active;
select slug, adapter_type, status from b2b.partners;
select name, consumer, active, events from b2b.webhook_endpoints;
select name, scopes, expires_at, revoked_at from b2b.api_keys;
select type, count(*) from b2b.events where created_at > now() - interval '1 day' and type like 'alert.%' group by 1;
```

## 15. Known limitations

`docs/go-live-setup.md` §16 lists them in full. The important ones: no partner CRM adapter has been run against a real
account yet (all tested on simulated replies); CAPI never sent to live Meta or Google; `.xls` imports unsupported;
opt-outs and erasures reach partners by email, not automatically; the B2C CRM still writes `student_leads` directly until
its developer moves to the API; Witty release W2 is not built; a penetration test and the first restore test are not
recorded as done.
