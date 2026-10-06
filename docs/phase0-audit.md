# Phase 0 audit: Eduwit B2B Partner CRM

Audit of Supabase project `xlseqwgyjuqhktrguhyc` ("EDUWIT LEAD TRACK", ap-south-1, Postgres 17.6) against `docs/B2B_CRM_PROMPT.md`.

- **Date:** 6 October 2026
- **Method:** read-only SQL against production (catalog queries, function sources, grants, policies, row counts) plus the Supabase security advisor. **Nothing was written, altered or enabled.**
- **Status:** waiting for Vikas's review. No migration runs until this report and the plan in section 9 are approved.

---

## 1. Summary

The database already has most of the B2B building blocks: partners, allocations, the engine, money tables and their functions. All of them were built for the old design, where the in-house team competed for every lead. The B2B tables are empty, so they can be moved and reshaped now at no risk to data.

Two problems need a decision before any B2B work. Both affect live systems today, not only the new CRM.

1. **Students' contact data is readable without a login.** The view `influencer_leads_dashboard` is `SECURITY DEFINER` and grants `SELECT` to `anon`. Anyone holding the project's public anon key, which ships inside the influencer dashboard's web page, can read every referred lead's name, phone, email and IP address, plus the influencer's `secret_password`. The B2B prompt says not to change influencer objects, so I have not touched it. The fix is one line (`revoke select on public.influencer_leads_dashboard from anon;`), and I recommend running it now (decision D1).
2. **Any signed-in account can call internal functions.** About 95 `SECURITY DEFINER` functions are executable by the `authenticated` role, and Supabase Auth is shared with the influencer dashboard (anyone who signs up gets that role). Several have **no role check inside**, including `lead_intake`, `crm_partner_event`, `crm_partner_duplicate`, `crm_sync_claim`, `crm_sync_result`, `crm_partner_verify` and `crm_api_key_check`. Any such account could create or overwrite leads, or fake partner events, through `/rest/v1/rpc/...` (decision D2).

Three findings change the plan:

3. **The old engine already runs inside Witty's write path.** `lead_intake()` sets `is_sales_ready = true` the moment Witty classifies a lead HOT, WARM or COLD. The live trigger `crm_auto_assign` then calls `crm_allocate_lead()` **synchronously, inside Witty's transaction**. It fired on the live lead on 5 Oct (`engine_decisions` id 1, mode `none`, "auto on sales-ready"). Today it does nothing harmful. But any error in that engine, including moving the `partners` table it reads, would make Witty's write fail. **This trigger must be re-scoped before any B2B table moves** (D4).
4. **Partner-sharing consent is never captured.** 0 of 1 live leads, and 0 of 98 in the 4 Oct backup, have `consent_partner_share_at`. Under the consent gate (B7.1 step 1), every lead would fall back to B2C until Witty, the website agent and the ad forms collect it (D7).
5. **No migrations are tracked.** `list_migrations` is empty, so every object was created by hand. Before the first change we need a baseline schema dump in the repo (step M0).

Smaller corrections to the prompt's description of the database:

| Prompt says | Database shows |
| --- | --- |
| "A trigger already catches direct inserts" on `student_leads` | No INSERT trigger exists. Only `student_leads_touch_trg` (before UPDATE), `crm_auto_assign`, and the delete and truncate guards |
| `crm_norm_phone()` adds a `+` | It returns digits only (`91XXXXXXXXXX`). The `910000xxxxxx` test match works as written |
| `student_leads` holds the live leads | 1 live row. The backup tables hold 94–98 rows from 1–4 Oct, so a reset appears to have happened on 4–5 Oct |
| Segment = university × course × level × mode | `crm_segment_of()` uses course, level and mode only. It has no university part and no roll-ups |
| pgmq queues, `pg_cron`, Realtime | **Not installed:** `pgmq` and `pg_cron`. The Realtime publication holds no tables. `pg_net`, `pgcrypto`, `pg_trgm`, `vector` and `supabase_vault` are installed |
| Develop against a branch or staging project | No Supabase branches exist (D3) |

---

## 2. Inventory at a glance

| Item | Count or state |
| --- | --- |
| Schemas with user objects | `public` only (198 tables, 6 views). No `b2b` schema yet |
| n8n's internal tables in `public` | About 115 tables (`workflow_entity`, `execution_entity`, …), all empty. It looks like an n8n instance was once pointed at this database. Leave them alone; don't drop them from this codebase |
| `w2_*` (Witty) | 30 tables, live (13 conversations, 154 messages). Not touched |
| Backup tables | 22 tables (`*_backup_20261001` … `_20261005`) holding copies of students' data with RLS and no policies. They need a retention decision (D12) |
| `student_leads` | 140 columns, 1 row, 10 indexes, RLS on |
| Partners, allocations, money tables | All empty, except `engine_decisions` (1 row, see finding 3) |
| `crm_users` / `auth.users` | 4 each (section 6) |
| Vault secrets | 0 |
| Storage buckets | 0 |
| Edge functions | 0 |
| Security advisor | 2 errors (SECURITY DEFINER views), 74 mutable `search_path` functions, 5 functions callable by `anon`, 95 by `authenticated`, leaked-password protection **off**, 163 tables with RLS and no policy (informational) |

---

## 3. Dependency map of shared objects (guardrail A3)

### 3.1 What Witty relies on (do not change)

| Object | Used by | How |
| --- | --- | --- |
| `lead_intake(p jsonb)` | Witty (n8n), every gated turn | Creates or merges the lead, sets profile and interest columns, sets `is_sales_ready` and `temperature` from `lead_status`, writes `touchpoints`. **Returns `crm_owned`** from `w2_crm_owned()` |
| `w2_crm_owned(phone)` | `lead_intake`, Witty | `destination_type is not null or owner_user_id is not null`. **This is how Witty knows to stop selling**: setting `destination_type` at allocation is enough (see D6) |
| `crm_find_lead(phone)` | `lead_intake`, `w2_crm_owned` | Matches on `regexp_replace(whatsapp_number,'\D','','g')`. There is no expression index, so every Witty turn scans the whole table. That's fine at 1 row, slow at 1M (section 8) |
| `crm_norm_phone`, `w2_is_test` | Intake | Test numbers: `910000\d{6}` or `w2_trusted.is_test` |
| `student_leads_touch_trg` | Every UPDATE | Sets `updated_at` |
| `student_leads_bulk_delete_guard` / `_truncate_guard` | DELETE, TRUNCATE | Blocks more than 5 rows unless `crm.allow_bulk_delete = on` |
| `crm_auto_assign` trigger → `crm_auto_assign_trg()` → `crm_allocate_lead()` or `crm_assign_lead()` | UPDATE OF `is_sales_ready` | **Runs synchronously inside Witty's write.** Reads `crm_settings`, `routing_rules`, `partners`, `allocations`, `crm_users`, `engine_decisions` |
| `w2_commit_turn` and other `w2_*` | Witty | Executable by `anon` and `authenticated` (Witty's own design, out of scope) |

Witty's SQL inside n8n workflows is not visible from the database. **Vikas: please export the n8n workflows** so I can confirm which other functions and columns Witty calls before anything changes.

### 3.2 Which functions read each B2B table (verified from function sources)

Each object needs a plan before it moves.

| Table | Read or written by |
| --- | --- |
| `partners` | `crm_allocate_lead`, `crm_dest_stats`, `crm_engine_flow`, `crm_partner_duplicate`, `crm_partner_event`, `crm_partner_health_check`, `crm_partner_rotate_secret`, `crm_partner_verify`, `crm_reallocate`, `crm_scorecards`, `crm_sync_claim`, `crm_upsert_partner`; view `partners_v` |
| `allocations` | `crm_allocate_lead`, `crm_apply_stage_system`, `crm_dest_stats`, `crm_engine_flow`, **`crm_merge_leads`**, `crm_partner_duplicate`, `crm_partner_event`, `crm_partner_health_check`, `crm_reallocate`, `crm_scorecards`, `crm_sync_claim`, `crm_sync_result` |
| `engine_decisions` | `crm_allocate_lead`, **`crm_merge_leads`**, `crm_reallocate` |
| `routing_rules` | `crm_allocate_lead`, `crm_save_routing_rule` |
| `partner_events` | `crm_partner_event`, `crm_partner_health_check`, `crm_scorecards` |
| `partner_mapping_profiles` | `crm_partner_event`, `crm_save_mapping_profile` |
| `earning_rates` | `crm_add_earning_rate`, `crm_earning_rate`, `crm_money_summary`, `crm_period_close`, `crm_report_enrollment` |
| `enrollments` | `crm_conversion`, `crm_dest_stats`, **`crm_merge_leads`**, `crm_money_summary`, `crm_partner_event`, **`crm_payout_run_set_status`** (B2C), `crm_period_close`, `crm_refund_enrollment`, `crm_report_enrollment`, `crm_scorecards`, `crm_verify_enrollment`; the type is used by **`crm_compute_payout`** (B2C) |
| `earnings` | `crm_invoice_set_status`, `crm_money_summary`, `crm_period_close`, `crm_refund_enrollment`, `crm_report_enrollment`, `crm_verify_enrollment` |
| `invoices` | `crm_invoice_set_status`, `crm_period_close` |

**Consequence:** these functions use `search_path = public` and unqualified table names. If a table moves to `b2b` with `ALTER TABLE … SET SCHEMA`, each listed function breaks unless its `search_path` is widened in the same migration. `crm_auto_assign` would then break **Witty's writes**, and `crm_merge_leads` would break lead merges. The plan in section 9 handles this ordering.

---

## 4. Verdict on every existing object

**keep**: reuse as is. **refactor**: reuse, with the change described. **leave to B2C**: owned by the B2C CRM; the B2B CRM reads it at most for the hand-off.

### 4.1 Leads and intake (shared hub)

| Object | Verdict | Notes |
| --- | --- | --- |
| `student_leads` | **keep** | All columns the B2B CRM needs exist (B3 list checked: 140 of 140, names match). No new columns. Propose one **expression index** on the phone digits (section 8), added `CONCURRENTLY` after approval |
| `student_leads_v` | **keep** | Read model for the B2B UI |
| `touchpoints` | **keep** | Intake-owned. The B2B CRM reads it for the journey timeline |
| `verifications` | **keep** | Website agent's OTP (0 rows) |
| `lead_intake()` | **keep, unchanged** | Witty's contract. The B2B Intake API calls it. Known gap: it marks a lead sales-ready on any HOT/WARM/COLD classification, earlier than the spec's "finished qualifying" signal (D5) |
| `crm_norm_phone()`, `crm_find_lead()`, `w2_is_test()` | **keep** | Index needed for `crm_find_lead` at scale |
| `crm_duplicate_candidates()` | **keep** | Shared de-duplication helper |
| `crm_merge_leads()` | **keep, refactor search_path** | Touches `allocations`, `engine_decisions`, `enrollments`; widen it to `public, b2b` when those move |
| `crm_new_lead()` | **leave to B2C** | Role-gated through `crm_users`. B2B manual entry calls `lead_intake()` with `source_system = 'b2b_manual'` |
| `student_leads_touch_trg`, delete and truncate guards | **keep** | B6.1.4 relies on the bulk-delete guard |
| `crm_auto_assign` trigger | **leave to B2C, but re-scope before B2B go-live** | Contradicts fallback-only routing and runs the engine inside Witty's transaction. Proposal in D4 |
| `crm_on_auth_user_created` (trigger on `auth.users` → `crm_handle_new_auth_user`) | **leave to B2C** | Inserts every new auth identity into `crm_users`. The B2B CRM does not use `crm_users` |

### 4.2 Catalogue

| Object | Verdict | Notes |
| --- | --- | --- |
| `catalog_universities` (29), `catalog_programs` (715), `catalog_synonyms` (32), `catalog_stage` | **keep** | Read-only for the B2B CRM. New programmes come only through reviewed "added from partner file" rows (B5.2.3), which need a `source` or `added_from_partner_version_id` column. **That is a change to a Witty-read table, so it needs approval (D11)** |
| `catalog_stage_add()`, `catalog_commit()`, `catalog_load()`, `catalog_remove_source()`, `catalog_programs_fee_check` trigger | **keep** | Never call `catalog_load()` or `catalog_remove_source()` from the B2B CRM |

### 4.3 Partners and sync

| Object | Verdict | How |
| --- | --- | --- |
| `partners` | **refactor, move to `b2b`** | Add the B5.1 fields (`display_name`, `logo_url`, `brand_color`, `dedupe_mode`, `hold_minutes`, `duplicate_window_hours`, `notify_enabled`, `test_endpoint`, `working_hours`, `holidays`, `live_mode`). Widen `adapter_type` to `leadsquared, salesforce, zoho, meritto, hubspot, generic_rest, webhook` and drop `portal`. **Move `inbound_secret` and `outbound_auth` into Vault**; the table keeps only the Vault secret IDs (they are plain columns today) |
| `partners_v` | **refactor** | Recreate in `b2b`; it never exposes secrets |
| `partner_mapping_profiles` | **refactor: normalise** | Recommendation: **normalise into the B8.3.6 tables.** A single JSON profile cannot cleanly hold pipelines, conditional rules, per-field direction, trusted flags, required flags and coverage gates, and the studio needs per-row confidence and history. The table is empty, so nothing is lost |
| `partner_events` | **keep shape, move to `b2b`** | Add `mapping_version`, `status` (`received`, `applied`, `held_unmapped`, `error`), `sequence` and `lead_id`. The unique `(partner_id, event_id)` index already gives idempotency |
| `crm_partner_verify()` (HMAC) | **refactor** | Same logic; read the secret from Vault |
| `crm_partner_rotate_secret()` | **refactor** | Write to Vault |
| `crm_partner_event()` | **refactor** | Route through the mapping layer, enforce column ownership (A3), write `partner_activities` and the lead roll-ups, enforce stage rank |
| `crm_partner_duplicate()` | **refactor** | Add the hold window, the 2-attempt and 3-partner limits, the commission dispute after acceptance, returning-student detection by `EDW-` reference, and B2C fallback reasons |
| `crm_partner_health_check()` | **refactor** | Auto-pause rules from B7.4 (5 SLA breaches, 30 minutes of sync failure, duplicate rate above 25% over 20 leads) |
| `crm_sync_claim()`, `crm_sync_result()` | **refactor → replace** | Become pgmq job handlers (route, push, poll, notify) |
| `crm_save_mapping_profile()` | **refactor → replace** | Functions for the mapping studio |
| `crm_upsert_partner()` | **refactor** | New fields; Admin check against `b2b.app_users` instead of `crm_require` |

### 4.4 Routing

| Object | Verdict | How |
| --- | --- | --- |
| `allocations` | **refactor, move to `b2b`** | B16: add `mode`, `attempt_no`, `cpe_net_inr`, `ncpl_inr`, `accepted_at`, `notify_status`, `hold_until`, `selection_probability`, `model_version`. Replace the status check with the B7.5 state machine and map `pending` → `queued`, `assigned` → `handed_off`. Change the open-allocation unique index to the new open states. **Change `lead_id … ON DELETE CASCADE` to `RESTRICT`**, so a hard delete of a lead can never silently drop allocation history |
| `engine_decisions` | **refactor, move to `b2b`** | Add `model_version`, `selection_probability`, `feature_hash` and `policy` (commission_first, performance, exploration, holdout). `ON DELETE CASCADE` → `RESTRICT`. The 1 existing row came from the old engine; keep it |
| `routing_rules` | **refactor, move to `b2b`** | Actions become `fix_partner`, `narrow` and `exclude` only. **Remove `destination = 'in_house'`** (B7.1 step 4). Version every change |
| `crm_allocate_lead()` | **refactor → new `b2b.route_lead()`** | New flow (B7.1): consent gate → repository candidates → exclusions → rules → capacity → commission-first or exploration → commit, plus B2C fallback reasons. The in-house team never competes. Retire the old function after cutover |
| `crm_dest_stats()` | **refactor** | Beta-binomial P̂ with maturity, half-life, prior and roll-ups; drop the in-house candidate |
| `crm_criteria_match()` | **keep** | Reused for `partners.lead_criteria` and rule conditions |
| `crm_rules_match()`, `crm_rules_where()` | **leave to B2C** | Used by marketing segments. The B2B CRM does not depend on them |
| `crm_segment_of()` | **keep; add `b2b.segment_of()`** | The new function adds university and the roll-up keys. The old one stays for anything still calling it |
| `crm_reallocate()` | **refactor** | Manual re-route rules from B7.7 (before first contact or after an SLA breach), recall through the adapter, the update message |
| `crm_engine_flow()`, `crm_scorecards()` | **refactor** | Into the B2B metric layer (rollups from `b2b.events`) |
| `crm_update_engine_settings()` + `crm_settings.engine` | **refactor** | Copy into `b2b.settings` with `b2b.engine_settings_versions`. Several defaults change: `share_cap` 0.70 → off, `exploration_floor` → `exploration_share` 0.20, and `fixed_split.in_house` is removed |

### 4.5 Money

| Object | Verdict | How |
| --- | --- | --- |
| `earning_rates` | **refactor, move to `b2b`** | Add scope `partner_programme`, add `superseded_by`, `reason`, `created_by_actor`. The current scope check allows only `university, programme, partner` |
| `enrollments` | **refactor, move to `b2b`: needs a decision** | B2C's `crm_compute_payout()` takes `enrollments` as an argument type, and `crm_payout_run_set_status()` reads it. Moving the table means updating those two B2C functions, or keeping `enrollments` in `public` as a shared "outcome" table (D9) |
| `earnings`, `invoices` | **keep shape, move to `b2b`** | `earnings.reverses_id` already follows the reverse-never-delete rule. Add a trigger that blocks DELETE on money rows |
| `crm_compute_earning()`, `crm_earning_rate()`, `crm_tier_pct()` | **refactor** | Most-specific-rate order with `partner_programme`; partner fee as `fee_base` (B5.2.4); GST net |
| `crm_period_close()`, `crm_verify_enrollment()`, `crm_refund_enrollment()`, `crm_report_enrollment()`, `crm_invoice_set_status()`, `crm_add_earning_rate()`, `crm_money_summary()` | **refactor** | Logic reused; Admin gate via `b2b.app_users`; GST invoice fields (GSTIN, SAC, numbering) |
| `crm_money_setting()`, `crm_settings.money` | **refactor** | Copy to `b2b.settings` (gst_rate 0.18, refund window 30 days). The CA confirms the values |

### 4.6 Platform (belong to the B2C CRM under A5)

| Object | Verdict |
| --- | --- |
| `crm_users`, `crm_teams`, `crm_tasks`, `crm_saved_views`, `crm_alerts` (1 row), `crm_notifications`, `crm_api_keys` (1 row), `crm_university_settings`, `message_templates`, `crm_leads_v` | **leave to B2C.** The B2B CRM builds its own equivalents in `b2b` |
| `crm_settings` | **leave to B2C.** Copy `engine`, `stages`, `sub_stages`, `lost_reasons`, `money` and `required_fields` into `b2b.settings` |
| `crm_activities` | **leave to B2C**, with one open question: B8.2 says "also write the stage change to `crm_activities`", while A5 says never write another product's tables (D10) |
| Role helpers `crm_role`, `crm_require`, `crm_me`, `crm_can_see`, `crm_b2b_reader`, `crm_money_reader`, `crm_masks`, `crm_mask_*` | **leave to B2C.** The B2B CRM uses `b2b.is_admin()` against `b2b.app_users` |
| `is_admin()` (email = connect@eduwit.in, used by influencer RLS) | **leave as is** (influencer product) |

### 4.7 B2C-only pieces

`calls`, `campaigns`, `campaign_sends`, `journeys` (6 rows), `journey_runs`, `segments`, `segment_members`, `payout_rates`, `payouts`, `payout_runs`, `crm_assign_lead()`, every `crm_campaign_*`, `crm_journey_*`, `crm_segment_*`, `crm_payout_*`, `crm_call_*`, `crm_score_*`, `crm_followup_tick`, `crm_daily_digest`, `crm_marketing_*`, `crm_unsubscribe*`, `crm_render_template`, `crm_send_job`, `crm_whatsapp_window`, `crm_verify_start` / `crm_verify_check`, `crm_agenda`, `crm_report`, `crm_conversion`, `crm_timeline`, `crm_add_note`, `crm_set_stage`, `crm_apply_stage_system`, `crm_update_lead`, `crm_update_user`, `crm_set_my_phone`, `crm_programme_fit`, `crm_sla_minutes`: **leave to B2C.** The B2B CRM reads none of them except to define the hand-off (B10).

### 4.8 Influencer dashboard (being redesigned separately)

`influencers` (3), `influencer_auth`, `influencer_leads_dashboard`, `current_referral_code()`, and the `student_leads` policy "Influencers can only view their own student leads": **do not change and do not depend on them**, apart from the security exposure in D1. The B2B CRM publishes `b2b_referral_outcomes` (masked) and `GET /v1/referrals/{code}/outcomes`.

---

## 5. Consent today

| Source (`lead_source`) | Leads | Partner-share consent | Sales consent | Sales-ready |
| --- | --- | --- | --- | --- |
| Live: `whatsapp_direct` | 1 | **0** | 1 | 1 |
| Backup 4 Oct: `organic` | 90 | 0 | 3 | 1 |
| Backup 4 Oct: (none) | 5 | 0 | 0 | 0 |
| Backup 4 Oct: `legacy` | 2 | 0 | 2 | 2 |
| Backup 4 Oct: `test_hermes` | 1 | 0 | 1 | 0 |

`lead_intake()` already accepts `consent_partner_share_at` and `consent_text_version` and keeps the first value. **No source sends them yet.** Witty's consent line, the website agent's, and the Meta and Google forms' must cover sharing with partner edtechs and ads measurement (B18). The text then needs the lawyer's approval.

---

## 6. Accounts and sign-in

| Account (masked) | Created | Last sign-in | Providers | MFA | `crm_users` |
| --- | --- | --- | --- | --- | --- |
| `con***@eduwit.in` (Admin) | 9 Jul 2026 | 2 Oct 2026 | google | **none** | admin, active |
| `pri***@gmail.com` (`226867ad…`) | 9 Jul 2026 | 9 Jul 2026 | google | none | viewer, inactive |
| `avk***@gmail.com` (`a7df2ced…`) | 10 Jul 2026 | 14 Jul 2026 | email, google | none | viewer, inactive |
| `dis***@gmail.com` (`d4c7236a…`) | 12 Jul 2026 | 12 Jul 2026 | email, google | none | viewer, inactive |

- The three Gmail accounts match the prompt's description and are listed for your decision (D8). I have not touched them.
- **The Admin identity has Google only.** Phase 0's exit test needs email and password with TOTP. You will need to set a password through a reset link on the existing identity, which links the email provider to the same user, and enrol TOTP on first password sign-in. No new user is created.
- **Leaked-password protection is off** in Supabase Auth. Turn it on in the dashboard: Auth → Providers → Email (B3 requires it).
- I can't see from SQL whether public sign-ups are open. Since anyone can authenticate against the shared project, the B2B CRM's allowlist check (B3) must run on the server for every request, as planned.

---

## 7. Security findings

| # | Severity | Finding | Proposed fix | Owner |
| --- | --- | --- | --- | --- |
| S1 | **Critical** | `influencer_leads_dashboard` is a `SECURITY DEFINER` view with `SELECT` (and write grants) for `anon` and `authenticated`. It exposes students' name, phone, email and IP address, plus `influencer_auth.secret_password`, to anyone with the anon key | `revoke all on public.influencer_leads_dashboard from anon, authenticated;` now. The redesigned influencer dashboard then reads `b2b_referral_outcomes` | Vikas (D1) |
| S2 | **High** | `SECURITY DEFINER` functions with no internal role check are executable by `authenticated`: `lead_intake`, `crm_partner_event`, `crm_partner_duplicate`, `crm_partner_verify`, `crm_sync_claim`, `crm_sync_result`, `crm_api_key_check`. Five more are executable by `anon` (`crm_auto_assign_trg`, `crm_handle_new_auth_user`, `rls_auto_enable`, `is_admin`, `current_referral_code`) | Revoke `EXECUTE` from `anon` and `authenticated` on these, after confirming which role n8n and Witty use to connect (if it's `service_role` or `postgres`, nothing breaks) | Vikas (D2) |
| S3 | Medium | Secrets stored in tables: `crm_settings.marketing.unsubscribe_secret` (present), and the `partners.inbound_secret` and `outbound_auth` columns (empty today) | Move to Vault; tables keep only secret IDs | B2B M5 |
| S4 | Medium | `authenticated` holds full table grants on `partners`, `allocations`, `crm_settings` and others. RLS blocks writes today only because no write policies exist | Revoke DML grants when the tables move to `b2b`; all writes go through functions | B2B M2 |
| S5 | Low | 74 functions with a mutable `search_path` (mostly `w2_*` and catalogue) | B2B functions all set `search_path`. Witty's are left to Witty | Mixed |
| S6 | Low | Backup tables hold full copies of students' data indefinitely | Retention rule (D12) | Vikas |
| S7 | Low | `vector` and `pg_trgm` are installed in `public` | Leave as is (Witty depends on them) | n/a |

---

## 8. Performance notes

- `crm_find_lead()` filters on `regexp_replace(whatsapp_number, '\D', '', 'g')` with no matching index (`student_leads_phone_idx` is on the raw column). At 10,000 leads a day this becomes a full-table scan on every Witty turn. Proposal: `create index concurrently student_leads_phone_digits_idx on student_leads ((regexp_replace(coalesce(whatsapp_number,''), '\D', '', 'g'))) where deleted_at is null and merged_into_id is null;`. This adds no columns and changes no behaviour, but it is on the shared table, so it needs approval.
- Master Lead Table search (name, email, `EDW-` reference, partner record ID in under 1 s at 1M rows) needs trigram indexes. These go on a B2B-owned search table kept current from `b2b.events`, not on `student_leads`, so Witty's write cost doesn't grow.
- The old engine counted `student_leads` per sales manager inside the trigger. The new engine never scans `student_leads` on the hot path.

---

## 9. Proposed plan (needs approval before anything runs)

### 9.1 Order of database changes

Each step is one tracked migration in `supabase/migrations/`. Each is tested on staging first, then applied to production only with your approval.

| Step | Migration | Notes |
| --- | --- | --- |
| **M0** | Baseline: dump the current `public` schema into `supabase/migrations/<ts>_baseline.sql` and mark it applied | No database change. Gives every later migration a reviewable diff |
| **M1** | Security hotfixes S1 and S2 (only if you approve them separately) | Revokes only; reversible with a matching `grant` |
| **M2** | Re-scope `crm_auto_assign` (D4). Recommended: replace its body with a **fast enqueue-only** trigger that catches its own errors and does nothing else. B2B routing runs from the queue | Must come **before** any table moves. Otherwise moving `partners` breaks Witty's writes |
| **M3** | `create extension pgmq; create extension pg_cron;` | Needed for jobs, timers and rollups |
| **M4** | `create schema b2b`; `b2b.app_users` (one row: connect@eduwit.in, linked to the existing `auth.users` id); `b2b.is_admin()`; `b2b.settings` copied from `crm_settings`; `b2b.events` (append-only); `b2b.integration_outbox`; RLS on every table | New objects only |
| **M5** | Move the 9 empty tables (`partners`, `allocations`, `partner_events`, `routing_rules`, `engine_decisions`, `earning_rates`, `earnings`, `invoices`, `partner_mapping_profiles`) with `ALTER TABLE … SET SCHEMA b2b`, in one transaction that also sets `search_path = public, b2b` on every dependent function from 3.2. Revoke DML from `authenticated`. Vault for partner secrets | `enrollments` waits for D9 |
| **M6** | Reshape the moved tables to the B16 design: allocation state machine, CASCADE → RESTRICT, `partner_programme` rate scope, new partner fields, Programme Repository and mapping tables, `partner_activities`, `student_notifications`, `conversion_events` | Phase 1 and 2 detail; separate plan |

### 9.2 Repository and app foundations (Phase 0, after approval)

- **Stack** (B14 and B15): Next.js App Router, TypeScript, Tailwind with shadcn/ui, TanStack Query and Table, ECharts, cmdk, sonner, Framer Motion; Geist fonts; design tokens as CSS variables (light and dark, indigo `#5B5BF7` accent). A Node 20 worker service in the same repo (`apps/web`, `apps/worker`, `packages/db`, `supabase/`).
- **Auth:** Supabase Auth with Google OAuth and email and password. A server-side allowlist check on every request against `b2b.app_users`. Any other identity is signed out with "This app is restricted", and the attempt is logged. TOTP is required for password sign-in and is a setting for Google sign-in. Sessions time out after 12 hours idle, and every sign-in is logged.
- **CI:** typecheck, lint, Vitest, pgTAP against a local Supabase, Playwright smoke tests.
- **First screen:** the app shell (left rail, top bar, ⌘K, theme toggle) with an empty Command Center, deployed to staging.

### 9.3 What I need from you

**D1.** Revoke `anon` and `authenticated` access to `influencer_leads_dashboard` now (S1)? It's a one-line fix for a live data exposure, even though the view belongs to the influencer product.

**D2.** Which database role do n8n (Witty) and the website agent connect with? If it's `service_role` or `postgres`, I'll revoke `EXECUTE` from `anon` and `authenticated` on the functions in S2.

**D3. Staging.** No Supabase branches exist. The options:
- (a) Supabase branching: needs the Pro plan; branches start empty, schema from migrations, so M0 comes first.
- (b) A separate staging project in ap-south-1.

I recommend (a).

**D4. `crm_auto_assign`.** Replace it with an enqueue-only trigger (recommended), or just disable it until the B2B engine is live? Disabling stops the B2C auto-assignment it does today. With no active sales managers, that assignment currently never succeeds anyway.

**D5. Witty's "finished qualifying" signal.** Today `is_sales_ready` turns true on Witty's first HOT/WARM/COLD classification. Options:
- (a) Witty sets an explicit flag at hand-off (for example `custom_fields.witty_handoff_at` through `lead_intake`). This needs a Witty-side change.
- (b) The B2B CRM decides "finished" itself: `lead_status` set and (escalated, or final programme confirmed, or 30 minutes since `last_agent_message_at`).

I recommend (b) for now, because it needs no Witty change, and (a) later.

**D6. `is_bot_paused`.** I recommend the B2B CRM does **not** set it. Witty already stops selling when `destination_type` is set (`w2_crm_owned`), and `destination_type` is a B2B-owned column.

**D7. Consent.** Who updates Witty's, the website agent's and the forms' consent lines to capture `consent_partner_share_at`, and by when? Until then every lead falls back to B2C.

**D8.** The three inactive Gmail accounts in section 6: keep, or delete them from the Supabase dashboard?

**D9. `enrollments`.** Move it to `b2b` and update the two B2C payout functions, or keep it in `public` as a shared outcome table?

**D10. `crm_activities`.** Should the B2B CRM still write stage changes there (B8.2), or only to `b2b.events`, with the B2C CRM subscribing through the outbox (A5)? I recommend outbox only.

**D11.** Approve adding `source` and `added_from_partner_version_id` columns to `catalog_programs` for "added from partner file" rows (B5.2.3)? Witty reads this table.

**D12.** Retention for the 22 `*_backup_*` tables: for example, drop them after 30 days.

**D13. Repository.** This repository is named `Influencersdashboard`, but A5 says each product has its own repository and the influencer dashboard is a separate product. Build the B2B CRM here, or in a new repository (for example `eduwit-b2b-crm`)? I've only added `docs/` here so far.

**D14. Hosting.** Which Google Cloud project (asia-south1) and who grants deploy access? Also confirm the Anthropic organisation's zero-retention setting (B7.8.2).

**D15.** A one-off export of the n8n workflows, so I can complete Witty's caller list before M2 and M5.

---

## 10. Open ambiguities in the prompt

1. Section 1 above lists where the database differs from the prompt (insert trigger, `+` in phone numbers, segment definition, extensions).
2. A4 lists `crm_partner_verify()` as HMAC. It exists, but it reads `partners.inbound_secret` from the table, which conflicts with the "no secrets in tables" rule. This is covered by S3.
3. B13.4 expects rollups every minute through `pg_cron`, but `pg_cron` is not installed (M3).
4. B14.3's "Admin: Users and roles" screen contradicts B3's "no user-management screens". I'll build no user management and show only the single Admin and their active sessions.
5. B7.4's kill switch "falls back to a fixed split", but the current `crm_settings.engine.fixed_split` is `{in_house: 100}`, which B7.4 forbids. The B2B copy starts with an empty split, and the kill switch refuses to engage until you set one.
