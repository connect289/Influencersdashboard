# Approvals needed

Changes to **shared** objects or to **other products' settings** that the website needs or would benefit from. None of
these have been applied to production. Shared-object migrations are in `supabase/migrations-shared/` and are applied
only to the local dev database and the `prod-replica`. Each item lists what, why, risk, rollback and who else is
affected. Status: ☐ awaiting owner · ☑ approved · ✗ declined.

**Blocking for go-live** items are marked 🔴. Everything else has a working fallback already built.

Every SQL proposal has a rollback file (`*.rollback.sql`) and, where it changes behaviour, a smoke test
(`migrations-shared/tests/`). On every build each one is applied, tested and rolled back to an identical state on the
production-schema replica (`check-shared-proposals.sh`); the full go-live sequence and rollback are rehearsed by
`scripts/db/go-live-dry-run.sh` — report in `docs/GO_LIVE_DRY_RUN.md`.

---

## Leads and routing

### 🔴 A-B2B-1 · Let website leads route without an OTP-verified phone
- **What:** in the B2B CRM's routing settings (Settings → Routing → engine, key `require_verified_phone_sources`,
  default `["website_agent","web_agent"]`), remove `website_agent` and `web_agent` — or change the rule so an
  email-verified website lead counts (code change in `b2b.lead_class`, B2B owner).
- **Why:** `b2b.lead_class` (`b2b-crm/supabase/migrations/m31d_a3_readiness.sql`) marks every lead that came through the
  website (lead_source in the list, or a `web_session_id`, or any `web_agent` touchpoint) as **unqualified /
  `phone_not_verified`** while `phone_verified_at` is null. The owner decided **no phone OTP at launch** (spec 7.2), so
  without this change no website lead would ever be routed to a partner or the B2C team.
- **Risk:** unverified phones reach partners. Mitigated by the email verification, Turnstile, junk-risk score and
  rate limits (spec 7.2); the website passes `phone_verified=false` honestly and never claims otherwise.
- **Rollback:** put the two values back in the list (settings change, takes effect on the next routing sweep).
- **Affects:** B2B CRM routing (owner: B2B CRM). No code change for the settings option.
- **SQL equivalent:** `supabase/migrations-shared/s07_b2b_routing_web_leads.sql` (through the CRM's audited
  `b2b.set_setting`; rollback file restores the two sources).
- **Status:** ☐

### A-LEAD-1 · `lead_intake()` accepts `email_verified_at` for `web_agent`
- **What:** add `email_verified_at` to the allowed keys when `source_system = 'web_agent'` (write-once, like consent).
  Migration: `supabase/migrations-shared/s01_lead_intake_email_verified.sql`.
- **Why:** spec 7.2 requires the email-verified flag on the lead. Today `lead_intake` silently drops it (the column
  exists on `student_leads`).
- **Fallback in place:** the verification is recorded in `web_email_verifications` (timestamp, method, lead id) and
  shown to staff through `web_lead_verification_v` (read-only view, proposed for the CRMs).
- **Risk:** low (one extra column in an allow-list; only `web_agent` may set it, write-once). **Rollback:**
  `s01_lead_intake_email_verified.rollback.sql` (production's body as of 17 Oct 2026, verbatim). **Test:**
  `migrations-shared/tests/s01.test.sql`. **Affects:** shared lead writer (Witty, CRMs call it; none of them send
  these keys today, so their behaviour is unchanged).
- **Status:** ☐

### A-LEAD-2 · Keep the fields Witty and the website already send
- **What:** keep `final_program_id`, `final_program_name`, `programs_shown`, `consent_partner_share_declined_at`
  (write-once) when Witty or the website sends them (silently dropped today). `student_leads` has no columns for
  them, so s01 merges them into the existing `custom_fields` jsonb (no new columns). Same migration file (s01).
- **Why:** an application from the website names one exact offering; without this the CRMs only see the course and
  university text. **Fallback:** stored in `web_applications` keyed by lead id. **Status:** ☐

### A-LEAD-3 · `junk_risk_score` and `phone_verification_method='none'` on the lead (optional)
- **What:** s01 keeps `junk_risk_score` from `web_agent` in `custom_fields` (no schema change). A dedicated nullable
  `smallint` column is only worth adding if the CRMs want to filter or sort on it.
- **Why:** spec 7.2 "a junk-risk score passed to the lead as a field if supported". Not supported today.
- **Fallback:** kept in `web_gate_attempts.junk_score` and in the lead's `Comments`-free attribution meta (`notes` is not
  used, so staff notes are never polluted). **Status:** ☐

## Consent

### 🔴 A-CONSENT-1 · Register the website consent text in the B2B CRM
- **What:** add the website's consent text versions (`web-gate-2026-10-v1` for the Witty gate,
  `web-form-2026-10-v1` for forms) to `b2b.consent_texts` (channel `website_agent` / `web_form`, active,
  `covers_admission_partners = true`, purposes `sales, partner_share`, lawyer approval date).
- **Why:** the B2B CRM counts partner-sharing consent only for registered, lawyer-approved text versions
  (`docs/go-live-setup.md` §4). Without it, website leads wait for partner-sharing consent.
- **Depends on:** lawyer review of the wording (S-44); the texts are in `docs/legal/consent-texts.md`.
- **Rollback:** deactivate the rows. **Affects:** B2B CRM (admin action, no code).
- **SQL equivalent:** `s05_b2b_consent_texts_web.sql` (bodies byte-identical to the website's versions; inserted with
  `lawyer_approved_at` empty until S-44). **Status:** ☐

## Witty / agent core

### A-AGENT-1 · Share Witty's decision engine as a versioned package
- **What:** provide the n8n export of workflow "Eduwit Witty" (`PKPs7tXg9bej8AgX`) or the `witty2/project` source, and
  agree that its `ENGINE` (ask order, eligibility, readiness, HOT/WARM/COLD, hand-off, verifier, fixed texts) becomes a
  shared, versioned package that Witty's n8n build and the website both import.
- **Why:** spec 7.3 — same brain, never different reasoning. The website's `witty-core` implements Witty's published
  contract; the exact rules must be verified against (or replaced by) Witty's own code before the advisor is switched on.
- **Fallback:** `web_advisor_enabled = false` → hero shows the guided finder + "Get free counselling" (spec 7.3).
- **Affects:** Witty's build (owner of Witty). Harness must stay 20/20. **Status:** ☐
- **Ready on the website (Phase 8):** `web/lib/witty-core/` (contract, engine, verifier, placeholders, fixed texts, lead
  payload; 47 scenario tests named after Witty's harness) and the whole web channel (gate, streaming route, storage,
  leads). **To switch Witty on:** (1) replace `engine.ts` with Witty's ENGINE or replay the harness + recorded fact
  sequences and fix every difference; (2) review the web-only fixed texts marked "web" in `fixed-texts.ts`; (3) set
  `ANTHROPIC_API_KEY` (S-14) or add a Gemini provider for byte-identical behaviour (D-011); (4) turn on
  `web_advisor_enabled` in the admin.

### A-AGENT-2 + A-AGENT-3 · One shared transcript with a channel column (must ship together)
- **What:** `w2_messages` gets `channel text not null default 'whatsapp'` and `session_id text`; every reader that means
  "WhatsApp" filters `channel = 'whatsapp'`: `crm_whatsapp_window__impl`, `b2b.student_last_inbound`,
  `b2b.reenquiry_scan`, `b2c.may_market`, `b2c.witty_busy`, `crm_marketing_allowed`, `w2_health_digest`; transcript
  readers (`b2c.witty_transcript`, `b2c.witty_messages`, `b2b.lead_detail`, `crm_timeline__impl`) show the channel.
  Migration (dev only): `supabase/migrations-shared/s02_w2_messages_channel.sql`.
- **Why:** spec 7.5 wants web messages in the shared messages table. Writing them there **today** would make the CRMs
  think a WhatsApp 24-hour window is open (they compute it from inbound `w2_messages` rows by phone) and could trigger
  free-form WhatsApp sends outside Meta's window — breaking other products (spec rule 1).
- **Fallback in place:** `web_advisor_messages` has exactly the `w2_messages` columns plus `channel` and `session_id`, so
  rows can be copied across unchanged once approved; a read-only union view is offered for CRM transcript screens.
- **Affects:** B2B CRM, B2C CRM, Witty health digest. **Status:** ☐

### A-AGENT-4 · `w2_prompts` row `channel_web` (formatting overlay)
- **What:** one data row, versioned like the others. Witty ignores prompt names other than `extractor`/`counselor`.
- **Fallback:** the overlay is held in `web_settings` (versioned). **File:** `s04_w2_prompts_channel_web.sql`.
  **Status:** ☐

### A-AGENT-5 · Prompt version history (optional)
- **What:** `w2_prompt_versions` (or the existing backup convention) so a session can replay an exact prompt version.
- **Fallback:** sessions record `name:version:md5`. **Status:** ☐

## Taxonomy and catalogue

### A-TAX-1 · Promote the website's taxonomy to a shared layer (later)
- **What:** move `web_tax_*` (canonical programmes, specialisations, categories, synonyms, goal/career tags, mapping to
  `catalog_programs.id`) to shared `catalog_tax_*` tables that Witty and the CRMs also read. Straight rename migration
  prepared in `supabase/migrations-shared/s03_shared_taxonomy.sql` (not applied anywhere but dev).
- **Why:** spec 5.3 — one taxonomy for all products. **Fallback:** website-owned tables keyed to catalogue ids.
  **Status:** ☐ (not needed for launch)

### A-TAX-2 · Structured catalogue fields (catalogue owner)
- **What:** add to the catalogue (owner: Witty/catalogue sheet): `duration_months`, `intakes`, `entrance_exam_required`,
  `fee_emi_from`, university `naac_grade`, `nirf_rank`, `state`, `ugc_deb_valid_until`, `logo_url`, `fee_verified_at`.
- **Why:** spec facets need them; today duration, intakes, NAAC/NIRF and state are absent or buried in free text
  (`accreditation_text`, `eligibility_text`). See `TAXONOMY_PROPOSAL.md` §Data quality.
- **Fallback:** the website derives only what the catalogue text states explicitly (deterministic parsers, each value
  carries its source snippet) and hides everything else; facets with no data are not shown. **Status:** ☐

## Extensions

### A-CRON-1 · Three website-owned pg_cron jobs in production (at go-live)
- **What** (owner chose pg_cron over Vercel Pro on 17 Oct 2026, D-082):
  - `web_catalog_poll` · `* * * * *` · `select public.web_catalog_poll()` (migration web4): checks the catalogue content
    and rebuilds the website's programme list only when something changed (D-031, D-081).
  - `web_outbox_worker` · `* * * * *` · `select public.web_job_call('/api/internal/outbox')` (migration web13): pg_net POST
    to the site's outbox worker (confirmation emails, page refreshes, ad conversion events, staff alerts).
  - `web_seo_daily` · `30 21 * * *` (03:00 IST) · `select public.web_job_call('/api/internal/seo-daily', 300000)`
    (migration web13): Search Console import, on-page checks, link suggestions, 404 log clean-up.
  - Plus one Vault secret `web_internal_key` and the setting `web_settings.internal_base_url`; until both exist the two
    HTTP jobs send nothing. Same pattern as the B2C CRM's `b2c.job_call` jobs already running in production.
- **Why:** keeps the finder in step with catalogue edits without adding a trigger to shared tables.
- **Risk:** a materialised-view refresh every time the catalogue changes (~2–3 s for 715 rows, `CONCURRENTLY`, so reads
  never block); one outbound HTTP call a minute from pg_net (the CRMs already run ~50 jobs, many every minute or every
  few seconds). **Rollback:** `rollback-web.sql` unschedules every `web_*` job; delete the Vault secret by hand.
  **Status:** ☐ (approach chosen by the owner; final approval at go-live)

### A-EXT-1 · Install `unaccent` (optional)
- **What:** `create extension if not exists unaccent with schema extensions;` (available, not installed in production).
- **Why:** spec 3 lists `unaccent` for search. **Fallback in place:** `web_norm(text)` (lower-case, punctuation folding,
  `&` → `and`, dots removed) — English/Hinglish queries rarely carry accents, so search quality is
  unaffected. **Risk:** none for other products (new extension only). **File:** `s06_unaccent.sql`.
  **Status:** ☐ (not needed for launch)

## Auth

### A-AUTH-1 · (Only if the owner wants students in Supabase Auth instead of website-owned verification)
- **What:** change `crm_handle_new_auth_user` to skip non-staff sign-ups; set project OTP expiry to 600 s and a code-only
  email template; custom SMTP; raise auth email rate limits.
- **Why:** see D-005. **Not recommended**; the website works without it. **Status:** ☐ (not needed)

## Observed in shared objects (outside the website's scope — owner to decide; nothing changed)
- `anon` and `authenticated` hold **TRUNCATE** (and INSERT/UPDATE/DELETE) on `catalog_*` and `w2_*` tables. RLS blocks
  row access, but RLS does not govern TRUNCATE. Not reachable through PostgREST today; still worth revoking
  (`revoke truncate on … from anon, authenticated`). Owner: Witty / platform.
- `b2b.witty_backup_20261015`, `b2b.witty_backup_20261016` have RLS disabled (no anon/authenticated grants, so not
  readable via the API). Owner: B2B CRM.
- `catalog.programmes_v` returns null duration and EMI for every row (reads the wrong `fee_other` keys). Owner: B2B CRM.
- 569 brochure URLs point to a different Supabase project's storage (`clfjuwoibezhrkpawuij`). Owner: catalogue.

## Other products' code (handoff notes, nothing changed)
- **CRMs:** show the website application details (`web_applications`) and email-verified flag in the lead screen via the
  proposed read-only views `web_lead_verification_v`, `web_application_v` (grant select to `b2c_app`).
- **B2B CAPI:** the B2B "Lead" signal is off today; the website sends Meta CAPI `Lead` itself (event id
  `web:<lead>:lead`). If B2B ever turns its "Lead" signal on, one of the two must be switched off to avoid double counting.
