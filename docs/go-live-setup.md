# B2B Partner CRM: go-live setup checklist

For the Eduwit developer who has to make real leads flow: into the B2B CRM, out to edtech partners or Eduwit's B2C CRM, and followed up. Do the sections in order. Every step says where to do it and how to check it worked.

Written 7 Oct 2026 from `docs/*.md`, `b2b-crm/README.md`, `b2b-crm/witty/*`, the migrations under `b2b-crm/supabase/migrations/`, the web app's `process.env` reads and the Addendum 3 interface contract. Where this file says "check X", the sources did not settle it. **[Vikas]** marks a decision only Vikas can take.

Short names used below:

| Name | Means |
| --- | --- |
| CRM | The B2B CRM web app (`b2b-crm/web`, Next.js, on Vercel) |
| Production DB | Supabase project `xlseqwgyjuqhktrguhyc` (EDUWIT LEAD TRACK, Mumbai), shared with Witty, the old CRM and the influencer dashboard |
| Staging DB | Supabase project `mplbspysxmtohnlwpbti` (free plan; pauses after a week idle; restore from the dashboard) |
| SQL editor | Supabase dashboard → SQL editor on the project named |
| Setting `x.y` | Row `x` in `b2b.settings`, key `y` inside its JSON. Changed only through `b2b.set_setting(key, value, reason)`, always with a reason; every change is a row in `b2b.settings_versions` |
| Live switch `s` | Row `s` in `b2b.live_switches`; read by `b2b.is_live(s)`; changed by `b2b.set_live_switch(s, true/false, reason)` |
| Test phone | `910000xxxxxx` (Witty harness) or `9190000000NN` (B2C / Hermes). Stored as `is_test`, never routed to a live partner, never messaged, never counted |

---

## 0. What exists today and what is deliberately off

Nothing in this section needs doing. Read it so you know the starting point.

1. **The CRM is built through M30 and the first four Addendum 3 steps.** Migrations `20261006…` to `20261007043511_m23b` are on production (per `docs/b2b-design.md` §7.2). `m24a` to `m30b` were applied to staging; several of their staging test runs are listed as pending in §7.2, and the production promotion is a planned "promotion window" (`b2b-crm/README.md`). `m31a0`, `m31a`, `m31b`, `m31c`, `m31d` exist as files; `m31e` to `m31o` (consent asks, the Addendum 3 engine, attribution, intake, after-push, B2C contract v3, re-decide, admin reads, AI/ML, facts, metrics) are specified in the interface contract but **not yet written**.
   Check: on the production DB, `select version from supabase_migrations.schema_migrations order by version desc limit 20;` and compare with the file names in `b2b-crm/supabase/migrations/`. Anything in the folder but not in that table is not live.
2. **Routing is off.** Live switch `routing` is false, and `engine.enabled` gates the sweep. `pg_cron` job `b2b-route-ready-leads` runs every minute and does nothing while the switch is off. Leads collect in the pre-routing pool (`/pool`).
3. **Every outbound channel is off.** Live switches `whatsapp`, `email`, `capi_meta`, `capi_google` are false (seeded by `m2d`). Each partner has its own switch `partner:<id>`, also false. The four student message templates in `b2b.message_templates` are drafts.
4. **AI is off.** Setting `ai.enabled = false`, `ai.mode = 'advisory'`, `ai.worker_url = null`. No `ANTHROPIC_API_KEY` or `AI_WORKER_KEY` on Vercel.
5. **Admin alerts are off.** Setting `admin_alerts.enabled = false`, no recipients.
6. **Sync is in real time** (the integration-and-testing mode). Setting `b2c_link.delivery = 'realtime'`; `sync.interval_minutes = 15` is only used once you switch to batched (section 14). Live partner polling defaults to that interval; sandbox polling runs every 2 minutes.
7. **Witty is half done.** The database half of release W1 (`20261007094058_w1_witty_addendum3.sql`: `w2_crm_owned`, `w2_nurture_due`, `w2_crm_payload`, `w2_commit_turn`, extractor prompt v5) is live on production. The workflow half (six Code nodes in n8n workflow "Eduwit Witty" `PKPs7tXg9bej8AgX`) is **not applied**: Witty still says "one of our Academic Counselors" and still stamps no partner-sharing consent. Section 6.
8. **Pending manual SQL** in `b2b-crm/supabase/pending/` (the Supabase connector refuses `DROP`/`DELETE`/`TRUNCATE` in migrations): `drop_tmp_transfer.sql` (production, housekeeping), `m25d_ml_training_rows_prune.sql`, `m30b_fact_views.sql`, `m31a_guards.sql` (apply right after `m31a`). Each file's header says when to run it.
9. **The old CRM is still online** at `https://eduwit-crm.vercel.app` (Vercel project `eduwit-crm`). Its n8n workflows **Eduwit CRM · Jobs** `Wx1uai9qtOkwFQDs` and **Partner Sync Worker** `UhSUqceTwQeuI5rR` are unpublished and **must stay unpublished** (the functions they call no longer exist in `public`). The n8n workflow **Meta Leads to WhatsApp Alert** `M4WnPdy9MEXsj30d` is still active and keeps writing Meta leads to a Google Sheet; switch it off only after section 7 is verified **[Vikas]**.
10. **No partners, no API keys, no webhook endpoints, no consent texts approved** are expected on production. Check: `select count(*) from b2b.partners; select count(*) from b2b.api_keys where revoked_at is null; select count(*) from b2b.webhook_endpoints;`.

---

## 1. Hosting and secrets

### 1.1 Vercel

1. **Project.** The CRM deploys from `b2b-crm/web` (framework Next.js, region `bom1` in `vercel.json`). The B2B CRM's own Vercel project name is not recorded in the sources: check the Vercel dashboard (account vikas@eduwit.in). Do not confuse it with `eduwit-crm` (the old CRM).
   Check: Vercel → Project → Settings → General shows Root Directory `b2b-crm/web`.
2. **Plan [Vikas].** Vercel Hobby forbids commercial use. Options in `b2b-design.md` §0.3: Vercel Pro ($20/month) for production, or Cloud Run. Not decided.
3. **Domain.** `.env.example` says `https://b2b.eduwit.in`; `docs/partner-api.md` says `https://crm.eduwit.in`. Check which DNS name is live and use that one everywhere below as `<crm host>` (webhook URLs, the B2C contract, partner contracts, `NEXT_PUBLIC_SITE_URL`, `ai.worker_url`).
   Check: `curl -sI https://<crm host>/login` returns 200.
4. **Environment variables** (Vercel → Project → Settings → Environment Variables, production scope). These are every `process.env` the app's own code reads (`lib/env.ts`, `lib/supabase/admin.ts`, `lib/supabase/browser.ts`, `proxy.ts`, `app/v1/ai/tick/route.ts`, `app/(app)/ai/actions.ts`):

   | Variable | What it is for | Where to get it |
   | --- | --- | --- |
   | `NEXT_PUBLIC_SUPABASE_URL` | The database the app talks to: `https://xlseqwgyjuqhktrguhyc.supabase.co` | Supabase → Project Settings → API |
   | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Browser-safe key (anon / publishable). RLS and grants protect the data | Supabase → Project Settings → API Keys |
   | `SUPABASE_SERVICE_ROLE_KEY` | Server only. Used to log sign-in attempts and check the lockout (`lib/supabase/admin.ts`). Never exposed | Supabase → Project Settings → API Keys (secret) |
   | `NEXT_PUBLIC_SITE_URL` | Public URL of the app, used in password-reset links (never taken from request headers) | Your `<crm host>` |
   | `ANTHROPIC_API_KEY` | AI Optimiser only (section 12). Leave unset until then | console.anthropic.com (organisation key, zero data retention if available) |
   | `AI_WORKER_KEY` | AI Optimiser only. An API key with scope `ai_worker` (section 12) | CRM → System health → Webhooks and API keys |

   Redeploy after changing any of them.
   Check: `/login` loads; signing in works (section 2); Vercel → Deployments → latest build log has no "Missing NEXT_PUBLIC_…" error (`lib/env.ts` throws on a missing value).
5. **Internal key.** There is **no** `x-internal-key` or `/api/internal/*` route in the shipped app: the design's job runner was replaced by `pg_cron` + `pg_net` inside Postgres (`b2b-design.md` §7.2, M8). Nothing to configure.

### 1.2 Supabase (production DB)

1. **Extensions** `pgmq`, `pg_cron`, `pg_net`, `vault` are already on (M2). Check: Supabase → Database → Extensions.
2. **Auth providers.** Supabase → Authentication → Providers: Google enabled (redirect `https://<crm host>/auth/callback`); Email enabled. Authentication → Multi-factor: TOTP enabled. Authentication → Settings: **leaked-password protection on** (`b2b-design.md` §3.1 says this must be done by hand in the dashboard).
   Check: Authentication → Providers shows Google and Email as enabled; MFA shows TOTP.
3. **Cron jobs.** The jobs listed below should exist (`select jobname, schedule, active from cron.job where jobname like 'b2b-%' order by 1;`): `b2b-route-ready-leads` (every minute), `b2b-push-tick` (10 s), `b2b-notify-tick` (30 s), `b2b-outbox-tick` (15 s), `b2b-b2c-sync-tick` (5 s), `b2b-intake-tick` (10 s), `b2b-import-tick`, `b2b-capi-tick`, `b2b-partner-sync-tick`, `b2b-sla-tick` (5 min), `b2b-guard-tick` (5 min), `b2b-money-tick` (5 min), `b2b-money-daily` (09:05 IST), `b2b-reconcile-nightly` (02:37 IST), `b2b-stats-refresh` (hourly :07), `b2b-stats-ai-catchup`, `b2b-refresh-facts`, `b2b-admin-alerts`, `b2b-ml-tick`, `b2b-ai-schedule`, `b2b-ai-autopilot`. Jobs from migrations not yet on production will be missing; that is expected.
   Check: System health (`/system`) → Background jobs shows each job with its last run and no failures. `select * from cron.job_run_details order by start_time desc limit 50;` has no `failed` rows.
4. **Migrations still to apply.** Apply any `m24…m31d` file not yet on production, staging first, each with Vikas's approval for that step, in the "promotion window" described in `b2b-crm/README.md` (pause every `b2b-*` cron job, apply, run the matching `supabase/tests/test_m*.sql` in a `begin … rollback` block, resume). Then the pending files by hand (section 0 step 8).
   Check: the migration row exists in `supabase_migrations.schema_migrations`; the matching `test_m*.sql` returns every row `ok = true`.

### 1.3 Secrets go in Vault, through the CRM screens

Never paste a secret into chat, a ticket or a document. Every secret below is typed once into a CRM screen, stored in Supabase Vault by a `SECURITY DEFINER` function, and never shown again (the screen shows "(stored)"). Leave a field empty to keep the stored value.

| Secret | Screen | Vault name (from the migration) |
| --- | --- | --- |
| Partner CRM credentials (token, access/secret keys, OAuth client secret, refresh token), live and sandbox | Partners → partner → Connection | `b2b_partner_<id>_outbound` (generic) or adapter JSON secret |
| Partner inbound signing secret (the partner signs its events with it) | Partners → partner → Connection → Signing secret → Generate / Rotate (shown once) | `b2b_partner_<id>_inbound` |
| WhatsApp Cloud API token (student messages and admin alerts) | Notifications → Providers and quiet hours | `b2b_whatsapp_token` |
| Email provider API key (Resend or Brevo) | Notifications → Providers and quiet hours | `b2b_email_api_key` |
| Meta Lead Ads verify token, app secret, Page access token; Google lead-form key | Intake → Connections | `b2b_intake_meta_*`, `b2b_intake_google_key` |
| Meta CAPI access token; Google Ads developer token, OAuth client secret, refresh token | Conversions (CAPI) → Setup | `capi` setting ids |
| Webhook endpoint signing secret (B2C CRM) | System health → Webhooks and API keys → endpoint → Generate secret (shown once) | `b2b_webhook_<id>` |

Check: `select name, description, created_at from vault.secrets order by created_at desc;` lists the names (never select `decrypted_secret`).

### 1.4 API keys

1. **Where.** System health (`/system`) → **Webhooks and API keys** → API keys → Create. Give a name and tick scopes. The key (`eb2b_…`) is shown **once**; only its SHA-256 is stored in `b2b.api_keys`.
2. **Scopes** (`lib/integrations.ts`, constraint in `m26a`): `intake` (Lead intake: `POST /v1/leads`), `events` (Product integrations: `GET /v1/handoffs`, `POST /v1/leads/{id}/route-to-partners`, webhook subscriptions), `b2c` (B2C CRM link: `/v1/b2c/*`), `referrals` (masked referral outcomes for the influencer dashboard), `ai_worker` (the AI worker route). There is **no `partner` scope**: partners never hold an API key; they sign events with their inbound signing secret (HMAC) and are identified by their slug in `POST /v1/partners/{slug}/events`.
3. **Create now:** one key for the B2C CRM with `b2c` + `events` + `intake` (`docs/b2c-contract.md` §0); one key per website / landing-page backend with `intake` only. Hand each over once, through a secure channel.
   Check: `select name, scopes, created_at, last_used_at from b2b.api_keys where revoked_at is null;`. A `curl -H "Authorization: Bearer <key>" https://<crm host>/v1/b2c/schema` returns `{ "ok": true, … }` for a `b2c` key and 401 for a key without that scope. `last_used_at` updates.
4. **Revoke** a leaked key on the same screen; it stops working at once.

---

## 2. Admin access

1. **The only user** is `connect@eduwit.in`, seeded into `b2b.app_users` (M2b) from the existing `auth.users` identity. There is no user management. `b2b.is_admin()` is checked in every server action and SQL function.
   Check: `select email, role, is_active, require_totp from b2b.app_users;` returns one row: `connect@eduwit.in`, `admin`, `true`, `false`.
2. **Google sign-in** needs no authenticator code (`require_totp = false` since M2g; it relies on the Google account's own 2-step verification). Keep Google 2SV on for that account.
   Check: `/login` → Continue with Google → lands on the Command Center. Settings → Security → Sign-in history shows the attempt as `google / success` (`b2b.sign_in_log`).
3. **Password sign-in** (fallback). `/forgot` sends a reset link to `NEXT_PUBLIC_SITE_URL/reset`; the password needs 12+ characters. The first password sign-in enrols TOTP at `/mfa`; every password session must be TOTP-verified (`aal2`) or `is_admin()` is false.
   Check: sign in with email + password + code; `select method, outcome from b2b.sign_in_log order by at desc limit 3;` shows `password / success` then `totp / success`.
4. **Any other account** is signed out with "This app is restricted" and logged (`outcome = refused_not_allowlisted`). Five failed attempts in 15 minutes lock the email. Sessions expire after 12 hours idle.
   Check: sign in with another Google account; it is refused and appears in Sign-in history.
5. **To add a second user later** you need a migration (widen the `role` check and insert into `b2b.app_users`). Not a screen.

---

## 3. Partners

Do this once per partner. Partners never log in.

1. **Create the partner.** Partners (`/partners`) → New: `name`, `slug` (goes in its events URL), student-facing `display_name`, `logo_url`, `brand_color` (`#RRGGBB`), **CRM type** (`adapter_type`: `leadsquared`, `zoho`, `salesforce`, `hubspot`, `meritto`, `inhouse`, `generic_rest`, `webhook`). Written by `b2b.partner_save`.
   Check: the partner card appears with status `draft`; `select slug, adapter_type, status from b2b.partners;`.
2. **Duplicate handling.** Settings tab: `dedupe_mode` = `sync` (the CRM rejects duplicates in the create call; hold window forced to 0 minutes), `async` (the partner reports duplicates by event; `hold_minutes`, default 30) or `none`. `duplicate_window_hours` (24): a duplicate claimed after acceptance inside it becomes a commission dispute, not a re-route. Confirm the mode with the partner's developer: it decides whether the student is told the partner's name at once or after 30 minutes.
   Check: `select dedupe_mode, hold_minutes, duplicate_window_hours from b2b.partners where slug = '…';`.
3. **Caps, minimums, criteria.** Settings tab: `daily_cap`, `monthly_cap`, `contract_min_monthly` (served first while behind), `lead_criteria` (JSON object: geography, qualification etc.; a lead that fails it is excluded; unknown values pass or fail per setting `engine.criteria_unknown`, default `fail`), `working_hours` (per weekday; default Mon–Fri 10–19, Sat 10–17 IST), `holidays`, `sla` (defaults: first attempt 2 working hours, first connect 1 working day, counselling 5 working days, status update every 7 days, enrolment proof 7 days), `notify_enabled` (whether the student is told this partner's name).
   Check: Partners → partner → Overview shows the caps and SLA; the go-live checklist item `sla_hours` turns done.
4. **Agreement and data-processing terms.** Spec B8.3.8 item 1 and B18 require a signed DPA before go-live. **Not built:** every version of `b2b.partner_checklist` hard-codes `agreement` as `done: false, available: false`, and `b2b.partner_set_live` refuses while any item is not done. **Today no partner can be switched live** until a migration either builds the agreement upload (`partner_documents`) or marks the item done/available. Raise this with Vikas before the first partner **[Vikas]**.
   Check: Partners → partner → the live switch error reads `go-live checklist incomplete: agreement, …`.
5. **Connection (adapter).** Connection tab, per environment (Sandbox first, then Live). Enter the non-secret settings and the keys (Vault). What each CRM needs from the partner is in `docs/partner-adapters.md` ("What the partner must do"): a reference field (`mx_Eduwit_Reference`, `Eduwit_Reference`, `Eduwit_Reference__c`, `eduwit_reference`), duplicates set to fail, an API user for sandbox and live. For a partner with its own CRM choose **In-house CRM** (create-lead URL, auth type, header name, wrapper key, record-ID path, duplicate HTTP status, changed-leads URL with `{since}`) or give them `docs/partner-api.md` to implement (`generic_rest` / `webhook`). Generate the **inbound signing secret** here and hand it over once.
   Check: **Preview a push** shows the exact create call with credentials masked; **Fetch fields** stores a schema snapshot (Mapping studio → Schema). Checklist item `credentials` turns done (needs `api_base_url`, an outbound credential or auth `none`, and the inbound secret).
6. **Programme sheet (Programme Repository).** Programme Repository (`/programmes`) → partner → upload the partner's `.xlsx` or CSV (template: `/programme-sheet-template.csv`; old `.xls` must be re-saved), or connect a Google Sheet shared as "anyone with the link can view" and press **Sync now**. Map the columns once (saved as the partner's template), review the rows the matcher flags, check the preview against live offers, **Publish**. Publishing writes `b2b.partner_programmes` (the routing candidates) and confirms the sheet's **commission %** column as partner + programme rates (`rates_from_offers`).
   **GST toggle:** the % is read as GST-inclusive by default (`partner_programme_sources.commission_includes_gst`). Untick *The % includes 18% GST* on the partner's Live programmes tab if the sheet states commission before GST. A programme missing from the catalogue becomes a `b2b.catalogue_requests` row for Vikas to approve **[Vikas]**; it cannot route until then.
   Check: `select count(*) from b2b.partner_programmes where partner_id = <id> and active and valid_to is null;` > 0; checklist item `programmes` done; Routing → Commission rates lists the file rates with source `file`.
7. **Rates the sheet cannot express.** Routing (`/routing`) → **Commission rates** → Level *Partner-wide* or *One university*: percent (of first-year or total fee), fixed rupees, or **tiered** (`0: 22.42, 7: 20.42, 9: 18.42` = conversion % → rate %). Tiered partners are compared on the **middle tier** at cold start (Addendum 3 PART 4). Precedence: partner+programme → partner+university → partner → programme → university. Rates are versioned, never edited.
   Check: Routing → Commission rates shows the rate with `valid_from` today; `select scope, rate_type, valid_from from b2b.rates where partner_id = <id> and valid_to is null;`.
8. **Mapping.** Mapping studio (`/mapping/<partnerId>`): map the partner's stages to Eduwit stages (**Status map** / Stages tab; a mapped `lost` sends the lead to B2C nurture after the 7-day grace), fields, picklist values, activities; add golden files; Publish. Required for `mapping_ready` (100% of required items and every golden file passing).
   Check: checklist item `mapping` done; Mapping studio → Test runs a sample event through to a lead.
9. **Branding.** `display_name`, `logo_url`, `brand_color` set; Notifications → Templates → preview per partner.
   Check: checklist item `branding` done.
10. **Test push to the sandbox.** Routing → **Simulate**: pick or create a test lead (phone `910000…`), route it to the partner sandbox (`test_endpoint`). Spec B8.3.8 asks for 10 test leads including one forced duplicate and one taken through every stage.
    Check: Partners → partner → Connection → Pushes table shows the push with the partner's **record ID** found and status `accepted` after the hold window; a forced duplicate is read as `duplicate`; `select status, partner_record_id from b2b.allocations where partner_id = <id> and is_test;`. Checklist item `test_leads` done (needs one test allocation `accepted` or `closed`). Then delete the test leads (section 7 step 8).
11. **Activate and switch live.** Settings tab → status `active` (`partner_set_status`). Then the live switch (`partner_set_live` → live switch `partner:<id>`). It is refused until every checklist item is done (see step 4). Live polling starts for CRM adapters; the partner's own `poll_minutes` (2–1,440, Connection → Fields and polling) wins over the global interval; turn polling off if the partner sends webhooks.
    Check: `select scope, live, reason, switched_at from b2b.live_switches where scope = 'partner:<id>';`; Command Center partner card shows "live".
12. **Partner billing details** (needed before the first invoice, section 13): Commission & Finance → Partner billing details: legal name, GSTIN or state code, billing address, accounts email, payment terms.

---

## 4. Consent

Without partner-sharing consent the engine sends every qualified lead away from partners (R8 asks for it; on "no" or no answer the lead goes to B2C). This is the hard prerequisite of Addendum 3 PART 7.

1. **The wording.** Every consent line must cover sharing with "our admission partners (edtech companies)", not only universities: Witty's first-reply notice, the website agent's sign-up, every website and landing-page form, and the Meta and Google lead-form disclaimers. The lawyer must approve the wording **[Vikas]**. Also the one-tap request: "To connect you with the best admission counsellor for {{programme}}, may we share your details with our admission partner? Reply YES or NO."
2. **Register each text** in `b2b.consent_texts` (`version`, `channel`, `purposes`, `body`, `covers_admission_partners`, `active`, `lawyer_approved_at`). `m31a` seeds `witty-notice-2026-10-v2`, `witty_partner_consent_v1` and `wa_partner_consent:v1` with `covers_admission_partners = true` but **no `lawyer_approved_at`**; it also copies every version already used by ad forms and leads with `covers_admission_partners = false`. The Admin function to edit them (`consent_text_save`) is planned in `m31l` and its screen is not shipped yet: check Routing → Hand-off rules (or wherever the Addendum 3 web step puts it) once `m31l` lands. Until then an approved text is recorded in the SQL editor by Vikas.
   Check: `select version, channel, covers_admission_partners, active, lawyer_approved_at from b2b.consent_texts order by version;`. Every version your forms send (section 7) must be in this table with `covers_admission_partners = true` and a lawyer date, or its leads will not count as consented (`stamp_uncovered`).
3. **Stamp consent at the source.** Each source writes `consent_partner_share_at` and `consent_text_version` on the lead through `lead_intake()`:
   - Witty: edits 3, 4 and 9 of the workflow half set `state.consent_partner_share_at` and `consent_text_version = 'witty-notice-2026-10-v2'` (section 6).
   - Intake API: `consent.partner_share_at` and `consent.text_version` in the body.
   - Meta and Google forms: the form's consent text, version and purposes on Intake → Meta and Google lead forms (`b2b.lead_forms.consent_text / consent_version / consent_purposes`; purposes must include `partner_share`).
   - Imports: the consent basis step of the wizard (routing to partners needs partner-share consent).
   - Manual entry: Intake → New lead asks how the student agreed and for which purposes.
   Check: `select consent_partner_share_at, consent_text_version from student_leads where id = <test lead>;` after one test lead per source.
4. **Consent policy settings.** `engine.consent_policy` = `ask` (default: a lead with no consent gets the one-tap request; YES → partners, NO → B2C sales, no answer in 48 h → B2C nurture) or `b2c_sales` (the pre-Addendum rule: straight to B2C sales). `engine.consent_admin_yes` (default false: the Admin may record a YES only with evidence). `engine.consent_requests_per_hour` (100).
5. **What the routing go-live gate checks** (`b2b.routing_golive_check()`, planned in `m31e`; the switch `set_live_switch('routing', true, …)` refuses with `routing cannot go live: …` while a blocking item fails):

   | Key | Blocking? | Passes when |
   | --- | --- | --- |
   | `consent_texts_approved` | yes | the covering consent texts are active and lawyer-approved (exact rule: check `m31e` when it lands) |
   | `witty_w1_consent_line` | yes, unless acknowledged with a reason | Witty's workflow half (the new consent line) is live |
   | `b2c_endpoint_subscribed` | yes | an active `b2c_crm` webhook endpoint subscribes to `b2c.consent_requested` (section 5) |
   | `witty_w2_consent_request` | yes, unless acknowledged | Witty can send the one-tap request itself (release W2, not built); acknowledge to let the B2C number send it instead |
   | `live_partner` | warning only | at least one partner is live |

   Acknowledgements go through `b2b.routing_golive_ack(key, reason)` into setting `golive_acks`.
   Check: `select b2b.routing_golive_check();` once `m31e` is applied; Command Center and Routing show the same list.

---

## 5. B2C CRM connection

The B2C CRM (in-house counsellors, nurture) is a separate product with its own developer. Give them `docs/b2c-contract.md` (version 2 today; version 3 adds `b2c.consent_requested`, `b2c.consent_closed`, `b2c.lead_requalified`, `b2c.lead_reengaged` and `contract_version: 3` in the envelope, per the Addendum 3 contract). Whether a B2C CRM exists yet to connect is not in the sources: check with Vikas **[Vikas]**.

1. **Hand over credentials** (System health → Webhooks and API keys): the API key from section 1.4 (`b2c` + `events` + `intake`) and the endpoint's signing secret (next step). Once each, secure channel.
2. **Register their webhook endpoint.** System health → Webhooks and API keys → Webhook endpoints → New: name, consumer `b2c_crm` (at most one), their HTTPS URL, events. Subscribe to **`b2c.*`** (covers `b2c.lead_handed_off`, `b2c.lead_upserted`, `b2c.lead_released`, `b2c.leads_batch`, `b2c.lead_reenquired`, `b2c.lead_flagged`, `b2c.lead_close_agreed`, and the v3 types `b2c.consent_requested`, `b2c.consent_closed`, `b2c.lead_requalified`, `b2c.lead_reengaged`) **plus `b2b.lead_routed_to_partner`**. Press **Generate secret** (shown once), **Send test** (a `ping` with `test: true`), and switch the endpoint **on** once they confirm the signature check passes. Nothing is delivered before that.
   Check: System health → Webhook deliveries shows the `ping` as delivered (HTTP 2xx); `select name, consumer, active, events from b2b.webhook_endpoints;`. The go-live item `b2c_endpoint_subscribed` passes only with `b2c.consent_requested` covered.
3. **Their endpoints** (contract §3–4): `GET /v1/handoffs?after=` (reconciliation feed), `GET /v1/b2c/schema`, `GET /v1/b2c/leads?after=` (change feed), `GET /v1/b2c/leads/{id}`, `PATCH /v1/b2c/leads/{id}`, `POST /v1/b2c/leads/{id}/activities`, `POST /v1/b2c/leads/batch`, `POST /v1/leads/{id}/route-to-partners`, `POST /v1/leads` (new students, `lead_source` `b2c_created` / `b2c_whatsapp`), and signed `POST /v1/events/b2ccrm` (`b2ccrm.opted_out`, `b2ccrm.erasure_requested`; v3 adds `b2ccrm.partner_consent` and `b2ccrm.consent_request_sent`).
4. **Link settings.** B2C CRM link (`/b2c`): `b2c_link.enabled`, `scope` (`held`: leads B2C holds; `all`: every lead read-only), `writable` (which fields B2C may write; default every B2C-owned field). Keep `delivery = realtime` until section 14.
   Check: `/b2c` → Overview shows the checklist steps; `select value from b2b.settings where key = 'b2c_link';`.
5. **The welcome message** (Addendum 3 Amendment 1). When an unqualified Witty lead is pushed to B2C qualification nurture after 18 idle hours, the hand-off event asks the B2C CRM to send a WhatsApp prompting the student to explore programmes. B2B sends nothing itself. The B2C developer needs a **Meta-approved template on the B2C number** (free-form is not allowed from a number the student never wrote to). Setting `engine.welcome_for_all_nurture` (default false) widens the ask to every nurture hand-off.
   Check: the `b2c.lead_handed_off` payload for a nurture test lead carries the welcome request (`b2b.handoff_payload`; check the exact key once `m31b`/`m31j` are on production).
6. **Round robin** for duplicate-cascade leads (B2C sales lane, badge "Already with other providers") and for partner-lost nurture leads that show interest again is the **B2C CRM's** job (PART 5.4, PART 6.1). B2B only emits the events. Confirm with the B2C developer.
7. **Test with `9190000000NN` phones** in the order of contract §6: `ping` verifies; a test lead without partner consent arrives as `b2c.lead_handed_off` (`reason: no_partner_consent`) and `b2c.lead_upserted` version 1; `GET /v1/b2c/leads?after=0` lists it; a `PATCH` with `stage: "assigned"` returns version 2 and echoes back; a repeated `request_id` replays; stale `if_version` → 409; an activity raises `contact_attempts`; writing `student.phone` → 422; a signed `b2ccrm.opted_out` → 200. Routing must be on for the hand-off to happen (section 11), so run this test on **staging** first, or on production right after switching routing on.
   Check: B2C CRM link → Inspect a lead shows every version and delivery; System health → Events from the B2C CRM lists the opted-out event.
8. **Moving the current B2C CRM off direct table access** (contract §5) is the B2C developer's work. B2B cannot detect direct writes (no trigger on the shared table). Until it is done, both products write `student_leads` directly.

---

## 6. Witty (release W1, workflow half)

Witty is the live WhatsApp bot (+91 96439 77407). Its database half is done; the workflow half is not. The procedure, checks, harness, publish and rollback are all in `b2b-crm/witty/WITTY_CHANGES_PROMPT.md`; the hand-edit alternative is in `b2b-crm/witty/README.md`.

1. **Confirm the editor lock [Vikas].** Nobody else (including the "Locbizz Solution" MCP agent) edits "Eduwit Witty" `PKPs7tXg9bej8AgX` until done. `get_workflow_history`: the newest and the published version must both be `1f79392c-ec02-4daf-a090-1d9d9dbb0a60` (5 Oct). If anything is newer, stop.
2. **Run `WITTY_CHANGES_PROMPT.md`** in a Claude Code session on Vikas's machine, in the Eduwit CRM folder (`CLAUDE.md`, `crm/`, `witty2/`), with the n8n and Supabase connectors. It: verifies the database half read-only; runs the harness once on the current version (`run_tag w1a3-before`, must be 20/20); asks Vikas about the consent wording (full release, or without edits 3/4/9) **[Vikas]**; patches the six nodes by exact find-and-replace with md5 checks (`Plan Reply`, `Verify Reply`, `Verify Rewrite`, `Finalize Counselor`, `Assemble Commit`, `Validate + Decide`); saves a draft; runs the harness on the draft (`1BGAINw5XDkSHb2q`, five scenarios, 20/20, with the turn-8 "academic counsellor" proof that the draft ran); publishes; watches 30 minutes; cleans up the `910000…` test leads. Rollback: publish version `1f79392c…` again.
   Check: `md5` of each node's `jsCode` equals the "After" column in `witty/README.md`; `w2_test_runs.summary` for the run tag is 20/20; `select count(*) from w2_outbox where created_at > <publish time> and last_error is not null;` is 0.
3. **What the database half already does** (live since 7 Oct 09:40 UTC): `w2_crm_owned` is true only when a partner allocation is `accepted` or a B2C counsellor is assigned (`owner_user_id`), so Witty keeps talking during a partner's hold window and to B2C leads with no counsellor; `w2_nurture_due` skips Witty's own follow-ups once the B2B CRM has routed the lead (`destination_type` set); `w2_crm_payload` sends `consent_partner_share_at` and `consent_text_version` from the chat state (empty until the workflow half ships); `w2_commit_turn` logs touchpoint `lead.interest` for interest intents on B2C-held leads; extractor prompt v5.
   Check (read-only): `select pg_get_functiondef('public.w2_crm_owned(text)'::regprocedure) like '%a.status = ''accepted''%';` is true; `b2b.witty_backup_20261007` holds the previous definitions.
4. **After a successful publish**, keep the sources from reverting it (prompt §5): copy the four functions into the old CRM's `crm/sql/001_lead_intake.sql` (re-running the old 001 would revert them), update `witty2/project` and its tests, `crm/sql/test_lead_intake.sql`, and the `CLAUDE.md` line on `w2_crm_owned`. Never run n8n's "Setup Request" webhook or its nodes.
5. **Decisions Witty still needs [Vikas]** (prompt §7): how a later "don't share my details" is recorded (`consent_partner_share_at` is write-once); whether the Chatwoot "Counselor Brief" + `witty-handoff` label stay for every escalation (Chatwoot has no counsellor team, so hand-offs are unassigned); whether Witty's 3-hour follow-up keeps running before the 18-hour hand-off; whether click-to-WhatsApp students without an access code must be recorded.
6. **Release W2** (prompt §8) is not built and waits for the B2B Addendum 3 engine: clearing Witty's escalation pause for B2C nurture leads, recording "Witty again" messages on CRM-owned leads, the one-tap consent request from Witty's number (PART 7.2), and the qualification-assist counsellor rule. Until W2, acknowledge `witty_w2_consent_request` in the go-live gate so the B2C number sends the request.

---

## 7. Lead sources

Every source ends in `b2b.intake_lead` → `public.lead_intake()`, so a known phone is merged, never duplicated. Contract: `docs/intake-api.md`.

1. **Meta Lead Ads.** Intake (`/intake`) → Connections → Meta: a verify token (any long random text, 8+ chars), the Meta **app secret** (webhook signatures), a long-lived **Page access token** with `leads_retrieval`, Graph API version (`v21.0`). Saved to Vault by `intake_settings_save`. In the Meta app dashboard: Webhooks → Page → subscribe to `leadgen`, callback `https://<crm host>/v1/webhooks/meta/leadgen`, the same verify token; subscribe the Page to the app. `b2b-intake-tick` (10 s) fetches each lead from the Graph API, 3 retries.
   Check: Meta's "Test" button on the webhook → Intake → Latest requests shows the request; a real test form fill appears as a lead within a minute; `select source, status, created_at from b2b.intake_requests order by created_at desc limit 5;`. A bad signature raises `alert.intake_bad_signature`, a failed fetch `alert.intake_failed` (Command Center → alerts).
2. **Form mapping.** A form Eduwit has not seen is added to Intake → Meta and Google lead forms with `alert.intake_new_form`. Standard questions (name, phone, email, city, state, country) map by themselves; everything else lands in notes until you map question → lead field, fixed values, and the form's **consent text, version and purposes** (`partner_share` included).
   Check: `select platform, name, consent_version, consent_purposes from b2b.lead_forms;`; the next lead from that form has `interested_course` and `consent_partner_share_at` set.
3. **Google Ads lead forms.** Intake → Connections → Google: a key (8+ chars). In the lead form asset → Lead delivery → Webhook integration: URL `https://<crm host>/v1/webhooks/google/leadform`, the same key. Google sends it in the body as `google_key`; a wrong key gets 401 and an alert. Use **Send test data**: Google marks it `is_test` and the CRM stores a test lead.
   Check: the test lead appears in Leads with the test badge; `select is_test, lead_source from student_leads order by id desc limit 1;`.
4. **Website and landing-page forms (Intake API).** The site's **server** calls `POST https://<crm host>/v1/leads` with `Authorization: Bearer <intake key>`, a unique `Idempotency-Key` per submission, the body in `intake-api.md` §1: `lead` (only `phone` required), `source`, `channel`, `campaign`, `utm`, `click_ids` (`gclid`, `fbclid`, …: needed for CAPI and attribution), `landing_url`, `consent` (`sales_at`, `partner_share_at`, `marketing_at`, `text_version`), `phone_verified` (true only after an OTP), `occurred_at`, `route` (`auto` / `hold` / `b2c` + `b2c_lane`). Unknown keys are refused with 400, so a typo cannot drop data silently. 600 requests a minute per key.
   Check: the `curl` example in `intake-api.md` §3 with a `910000…` phone returns 201 and `{"ok": true, "is_test": true, "routing": {...}}`; a replay with the same key returns 200 with header `Idempotent-Replayed: true`. Move the website forms from the old CRM's `/api/v1/leads` to the new URL (`b2b-design.md` §7.1).
5. **Website agent OTP.** `/api/v1/verify/*` stays in the old CRM (it belongs to the website agent and B2C). Leads from `website_agent` / `web_agent` need a verified phone (`engine.require_verified_phone_sources`) before they are qualified.
6. **Imports.** Intake → Import a file: `.xlsx` or CSV, up to 50,000 rows / 15 MB (no `.xls`). Map columns (template saved), check courses against the catalogue, see duplicates, record the consent basis, choose route now / hold for review / send to B2C. Rollback for 24 hours while nothing has routed the leads. Held leads wait in the pool group `held` until Intake → Release.
   Check: Intake → Imports shows the job as done with counts; `select status, rows_total, rows_done from b2b.imports order by id desc limit 1;`.
7. **Manual entry.** Intake → New lead (`intake_manual`): consent (how and for which purposes) is mandatory.
8. **Test leads.** Phones `910000…` and `9190000000NN` are stored as `is_test`, hidden from Leads unless asked, never routed to a live partner, never messaged, never sent to CAPI. Clean them up after each test: the lead's `w2_*` rows (if Witty created it), then `delete from student_leads where id = <id> and is_test;` one row at a time (the bulk-delete guard blocks more than 5 rows; never set `crm.allow_bulk_delete` for test data).
   Check: Leads → filter "test" shows none left.
9. **Switch off the old path [Vikas].** Once Meta leads arrive through the CRM for a few days, deactivate the n8n workflow **Meta Leads to WhatsApp Alert** `M4WnPdy9MEXsj30d`.

---

## 8. Student messages (WhatsApp and email)

Once a partner **accepts** a lead (hold window passed with no duplicate or rejection), the student gets one WhatsApp message and one email naming the partner, inside quiet hours. B2B never messages a student handed to B2C (the B2C CRM does), never a test lead, never an opted-out student, never for a partner with `notify_enabled = false`.

1. **WhatsApp provider.** Notifications (`/notifications`) → Providers and quiet hours: **Phone number ID** (Meta Business Suite → WhatsApp → API setup), a **permanent system-user access token** (Vault), Graph API version. Messages go straight to Meta's Cloud API from Postgres (`pg_net`), not through Chatwoot. **Which number [Vikas]:** the design (`b2b-design.md` §6) sends from Witty's number (+91 96439 77407, Chatwoot inbox 4) so replies land in Chatwoot; spec B21 leaves "same number as Witty, or a separate one" open.
   Check: the field shows "Access token (stored)"; `select value -> 'whatsapp' ->> 'phone_number_id' from b2b.settings where key = 'notifications';`.
2. **WhatsApp templates.** In Meta Business → WhatsApp Manager → Message templates, submit a **utility** template with 5 body parameters in English and one in Hindi/Hinglish, body as in spec B9: "Hi {{1}}, thank you for your interest in {{2}}. An academic counsellor from {{3}} will call you on this number {{4}} to guide you on admission and next steps. If you need help in the meantime, contact Eduwit at {{5}}. — Team Eduwit" ({{1}} student first name, {{2}} programme, {{3}} partner display name, {{4}} expected contact window, {{5}} Eduwit support contact). After approval, Notifications → Templates → the `accepted` WhatsApp template (`en`, `hi`): enter the **approved template name** (`wa_template`) and set status **active** (`template_save` refuses activation without the name). Also `reroute_update` for manual re-routes.
   Check: `select kind, channel, language, status, wa_template from b2b.message_templates;` shows `active` with a template name for the WhatsApp rows.
3. **Email provider.** Same screen: provider `resend` or `brevo`, **API key** (Vault), sender address on Eduwit's domain, sender name (`Team Eduwit`), reply-to. Add the provider's **SPF, DKIM and DMARC** records on the sending domain (the old CRM's SMTP is not used: `pg_net` speaks HTTP only). Activate the `accepted` email templates (`en`, `hi`).
   Check: the provider dashboard shows the domain verified; the field shows "API key (stored)".
4. **Quiet hours and support contact.** Same screen: quiet hours 08:00–21:00 IST (a message due outside is scheduled for 09:00), **Eduwit support contact** (5–120 chars, required, staffed phone or email; it is `{{5}}`), unsubscribe link.
5. **Live switches.** Notifications → the `whatsapp` and `email` switches (`set_live_switch`). A message due while its switch is off is **cancelled**, not sent late. Turn them on only after the templates are active and a provider test passed.
   Check: `select scope, live from b2b.live_switches where scope in ('whatsapp', 'email');`.
6. **Test and watch.** Accept a test allocation on staging: the Send log shows the message as a dry run / cancelled for a test lead (test leads never use a live channel). The first real acceptance after go-live: Notifications → Send log row `sent` with a provider message ID; `select channel, status, error, sent_at from b2b.student_notifications order by created_at desc limit 5;`. A failure retries once, then `alert.notification_failed` and the lead drawer's Routing tab shows why.
7. **Replies.** A student who replies to the WhatsApp message reaches Chatwoot (if sent from Witty's number) where Witty is silent once `w2_crm_owned` is true; a human must answer. Delivery and read receipts (provider webhooks) are not built.

---

## 9. Admin alerts and scheduled reports

Nothing is sent until the Admin switches it on and enters recipients. Spec: `docs/dashboards-reports.md` §3–4.

1. **Where alerts go.** Dashboards (`/dashboards`) → Alerts and e-mails → **Where alerts go**: `admin_alerts.enabled`, `emails[]`, `whatsapp_numbers[]`, `whatsapp_template` + `whatsapp_language`, `digest_minutes` (5–1440, default 15), `types[]` (default: partner auto-paused, NCPL drop, model fallback, SLA breach, reconciliation items, bad partner signature, failed student notification, AI budget, AI run failed, routing error).
2. **Provider.** Email uses the provider from section 8 (Resend/Brevo key in Vault). WhatsApp uses the same Cloud API number and token, but needs **its own Meta-approved template with exactly one body parameter** (the digest text, up to 900 characters; parameters cannot hold newlines). Submit it in WhatsApp Manager, then enter its name as `whatsapp_template`.
3. **Send a test.** The *Send a test* button queues one message per channel.
   Check: Dashboards → Messages to you shows it `sent`; `select kind, channel, status, provider_response from b2b.admin_messages order by created_at desc limit 3;`.
4. **Metric alerts.** Same screen: a threshold on any metric with filters and a window (for example duplicate rate for one partner over 24 h above 30% with at least 20 leads), checked every 5 minutes, cooldown 24 h. Add at least: duplicate rate, SLA compliance, pushes failed, CAPI failed.
5. **Scheduled e-mails.** Dashboards → Scheduled delivery: a dashboard or saved report daily / weekly / monthly at an hour (IST) to a list of addresses; tables attached as CSV. Reports (`/reports`) for tabular, summary and matrix reports.
   Check: the first scheduled run appears in Messages to you; a failure retries an hour later and raises an alert.

---

## 10. Conversions (CAPI): Meta and Google

Reports how far each lead from a **paid** Meta or Google ad got, only to the platform that brought it. Guide: `docs/capi-setup.md`. Nothing is sent until a platform's switch is on. Test leads are logged as dry runs.

1. **Consent basis.** Conversions (`/capi`) → Setup → consent: `marketing` (default) or `contact`. Only students with that consent are reported; others are logged as skipped and sent if consent arrives within 7 days (Meta) / 90 days (Google).
2. **Meta.** Events Manager → the dataset (pixel) your lead forms and site use → Settings → Conversions API → generate a token. Setup: `dataset_id`, token (Vault), API version, a **test event code** from Events Manager → Test events while testing. For Lead Ads set up the CRM integration (conversion leads) with the same stage names as the "Meta event name" column: Qualified Lead, Interested, Applicant, Enrolled. Turn the `capi_meta` switch on; watch Test events; then clear the test event code.
   Check: Events Manager → Test events shows events from "Eduwit CRM"; `select platform, status, count(*) from b2b.conversion_events group by 1, 2;`.
3. **Google Ads.** Create one conversion action per signal (Qualified lead, Interested, Applicant, Enrolled) via Import → CRMs, files or other data sources → Track conversions from clicks; copy each `customers/<id>/conversionActions/<id>`. API Center → developer token. Google Cloud → OAuth client; refresh token with the `adwords` scope for a user on the Ads account. Setup: `customer_id`, `login_customer_id` (if through an MCC), developer token, client ID, client secret, refresh token (all secrets to Vault), and each signal's conversion action. Accept enhanced-conversions terms in Google Ads. Turn `capi_google` on.
   Check: Google Ads → Conversions → Diagnostics shows uploads received; `alert.capi_auth` absent.
4. **Quality ladder and values.** Setup → *Signals and their value*: enrolled (verified) = expected then realised net commission; applicant 40%; interested 15%; qualified 5%; default commission ₹15,000 when the allocation has none. Weak signals (lead received, accepted, contacted, disqualified) stay off; the junk "disqualified" signal is sent only when Routing → Hand-off rules → junk signal (`engine.junk_capi_signal`) is on. Optimise each campaign for the strongest signal with about 50 events a week.
5. **Campaign attribution.** Every lead gets a `b2b.lead_campaigns` row (platform, paid, campaign/ad set/ad, form, UTMs, click key). Only leads with a Meta lead ID or a click ID (`fbclid`/`fbc`, `gclid`/`gbraid`/`wbraid`) are matchable; UTM-only leads are recorded but not sent, so the website must pass the click ID to the Intake API. Under Addendum 3 "paid" is an attribution label only, never a routing rule; the paid lists on Routing → Hand-off rules (paid sources, click IDs, utm_medium values, always/never-paid campaigns) feed attribution and reports. The `attribution` setting (`m31a`) and its save (`m31g`) refine this.
   Check: Conversions → Campaigns lists the paid campaigns with leads, matchable count and events sent; Conversions → **Check a lead** on a `910000…` test lead shows its campaign, identifiers, consent and the exact dry-run payload.
6. **Failures** retry at 1, 5, 30 minutes, 2 h, 6 h, then dead; refused events are `rejected`; `alert.capi_failed` / `alert.capi_auth` on the Command Center; Retry on the Event log.

---

## 11. Routing go-live

Do this only after sections 3 to 8 are green for at least one partner and the B2C link. Rulebook: `docs/B2B_CRM_ADDENDUM_3.md` (PART 3 order R1–R9, PART 4 stages A/B/C, PART 5 after push, PART 6 later movements, Amendment 1).

1. **Confirm the Addendum 3 engine is on production.** The engine (`m31f route_decide`), consent asks (`m31e`), re-decide (`m31k`) and admin reads (`m31l`) are planned, not yet in the migrations folder (section 0). Until they land, `route_decide` is the `m24b` version (Addenda 1–2 rules, paid → B2C, no 18-hour wait, no partner bar). **Do not switch routing on with the old engine** unless Vikas accepts those rules **[Vikas]**.
   Check: `select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2b' and proname in ('routing_golive_check', 'consent_request_create', 'requalify_lead', 'partner_bar');` returns all four.
2. **Engine settings to review** (Routing → Engine settings; setting `engine`; saved as a new version with a reason by `engine_settings_save`). **Caution:** the shipped Engine settings form still shows pre-Addendum-3 fields (kill switch, fixed split, witty idle minutes, trusted sources, exploration share, attempt limits, require consent). After `m31a` the save **refuses** those keys (`retired by Addendum 3` / `fixed by Addendum 3`), and the Addendum 3 fields are not on the form yet. Until the web step ships, review them in SQL (`select value from b2b.settings where key = 'engine';`) and change them with `select b2b.set_setting('engine', <new json>, '<reason>');` as the Admin:

   | Key | Default | Range | Meaning |
   | --- | --- | --- | --- |
   | `witty_unqualified_idle_hours` | 18 | 1–72 | Amendment 1: an unqualified Witty lead is decided (B2C nurture) only after this many hours with no student message |
   | `effort_factor` | `{enabled true, bounds [0.85,1.15], weights {first_call, attempts_72h, connect_rate, followup, acts_per_open, stale_share} = 1 each, min_sample 10}` | bounds inside 0.85–1.15; weights 0–5; min_sample 3–100 | Stage B/C sales-effort multiplier; a partner that syncs no activity never gets above 1.0 |
   | `sla_factor` | `{enabled true, floor 0.80, ceiling 1.00, step 0.05, weights {first_attempt, status_update, enrollment_proof} = 1 each}` | 0.80 ≤ floor ≤ ceiling ≤ 1.00; step 0.01–0.20 | Stage B/C SLA-adherence multiplier (0.05 per 10 points below 100%) |
   | `consent_policy` | `ask` | `ask` / `b2c_sales` | R8 behaviour (section 4) |
   | `consent_admin_yes`, `consent_requests_per_hour` | false, 100 | —, 10–1000 | Admin-recorded YES needs evidence; rate limit on asks |
   | `reenquiry_quiet_hours` | 24 | 1–168 | How often a re-enquiry on a held lead is re-announced to B2C |
   | `max_interests` | 5 | 1–10 | Secondary interests tried before falling back |
   | `criteria_unknown` | `fail` | `pass` / `fail` | A partner criterion the lead has no value for |
   | `welcome_for_all_nurture` | false | — | Ask B2C to send the welcome message for every nurture hand-off, not only the 18-hour Witty case |
   | `require_verified_phone_sources` | `[website_agent, web_agent]` | — | Sources whose leads need an OTP-verified phone |
   | `requalify` | `{enabled true, wait_for_chat_gate true, max_per_run 25}` | max_per_run 10–100 | Nurture leads return to partner routing once qualified |
   | `guard.duplicate_rate_pause` | false | — | Auto-pause a partner when >25% of its last 20 leads were duplicates |
   | `spam` | Witty blocks on; 10 disposable email domains; 5 leads per IP / fingerprint per hour | 1–100 | R5 spam rules |
   | `b2c_sources`, `blocked_phones`, `junk_capi_signal` | `[b2c_created, b2c_whatsapp]`, `[]`, false | — | Routing → Hand-off rules |

   Fixed by the rulebook and **not** changeable (`engine.a3_fixed`): stage B after 20 leads each (oldest 7 days), stage C after 30 matured leads at 2 partners, maturity 60 days, exploration lane 20% while a partner has <30 leads, hold 0 (sync) / 30 (async) minutes, duplicate window 24 h, retries 10 s / 1 m / 5 m / 15 m / 40 m, attempt limit 2, partner limit 3, lost grace 7 days, consent wait 48 h, Witty idle 30 minutes, auto-pause after 5 breaches or 30 minutes of sync failure, CPE aggregate median.
   Also: setting `lost_nurture_delays` (`default` 14 days, `reasons {lost_reason: days}`, 3–90; `lost_delays_save` in `m31l`) decides when B2C's first nurture message after a partner-lost goes out; `engine_policy.holdout_share` 0.10 (10% of leads ignore AI changes).
   Check: `select version, reason, created_at from b2b.settings_versions where key = 'engine' order by version desc limit 3;` shows your change with its reason.
3. **Routing rules** (Routing → Rules): optional *always send to* (`fix_partner`), *only consider* (`narrow`), *never send to* (`exclude`) or *to B2C with a lane* (`to_b2c`), with conditions and priority. None are needed for go-live.
4. **Hand-off rules** (Routing → Hand-off rules): B2C-created sources, blocked phones, the paid lists (attribution only), junk CAPI signal.
5. **The go-live checklist.** `b2b.routing_golive_check()` (section 4 step 5) is shown on the Command Center, Routing → Overview and the Pool once `m31e`/`m31l` are live. All blocking items must pass or be acknowledged with a reason (`routing_golive_ack`).
6. **Switch routing on.** Routing → Overview → **Turn on automatic routing?** → reason for the audit log (for example "first partner live") → confirm. This calls `set_live_switch('routing', true, reason)`; it is refused with `routing cannot go live: <key>: <why>; …` while a blocking item fails. Also `engine.enabled` must be true.
   Check: `select live, reason, switched_at from b2b.live_switches where scope = 'routing';`; `select type, payload from b2b.events where type = 'live_switch.changed' order by id desc limit 1;`. Within a minute the pool group `due` empties and Routing → Overview counts today's decisions.
7. **Watch the first 48 hours.**
   - **Command Center** (`/`): today's leads, leads to partners and accepted (against the same hours yesterday), 7-day duplicate rate, first-contact SLA compliance, partner cards (today against the daily cap, pushes retrying or failed), the lead stream, **alerts**, every live switch.
   - **Pre-routing pool** (`/pool`): groups `test`, `opted_out`, `held`, `awaiting_consent`, `waiting_inactivity` (the 18-hour clock), `chatting`, `too_old` (90 days), `routing_off`, `due`, with where each lead would go. A growing `due` group means the sweep is failing: `select lead_id, why, decide_after from b2b.lead_waits where why in ('error', 'reroute_error', 'locked');` and `select * from b2b.events where type = 'routing.error' order by id desc limit 20;`.
   - **Decisions** (Routing → decision log → a decision): the stage used (A/B/C), every candidate's CPE, P(enrol), effort and SLA factors, score, exploration draw, holdout flag, and "why this partner". Spot-check the first ten by hand against the rulebook.
   - **Pushes** (Partners → partner → Connection → Pushes): record ID returned, duplicates read as duplicates, retries, acceptance after the hold window.
   - **Student messages** (Notifications → Send log) and **webhook deliveries to B2C** (System health → Webhook deliveries; `alert.webhook_dead` after 8 failed attempts).
   - **Not passed** (Leads → Not passed): junk and programme-mismatch leads, with **Pass to CRM** when Witty misclassified. **Review queue** (Routing): passed leads Witty later reclassified.
   - **Alerts in SQL:** `select type, count(*) from b2b.events where created_at > now() - interval '48 hours' and (type like 'alert.%' or type = 'routing.error') group by 1 order by 2 desc;`.
8. **Watch the first week.** Partner **Sync & SLAs** tab (events applied, held unmapped, dead letters; SLA scorecards; `partner_stale_at`); Mapping studio → Queue (unmapped stages/values: map them, held events re-apply in order); nightly reconciliation at 02:37 IST (`alert.reconciliation_items`; close items with a note); guardrails every 5 minutes (auto-pause after 5 first-contact breaches in a row, 30 minutes of push failure, or the duplicate rate if enabled; `alert.partner_auto_paused`); commission disputes (duplicate claimed after acceptance, late activity on a lost lead); the 7-day grace on partner-lost leads; consent requests (`select status, channel, count(*) from b2b.consent_requests group by 1, 2;`). Compare partner-reported counts with Eduwit's each day.
9. **How to pause.**
   - **All routing:** Routing → Overview → Turn off automatic routing (reason). New leads wait in the pool; the sweep stops. Pushes already queued, hold windows, notifications and sync keep running (check: `select status, count(*) from b2b.allocations where created_at > now() - interval '1 day' group by 1;`).
   - **One partner:** Partners → partner → Pause (reason). A paused partner receives no new leads; its open leads stay with it. Or turn its live switch off.
   - **One channel:** the `whatsapp`, `email`, `capi_meta`, `capi_google` switches. A student message due while off is cancelled.
   - **Emergency from SQL** (as the Admin): `select b2b.set_live_switch('routing', false, 'incident <ref>');`.
   - A kill switch with a fixed partner split no longer exists (retired by Addendum 3).

---

## 12. AI Optimiser (optional, costs money)

Claude reads aggregated, pseudonymised scorecards and proposes bounded engine changes. Advisory first: nothing changes until the Admin approves in the inbox. Guide: `docs/ai-optimiser.md`. Expect a few dollars a day at most; the daily budget is a hard stop.

1. **Anthropic key.** Vercel env `ANTHROPIC_API_KEY` (organisation key, zero data retention if available). Never stored in the database. Redeploy.
2. **Worker key.** System health → Webhooks and API keys → create a key with scope **`ai_worker`**; put it in Vercel env `AI_WORKER_KEY`. Redeploy.
   Check: AI Optimiser (`/ai`) → Set up card shows the key as seen and the worker key present (`select exists (select 1 from b2b.api_keys where 'ai_worker' = any (scopes) and revoked_at is null);`).
3. **Worker address.** AI Optimiser → Settings → Worker: `ai.worker_url` = `https://<crm host>`; the database wakes `<worker_url>/v1/ai/tick` when a run is queued.
4. **Budget and models.** `ai.daily_budget_usd` (default $5, 0–200); models for regular / deep / quick runs with their prices per million tokens (`ai.prices_per_mtok`; the save refuses a model without a price); `max_tokens` 12,000; schedules light / hourly / nightly / weekly.
5. **Switch on** (`ai.enabled = true`, `mode = advisory`). Autopilot stays locked until AI-steered leads beat the holdout over 4 weeks of matured leads (60–88 days after allocation), so it cannot be on for at least two months.
   Check: AI Optimiser → Runs shows the first light check or hourly run finishing `done`; Spend shows the cost; `select kind, status, cost_usd from b2b.ai_runs order by id desc limit 5;`. The inbox says "little to replay" until leads mature (60 days): that is expected.

---

## 13. Money (commission and invoices)

Guide: `docs/money.md`. Screen: Commission & Finance (`/money`).

1. **Money settings** (Settings tab; `money_settings_save`, versioned): `gst_rate` (0–0.28), `sac_code` (4–8 digits), `tds_rate` (0–0.20), `refund_window_days` (default 30), `invoice_prefix` (`EDW`), `tier_min_leads` (accepted leads before a tier is projected), `close_day` (1–28, default 7), `auto_close`, `confirmed_by_ca` (tick only when Eduwit's CA has confirmed GST, SAC and TDS **[Vikas / CA]**), and **Eduwit on the invoice**: `legal_name`, `gstin` (15 chars), `address`, `state_code` (2 digits), `bank`.
   Check: `select value -> 'eduwit' from b2b.settings where key = 'money';` has every field; an invoice cannot be approved without legal name, GSTIN, address and SAC.
2. **Partner billing** (section 3 step 12) for each live partner.
3. **Flow.** A partner stage mapped to `enrolled` → `b2b-money-tick` (5 min) records an enrolment *to verify* with an expected commission line → you **Verify** with proof (statement line, university confirmation or fee receipt; correct fee or date first) → realised, net of GST → month close on `close_day` settles tiers and builds one draft invoice per partner → **Approve** (sequential number `PREFIX/FY/0001`, IGST or CGST+SGST by state) → **Print or save PDF** and send it yourself (no e-mailing of invoices) → **Mark as sent** → **Record a receipt** (amount, TDS, UTR) → paid. Overdue invoices raise `alert.invoice_overdue` at due date, 30, 60, 90 days.
   Check: Commission & Finance → Overview totals and ageing; `select status, count(*) from b2b.invoices group by 1;`; test leads never earn commission (`enrollment_record` refuses them).
4. **Statements.** Upload the partner's statement (`.xlsx`/CSV, up to 5,000 rows) → the four piles (matched, amount mismatch, partner only, Eduwit only) → verify or record or dismiss; export each pile as CSV for the partner.
5. **Exports** for Tally / Zoho Books: sales register, receipts, earning lines (Overview → Export for accounts).

---

## 14. Sync cadence: switch to 15-minute batches

Real-time sync is for integration and testing (Vikas: real-time calls to partner CRMs and the B2C CRM cost too much). After the end-to-end tests pass:

1. **B2C CRM.** B2C CRM link → Sync cadence card: delivery **batched**, interval `sync.interval_minutes` (default 15, 5–60). Real students' changes then go out as one `b2c.leads_batch` per interval (100 leads per webhook, each at its newest version); test leads stay real time; the change feed, reads and writes are unchanged; the B2C CRM should batch its own writes with `POST /v1/b2c/leads/batch`. Tell the B2C developer the date.
   Check: `curl … /v1/b2c/schema` shows `"delivery": "batched", "interval_minutes": 15`; the card shows the next batch time; `select value from b2b.b2c_link_state where key = 'batch';` advances every interval; B2C CRM link → Overview checklist step 10 done.
2. **Partners.** Live polling of CRM adapters follows the interval unless the partner has its own `poll_minutes` (Connection → Fields and polling, 2–1,440). Turn polling off for partners that send webhooks. Sandbox polling stays at 2 minutes while test allocations exist.
   Check: `select b2b.sync_cadence();` lists each partner's polling and last poll.
3. **Not batched, on purpose:** pushing a new lead, student messages, CAPI.

---

## 15. Known limitations and not built

From `docs/b2b-design.md` §7.2 (as-built notes), the addenda, the feature guides and the sources above.

**Blocks go-live until fixed**
- Partner **agreement** checklist item is hard-coded not done; `partner_set_live` refuses every partner (section 3 step 4). Needs a migration.
- The Addendum 3 engine steps `m31e`–`m31o` and their web forms are not written; the shipped Engine settings form saves retired keys that the database now refuses (section 11 step 2).
- `routing_golive_check` / `consent_text_save` / `lost_delays_save` do not exist until `m31e` / `m31l`.
- Partner-sharing consent: no lead carries it today; Witty's workflow half is not applied; the lawyer has not approved the texts.

**Partners and sync**
- Partners **without an API** cannot be routed to automatically (no email or CSV push). Keep them paused; export leads from Leads and hand them over; reconcile their export on Sync & SLAs and their statement on Commission & Finance.
- No adapter (LeadSquared, Zoho, Salesforce, HubSpot, Meritto, in-house) has been run against a **real** account; all were tested on simulated replies. Salesforce's token call may need a server route (pg_net sends the grant as query parameters); Meritto's API shape varies by account; Zoho refresh tokens are per data centre.
- Google Sheet programme sources are read only on **Sync now**; no scheduled read (needs a Vercel Cron secret).
- `.xls` files are not supported (save as `.xlsx` or CSV); an import rollback does not undo merges into existing leads.
- Pushes are not paused automatically on mapping drift of a required field (alert and queue item only). Events are applied as they arrive, not strictly in order per lead.
- `describeSchema()` through partner APIs exists only for the five CRM adapters.
- Opt-outs and erasure are **not** forwarded to partners automatically (an Admin alert tells you to do it).
- The 7-day "lost, in grace" period is planned as allocation status `accepted` so Witty stays quiet; today `allocation_partner_lost` hands the lead to B2C at once (Witty prompt §9).

**B2C and Witty**
- The B2C CRM still reads and writes `student_leads` directly; B2B cannot detect direct writes (no trigger on the shared table). `b2c_enrollment_money_v` (B2C money in the Master Lead Table) does not exist.
- Witty release W2 (clear the escalation pause for B2C nurture leads, record "Witty again" messages, one-tap consent request from Witty's number (PART 7.2), qualification-assist rule) is not built. Chatwoot has no counsellor team, so every escalation's hand-off is unassigned; the `witty-handoff` label and brief still fire for leads that will go to a partner.
- Witty's "Register Lead" webhook is disabled (needs a header-auth secret); Witty nurture follow-ups 3–6 need Meta-approved templates (`eduwit-crm/CLAUDE.md`).
- A corrected Witty-owned field is not locked against Witty overwriting it (needs a `lead_intake` change, Vikas's approval). Bulk edit and inline grid editing are not built.

**Money**
- No e-invoicing (IRN), no e-mailing of invoices, no credit-note documents (a reversal shows on the next invoice), no proof file upload (a link is stored). PDF only via the browser's print.

**Messages and CAPI**
- WhatsApp delivery/read receipts and email bounces are not recorded (no provider webhooks).
- CAPI was never sent to live Meta or Google accounts; ad-spend import (cost per enrolment) is not built; UTM-only leads cannot be reported.

**Routing, AI and analytics**
- Stages B and C, performance mode and the per-lead model need matured data: stage B after 20 leads per competing partner (oldest 7 days), stage C after 30 matured (60-day) leads at 2 partners, the ML gate after 500 matured outcomes. Until then every decision is stage A (programme match, highest commission, 20% exploration lane).
- AI simulations have "little to replay" until leads mature; Autopilot is locked for at least 60–88 days after the first allocations; the AI-assisted programme-matching step (B5.2.3) is not built (costs money per call).
- Staging test runs for `m24`–`m30` were still listed as pending in `b2b-design.md`; the `m27–m30` analytics checks likewise.

**Housekeeping (from `eduwit-crm/CLAUDE.md` and `b2b-design.md`)**
- Google Cloud SQL instance `n8n-db` is stopped (n8n's database moved onto the VM `n8n-vm`); delete it and the `roles/cloudsql.client` grant on the compute service account after ~12 Oct if nothing broke **[Vikas]**. Do not delete Cloud Run service `n8n` (it forwards the old webhook address to the VM).
- `*_backup_20261004` / `*_backup_20261005` tables and `b2b.witty_backup_20261007` stay until Vikas says otherwise (planned review after 12 Nov).
- The old CRM's Exotel calls and MSG91 OTP were never tested against live accounts; they are B2C's, not the B2B CRM's.
- Pending SQL files in `b2b-crm/supabase/pending/` need a confirmed run in the SQL editor (section 0 step 8).
- A penetration test before go-live and a quarterly restore test are required by spec B18 and are not recorded as done.
