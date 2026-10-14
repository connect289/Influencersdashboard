# Eduwit B2C CRM: Phase 0 audit

Version 1 · 14 October 2026 · Status: **for Vikas's review. No migration written, no database changed.**

Inputs: `docs/B2C_CRM_PROMPT.md` (the spec, final of 14 Oct; B21 wins where it differs), the B2B CRM's published contract
`../../docs/b2c-contract.md` (version 3) and its code in `../../b2b-crm/`, the B2B Phase 0 audit `../../docs/phase0-audit.md`,
the old CRM (`connect289/eduwit-crm`: `crm/sql` 001–008, `crm/web`), and the logo in `docs/brand/`.

**How this was checked.** Every database fact below was read on the **staging project `mplbspysxmtohnlwpbti`**
(read-only `select`s on the catalog), which holds production's schema as loaded from the B2B baseline of 6 Oct plus the
B2B migrations up to `20261007063231`. **Production (`xlseqwgyjuqhktrguhyc`) was not queried.** Where a production fact is
needed (row counts, consent coverage, which B2B migrations are live), it is marked **[prod count needed]**; I can run
those as read-only counts once you allow it, or you can run the queries in §8 yourself.

Where this work lives: `b2c-crm/` in this repository, on branch `claude/exciting-heisenberg-fse6ik`, next to `b2b-crm/`.
The spec (A5) asks for a separate repository (for example `eduwit-b2c-crm`); I have not created one. Say the word and I
will create it and move this folder there with its history. My earlier draft `../../docs/b2c-design.md` is superseded
by the spec and this audit.

---

## 1. Decisions (settled 14 October)

Vikas decided the sync direction and the palette, and asked me to settle the rest by judgement. The B2B CRM's side is
written up as `../../docs/B2B_CRM_ADDENDUM_4.md` (the modification prompt for the B2B CRM; contract version 4).

| # | Point | Decision | Why |
| --- | --- | --- | --- |
| **K1** | How B2C reads leads | **The contract's model.** B2B pushes each record in real time; B2C keeps it as a **read-only cache** (`b2c.lead_records`: id, version, record), never edited locally, overwritten by every higher version, rebuildable from the feed. `student_leads` stays the master. B2C's own pipeline state lives in `b2c` tables. Witty transcripts and the `catalog` views are read in the same project through B2C's own functions | Matches Vikas's rule that B2B sends leads to B2C in real time, needs no change to the read side of the built contract, and keeps B2C off `student_leads`. The spec's "no copy" concern (a second editable master that drifts) does not arise: the cache is read-only and versioned |
| **K2** | Sync speed | **B2B → B2C real time; B2C → B2B one batch every 15 minutes** (Vikas). The batch carries assignments, stages, field and cross-sell changes, calls, messages, notes, applications, enrolments and scores, merged to one update per lead. **Sent at once:** consent request sent, consent answer, opt-out, erasure request, route-to-partners, and new students (Intake API) | Those six would break a rule if delayed (the 48-hour consent clock, opt-out "at once" in A3, the Admin waiting on a routing answer, a counsellor waiting for a new lead's id). Consequences: `student_leads` and the B2B Master Lead Table trail the B2C CRM by up to 15 minutes; a nurture lead a counsellor qualifies returns to partner routing within about 16 minutes |
| **K3** | Hand-off reasons | Every sales-lane hand-off goes through the B2C allocation engine at once; `handling` and `reason` are rule conditions; `manual_route_failed` returns to the previous counsellor; `consent_no_answer` is qualification nurture | Spec B7, with contract v3's extra reasons covered |
| **K4** | Partner-consent requests | Built in Phase 1 (template `wa_partner_consent_v1`, YES/NO buttons, send and answer reported at once) | B2B routing cannot go live without it |
| **K5** | Hosting | **Vercel** (`bom1`), like the B2B CRM; timers and queues in Postgres (`pg_cron`, `pgmq`) calling the app's internal endpoints, the pattern B2B already runs | No new paid infrastructure (B2B D14); the 15-minute batch and the jobs fit in serverless functions. Cloud Run stays an option if a long-running worker is ever needed |
| **K6** | New students | Through the B2B Intake API, never `lead_intake()` directly | A3: every write goes through B2B |
| K7 | Database | Shared Supabase project, schema `b2c` (spec B16); development on the staging project or a branch | Spec |
| K8 | Repository | `b2c-crm/` in this repository, deployed separately from `b2b-crm/` | One place for both CRMs and their contract; can move to its own repository at any time |
| K9 | Old B2C tables | Moved into `b2c` (or retired) only at cut-over, when the old CRM is switched off | §3: the old CRM reads them by name |
| K10 | Re-engagement | Decided by the B2C CRM on its own triggers (B6.3); B2B's `reactivation` flag is a hint | B2C computes the score and sees the replies |
| K11 | Roles | Admin, Marketing, Counsellor, Sales head (off). Old `finance`, `revenue`, `viewer` are retired; money actions are Admin-only | Spec B3.1 |
| K12 | Palette | Sampled navy and amber, plus a red and a green for status only; no black in light mode (`brand/palette.md`) | Vikas: best judgement, no black except in dark mode |
| K13 | Production counts | Not run (your hard limit: staging only). The read-only queries are in §7 for you to run | |

## 2. Inventory of existing objects, with verdicts

Verdicts: **keep** (reuse as is), **refactor** (reuse with the change named), **not ours** (another product's; B2C reads
at most). "Move to `b2c`" happens only with your yes (B14) and only after the dependency check in §3.

Row counts are staging's (synthetic). On production the spec (A4) says almost everything is empty except `crm_users`
(4), `journeys` (6), `crm_settings` (populated) and the catalogue **[prod count needed]**.

### 2.1 Tables and views

| Object | Verdict | Why and how |
| --- | --- | --- |
| `crm_users` | **refactor, stay in `public`** | B2C's user table (A5). Add `marketing` and `sales_head` roles and the B14 columns (`workspace_user_id`, `job_title`, `photo_url`, `synced_at`, `invited_at`, `invite_token_hash`, `push_subscription`, `on_call`, `away_until`, `weight`, `skills jsonb`, `tz`). Drop roles `sales_manager` → `counsellor`, `revenue`/`finance`/`viewer` retired (map to `marketing` or deactivate). 3 inactive Gmail sign-ups stay inactive (§9) |
| `crm_teams` | **keep** | Optional now |
| `crm_settings` | **refactor, stay in `public`** | Shared with `lead_intake()`'s helpers. Add keys: `eduwit_stages` (the B5.1 model, versioned), `allocation_defaults`, `lost_nurture`, `gmail`, `reply_classification`, `live_mode`. **Move `marketing.unsubscribe_secret` to Vault** (A3). Empty on staging; populated on production **[prod read needed]** |
| `crm_activities`, `crm_tasks` | **refactor → move to `b2c`** | Timeline and tasks (B14 keeps them). Change the FK to `student_leads` from **ON DELETE CASCADE to RESTRICT** (audit rows must outlive a delete). Add `kind`s for follow-up types, reminder and escalation columns |
| `calls` | **refactor → move to `b2c`** | Add `provider = 'manual'`, `tapped_at`, `logged_at`, approximate duration (B8.4). CASCADE → RESTRICT |
| `message_templates` | **refactor → move to `b2c`** | Add `audience` (marketing, sales), `usable_by_sales`, Meta `category`, `status`, language variants, buttons, versions. Sales **email** templates get their own table (`b2c.sales_email_templates`, fork-on-edit) |
| `segments`, `segment_members`, `campaigns`, `campaign_sends` | **refactor → move to `b2c`** | Rules read `b2c.leads_v`. `campaign_sends` gains reply class, re-engagement, cost. CASCADE → RESTRICT on `student_leads` |
| `journeys`, `journey_runs` | **refactor → move to `b2c`** | Add versions, `lane`/trigger reason, test mode, exits (`requalified`, `routed_to_partner`, `assigned`, `opted_out`, `dormant`). The **6 starter journeys** on production are reviewed in §4.6 |
| `payout_rates`, `payouts`, `payout_runs` | **refactor → `b2c.commission_lines` + runs** | They model a payout *to* the counsellor; the rule is now a commission *owed to* Eduwit at the highest partner rate (B11.2). New lines go to `b2c.commission_lines`; keep the old tables empty and drop them later with your yes. `payouts.enrollment_id` → `b2c.enrollments` |
| `crm_university_settings` | **refactor → `b2c.university_settings`** | Refund window, invoicing details |
| `enrollments`, `earnings`, `earning_rates`, `invoices` (public) | **not ours** | Empty legacy tables. B2B built its own `b2b.earnings`, `b2b.invoices`, `b2b.receipts`; B2B design D9 keeps `public.enrollments` as a shared outcome table. B2C creates `b2c.enrollments`, `b2c.earnings`, `b2c.university_rates`, `b2c.invoices`, `b2c.receipts` (B14) and never writes these. Who drops the public ones is a B2B decision |
| `crm_notifications`, `crm_alerts`, `crm_saved_views`, `crm_api_keys` | **refactor → `b2c`** | Notifications gain push; saved views become `b2c.saved_views` (filters, columns, layout, standard, default, shared with role). API keys: B2C needs none inbound except webhook secrets (Vault) |
| `verifications` | **not ours** | Website agent's OTP. Stays where it is |
| `crm_leads_v` | **not used** | Replaced by `b2c.leads_v` over the record cache (K1) |
| `student_leads`, `student_leads_v`, `touchpoints` | **not ours (shared)** | Never read or written by B2C directly; records arrive from B2B (K1) |
| `catalog_programs`, `catalog_universities`, `catalog_synonyms`, `catalog_stage`, `course_directory` | **not ours** | Read through the `catalog` views the B2B CRM publishes (§5.3). Staging holds 3 programmes and 1 university; production 715 and 29 (A4) |
| `w2_*` (25 tables, 2 views), `n8n_chat_histories`, `conversation_locks`, `processed_whatsapp_messages`, `eduwit_knowledge_base` | **not ours** | Witty's. B2C reads `w2_messages` (transcripts) through a read-only `SECURITY DEFINER` function, never directly by a role grant, and never writes (A3) |
| `allocations`, `engine_decisions`, `partner_events`, `partner_mapping_profiles`, `routing_rules`, `partners_v` (public) | **not ours** | Old combined-engine tables; B2B has its own in `b2b`. B2C reads none |
| `influencers`, `influencer_auth`, `influencer_login_attempts`, `influencer_leads_dashboard` | **not ours** | Influencer dashboard |

### 2.2 Functions (119 `crm_*` in `public` on staging, 10 of them `__impl`)

Every old write function writes `student_leads` **directly**, which the spec now forbids (A3, B21 #11). So none of them is
reused as is; their logic is ported into `b2c.*` functions that write B2C tables and put the `student_leads` part in the
outbox for the B2B write API.

| Functions | Verdict | How |
| --- | --- | --- |
| `crm_me`, `crm_role`, `crm_require`, `crm_can_see`, `crm_masks`, `crm_mask_phone`, `crm_mask_email` | **refactor** | New `b2c.me()`, `b2c.can(permission)` with the four roles (Admin, Marketing, Counsellor, Sales head). Masking is no longer needed for Marketing (B21 #6: full numbers visible); every phone reveal and Call tap is logged instead |
| `crm_update_user`, `crm_set_my_phone`, `crm_handle_new_auth_user` (trigger on `auth.users`) | **refactor** | Accounts come from Teams (Workspace sync or invite), not from any sign-up. The trigger keeps inserting new identities as inactive (harmless) until Phase 1 replaces it; changing a trigger on `auth.users` is shared, so it waits for your yes |
| `crm_assign_lead`, `crm_auto_assign_trg` + trigger `crm_auto_assign` | **refactor → `b2c.allocate()`** | See §6. The trigger is **already disabled** (staging shows `crm_auto_assign (disabled)`; B2B hotfix H1). Keep it disabled; drop it at cut-over with your yes |
| `crm_set_stage`, `crm_apply_stage_system`, `crm_update_lead`, `crm_add_note`, `crm_new_lead`, `crm_merge_leads` | **refactor** | Port to `b2c.set_stage()` (Eduwit stages, sub-stage required, comment, canonical mapping), `b2c.correct_lead()`, `b2c.add_note()`. New leads go through the Intake API (K6). Merging leads is the B2B CRM's job; B2C shows duplicate suspects only |
| `crm_timeline`, `crm_agenda`, `crm_followup_tick`, `crm_daily_digest`, `crm_notify`, `crm_my_notifications`, `crm_notifications_*`, `crm_pending_notification_emails`, `crm_resolve_alert` | **refactor** | Logic is right (reminders 10 min before, overdue, escalation, SLA breach, digest); repoint to `b2c` tables and the working calendar (B7.1) |
| `crm_call_start`, `crm_call_event`, `crm_call_outcome_task`, `crm_sla_minutes` | **refactor** | Manual-call flow (B8.4) plus the telephony adapter later; outcome → next task stays |
| `crm_programme_fit` | **refactor** | Reads the `catalog` views instead of `catalog_programs` |
| `crm_duplicate_candidates` | **keep (read)** | Used to warn on a new contact number |
| `crm_rules_where`, `crm_rules_match`, `crm_segment_*`, `crm_save_segment` | **refactor** | Evaluate against `b2c.leads_v` |
| `crm_save_template`, `crm_render_template`, `crm_send_job`, `crm_whatsapp_window`, `crm_marketing_allowed`, `crm_unsubscribe`, `crm_unsubscribe_token` | **refactor** | Guardrails are right (B9.4); window and sends move to `b2c.wa_*`; token secret → Vault |
| `crm_save_campaign`, `crm_campaign_*`, `crm_save_journey`, `crm_journey_*`, `crm_marketing_stats` | **refactor** | Versioned journeys, A/B, test mode, lane triggers |
| `crm_score_lead`, `crm_score_tick`, `crm_update_scoring` | **refactor** | Scores in `b2c.score_events`; write `lead_score`/`temperature` back only on a band change or crossing 60 (B9.5) |
| `crm_compute_payout`, `crm_payout_rate`, `crm_payout_run_*`, `crm_add_payout_rate`, `crm_period_close`, `crm_tier_pct`, `crm_money_summary`, `crm_verify_enrollment`, `crm_refund_enrollment`, `crm_report_enrollment`, `crm_invoice_set_status`, `crm_compute_earning`, `crm_earning_rate`, `crm_add_earning_rate`, `crm_conversion`, `crm_money_setting` | **refactor** | Port the ledger rules (reverse never delete, tiers, period close) into `b2c` money functions; payout logic is replaced by the highest-partner-rate commission (B11.2) |
| `crm_report` | **refactor** | Replaced by roll-ups and the Analytics page |
| `crm_create_api_key`, `crm_api_key_check` | **not needed** | B2C exposes no key-based API; webhooks are HMAC |
| `crm_allocate_lead`, `crm_reallocate`, `crm_dest_stats`, `crm_engine_flow`, `crm_scorecards`, `crm_criteria_match`, `crm_segment_of`, `crm_partner_*`, `crm_sync_*`, `crm_upsert_partner`, `crm_save_mapping_profile`, `crm_save_routing_rule`, `crm_update_engine_settings`, `crm_b2b_reader` | **not ours** | Old partner engine; superseded by B2B |
| `lead_intake`, `crm_find_lead`, `crm_norm_phone`, `crm_num`, `student_leads_bulk_delete_guard`, `is_admin`, `current_referral_code`, `rls_auto_enable`, `crm_verify_start`, `crm_verify_check` | **not ours (shared)** | Never changed (A3) |
| `*__impl` (10) | **note** | B2B's M1 wrapped 10 old functions: the original moved to `<name>__impl` and the wrapper refuses non-staff. The B2C ports start from the `__impl` bodies |

### 2.3 Triggers on `student_leads` (staging)

`crm_auto_assign` (**disabled**), `student_leads_bulk_delete_guard`, `student_leads_touch_trg`,
`student_leads_truncate_guard`. B2C adds **none** (it reads through the view and writes through B2B).

### 2.4 Columns the spec names (B3.3) vs the live table

All B3.3 columns exist on staging with those exact names (`academic_score_pct`, `work_experience_years_num`,
`annual_budget_inr`, `consent_marketing_at`, `is_opted_out`, `opted_out_channels`, `email_bounced_at`,
`active_journey_id`, `last_campaign_id`, `last_marketing_message_at`, `enrollment_verified_at`, …). No column needs adding
for Phase 1. `student_leads_v2_rename.sql` is not run and not referenced.

---

## 3. Dependency map (what calls what)

Foreign keys on staging that matter for moving tables:

| From | To | On delete | Action |
| --- | --- | --- | --- |
| `calls`, `crm_activities`, `crm_tasks`, `campaign_sends`, `segment_members`, `journey_runs` | `student_leads` | **CASCADE** | Change to RESTRICT when moved (a lead is soft-deleted, never hard-deleted while it has history) |
| `campaign_sends` → `campaigns`, `journey_runs` → `journeys`, `segment_members` → `segments` | | CASCADE | Keep |
| `campaigns` → `message_templates`, `segments` | | no action | Keep |
| `crm_users` → `crm_teams` | | no action | Keep |
| `payouts` → `enrollments`, `earnings` → `enrollments` | | no action | `payouts` repointed or retired (§2.1) |

**Callers outside the database.** `alter table … set schema b2c` keeps OIDs, so SQL functions keep working, but anything
that names `public.<table>` in text breaks. Before any move I need: (1) the n8n workflow exports (the B2B audit asked for
these too; `Eduwit CRM · Jobs` `Wx1uai9qtOkwFQDs` calls these tables through the old CRM and must stay unpublished), (2)
confirmation that the old CRM (`eduwit-crm.vercel.app`) can lose its B2C screens at that moment, since it reads these
tables by name. **Recommendation:** move the tables only at cut-over (old CRM switched off), not in Phase 1; until then
new B2C tables go in `b2c` and the old ones are read by nothing new.

---

## 4. Schema plan for `b2c`

Nothing below is written yet. Each block becomes one migration, applied to a Supabase branch or the staging project first,
tested with pgTAP inside `begin … rollback`, and promoted only with your approval (A3, your hard limits).

### 4.1 Rules for every `b2c` object

- RLS on every table; reads by role through `(select b2c.can('…'))`; counsellors see only rows whose lead they own.
- No insert, update or delete policies: writes through `SECURITY DEFINER` functions with `search_path = ''`.
- `bigint` identity keys, `timestamptz`, `created_at` everywhere, `updated_at` + `actor_type` + `actor_id` on mutable rows,
  money `numeric(12,2)`.
- FKs to `student_leads(id)` are **RESTRICT**. Money and audit rows are never deleted (a trigger blocks DELETE).
- Test leads (`is_test` or phone digits `910000…` / `9190000000NN`) are refused by `b2c.allocate()` for real counsellors
  and by every sender while `LIVE_MODE` is off or on.

### 4.2 Blocks (migration order)

| # | Block | Tables and functions |
| --- | --- | --- |
| C1 | Access | `b2c.me()`, `b2c.can()`, `crm_users` columns, `b2c.trusted_devices`, `b2c.email_codes` (hashed, 10 min, 5 tries), `b2c.sign_in_log`, `b2c.audit_log` |
| C2 | Read model | `b2c.lead_records` (the read-only cache, K1), `b2c.leads_v`, `b2c.leads_state` (lane, reason, hand-off event, pool dates, re-engagement, `eduwit_stage`, `eduwit_sub_stage`, `stage_comment`, dormant, closed), `b2c.lead_contacts` (intake rows locked by trigger; one primary per kind), `b2c.field_history` |
| C3 | Contract plumbing | `b2c.handoff_inbox` (raw, unique event id), `b2c.outbox` (every B2B write: merged per lead into the 15-minute batch, or sent at once for the six urgent kinds; idempotency key, attempts, answer), `b2c.sync_cursors` |
| C4 | Stages | `b2c.stage_definitions`, `b2c.sub_stage_definitions` (seeded from B5.1, canonical mapping, required fields, lost journey and delay), `b2c.set_stage()` |
| C5 | Allocation | `b2c.work_schedules`, `b2c.shift_rosters`, `b2c.holidays`, `b2c.leaves`, `b2c.allocation_rules`, `b2c.allocation_pools`, `b2c.allocation_decisions`, `b2c.assignments`, `b2c.allocate()`, `b2c.working_now()`, `b2c.simulate()` |
| C6 | Work | `b2c.tasks` (from `crm_tasks`), `b2c.activities`, `b2c.calls`, `b2c.sla_clocks`, `b2c.saved_views`, `b2c.notifications` |
| C7 | Messaging | `b2c.wa_numbers`, `b2c.wa_conversations`, `b2c.wa_messages`, `b2c.emails`, `b2c.user_connections` (token refs in Vault), `b2c.reply_classifications`, `b2c.consent_requests` (K4), `b2c.suppression` |
| C8 | Templates | `b2c.message_templates` (marketing + sales WhatsApp, marketing email), `b2c.sales_email_templates` (fork-on-edit, immutable parent) |
| C9 | Marketing | `b2c.segments`, `b2c.segment_members`, `b2c.campaigns`, `b2c.campaign_sends`, `b2c.journeys`, `b2c.journey_versions`, `b2c.journey_runs`, `b2c.score_events` |
| C10 | Applications | `b2c.applications`, `b2c.documents` (private storage paths), `b2c.document_checklists` |
| C11 | Catalogue cache | `b2c.programme_cache`, `b2c.partner_rate_cache` (filled from the `catalog` views, §5.3) |
| C12 | Money | `b2c.enrollments`, `b2c.university_rates`, `b2c.earnings`, `b2c.invoices`, `b2c.receipts`, `b2c.statement_imports`, `b2c.statement_matches`, `b2c.commission_lines`, `b2c.commission_fallbacks`, `b2c.commission_runs` |
| C13 | Analytics | `b2c.events` (append-only), `b2c.rollup_*`, `b2c.dashboards`, `b2c.widgets`, `b2c.metric_alerts`, `b2c.schedules`, `b2c.ai_queries` |
| C14 | Platform | `b2c.exports`, `b2c.deletions`, `b2c.user_guides`, `b2c.guide_progress`, `b2c.settings_versions` |
| C15 | Published views | `public.b2c_enrollment_money_v`, `public.b2c_lead_status_v` (read-only, versioned, for B2B and the referral view) |

### 4.3 Eduwit stages → canonical (B5.1, B21 #1)

| Eduwit stage | Canonical `student_leads.stage` | Accepted by the B2B API today? |
| --- | --- | --- |
| New Lead | `assigned` | yes |
| Could Not Connect, Contacted | `contacted` | yes |
| Qualified, Follow Up, Program Details Explained | `counselled` | yes |
| Applicant, Docs Submitted | `applied` | yes |
| Enrolled | `enrolled` → `verified` on Admin verification | yes |
| Lost | `lost` | yes |
| (hidden) Nurture, Routed to partner, Dormant | `nurture`, `routed_to_partner`, `dormant` | yes (added by B2B M7e as `held_by_b2c`) |

The Eduwit stage, sub-stage and comment are written as `sub_stage` (≤ 80 characters, B2B limit) plus
`custom_fields.b2c_stage`, `custom_fields.b2c_sub_stage` and `custom_fields.b2c_stage_comment` until B2B adds proper
fields (§5.1 gap G3).

### 4.4 Lead read path (K1)

`b2c.lead_records` holds the latest record B2B pushed for each lead B2C can see (`id`, `version`, `seq`, `record jsonb`,
`held_by_b2c`, `received_at`), written only by `b2c.apply_record()` when the version is higher. `b2c.leads_v` joins it to
`b2c.leads_state` and exposes typed columns (name, phone, course, stage, lane, reason, partner bar, consent state, …)
for screens, segments and allocation rules; `b2c.leads_for_me()` filters by role. B2C's own pending changes (not yet in
the 15-minute batch) are overlaid from `b2c.outbox`, so a counsellor always sees their own latest edit.

### 4.5 The 6 starter journeys (production)

From `crm/sql/006_crm_marketing.sql`: *New enquiry, no answer*; *Programme interest, eligibility unknown*; *Fee concern*;
*Admission deadline countdown*; *Lost (not now): re-engage after 60 days*; *Long-term: monthly update*. Verdict: keep the
step logic; re-key their triggers to the B6 pool reasons and lost sub-stages; add the two missing starters from B9.4
(*not eligible → programmes they qualify for*, *not reachable → "we tried to reach you"*), plus *partner-lost by reason*,
*qualification nurture* (missing details), *consent repeat* (K4) and *fix and reapply*. All need Meta-approved templates
on the B2C number before they can send.

---

## 5. What the B2C CRM needs from the B2B CRM

The B2B CRM is not changed from here (A3). This is the request list for its developer, against what exists today
(`b2b-crm/supabase/migrations/20261007041838_m22a_b2c_link_sync.sql`, `m31j_a3_b2c_contract.sql`, contract v3).

### 5.1 Write API (B17 out)

**Exists:** `PATCH /v1/b2c/leads/{id}` (idempotent `request_id`, `if_version`, `actor`), `POST /v1/b2c/leads/batch`,
`POST /v1/b2c/leads/{id}/activities`, `POST /v1/leads/{id}/route-to-partners`, `POST /v1/leads` (intake),
`POST /v1/events/b2ccrm` (signed). Writable by B2C today: student and education fields (not phone), interest (course,
specialization, university, level, mode, field of interest, timeline, budget, counselling time, other courses),
`lead_score`, `temperature`, the whole pipeline group (owner, team, assigned at, stage, sub-stage, stage changed at,
contact timestamps and attempts, next task due), application, enrolment (incl. expected and realised net revenue), lost,
`custom_fields`.

**Gaps** (all requested in `../../docs/B2B_CRM_ADDENDUM_4.md`):

| # | Needed by the spec | Today | Ask |
| --- | --- | --- | --- |
| G1 | Marketing columns `active_journey_id`, `last_campaign_id`, `last_marketing_message_at`, `email_bounced_at` (B3.3) | Not in the field catalogue | Add them as B2C-writable |
| G2 | `enrollment_verified_at` (Admin verification) | Not in the catalogue | Add as B2C-writable |
| G3 | Eduwit stage, sub-stage and comment on the record and in `b2ccrm.stage_changed` (B5.2) | `sub_stage` text ≤ 80; event is "timeline only" | Add `b2c_stage`, `b2c_sub_stage`, `b2c_stage_comment` to the record (or confirm `custom_fields` keys) and show them on the Master Lead Table |
| G4 | Marketing consent and opt-out per channel, recorded by B2C (B9.6) | Consent is B2B-only; `b2ccrm.opted_out` exists (all channels) | A signed `b2ccrm.marketing_consent` event (channel, text, source, time) and channel-level opt-out |
| G5 | Extra contact numbers and emails (B8.3) | Only `alternate_phone`, read-only for B2C | Accept `b2ccrm.contact_added` (kind, value, label, primary) so B2B's duplicate check sees them; originals stay B2B/Admin-only |
| G6 | `b2ccrm.lead_updated`, `b2ccrm.commission_booked` (B17) | Unknown types are stored and ignored | Either accept them, or agree that field changes travel as `PATCH` (B2B emits its own events) and drop these two names from the spec. I recommend the latter |
| G7 | B2B → B2C real time, B2C → B2B every 15 minutes (K2) | B2B offers a 15-minute delivery mode | Lock B2B → B2C to real time; accept the 15-minute batch with `occurred_at`, order-safe contact roll-ups, and no echo webhooks |

### 5.2 Reads

No change to the read model (K1). Two small additions, in Addendum 4 §5: a lookup answer that names the partner holding
a student outside B2C's scope, and a partner-history read for partner-lost leads.

### 5.3 Shared `catalog` schema (B8.9, B11.2, B21 #3)

Nothing exists yet (no `catalog` schema on staging). Phase 0 of the spec puts views over the existing `catalog_*` tables
so nothing moves and Witty is unaffected. As B2B owns the catalogue, the ask is that B2B creates:

- `catalog.programmes_v`: programme, university, specialization, level, mode, duration, eligibility, fees (year,
  semester, total, exam, registration), EMI, scholarship, intakes and deadlines, accreditation, brochure, active;
- `catalog.universities_v`, `catalog.synonyms_v`;
- `catalog.partner_rates_v`: partner, university, programme (nullable for a university-wide rate), rate type and value,
  fee base, tier, valid from (from `b2b.partner_programmes` and B2B's partner-programme earning rates), **readable by the
  B2C role only for Admin and Marketing screens**;
- `catalog.changes` (or a `catalog.updated` event) so `b2c.programme_cache` refreshes on change.

### 5.4 Events B2B → B2C (B17 in)

All exist in contract v3: `b2c.lead_handed_off`, `b2c.lead_reenquired`, `b2c.lead_requalified`, `b2c.lead_reengaged`,
`b2c.lead_released`, `b2c.lead_flagged`, `b2c.lead_close_agreed`, `b2c.consent_requested`, `b2c.consent_closed`,
`b2b.lead_routed_to_partner`, `ping`, reconciliation by `GET /v1/handoffs?after=` (the spec's `?since=` also works).
Endpoint on our side: `POST /v1/handoffs` (HMAC `sha256=` over `<timestamp>.<raw body>`, ±5 min, `2xx` within 10 s).

### 5.5 Events B2C → B2B

`b2ccrm.consent_request_sent`, `b2ccrm.partner_consent` (YES needs the student's WhatsApp `message_id`),
`b2ccrm.opted_out`, `b2ccrm.erasure_requested`, plus `b2ccrm.lead_assigned`, `b2ccrm.stage_changed`, `b2ccrm.enrolled`
for the timeline. B2C also serves `GET /v1/events?since=` (B17) as its own reconciliation feed.

---

## 6. Witty and `crm_auto_assign`

**Witty interest signal (B6.3, B2B Addendum 1 §4b).** Not defined yet; it needs Witty's developer. Proposal for that
conversation (no Witty change is made from here): Witty records a `touchpoints` row `event_type = 'lead.interest'` with
`{intent: fees | admission | eligibility | apply | human | qualified | escalated}` when a pooled lead writes again; B2B
forwards it as `b2c.lead_reenquired` with `interest: true` (contract v3 already carries `interest`). B2C never parses
`w2_messages`.

**Keep talking to pooled leads.** `w2_crm_owned()` today stops Witty once `destination_type` is set, so Witty also stops
for B2C nurture leads. The rule wanted is "stop only once a counsellor is assigned (`owner_user_id`)". That is a Witty
function change: **your call with Witty's developer.**

**`crm_auto_assign`.** Disabled since 6 Oct. Plan: leave it disabled; B2C assignment is driven only by its own hand-off
and re-engagement events (`b2c.allocate()`); drop the trigger and `crm_auto_assign_trg()` at cut-over with your yes.

---

## 7. Consent coverage

The spec asks how many leads carry marketing and partner consent today. Staging holds 7 synthetic leads, so its numbers
mean nothing. **[prod count needed]** (read-only):

```sql
select count(*) total,
       count(consent_marketing_at) marketing,
       count(consent_partner_share_at) partner_share,
       count(*) filter (where is_opted_out) opted_out,
       count(*) filter (where destination_type = 'in_house') held_by_b2c
  from public.student_leads
 where deleted_at is null and not coalesce(is_test, false);
```

The B2B audit of 6 Oct found 0 of 1 live leads with partner consent; Witty sends `consent_sales_at` only. Marketing
consent capture by Witty, the website agent and every form is a Witty/website change: listed in §10.

---

## 8. Google Workspace setup (you, in the Google Admin and Cloud consoles)

1. **Cloud project.** Create `eduwit-b2c-crm` in the Google Cloud organisation of `eduwit.in` (or reuse
   `even-crossing-499410-j3`; a separate project keeps quotas and keys apart, recommended).
2. **APIs.** Enable Gmail API, Admin SDK API, Cloud Pub/Sub API.
3. **OAuth consent screen.** User type **Internal** (only `@eduwit.in`), app name "Eduwit CRM", support email
   `connect@eduwit.in`, authorised domain `eduwit.in`. Scopes: `openid`, `email`, `profile`,
   `https://www.googleapis.com/auth/gmail.send`, `…/gmail.readonly`, `…/gmail.metadata`.
4. **OAuth client** (Web): redirect URIs for Supabase Auth (`https://<project>.supabase.co/auth/v1/callback`) and the
   app's Gmail connect callback (`https://crm.eduwit.in/connectors/google/callback`, plus staging). Put the client ID and
   secret in Supabase Auth → Google and restrict to the hosted domain `eduwit.in`.
5. **Service account** `b2c-crm-directory@…`, no key download if Workload Identity is available on Cloud Run; otherwise
   one JSON key straight into Secret Manager.
6. **Domain-wide delegation** (Google Admin → Security → API controls → Domain-wide delegation → Add new): the service
   account's client ID with scopes `https://www.googleapis.com/auth/admin.directory.user.readonly` (Teams sync) and, if
   you want zero-touch Gmail for every user, `gmail.send`, `gmail.readonly`, `gmail.metadata`.
7. **Impersonated admin** for directory reads: a super-admin or a custom role with "Users → Read".
8. **Gmail watch.** A Pub/Sub topic `gmail-b2c` with `gmail-api-push@system.gserviceaccount.com` as publisher, and a push
   subscription to `https://crm.eduwit.in/v1/webhooks/email`.
9. **System sender.** A Google Group or alias (e.g. `crm@eduwit.in`) with "Send mail as" on the system mailbox, for 2FA
   codes and assignment fallbacks, kept apart from marketing volume.
10. **DNS.** SPF, DKIM (Google Workspace) and DMARC on `eduwit.in` are probably in place for Gmail already; confirm DKIM
    is on, since marketing goes out from your mailbox.

---

## 9. Other findings

- **Accounts.** `crm_users` on production: 4 rows, `connect@eduwit.in` (admin, active) and 3 inactive Gmail sign-ups from
  9–12 July 2026 (spec A4; staging has 0). They stay inactive and gain no access; delete them only on your word.
- **Secret in a table.** `crm_settings.marketing.unsubscribe_secret` must move to Vault (A3); done in block C1 with your
  approval. **[prod read needed]** to confirm it is set.
- **WhatsApp (B8.5).** Recommend **Meta Cloud API directly** behind an adapter (B20 default): no per-message markup,
  webhooks straight to the app, templates managed from the CRM. Needs: the B2C number (not Witty's +91 96439 77407), its
  WABA, a permanent system-user token, the app secret, and template approvals (assignment message in-hours and
  out-of-hours, consent `wa_partner_consent_v1`, welcome `explore_programmes`, the sales openers, journey templates).
- **Email volume (B21 #8).** 2,000 per mailbox a day cannot carry the 5,000-a-day pool or a 100,000-lead pool campaign;
  WhatsApp carries nurture first, and a bulk provider or more sending accounts can sit behind the same adapter later.
- **Reply classification model.** The spec names `claude-haiku-4-5-20251001` (B6.6) and `claude-sonnet-5` (B16). Both
  stay configurable settings; I will confirm the current model IDs when the AI work starts in Phase 2.
- **Test phones.** The spec says `910000…`; the B2B CRM and the old CRM also treat `9190000000NN` (Hermes) as test. B2C
  will treat both as test.

---

## 10. Still open

1. Production counts in §7 and §9 (read-only; for you to run, or allow me to).
2. The B2B changes in `../../docs/B2B_CRM_ADDENDUM_4.md`: hand to the B2B CRM's Claude Code session.
3. Witty: the interest signal and "keep talking until a counsellor is assigned" (§6) need Witty's developer.
4. Marketing-consent capture on Witty, the website agent and forms: who, and by when.
5. From B21: rows 1, 2 (a–d), 5, 7, 8, 10, 13, 16; the B20 defaults apply until you answer.

## 11. Next step

The clickable design of the three interfaces is in `../design/` (`prototype.html`, sample data only). After your review
of this audit, the palette, Addendum 4 and the design, Phase 1 starts with its plan. No migration and no database change
until you approve.
