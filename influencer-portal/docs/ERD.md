# Proposed data model (ERD)

Status: **proposal, waiting for owner approval** (Phase 0, HARD STOP 1). No migration is written until this is approved.

All tables live in schema **`inf`** (decision D-01; spec names map `inf_x` → `inf.x`). Conventions for every table:

- `id uuid primary key default gen_random_uuid()` (bigint identity for very high-volume logs: clicks, audit, events,
  ledger, stage events), `created_at timestamptz not null default now()`, `updated_at` where rows change, and
  `created_by uuid` (auth user) where a person creates the row.
- Money is `bigint` **paise**, suffix `_paise`. Times are `timestamptz` (UTC). IST is applied only in queries and the UI.
- Status columns are `text` with `check` constraints, so a new status is a one-line migration.
- RLS is on for every table. Policies call helpers as `(select inf.has_perm('…'))`, so they run once per statement.
  Writes go through `SECURITY DEFINER` functions; direct table writes are granted only where RLS fully covers them.
- Append-only tables (signatures, contract versions, ledger entries, audit log, stage events, deliveries) have a
  `before update or delete` trigger that raises, and no UPDATE/DELETE grant.
- `→ public.student_leads` means a soft reference by `student_lead_id bigint` **with no foreign key** to the shared
  table. A foreign key would add locking and `ON DELETE` coupling to the master table; integrity is checked by the
  sync job instead (decision D-07).

The diagrams below show keys and the columns that matter for relationships and logic. Full column lists come in the
Phase 1+ migrations.

## 1. Identity, roles, agencies

```mermaid
erDiagram
  auth_users ||--o| staff_profiles : "is staff"
  auth_users ||--o| creator_accounts : "is creator user"
  auth_users ||--o| agency_members : "is agency user"
  staff_profiles ||--o{ staff_role_grants : has
  creators ||--o| creator_accounts : "login for"
  creators ||--o{ creator_platforms : has
  creators ||--o| creator_kyc : has
  creators ||--o{ creator_rate_cards : has
  creators ||--o{ creator_portfolio : has
  creators ||--o{ creator_contacts : "family/self numbers"
  agencies ||--o{ agency_members : has
  agencies ||--o{ agency_creator_links : manages
  creators ||--o{ agency_creator_links : "managed via"
  tiers ||--o{ creators : "current tier"
  staff_profiles ||--o{ creators : owns

  staff_profiles {
    uuid user_id PK "auth.users"
    text full_name
    text email
    bool is_signatory
    text signatory_designation
    text status "active|suspended"
  }
  staff_role_grants {
    uuid user_id FK
    text role "super_admin|influencer_manager|content_reviewer|finance|viewer"
  }
  creators {
    uuid id PK
    text legal_name
    text display_name
    citext handle UK
    citext email
    text phone_e164
    text city
    text state
    text_arr languages
    text_arr niches
    text bio
    text avatar_path
    text status "prospect|invited|onboarding|active|paused|blocked|archived"
    text pipeline_stage "prospect..archived"
    bool is_blocked
    uuid tier_id FK
    uuid owner_id FK
    text source
    text_arr tags
    bool public_page_enabled
    bool leaderboard_opt_in
    bool is_test
    timestamptz last_activity_at
  }
  creator_accounts {
    uuid creator_id PK
    uuid user_id UK "auth.users"
    timestamptz terms_accepted_at
    text terms_version
  }
  creator_platforms {
    uuid id PK
    uuid creator_id FK
    text platform "instagram|youtube|facebook|linkedin|x|telegram|moj_josh|other"
    text url
    text handle
    bigint followers
    bigint avg_views
    numeric engagement_rate
    jsonb audience
    text source "manual|api"
    timestamptz stats_updated_at
  }
  creator_kyc {
    uuid creator_id PK
    bytea pan_enc
    text pan_last4
    text name_on_pan
    text gstin
    text gst_status
    bytea bank_account_enc
    text bank_last4
    text ifsc
    text account_holder
    text proof_path
    text status "pending|submitted|verified|rejected"
    uuid verified_by
    timestamptz verified_at
  }
  creator_rate_cards {
    uuid id PK
    uuid creator_id FK
    text platform
    text format
    bigint suggested_paise
  }
  creator_portfolio {
    uuid id PK
    uuid creator_id FK
    text url
    text media_path
    text caption
  }
  creator_contacts {
    uuid id PK
    uuid creator_id FK
    text kind "self|family|team"
    text phone_hash
    text email_hash
  }
  agencies {
    uuid id PK
    text name
    citext email
    text phone
    text gstin
    text status
  }
  agency_members {
    uuid id PK
    uuid agency_id FK
    uuid user_id FK
    text role "owner|member"
  }
  agency_creator_links {
    uuid id PK
    uuid agency_id FK
    uuid creator_id FK
    bool can_view
    bool can_act_deliverables
    bool can_negotiate_sign
    bool can_view_earnings
    bool is_payee_by_contract
    timestamptz granted_at
    timestamptz revoked_at
  }
```

Notes:
- PAN and bank account numbers are encrypted with `pgp_sym_encrypt` using a key held in Vault (`inf_pii_key`), with
  `pan_last4`/`bank_last4` kept for masked display. Only `inf.kyc_reveal(creator_id)` decrypts, for the Finance role,
  and every call is audit-logged (D-08).
- `creator_contacts` stores **hashes** (HMAC with a Vault key) of the creator's own and family numbers and emails, for
  self-referral checks without keeping extra plain copies.

## 2. Prospecting, tasks, campaigns, applications

```mermaid
erDiagram
  creators ||--o{ outreach_activities : logged
  staff_profiles ||--o{ tasks : assigned
  campaigns ||--o{ campaign_programmes : targets
  campaigns ||--o{ campaign_invites : sends
  campaigns ||--o{ campaign_applications : receives
  creators ||--o{ campaign_invites : receives
  creators ||--o{ campaign_applications : submits
  campaign_applications ||--o{ application_offers : "negotiation rounds"
  deal_presets ||--o{ campaigns : "default preset"
  brief_templates ||--o{ campaigns : "default brief"
  contract_templates ||--o{ campaigns : "default contract"

  outreach_activities {
    uuid id PK
    uuid creator_id FK
    text kind "call|dm|email|whatsapp|meeting|note"
    text outcome
    date next_follow_up_on
    uuid actor_id
  }
  tasks {
    uuid id PK
    text title
    uuid assignee_id FK
    date due_on
    text entity_type
    uuid entity_id
    text status "open|done|cancelled"
  }
  campaigns {
    uuid id PK
    text name
    text slug UK
    text objective
    text description
    text status "draft|open|invite_only|active|paused|completed|archived"
    text visibility "open|invite_only|both"
    date starts_on
    date ends_on
    bigint budget_paise
    int slots
    jsonb eligibility
    uuid default_preset_id
    uuid default_brief_template_id
    uuid default_contract_template_id
    jsonb deliverable_template
    text wa_message_template
    text attribution_model_override
    int attribution_window_days_override
  }
  campaign_programmes {
    uuid campaign_id FK
    bigint programme_id "catalog_programs.id"
  }
  campaign_invites {
    uuid id PK
    uuid campaign_id FK
    uuid creator_id FK
    text status "sent|accepted|declined|countered|expired"
    timestamptz expires_at
  }
  campaign_applications {
    uuid id PK
    uuid campaign_id FK
    uuid creator_id FK
    text pitch
    text proposed_deal_type
    jsonb proposed_terms
    text_arr sample_links
    text status "submitted|shortlisted|countered|accepted|rejected|withdrawn"
    text reject_reason
    uuid thread_id FK
  }
  application_offers {
    bigint id PK
    uuid application_id FK
    text party "creator|eduwit"
    jsonb terms
    text note
  }
```

## 3. Deals and compensation

```mermaid
erDiagram
  creators ||--o{ deals : has
  campaigns ||--o{ deals : "optional"
  deals ||--o{ deal_versions : "immutable versions"
  deal_presets ||--o{ deal_versions : "started from"
  deals ||--o{ contracts : "governed by"
  deal_versions ||--o{ penalty_proposals : "rules"
  deals ||--o{ comp_runs : "engine runs"

  deals {
    uuid id PK
    uuid creator_id FK
    uuid campaign_id FK
    text status "draft|proposed|negotiating|agreed|active|completed|terminated|expired"
    date starts_on
    date ends_on
    uuid current_version_id FK
    uuid governing_contract_id FK
    text deal_model "commission_only|fixed_only|hybrid|custom"
  }
  deal_versions {
    uuid id PK
    uuid deal_id FK
    int version
    jsonb comp_config "validated, see notes"
    text config_hash "sha256"
    text origin "builder|counter_offer|amendment|renewal"
    uuid proposed_by
    timestamptz effective_from
    bool is_signed
  }
  deal_presets {
    uuid id PK
    text name
    jsonb comp_config
    bool is_system
  }
  penalty_proposals {
    uuid id PK
    uuid deal_id FK
    uuid deliverable_id
    text rule_id
    bigint amount_paise
    text status "proposed|approved|rejected"
    uuid decided_by
    text reason
  }
  comp_runs {
    bigint id PK
    uuid deal_id FK
    uuid deal_version_id
    text kind "live|dry_run"
    int entries_posted
    jsonb diff
  }
```

**Decision D-05: compensation config as validated JSONB, not child tables.** Each `deal_versions.comp_config` is one
immutable document (fixed components with milestone schedules, commission rules with scope, basis, slabs, caps,
floors, recoupment, accrual and confirmation, bonus rules with AND/OR conditions, penalty rules, additional fees, caps
and non-cash items), every element carrying a stable `rule_id`. Reasons:
1. The pure engine (`lib/compensation`) takes exactly this document as input, so the stored config and the tested
   input are the same thing (no mapping layer to drift).
2. Versions are snapshots. With ~10 child tables, each amendment would copy rows across all of them.
3. Validation runs twice: the zod schema in the app, and `inf.comp_config_valid(jsonb)` as a `check` constraint. The
   SQL check is **generated** from the zod schema (JSON Schema → a PL/pgSQL validator) by a build script, and a CI test
   fails if they drift.
4. Reporting needs ("which deals have retroactive slabs?") use a GIN index and the generated column
   `deal_model`.

## 4. Contracts and signatures

```mermaid
erDiagram
  clause_library ||--o{ clause_versions : versions
  contract_templates ||--o{ template_clauses : "ordered"
  clause_versions ||--o{ template_clauses : uses
  deals ||--o{ contracts : has
  contracts ||--o{ contracts : "amends (parent)"
  contracts ||--o{ contract_versions : "immutable renders"
  contract_versions ||--o{ contract_comments : "clause-anchored"
  contract_versions ||--o{ contract_change_requests : proposes
  contract_versions ||--o{ signatures : "signed"
  otp_challenges ||--o| signatures : verifies

  clause_library {
    uuid id PK
    text category
    text title
    bool required
    bool negotiable
    bool locked
    text_arr deal_types
    text_arr campaign_types
    uuid current_version_id
  }
  clause_versions {
    uuid id PK
    uuid clause_id FK
    int version
    jsonb body_doc "Tiptap JSON"
    bool legal_reviewed
    uuid reviewed_by
    timestamptz reviewed_at
  }
  contract_templates {
    uuid id PK
    text name
    jsonb header_doc
    jsonb footer_doc
    int version
    text status
  }
  template_clauses {
    uuid template_id FK
    int position
    uuid clause_version_id FK
    jsonb condition "e.g. deal.has_commission"
  }
  contracts {
    uuid id PK
    uuid deal_id FK
    uuid template_id FK
    text status "draft|sent|in_negotiation|ready_to_sign|signed_by_creator|active|completed|terminated|expired|void|superseded"
    uuid current_version_id
    text payee "creator|agency"
    date effective_on
    date expires_on
    uuid parent_contract_id FK
    text stamp_duty_reference
    timestamptz negotiation_deadline
  }
  contract_versions {
    uuid id PK
    uuid contract_id FK
    int version
    text html
    text canonical_json
    text sha256
    uuid deal_version_id
    uuid created_by
    text pdf_path
  }
  contract_comments {
    uuid id PK
    uuid contract_version_id FK
    text clause_anchor
    uuid parent_id
    text body
    uuid author_id
    bool resolved
  }
  contract_change_requests {
    uuid id PK
    uuid contract_version_id FK
    text clause_anchor
    jsonb proposed_doc
    text status "pending|accepted|rejected|countered"
    uuid decided_by
  }
  otp_challenges {
    uuid id PK
    uuid user_id
    text purpose "sign|login_2fa"
    text channel "email|whatsapp|sms"
    text code_hash
    int attempts
    timestamptz expires_at
    timestamptz verified_at
    text provider_ref
  }
  signatures {
    bigint id PK
    uuid contract_version_id FK
    uuid signer_user_id
    text signer_role "creator|agency|eduwit_signatory"
    text document_sha256
    text typed_name
    text consent_text_version
    uuid otp_challenge_id FK
    text otp_channel
    inet ip
    text user_agent
    jsonb geo
    timestamptz signed_at
  }
```

## 5. Briefs, deliverables, content review

```mermaid
erDiagram
  brief_templates ||--o{ briefs : "generated from"
  deals ||--o{ briefs : has
  briefs ||--o{ brief_versions : versions
  brief_versions ||--o{ brief_acknowledgements : acknowledged
  briefs ||--o{ brief_questions : "Q&A"
  deals ||--o{ deliverables : has
  briefs ||--o{ deliverables : specifies
  deliverables ||--o{ deliverable_submissions : versions
  deliverable_submissions ||--o{ review_comments : has
  deliverables ||--o{ published_posts : "go-live"
  published_posts ||--o{ post_metric_snapshots : metrics
  deliverables ||--o{ compliance_checks : scanned
  deliverables ||--o{ deliverable_transitions : history

  briefs {
    uuid id PK
    uuid deal_id FK
    uuid campaign_id FK
    uuid current_version_id
  }
  brief_versions {
    uuid id PK
    uuid brief_id FK
    int version
    jsonb doc
    jsonb approved_claims
    jsonb banned_claims_snapshot
  }
  brief_acknowledgements {
    bigint id PK
    uuid brief_version_id FK
    uuid user_id
    timestamptz acknowledged_at
  }
  deliverables {
    uuid id PK
    uuid deal_id FK
    uuid brief_id FK
    text type "reel|story|post|youtube_video|short|live|carousel|blog|other"
    text platform
    jsonb specs
    jsonb stage_toggles
    jsonb due_dates
    int revision_limit
    int revisions_used
    text status
    text milestone_rule_id
    uuid tracking_link_id FK
  }
  deliverable_submissions {
    uuid id PK
    uuid deliverable_id FK
    text kind "concept|script|draft|final"
    int version
    text body
    text file_path
    text link_url
    text creator_note
    text status
  }
  review_comments {
    uuid id PK
    uuid submission_id FK
    int video_timestamp_ms
    jsonb image_region
    text body
    bool resolved
    uuid author_id
  }
  published_posts {
    uuid id PK
    uuid deliverable_id FK
    text live_url
    date posted_on
    jsonb oembed
    bool disclosure_ok
    text verification_status
    uuid verified_by
    timestamptz verified_at
  }
  post_metric_snapshots {
    bigint id PK
    uuid published_post_id FK
    text checkpoint "24h|7d|30d|adhoc"
    bigint views
    bigint reach
    bigint likes
    bigint comments
    bigint shares
    bigint saves
    bigint clicks
    bigint watch_time_s
    text source "manual|screenshot|api"
    text screenshot_path
    timestamptz captured_at
  }
  compliance_checks {
    uuid id PK
    uuid deliverable_id FK
    uuid submission_id
    text kind "banned_claims|disclosure|asci_checklist"
    jsonb result
    bool passed
    bool overridden
    text override_reason
  }
  deliverable_transitions {
    bigint id PK
    uuid deliverable_id FK
    text from_status
    text to_status
    uuid actor_id
  }
```

## 6. Attribution and the creator lead pipeline

```mermaid
erDiagram
  creators ||--o{ tracking_links : owns
  deals ||--o{ tracking_links : "optional"
  deliverables ||--o{ tracking_links : "optional"
  tracking_links ||--o{ link_clicks : logs
  tracking_links ||--o{ lead_attributions : credits
  student_leads ||--o{ lead_attributions : "soft ref, no FK"
  lead_attributions ||--o{ attribution_decisions : "history"
  student_leads ||--o{ lead_stage_events : "soft ref"
  lead_attributions ||--|| creator_lead_feed : "masked projection"
  stage_mappings }o--o{ lead_stage_events : "maps"
  lead_attributions ||--o{ fraud_flags : raises

  tracking_links {
    uuid id PK
    citext code UK
    uuid creator_id FK
    uuid deal_id FK
    uuid deliverable_id FK
    uuid campaign_id FK
    bigint programme_id
    text destination "whatsapp_witty|website_landing|custom_url"
    text custom_url
    jsonb utm
    bool active
  }
  link_clicks {
    bigint id PK
    uuid link_id FK
    text ip_hash
    text ua
    text referrer
    jsonb utm
    text device
    text w2_access_code
    timestamptz clicked_at
  }
  lead_attributions {
    uuid id PK
    bigint student_lead_id "public.student_leads.id"
    uuid creator_id FK
    uuid deal_id FK
    uuid deliverable_id FK
    uuid link_id FK
    text code
    text touch "first|last|assisted"
    text status "credited|duplicate|outside_window|self_referral|fraud_suspected|manually_rejected|manually_credited"
    text reason
    uuid decided_by
    timestamptz decided_at
    timestamptz touch_at
    text evidence_source
  }
  attribution_decisions {
    bigint id PK
    uuid attribution_id FK
    text from_status
    text to_status
    text reason
    uuid actor_id
  }
  fraud_flags {
    uuid id PK
    uuid creator_id FK
    uuid attribution_id FK
    text signal "velocity|same_device|no_witty_reply|off_hours_burst|junk_rate"
    jsonb detail
    text status "open|cleared|confirmed"
  }
  lead_stage_events {
    bigint id PK
    bigint student_lead_id
    text creator_stage
    text reason_category
    text source
    text idem_key UK
    timestamptz occurred_at
  }
  stage_mappings {
    uuid id PK
    int priority
    text source
    jsonb match
    text creator_stage
    text reason_category
    bool active
  }
  creator_lead_feed {
    uuid attribution_id PK
    uuid creator_id
    text lead_ref
    text display_name
    text phone_masked
    text email_masked
    text city
    text state
    text programme
    text creator_stage
    text reason_category
    text temperature
    jsonb stage_timeline
    text earning_status
    timestamptz updated_at
  }
```

- `creator_lead_feed` is a **table** maintained by the sweep, holding only whitelisted, already-masked values. It is
  the only lead-shaped object creators can `SELECT` (RLS: `creator_id` is theirs, or an agency grant with `can_view`)
  and the only one in the Realtime publication. Raw lead data never reaches it.
- Uniqueness: one credited first-touch attribution per `student_lead_id` (partial unique index), so two creators can
  never both be paid for the same lead under first-touch; assisted rows are recorded separately.

## 7. Money

```mermaid
erDiagram
  creators ||--o{ ledger_entries : earns
  deals ||--o{ ledger_entries : from
  ledger_entries ||--o{ ledger_status_events : lifecycle
  ledger_entries ||--o| ledger_entries : "reverses"
  payout_batches ||--o{ payouts : contains
  payouts ||--o{ payout_items : includes
  ledger_entries ||--o| payout_items : "paid in"
  creators ||--o{ invoices : uploads
  payouts ||--o| invoices : "requires (GST)"
  creators ||--o{ tds_records : withheld
  eduwit_commission_receipts }o--|| lead_attributions : "confirms commission"
  tds_sections ||--o{ tds_records : under

  ledger_entries {
    bigint id PK
    uuid creator_id FK
    uuid deal_id FK
    uuid deal_version_id
    text type "fixed_fee|milestone|commission|bonus|usage_fee|exclusivity_fee|penalty|clawback|tds|gst|adjustment|payout|reversal"
    bigint amount_paise
    text direction "credit|debit"
    text status "accrued|confirmed|payable|in_batch|paid|reversed|on_hold|clawed_back"
    text event_key UK
    text rule_id
    bigint subject_ref
    text source_ref
    text period_ist "YYYY-MM"
    date due_on
    bigint reverses_id FK
    text notes
  }
  ledger_status_events {
    bigint id PK
    bigint entry_id FK
    text from_status
    text to_status
    uuid actor_id
    text reason
  }
  payout_batches {
    uuid id PK
    text status "draft|approved|processing|paid|failed|cancelled"
    uuid created_by
    uuid approved_by
    uuid second_approved_by
    text bank_export_path
  }
  payouts {
    uuid id PK
    uuid batch_id FK
    uuid creator_id FK
    text payee "creator|agency"
    bigint gross_paise
    bigint tds_paise
    bigint gst_paise
    bigint net_paise
    text status
    text utr
    date paid_on
    text advice_pdf_path
  }
  payout_items {
    uuid payout_id FK
    bigint entry_id FK "unique"
  }
  invoices {
    uuid id PK
    uuid creator_id FK
    uuid payout_id FK
    text kind "creator_gst_invoice|payout_statement"
    text number
    date issued_on
    bigint taxable_paise
    bigint gst_paise
    bigint total_paise
    text file_path
    text status "submitted|accepted|rejected"
  }
  tds_sections {
    text code PK
    text label
    numeric rate_pct
    numeric rate_no_pan_pct
    bigint threshold_single_paise
    bigint threshold_fy_paise
    text_arr component_types
    bool confirmed_by_ca
  }
  tds_records {
    uuid id PK
    uuid creator_id FK
    text section FK
    numeric rate_pct
    bigint base_paise
    bigint amount_paise
    text quarter "Q1..Q4"
    text fy "2026-27"
    text form16a_path
  }
  eduwit_commission_receipts {
    bigint id PK
    bigint student_lead_id
    text enrollment_ref
    bigint gross_paise
    bigint gst_paise
    bigint net_paise
    bigint received_paise
    date received_on
    text status "expected|partly_received|received|reversed"
    text source "b2b|b2c|manual"
    text source_version
    uuid entered_by
    text reason
  }
```

**Decision D-06: ledger immutability.** Financial columns (`amount_paise`, `type`, `direction`, `event_key`,
`creator_id`, `deal_id`, `rule_id`) can never change (a trigger raises). The lifecycle moves through
`ledger_status_events` (append-only), with `ledger_entries.status` kept as a denormalised current value that only the
`inf.ledger_transition()` function may change, and only along allowed edges (accrued → confirmed → payable → in_batch →
paid; any → on_hold; reversals and clawbacks are new entries). This keeps "corrections are new reversing entries" while
still letting a payout batch claim entries.

## 8. Engagement, configuration and operations

```mermaid
erDiagram
  threads ||--o{ messages : has
  messages ||--o{ message_reads : "read receipts"
  notification_templates ||--o{ notifications : renders
  notifications ||--o{ notification_deliveries : "per channel"
  creators ||--o{ scorecards : periodic
  tiers ||--o{ scorecards : "resulting tier"
  webhook_endpoints ||--o{ webhook_deliveries : logs
  domain_events ||--o{ webhook_deliveries : "fans out"
  domain_events ||--o{ jobs : triggers

  threads {
    uuid id PK
    text entity_type
    text entity_id
    text subject
    bool staff_only
  }
  messages {
    uuid id PK
    uuid thread_id FK
    uuid author_id
    text body
    text_arr attachment_paths
    uuid_arr mentions
    tsvector search
  }
  message_reads {
    uuid message_id FK
    uuid user_id
    timestamptz read_at
  }
  notifications {
    uuid id PK
    uuid user_id
    text event
    text title
    text body
    jsonb data
    bool mandatory
    timestamptz read_at
    text idem_key UK
  }
  notification_deliveries {
    bigint id PK
    uuid notification_id FK
    text channel "email|whatsapp|in_app"
    text status "queued|sent|failed|skipped"
    int attempts
    text provider_ref
    text error
  }
  notification_preferences {
    uuid user_id
    text event
    text channel
    bool enabled
  }
  notification_templates {
    uuid id PK
    text event
    text channel
    text locale
    int version
    text subject
    text body
    bool active
  }
  announcements {
    uuid id PK
    text title
    jsonb body
    jsonb segment
    timestamptz publish_at
  }
  tiers {
    uuid id PK
    text name
    int rank
    jsonb entry_rules
    jsonb benefits
  }
  scorecards {
    uuid id PK
    uuid creator_id FK
    text period
    jsonb metrics
    numeric composite
    uuid tier_id FK
  }
  banned_claims {
    uuid id PK
    text pattern
    text kind "phrase|regex"
    text severity
    text note
    bool active
  }
  settings {
    text key PK
    jsonb value
    int version
    uuid updated_by
    timestamptz updated_at
  }
  settings_versions {
    bigint id PK
    text key
    jsonb value
    int version
    uuid actor_id
    text reason
  }
  audit_log {
    bigint id PK
    uuid actor_id
    text actor_role
    text entity_type
    text entity_id
    text action
    jsonb before
    jsonb after
    inet ip
    text user_agent
    text request_id
    timestamptz at
  }
  domain_events {
    bigint id PK
    text type
    text subject_type
    text subject_id
    jsonb payload
    text idem_key UK
    timestamptz occurred_at
  }
  jobs {
    bigint id PK
    text kind
    jsonb payload
    text status "queued|running|done|failed|dead"
    int attempts
    timestamptz run_at
    text last_error
    text idem_key UK
  }
  webhook_endpoints {
    uuid id PK
    text url
    text_arr events
    uuid secret_id
    bool active
  }
  webhook_deliveries {
    bigint id PK
    uuid endpoint_id FK
    bigint event_id FK
    int attempt
    int status_code
    text error
    timestamptz next_attempt_at
  }
  sync_state {
    text key PK
    bigint last_id
    timestamptz last_ts
    timestamptz ran_at
    jsonb stats
  }
  email_codes {
    uuid id PK
    uuid user_id
    text code_hash
    int attempts
    timestamptz expires_at
  }
  trusted_devices {
    uuid id PK
    uuid user_id
    text token_hash
    text label
    timestamptz expires_at
    timestamptz revoked_at
  }
  dpdp_requests {
    uuid id PK
    uuid creator_id
    text kind "export|deletion"
    text status
    jsonb result
  }
  terms_versions {
    uuid id PK
    text kind "platform_terms|privacy|consent_otp|sign_consent"
    int version
    text body
    timestamptz effective_at
  }
  terms_acceptances {
    bigint id PK
    uuid user_id
    uuid terms_version_id FK
    inet ip
    timestamptz accepted_at
  }
```

## 9. Summary of decisions embodied here

| # | Decision | Where |
| --- | --- | --- |
| D-01 | Dedicated schema `inf` | All |
| D-05 | Compensation config as validated JSONB per immutable deal version | §3 |
| D-06 | Ledger: immutable amounts, status through an append-only lifecycle | §7 |
| D-07 | Soft references to `student_leads` (no foreign key) | §6, §7 |
| D-08 | PAN and bank encrypted with pgcrypto and a Vault key; last 4 stored for display | §1 |
| D-09 | Creator-safe masked projection table for Realtime and creator reads | §6 |
| D-10 | One credited first-touch attribution per lead (partial unique index) | §6 |
