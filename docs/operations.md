# Eduwit B2B CRM: operations runbook

What to do when something routine or urgent happens, in the order to do it. Written for the Admin (Vikas) and whoever
covers; nothing here needs a developer unless a step says so. Screens are on `https://crm.eduwit.in`; SQL runs in the
Supabase SQL editor on the production project `xlseqwgyjuqhktrguhyc` (take care: the same database serves Witty).

## 1. Daily and weekly checks

| When | Where | Look for |
|---|---|---|
| Daily | System health → **Health** | Every background job has a recent run and no failures; the B2C link shows p95 under 5 s; no open alert |
| Daily | Command Center | Leads waiting in the pool, SLA breaches, partners paused by mistake |
| Daily | System health → **Data protection** | Open erasure requests (answer within 72 hours), partner erasure notices to carry out |
| Weekly | System health → **Webhooks and API keys** | Keys expiring within 30 days (the health check also lists them), keys over their rate limit, failed deliveries |
| Weekly | Leads → **Duplicates** | Possible duplicates: merge or dismiss |
| Weekly | System health → **Audit log** (filter "Admins") | Changes you do not recognise; every settings change, live switch, route and erasure is there |
| Monthly | Supabase → Database → Backups | A daily backup exists; do the restore test below once a quarter |

**External uptime monitor.** Point a free monitor (UptimeRobot, Better Stack, Cronitor) at `GET https://crm.eduwit.in/api/health`
every 5 minutes. It answers `200 {"ok": true, …}` while the database is reachable, the cron jobs ran recently and nothing is
stuck; `503` with `problems: [...]` otherwise. No login and no key needed; it never returns personal data.

## 2. Access

- **Invite a colleague:** Settings → **Team** → Invite: email, role **Admin** (full control) or **Viewer** (sees every
  screen, can export, cannot change anything, cannot see secrets). They sign in with Google or the magic link at the
  same email; the invite is used up on first sign-in and expires after 14 days. Every Admin must set up two-factor
  authentication (Settings → Security) before the CRM lets them past the sign-in screen.
- **Remove someone:** Team → Remove access. Their sessions end within a minute. You cannot remove the last Admin or your own access.
- **Lost phone (two-factor):** another Admin opens Team → the member → **Reset two-factor**; the member enrols again at the next sign-in.
- **Suspicious sign-in:** Settings → Security shows the last 50 sign-ins (email, method, IP, outcome). Remove the account's
  access, then rotate anything they could see (API keys, section 3).

## 3. Keys and secrets

- **API keys** (System health → Webhooks and API keys) are shown once at creation. Each has scopes, an optional expiry
  (90 days by default for new keys), a per-minute rate limit and a note saying who holds it. A caller over its limit gets
  `429` with `Retry-After`; an expired key gets `401` and the health check lists keys expiring within 30 days.
  **Rotate:** create the new key, give it to the integrator, wait for the first request from it (the usage column), then
  revoke the old one. Never paste a key into chat, email or a ticket; use the integrator's secret store.
- **Webhook signing secrets** (per endpoint and per partner): **Rotate secret** on the endpoint or the partner's
  Connection tab. Both sides must switch at the same time; the old secret stops working at once.
- **Provider keys** (Resend or Brevo, WhatsApp, Meta, Google, partner CRMs) live in Supabase Vault and are only ever
  referenced by id. Replace them on their screen (Notifications, Conversions, the partner's Connection tab); the old
  value is overwritten.
- **Database password:** Supabase → Project settings → Database → Reset. Then update it wherever a connection string
  is stored (only the deploy shell on your machine should have it). If a password was ever pasted into a chat, email or
  document, reset it the same day.

## 4. Deploying a change

1. Merge the pull request into `main`; Vercel builds and deploys the web app in about two minutes (project `web`).
2. Database migrations are **not** automatic. From `b2b-crm/supabase`, with the connection string in the shell only:
   ```
   node deploy.mjs
   ```
   It pauses the `b2b-*` cron jobs, applies the migrations that are not yet recorded, in order, each in its own
   transaction, records them, and resumes the jobs. Run it against **staging** (`mplbspysxmtohnlwpbti`) first, run the
   matching `tests/test_*.sql` files there (every row must say `ok`), then against production. Take a backup first
   (Supabase → Database → Backups → Create) before a production run.
3. Afterwards open System health → Health: every job green, the migration list ends with the new file.

Rolling back: the web app rolls back from Vercel → Deployments → Promote the previous one. A migration is not rolled
back; fix forward with a new migration, or restore the backup if data was damaged (section 6).

## 5. Students' rights (DPDP Act)

- **Erasure request.** Requests from the B2C CRM appear on System health → **Data protection**; a request made to you
  directly (phone, email) is done from the lead: Leads → the lead → **Erase**. Both remove the student's name, numbers,
  email, guardian, notes, contact numbers, message copies and delivery payloads from this CRM at once, opt the student
  out, release the lead from the B2C CRM and keep only identity-free statistics (course, city, stages, money). The lead
  cannot be found or restored afterwards.
  Then, within the same 72 hours:
  1. **Partners.** The erasure raises one alert per partner that received the lead (`Partner erasure notice`). Email each
     partner's data officer asking them to delete the student's record (the reference in the alert identifies it without
     the name) and note the date on the alert when they confirm.
  2. **Witty.** The WhatsApp chat history lives in Witty's tables (`w2_*`), which this CRM never writes. Ask the Witty
     maintainer to delete the conversation for the number (they have the procedure). The number itself is no longer in
     this CRM, so take it from the request before erasing.
  3. **Backups.** Backups keep the data for their retention period (7 days on the current plan); this is permitted as long
     as a restored backup is not used without re-applying the erasures (the audit log lists them: filter "lead.anonymised").
- **Access request** ("what do you hold about me"): open the lead and export it (Leads → Export, filtered to the lead),
  plus the audit log for that lead (System health → Audit log, lead id). Send within 30 days.
- **Opt-out** ("stop messaging me"): Leads → the lead → Opt out, or the B2C CRM reports it. No message goes out afterwards;
  partners are told through the sync (connected CRMs) or must be emailed (email partners).
- **Retention.** System health → Data protection sets two rules: erase leads idle for N months (6 to 120; empty keeps
  them), and delete test leads older than N days. The nightly job (02:15 IST) applies them, 200 erasures and 500
  deletions at most a night, and writes its last run on that screen. Leads with an enrolment, a partner still working
  them or a counsellor hand-off in the period are never erased by the rule.

## 6. Backups and restore

- **Automatic:** Supabase daily backups (Pro plan, 7 days). Point-in-time recovery is an add-on worth switching on
  before the first paying partner.
- **Before risky work** (bulk import, deploy, merge of many duplicates): Database → Backups → Create backup, or copy the
  affected table: `create table b2b.<table>_backup_<yyyymmdd> as select * from b2b.<table>;` (the Supabase guard
  requires a backup table before any bulk delete on `student_leads`).
- **Restore test (quarterly, required by spec B18):** restore the latest backup into the **staging** project (Supabase →
  Backups → Restore to a new project, or download and `pg_restore` into staging), sign in to a Vercel preview pointed at
  it, open a lead, a partner, the Command Center and the audit log. Record the date and result in `docs/b2b-design.md`.
- **Partial recovery** (one lead deleted by mistake): Leads → show deleted → Restore (soft deletes keep the row for 90
  days). Merged leads: the kept lead's timeline names the merged one; merges are not undone automatically.

## 7. Partners

- **Partner without an API (email).** Partners → New → CRM type **Email**: to-address, optional cc and subject prefix,
  live and sandbox addresses apart. Every allocated lead is emailed from the Notifications email provider as a table
  (reference, student, course, consent) and is **accepted** after the hold window. What the partner reports back by phone
  or email is recorded from the lead's Routing tab → **Record partner's report** (stage, sub-stage, note, lost reason);
  the engine applies it like a synced stage, including the 7-day grace for a loss.
- **Partner CRM credentials expired:** the Connection tab shows the push error; replace the credential and press
  **Retry failed pushes**. Leads waiting more than the SLA are listed on Sync & SLAs.
- **Pausing a partner:** the partner's live switch (`partner:<id>`) off. Routing skips it; leads already with it keep syncing.

## 8. Incidents

| Symptom | First look | Then |
|---|---|---|
| `/api/health` red, site up | System health → Health: which job is stale | Supabase → Database → Extensions: `pg_cron` on; `select * from cron.job_run_details where status = 'failed' order by start_time desc limit 20;` |
| Site down, Supabase up | Vercel → Deployments: last build failed? | Promote the previous deployment |
| B2C link p95 above 5 s or deliveries failing | System health → Deliveries: the error on the row | The B2C endpoint is down or refusing the signature: tell the B2C team; deliveries retry on their own |
| A partner says they got no leads | Routing tab of a sample lead; the partner's Connection tab | Push errors show the CRM's reason; `Retry failed pushes` after fixing |
| A student complains of messages after opting out | The lead's timeline (opt-out time vs message time) | If a message went after the opt-out, open an incident: check the live switches and the partner's copy |
| Suspected data breach | Settings → Security sign-ins; Audit log (Everyone, last 48 hours); API key usage | Revoke keys and access first, then assess; a breach affecting students must be reported to the Data Protection Board and the students (DPDP s.8(6)) |

## 9. Useful SQL (read-only)

```sql
-- migrations on this database
select version from supabase_migrations.schema_migrations order by version desc limit 15;
-- cron jobs and their last run
select j.jobname, j.schedule, j.active, max(d.start_time) last_run from cron.job j left join cron.job_run_details d on d.jobid = j.jobid
 where j.jobname like 'b2b-%' group by 1, 2, 3 order by 1;
-- today's events by type
select type, count(*) from b2b.events where at > now() - interval '1 day' group by 1 order by 2 desc;
-- the retention job's last run and the erasures of the last 30 days
select value from b2b.job_state where key = 'retention';
select count(*) from b2b.events where type = 'lead.anonymised' and at > now() - interval '30 days';
```
