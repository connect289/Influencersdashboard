# Runbook

Operating and go-live notes for the Influencer Portal: the go-live checklist (everything the owner, counsel, the CA and
the providers must supply), the deployment and rollback procedure, backups, incidents and day-to-day operations. Going
live is HARD STOP 6: nothing here is run against production without the owner's approval.

## Go-live checklist

| # | Item | Added |
| --- | --- | --- |
| G-1 | Mark the shared baseline applied, never run it: `supabase migration repair --status applied 00000000000000` (D-34). Then apply only the `inf` migrations | Phase 1 |
| G-2 | Add `inf` to the Data API's exposed schemas (SHARED_CHANGES S-2) | Phase 1 |
| G-3 | Vault secrets: `inf_app_base_url`, `inf_internal_key` (cron dispatch), **`inf_pii_key`** (created by migration 20261018000100 if missing) | Phase 1–2 |
| G-4 | **Back up `inf_pii_key`** to the company password manager immediately after go-live. Without it, stored PAN and bank account numbers cannot be decrypted. Never rotate it without the re-encryption script | Phase 2 |
| G-5 | Legal review of the compliance course text (`inf.course_lessons`, `inf.course_questions`) and of the creator platform terms and privacy notice before creators are invited | Phase 2 |
| G-6 | Auth settings: allow sign-ups (S-13), redirect URLs and the code-carrying email template (S-14), leaked-password protection (S-15) | Phase 1–2 |
| G-7 | Retire the legacy influencer objects L-1 to L-3 (SHARED_CHANGES §E) | Phase 0 |
| G-8 | Optional: CAPTCHA keys for `/signup` (D-50) | Phase 2 |
| G-9 | Contracts: counsel reviews every clause and the default template, and a Super Admin marks each clause reviewed (the seed clauses start unreviewed and carry the DRAFT marker; keep the legal-review gate on). Counsel also confirms the consent text (`inf.consent_texts` v1), OTP click-sign for creator agreements, and stamp duty per state (D-84, D-97) | Phase 4 |
| G-10 | Name at least one Authorised Signatory with a designation; set the organisation's legal name, address, GSTIN and PAN (printed in contracts) | Phase 4 |
| G-11 | A live email provider before contracts are sent (signing codes and signed copies). For WhatsApp codes, get the `contract_sign_code` template (two parameters: code, contract number) approved in Meta and add `whatsapp` to Settings → Contracts → OTP channels (D-91) | Phase 4 |
| G-12 | Storage: raise the project's global upload size limit to at least 2 GB (the `inf-deliverables` bucket allows 2 GB videos; the default project limit is lower) and confirm resumable uploads are enabled | Phase 5 |
| G-13 | Content compliance: Eduwit reviews the starting banned-claims list and the default brief template; counsel confirms the ASCI checklist wording and the disclosure terms per platform (Settings → Content) | Phase 5 |
| G-14 | **Connecting attribution to live leads is a separate, owner-approved step (HARD STOP 6).** The migrations create the `inf-lead-sync` schedule, but nothing reads `student_leads` until the app runs with `LEAD_SYNC=on` (D-122). Before switching it on: confirm the read-only production drift check is clean, choose the backfill start date with the owner, then set `LEAD_SYNC=on`, redeploy, watch one sweep in System status and the Leads → Tools page, and run the backfill | Phase 6 |
| G-15 | **Back up `inf_lead_ref_key`** (Vault, created by migration 20261021000100 if missing) with `inf_pii_key`. Rotating it changes every lead reference creators and staff have seen | Phase 6 |
| G-16 | Witty and the website (approved R-1, R-3, R-5): Witty validates typed creator codes with `inf.witty_resolve_code` and keeps issuing access codes with `w2_issue_code`; the website's co-branded page reads `GET /api/public/v1/creators/<handle>`. Set Settings → Attribution → Links and Witty (Witty's number, message template, UTM source, short-link base, website address) before creators share links | Phase 6 |
| G-17 | Review the attribution defaults (window, model, duplicate grace, self-referral) and the fraud thresholds with the owner, and confirm the stage rules against the CRM's current stage list (Leads → Stage rules) | Phase 6 |
| G-18 | **Tax with a CA before the first payout run:** confirm the TDS sections, rates and thresholds per component, that TDS is deducted when a payout is paid (D-132), the GST rate and SAC code, and the payout statement for creators without GST; then mark the settings confirmed. Until then keep `hold_until_tax_confirmed` in mind (Settings → Finance → Payouts) | Phase 7 |
| G-19 | Finance set-up: payout cycle and day, two-person approval, minimum payout, agency-payee handling, the bank's bulk-upload column format (test one file with the bank before the first run) and the reconciliation flag days. Fill the organisation profile (printed on payment advice and statements) | Phase 7 |
| G-20 | Private buckets `inf-invoices` and `inf-documents` are created by migration 20261017000600 (ops); confirm they exist and are not public after the migrations run. Payment advice and Form 16A files are kept for the retention period; never make these buckets public | Phase 7 |
| G-21 | Optional (approved R-4): the B2B team publishes `public.b2b_enrollment_money_v`; the receipts sync then reads it instead of `b2b.earnings` and `b2b.invoices` (one function to change, `inf.commission_receipts_sync`). Until then the read is limited to those two tables, read only | Phase 7 |
| G-22 | Analytics: the migration schedules pg_cron `inf-analytics` (every 15 minutes, `inf.analytics_refresh()`); confirm it runs in System status after go-live. Review the metric definitions in `docs/METRICS.md` with the owner (especially committed spend, revenue basis and how deal-level fees are shown by platform), and decide whether the staff dashboards' Viewer role should see revenue | Phase 8 |
| G-23 | Communication providers (HARD STOP 4): a live email provider (SMTP, Resend or Brevo) for notifications and digests, and for WhatsApp a Meta WhatsApp Business account with approved templates for each event you want on WhatsApp (enter each approved name in Communication → Templates; one variable per line in the template's order). Creators need a phone number on their profile. Then set `LIVE_MODE=on` | Phase 9 |
| G-24 | Review the notification catalogue with the owner (which events are required, default channels, the digest defaults) and the wording of the main templates (contract, payout, KYC). pg_cron schedules created by the migration: `inf-announcements` (every 5 minutes), `inf-comm-daily` (09:00 IST), `inf-digests` (hourly, sends at the digest hour in Settings → Notifications), `inf-scorecards` (1st of the month, 06:00 IST); confirm they run in System status | Phase 9 |
| G-25 | Webhooks: register endpoints only after `LIVE_MODE=on`; give each receiving system its signing secret (shown once) and the verification rule (HMAC-SHA256 of `timestamp.body`, reject after 5 minutes). Point n8n at a public HTTPS address; internal addresses are refused by design | Phase 9 |
| G-26 | Privacy and retention with counsel and the CA: the financial-records retention period (Settings → Retention and privacy, default 8 years), click anonymisation and sign-in log periods, the privacy notice (grievance officer contact, data export and deletion), and who holds `privacy.manage`. Decide whether creators may request deletion in the portal from day one | Phase 10 |
| G-27 | Error tracking (HARD STOP 4): a Sentry project and DSN (or the team's tracker). Until then unhandled server errors are logged as `request.error` with the route, digest and request id (`instrumentation.ts`) | Phase 10 |
| G-28 | Hosting (HARD STOP 4): the Vercel project, the domain and TLS, environment variables from `.env.example` (production values, `NEXT_PUBLIC_SITE_URL` on the real domain), and the edge rate limit for `/m/*`; per-IP limits trust Vercel's client IP header (`docs/SECURITY_REVIEW.md`) | Phase 10 |
| G-29 | Tiers and scorecards: the Super Admin creates the tiers (Settings → Tiers) and confirms the score weights and thresholds; no tiers exist until then, and the first monthly scorecards run on the 1st after go-live | Phase 10 |

## Deployment

Prerequisites: G-1 to G-29 answered, the owner's written go-live approval, and a green CI run (typecheck, lint, unit,
pgTAP, Playwright) on the release commit.

1. **Dry run on a copy.** First run the read-only drift check (`scripts/baseline/generate-baseline.sql`, see
   Operations): the shared objects must match the recorded baseline hash, or stop and re-check `SHARED_CHANGES.md`.
   Then restore the latest production backup into a new Supabase project (or a branch), apply the baseline repair and
   every `inf` migration there (G-1), point a preview deployment at it and walk the main journeys (staff sign-in,
   creator sign-in, a deal, a contract preview, the Finance screens). The pgTAP suite and Playwright run on the local
   stack in CI; they never run against a hosted project.
2. **Production database.** In a quiet window, take a manual backup, then `supabase migration repair --status applied
   00000000000000` and `supabase db push` (only the `inf` migrations run). Expose `inf` (G-2), create the Vault secrets
   (G-3) and back up `inf_pii_key` and `inf_lead_ref_key` (G-4, G-15).
3. **Application.** Set the production environment variables with `LIVE_MODE=off`, `LEAD_SYNC=off` and
   `PAYOUT_PROVIDER=bank_file`, deploy, and check `/api/health`, staff sign-in with the emailed code, and System status
   (all pg_cron jobs present, the job queue draining).
4. **Set-up in the console.** Organisation profile and signatories (G-10), settings reviewed with the owner (attribution,
   finance, content, notifications, retention), tiers (G-29), staff accounts and roles.
5. **Providers.** Configure email (and WhatsApp templates), send a test from Communication → Templates, then
   `LIVE_MODE=on` (G-23).
6. **Live leads (separate approval, G-14).** `LEAD_SYNC=on`, watch one sweep, run the backfill.

**Rollback.** The portal only adds the `inf` schema, its buckets and its cron jobs; nothing shared is changed. To stop
the portal: set `LIVE_MODE=off` and `LEAD_SYNC=off` and redeploy (no email, WhatsApp or lead reads), or unschedule the
`inf-*` cron jobs (`select cron.unschedule(jobname) from cron.job where jobname like 'inf-%'`). To roll back the
application, redeploy the previous Vercel build. Database rollback is a restore of the pre-deploy backup into a new
project; never drop `inf` on the live project while Finance records exist in it.

## Backups and recovery

- Supabase daily backups (and point-in-time recovery on the plan that has it) cover the `inf` schema with the rest of
  the project. Before each production migration, take a manual backup.
- Vault keys are not useful without the backup of `inf_pii_key` and `inf_lead_ref_key` (G-4, G-15): keep both in the
  company password manager.
- Storage: signed contracts (`inf-contracts`) are written once and verified by hash on every download; payment advice,
  Form 16A and invoices are private. Keep bucket versioning or a nightly copy of `inf-contracts`, `inf-documents` and
  `inf-invoices` to another region.
- Restore drill (once before go-live, then yearly): restore a backup into a new project, point a preview deployment at
  it, sign in as staff, open a signed contract (hash verifies) and a payment advice.

## Incidents

- **Money shown wrongly**: put the creator's lines on hold (Finance → Ledger → Hold) before investigating; the ledger is
  append-only, corrections are adjustments. Re-run the deal from its Ledger tab after fixing the cause.
- **A student's contact details visible to a creator or agency**: switch the creator portal off by blocking the
  affected accounts (Creators → Block), capture the audit log, and treat it as a DPDP incident (notify the owner and
  the grievance officer the same day).
- **Lead sweep failing**: System status shows the last sweep; `leads.sweep_failed` retries from the same watermark.
  Switch `LEAD_SYNC=off` if it misbehaves; nothing else depends on it.
- **Provider outage**: notifications queue and retry with backoff; nothing is lost. Webhook deliveries retry for 24
  hours.
- Every unhandled server error is logged as `request.error` with a digest the user can quote.

## Operations

- **Public media kits** (`/m/<handle>`) exist only for approved creators who turned the page on; pages are cached for
  five minutes and the PDF route is rate limited per IP (60 a minute). Every page carries `X-Robots-Tag: noindex`.
  Before go-live, add `/m/*` to the edge rate limit (Vercel firewall) as well (`docs/SECURITY_REVIEW.md`).
- **Signed contracts** live in the private `inf-contracts` bucket, written once by the service role. Downloads go only
  through `/api/contracts/<id>/pdf`, which re-verifies the document and PDF hashes. A contract flagged
  `integrity_failed_at` (event `contract.integrity_failed`) must be investigated before anyone relies on it: compare the
  stored version's HTML hash with the signatures' `document_sha256` and the file's hash with `inf.contract_files`.
- **Contract reminders and expiry** run inside the nightly job (`inf.contracts_remind()`).
- **Content reminders** (due dates, overdue, escalation, missing metrics) run inside the nightly job
  (`inf.content_remind()`). Penalty proposals are recomputed by the `penalties.refresh` job; nothing is charged until a
  manager approves a proposal.
- **Deliverable files** live in the private `inf-deliverables` bucket under `<deliverable id>/`; brief assets in
  `inf-briefs` under `<brief id>/`. Links are signed for an hour after an access check.
- **Dormancy** runs inside the nightly `inf-nightly` job (`inf.nightly_prune()` → `inf.creators_flag_dormant()`).
- **Lead sweep** (`inf-lead-sync`, every minute, only with `LEAD_SYNC=on`): reads new and changed leads read-only,
  applies the rules and refreshes the masked creator feed. A warning `leads.stage_unmapped` means a CRM stage no rule
  maps: add a stage rule. `leads.sweep_failed` returns 503 and the next minute retries from the same watermark. After a
  rule or settings change, re-run a date range from Leads → Tools (manual decisions are kept).
- **Fraud flags** never reject on their own; a manager clears or confirms each one with a reason (Leads → Fraud review).
- **Short links** (`/r/<code>`): an unknown or switched-off code goes to `/link-inactive`. If Witty is slow or failing,
  visitors still reach WhatsApp without an access code (log `redirect.witty_issue_failed`); attribution then relies on
  the code in the message.
- **Ledger runs** (`ledger.run` jobs, queued per deal by domain events and nightly by `inf.ledger_nightly()`): a failed
  run is retried with backoff; Finance or the deal owner can press **Run now** on the deal's Ledger tab. The tab's
  **Next run** preview shows what a run would change without posting it.
- **Payouts:** the bank file is generated on each download from `inf.payout_bank_rows()` (audited) and never stored.
  If the bank rejects a payment, mark that payout failed: its lines return to payable for the next run. A batch can be
  cancelled until it is exported. Payment advice PDFs are built by the `payout.advice` job; if one is missing, check the
  job in System status (it is idempotent and safe to re-run).
- **Receipts:** `inf.commission_receipts_sync()` runs after each lead sweep (so only with `LEAD_SYNC=on`). A manual
  receipt overrides the CRM for that enrolment until it is withdrawn.
- **Dashboards** read summary views refreshed every 15 minutes (`inf-analytics`). A refresh that fails leaves the last
  data in place; the page shows when it last refreshed. Staff can press **Refresh** (skipped if the last refresh is under
  two minutes old). At 100k leads a refresh takes about 16 s; re-measure with `scripts/perf/analytics.sql` (local only,
  rolled back) after changing the views or functions.
- **Notifications and messages:** each notification's email/WhatsApp copies are sent by the `notify.deliver` job; a
  copy marked skipped says why (`live_mode_off`, `no_template`, `no_number`). Message attachments live in
  `inf-documents/threads/<thread>/` and open through `/api/threads/file` after an access check. Announcements scheduled
  for a time go out within five minutes (`inf-announcements`); a stuck one can be cancelled until it is sent.
- **Digests** (`digest.run`, queued once a day at the digest hour from Settings → Notifications by `inf-digests`) are idempotent per person and day; re-running
  the job for a date sends nothing twice.
- **Webhooks:** each delivery is a `webhook.deliver` job; Communication → Webhooks shows the last 20 attempts with HTTP
  status and error. An endpoint that keeps failing is marked "failing since"; pause it from the same page. After the
  last retry a delivery stays failed; send a test event once the receiver is fixed.
- **Production schema drift check** (read-only): run `scripts/baseline/generate-baseline.sql` against production and
  compare with `scripts/baseline/exact.sql`, or compare one md5 over all generated statements (production and a fresh
  local database must give the same hash; Phase 7 gate: 100 statements, `3f8bdfc5…`).
- **Storage clean-up** (`storage.remove` jobs): an approved deletion removes the creator's photo (and KYC proofs no
  record needs) at once; KYC kept for the retention period is purged by `inf.retention_run()` on its date, which queues
  this job for the proof file. A failed job retries; it only ever removes files under `inf-public-avatars` and `inf-kyc`.
- **Custom link addresses** are set by staff only (Leads → links on the creator's page); creators and agencies always
  link to Witty, the website or a programme page, so `/r/<code>` cannot be used as an open redirect.
- **Webhook endpoints** must be public HTTPS addresses; addresses written as IP numbers in any form are checked before
  connecting, names when they resolve.
