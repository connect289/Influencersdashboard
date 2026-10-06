# Eduwit B2B Partner CRM — Build Prompt for Claude Code

Version 6 October 2026 · Owner: Vikas Jha, Eduwit Learning Services

> **How to use this file.** Save it in the new repository as `docs/B2B_CRM_PROMPT.md`, then open Claude Code in that repository and say:
> *"Read docs/B2B_CRM_PROMPT.md end to end. Start with Phase 0 and stop after the audit report for my review."*
> Part A tells Claude Code how to work. Part B is the product specification it builds from.

---

# PART A — Brief to Claude Code

## A1. Your role

You are the lead engineer building **Eduwit's B2B Partner CRM**: a production web application that receives every student lead Eduwit generates, sends each lead to the partner edtech that will earn Eduwit the most from it, keeps that lead in live sync with the partner's own CRM, tells the student who will call them, keeps improving its routing with machine learning and a Claude-based optimiser so every lead earns the most commission it can, and gives Eduwit's Admin a complete, customisable view of partner sales effort, SLAs and commissions.

Build it as an industry-grade system: correct before clever, explainable in every decision, fast, and pleasant to use. Treat money, routing and student messaging as safety-critical.

## A2. How to work

1. **Plan before you build.** For each phase, write a short plan (files, migrations, tests) and wait for approval before large or irreversible changes.
2. **Audit first (Phase 0).** The shared Supabase database already holds much of the backend described in an earlier, broader PRD (see A4). Inventory it, test it, and write a gap report before writing any new migration. Reuse what fits, refactor what conflicts, and never build a parallel copy of something that exists.
3. **Small, reviewable steps.** One feature per branch and pull request, each with tests and a short description of what changed and how it was verified.
4. **Business rules live in the database.** Routing, allocation records, stage moves, commission booking and the duplicate cascade run as SQL functions in transactions with constraints, so no screen or worker can bypass them. Workers and the UI call these functions.
5. **Test with test leads only.** Every flow is proven on test leads against a mock partner server before any real partner or student is touched. A `LIVE_MODE` flag per partner and per channel (WhatsApp, email, CAPI) defaults to off.
6. **Explain everything.** Every routing decision, commission line and notification can be traced from stored records. If you cannot explain a number from the database, it is a bug.
7. **Ask when a rule is ambiguous.** Part B states defaults for open decisions (B21). Use them, and list any new ambiguity in your phase report instead of guessing silently.

## A3. Hard guardrails (never break these)

- **Witty is live for every student.** The Supabase project is shared with Witty, Eduwit's WhatsApp AI agent, which runs in n8n. Never change, drop or rename anything Witty uses without a written plan approved by Vikas:
  - every `w2_*` table and function (for example `w2_conversations`, `w2_messages`, `w2_outbox`, `w2_commit_turn`, `w2_crm_payload`);
  - `lead_intake(p jsonb)`, which Witty calls on every gated turn;
  - the `student_leads` columns Witty writes.
- **`student_leads` is shared.** Add columns only by tracked migration, never rename, retype or drop one. A pending rename script, `student_leads_v2_rename.sql`, must **not** be run. Use the live column names listed in B3 (for example `whatsapp_number`, `student_name`, `email_id`, `lead_source`), or the existing compatibility view `student_leads_v`.
- **`w2_messages` belongs to Witty and the website agent.** The B2B CRM never writes to it. Student notifications go to the CRM's own table (B9).
- **Never slow down or break Witty's writes.** Any trigger you add on `student_leads` only enqueues a job: it is fast, never calls out, and catches its own errors so it can never make `lead_intake()` or Witty's update fail. Do not enable or change row-level security or policies on `student_leads` or any `w2_*` table; the app reads them through views and `SECURITY DEFINER` functions. Before refactoring or dropping any existing function, check what depends on it (`pg_depend`, triggers, and the SQL inside Eduwit's n8n workflows, which Vikas can export for you) and list the callers in your plan. Analytics roll-ups read the CRM's own event log, never full scans of `student_leads` every minute.
- **Column ownership on `student_leads`.** Witty and the website agent own the conversation, AI-qualification, interest and profile columns. Intake owns source, attribution and verification. The B2B CRM owns the allocation, partner-sync, sales-effort, application, enrollment and revenue columns. A system writes only the columns it owns; partner data fills an interest or profile column only when it is empty and the mapping marks the partner as trusted for that field (B8.3.1).
- **Use a staging copy.** Develop against a Supabase branch or a separate staging project, never directly against production.
- **Test leads stay out.** Rows with `is_test = true`, and every phone whose digits match `910000xxxxxx` after normalisation (Witty's test harness; `crm_norm_phone()` adds a `+`, so match on digits), are never pushed to a real partner's production pipeline, never messaged on a live channel, never sent to Meta or Google, and never counted in analytics, routing statistics or commissions. They may be pushed to a partner's sandbox or test pipeline when one is configured (`partners.test_endpoint`).
- **No secrets in code or in tables.** API keys, partner credentials, HMAC secrets and provider tokens live in Supabase Vault or the cloud secret manager. One existing setting, `crm_settings.marketing.unsubscribe_secret`, is stored in a table. Flag it in the audit and propose moving it to Vault.
- **No real student is messaged, and no real partner receives a lead, until Vikas switches that partner or channel to live.**
- **Consent before sharing.** A lead without partner-sharing consent (`consent_partner_share_at`) is never pushed to a partner. It goes to Eduwit's B2C CRM instead (B10).
- **Money rows are never deleted,** only reversed by a new line.
- **Do not modify** n8n workflows, Witty's prompts, or the old Zoho integration from this codebase.

## A4. What already exists (audit, then reuse or refactor)

Supabase project `xlseqwgyjuqhktrguhyc` ("EDUWIT LEAD TRACK", ap-south-1) already contains:

| Area | Objects | State on 6 Oct 2026 |
| --- | --- | --- |
| Leads | `student_leads` (140 columns, one row per phone), `student_leads_v`, `touchpoints`, `verifications`, `lead_intake()`, `crm_norm_phone()`, `crm_find_lead()`, `crm_new_lead()`, `crm_duplicate_candidates()`, `crm_merge_leads()` | Live. Witty writes through `lead_intake()` |
| Catalogue | `catalog_universities` (29), `catalog_programs` (715: university, course, specialization, level, mode, `fee_yearly`, `fee_semester`, `fee_total`, eligibility, brochure), `catalog_synonyms`, and the loader functions `catalog_stage_add()`, `catalog_commit()`, `catalog_load()` | Loaded. Witty reads it, so the Programme Repository adds to it only through reviewed "added from partner file" rows (B5.2.3), never by reloading it |
| Partners and sync | `partners`, `partner_mapping_profiles` (status, field and value maps, versioned), `partner_events`, `allocations`, `routing_rules`, `engine_decisions`, `crm_partner_event()`, `crm_partner_verify()` (HMAC), `crm_partner_duplicate()`, `crm_partner_health_check()`, `crm_partner_rotate_secret()`, `crm_sync_claim()`, `crm_sync_result()`, `crm_save_mapping_profile()`, `crm_upsert_partner()` | Built, no partners or allocations yet |
| Routing | `crm_allocate_lead()`, `crm_dest_stats()`, `crm_criteria_match()`, `crm_rules_match()`, `crm_segment_of()`, `crm_reallocate()`, `crm_engine_flow()`, `crm_scorecards()`; settings in `crm_settings.engine` | Built for the **old** design (see below) |
| Money | `earning_rates` (percent, fixed, tiered; GST-inclusive flag; scopes university, programme, partner), `enrollments`, `earnings`, `invoices`, `crm_compute_earning()`, `crm_earning_rate()`, `crm_tier_pct()`, `crm_period_close()`, `crm_verify_enrollment()`, `crm_refund_enrollment()` | Built, empty |
| Platform | `crm_users`, `crm_api_keys`, `crm_alerts`, `crm_notifications`, `crm_saved_views`, `crm_settings`, `crm_activities`, `message_templates` | Built for the combined design. Under the separation rules (A5) these belong to the **B2C CRM**. The B2B CRM creates its own equivalents in schema `b2b` (settings, API keys, alerts, templates, activity log) and copies over any settings it needs, such as the engine settings and stage lists |
| B2C pieces | `calls`, `campaigns`, `campaign_sends`, `journeys`, `journey_runs`, `segments`, `payout_rates`, `payouts`, `payout_runs`, `crm_assign_lead()` and the marketing functions | Belong to the **B2C CRM**, which Vikas designs separately. Do not extend these. Read them only to define the hand-off |

**What changed since those objects were built.** They follow an earlier PRD in which the in-house team competed for every lead like a partner, scored by Thompson sampling. This product changes three rules:

1. **Eduwit's in-house B2C team never competes.** It receives a lead only as a fallback (B7.6).
2. **Routing starts by commission and moves to net commission per lead** as conversion data matures (B7).
3. **The B2B CRM sends the student a WhatsApp message and an email naming the partner** once the partner has the lead (B9).
4. **Routing is steered by a real-time machine-learning model and a Claude optimiser agent** (B7.8), inside the rules layer.

`crm_allocate_lead()` and `crm_partner_duplicate()` therefore need refactoring, not reuse as they stand. Note also the live trigger `crm_auto_assign` on `student_leads`. It assigns a lead to an in-house sales manager as soon as `is_sales_ready` turns true, which contradicts the fallback-only rule. Propose with Vikas how to retire or re-scope it (it belongs to the B2C design) before the B2B engine goes live; do not drop it on your own. Your Phase 0 report must list every existing object with one of three verdicts: **keep**, **refactor** (and how), or **leave to B2C**.

## A5. Eduwit's product ecosystem: separate products, connected seamlessly

Eduwit is building **six separate products**. Each has its own function, codebase, deployment, sign-in and data, and they work together through a shared lead hub and explicit contracts. The B2B CRM is one of them. Build it as a self-contained product that plugs into the others; it never reaches into another product's internals.

| Product | Its job | Owns | How it connects to the B2B CRM |
| --- | --- | --- | --- |
| **Witty** (WhatsApp AI agent, n8n) | Talks to students on WhatsApp, recommends programmes, qualifies leads | `w2_*` tables and functions; conversation, AI-qualification, interest and profile columns of `student_leads` | Writes leads through `lead_intake()` and signals "finished qualifying" (B4). Reads the allocation columns to stop selling once a lead is allocated. The B2B CRM never writes Witty's tables |
| **Website AI agent** (Witty-like programme-mapping and recommendation agent on the website) | Sign-up with OTP, then a chat that maps the student to the right programme | Its own tables and chat sessions; writes chats to `w2_messages` | Same contract as Witty: `lead_intake()` after the phone is verified, plus a qualification signal. Passes the click IDs it captured (`fbclid`, `gclid`) for CAPI |
| **Website** (eduwit.in) | Marketing site, programme pages, forms, ad landing pages | Its content and forms | Forms post to the B2B CRM's Intake API (`POST /v1/leads`) with UTM and click IDs; it hosts the website agent's widget and the Meta and Google tags |
| **Influencer dashboard** | Creators' referral links and codes, and how their referred leads progress | `influencers`, `influencer_auth` and its own views; creator logins | Reads referred-lead progress (stage, enrolled yes or no, programme) through a **read-only, masked view or API** that the B2B CRM publishes (`b2b_referral_outcomes`, keyed by referral code). It never reads `student_leads` or partner data directly. Students' phone and email are never shown to creators |
| **B2C CRM** (Eduwit's in-house sales) | In-house sales team works fallback leads; marketing journeys | Its users, pipeline, tasks, calls, campaigns, journeys and payouts (the `crm_*` platform tables and the B2C tables in A4) | Receives leads only through the hand-off contract (B10). Reports in-house outcomes back through the shared lead hub, so the B2B CRM's Master Lead Table and analytics show them |
| **B2B CRM** (this product) | Allocates every lead; real-time sync with partner CRMs and the B2C CRM; notifications, CAPI, partner commission, analytics, AI optimisation | Its own schema `b2b` (B16); the allocation, partner-sync, sales-effort, application, enrollment and revenue columns of `student_leads` | The hub between all of them |

**Boundary rules.**

1. **Separate codebases and deployments.** Each product is its own repository and deployment, with its own domain or subdomain (for example `b2b.eduwit.in`). Nothing is shared at code level except published contracts: SQL function signatures, API schemas and event payloads.
2. **`student_leads` is the master database for all six products** (confirmed by Vikas). It lives in the shared Supabase project and is the single record of every lead. Every product reads it, and each writes only the columns it owns (A3). No product keeps its own copy of lead records; product tables link to `student_leads.id`.
3. **Each product's own tables live in its own schema.** Witty keeps its `w2_*` tables. The B2B CRM creates all new tables in a Postgres schema named `b2b`. The B2B tables already created in `public` by the earlier combined design (`partners`, `allocations`, `partner_events`, `partner_mapping_profiles`, `routing_rules`, `engine_decisions`, `earning_rates`, `enrollments`, `earnings`, `invoices`) are empty. Propose moving them into `b2b` in Phase 0, while nothing depends on their data. The B2C CRM and the influencer dashboard keep their own.
4. **Separate sign-in per product.** The Supabase project's authentication is shared at identity level, so each product decides who may enter.
   - The B2B CRM admits only its own allowlist (B3), kept in its own table (`b2b.app_users`), not in the B2C CRM's `crm_users`.
   - A login to the influencer dashboard, the B2C CRM or any other product never opens the B2B CRM, and the reverse.
5. **Integration only through contracts.** Events go through `b2b.integration_outbox` and signed webhooks (`lead.allocated`, `lead.accepted`, `lead.status_changed`, `lead.enrolled`, `b2c.lead_handed_off`). Reads go through versioned views and APIs; intake goes through `lead_intake()` or the Intake API. A product never calls another's internal functions or writes another's tables.
6. **Failure isolation.** If any other product is down, the B2B CRM keeps allocating and syncing. If the B2B CRM is down, Witty and the website keep capturing leads (they write through `lead_intake()`), and routing catches up from the pre-routing pool when it returns.

**Influencer dashboard: being redesigned separately.** Its current objects (`influencer_leads_dashboard`, which exposes students' contact details, and `influencer_auth` with its `secret_password` column) are being replaced by Eduwit in that product's own redesign. Do not change or depend on them. The B2B CRM's only obligation is to publish the masked `b2b_referral_outcomes` view and the referral API (B17) for the redesigned dashboard to use.


---

# PART B — Product specification

## B1. The product in one paragraph

Leads arrive from Witty on WhatsApp, the website AI agent, Meta and Google lead ads, and Excel or CSV files. Every lead lands in `student_leads` through one intake function. When a lead is ready to route, the routing engine finds every partner whose programme file (in the Programme Repository) offers the programme the student wants and sends the lead to the one expected to earn Eduwit the most from it:

- **at first,** the partner paying the highest commission;
- **once conversion data matures,** the partner earning Eduwit the highest net commission per lead, predicted for each student by a real-time machine-learning model while a Claude agent continuously tunes the engine (B7.8).

The lead is pushed into that partner's CRM by API. If the partner accepts it, the student gets a WhatsApp message and an email saying an academic counsellor from that partner will call them. If the partner reports the student as an existing lead (a duplicate), the lead moves to the next-best partner. If that partner also reports a duplicate, it goes to Eduwit's own B2C CRM. From then on, every call, note, stage change, application and enrollment the partner records syncs back live into `student_leads` and the CRM's tables. Dashboards show every partner's lead stages, sales effort, SLA compliance and commission, and each user can customise them.

## B2. Glossary

| Term | Meaning |
| --- | --- |
| Partner | A partner edtech that sells university programmes and pays Eduwit a commission per enrollment. Each has its own CRM, connected by API |
| B2C CRM | Eduwit's own in-house sales CRM, designed separately. It is the fallback destination |
| Programme | One row of `catalog_programs`: university × course × specialization × level × mode |
| Segment | The comparison unit for routing and analytics: university × course × level × mode (`crm_segment_of()`). Rolls up to course × level × mode, then to course, when data is thin |
| Interest | What the student wants, possibly partial: course and specialization always; university and mode when known |
| Allocation | One hand-off of one lead to one destination (a partner or the B2C CRM), with its own status history. A lead can have several over time (after duplicates), but at most one open |
| Push | Creating the lead in the partner's CRM through its API |
| Accepted | The partner's CRM created the lead and returned a record ID, and the hold window passed with no duplicate claim or rejection (B7.5) |
| Duplicate | The partner shows the student already existed in its own CRM, created before Eduwit's push, matched by phone or email |
| Hold window | Minutes after a successful push during which a duplicate or rejection still moves the lead to the next partner; the student is notified only after it (B7.5) |
| CPE | Commission per enrollment: the rupees a partner pays Eduwit for one enrollment in a programme, **net of GST** |
| NCPL | Net commission per lead: expected rupees Eduwit earns per lead sent to a partner = P(enroll) × CPE × (1 − refund rate) |
| Commission-first mode | Routing by CPE, used while a segment's conversion data is immature |
| Performance mode | Routing by NCPL, used once enough matured leads exist |

## B3. Access: one Admin, no other users

The B2B CRM is an automation and control system: it allocates incoming leads and keeps them in real-time sync with partner CRMs and Eduwit's B2C CRM. **It has exactly one user, the Admin: `connect@eduwit.in` (Vikas).** There are no other staff accounts, and partners never log in (they work in their own CRMs, which sync by API).

The Admin does everything: partners, programme files, rates, routing settings and rules, mappings, re-routes, duplicate disputes, enrollment verification, invoices, dashboards, exports, AI approvals and live switches. Every other "actor" is the system itself (routing engine, workers, AI optimiser), and each system action is logged with its source.

**Consequences for the build:**

- **No user management.** No user-management screens, no role builder, no per-role masking and no approval chains between people. Where this spec says a change needs approval (commission from a partner file, AI recommendations, live switches, bulk deletes), the Admin confirms it in a dialog that shows the impact first.
- **Keep the data model ready for more users.** Every action still records an actor, so a user could be added later without redesign. But build no UI for it now.

**Sign-in.** Supabase Auth, with two ways to sign in, both for `connect@eduwit.in` only:

1. **Continue with Google:** Google OAuth.
2. **Email and password:** with "forgot password" by email link. The password needs at least 12 characters and is checked against known-breached passwords. Sign-in locks for 15 minutes after 5 failed attempts.

**Rules for both ways.**

- **Use the existing identity.** `connect@eduwit.in` already exists in `auth.users`. Reuse that identity; do not create another. Both sign-in methods must resolve to it (link the Google identity and the email-password identity). The B2B CRM records it as its Admin in its own `b2b.app_users` table (A5). It does not rely on the B2C CRM's `crm_users`.
- **Allowlist of one.** The B2B CRM admits only `connect@eduwit.in`. The sign-in page has no "create account" option. Any other account that authenticates (the Supabase project's identities are shared with Eduwit's other products, A5) is signed out at once with "This app is restricted", and the attempt is logged. Check the allowlist on the server for every request, not only on the sign-in page.
- **Do not touch other accounts.** `auth.users` (and the B2C CRM's `crm_users`) also hold three inactive Gmail accounts created on 9–12 July 2026, before this CRM existed (most likely sign-ups from Eduwit's earlier influencer dashboard, which uses the same Supabase project). They have no access to the B2B CRM under the allowlist. Do not delete them from this codebase; list them in the Phase 0 report so Vikas can decide.
- **Two-step verification.**
  - Email and password sign-in requires a TOTP code from an authenticator app.
  - Google sign-in relies on the Google account's 2-step verification. Requiring TOTP on top is a setting, on by default.
- **Sessions.** They expire after 12 hours idle. The Admin can see active sessions and sign out any device. Every sign-in (method, IP, device, success or failure) is logged.

**Integrations use keys, not logins.** Partner CRMs, Meta, Google, the B2C CRM and the providers connect through API keys and signed webhooks (B17), never through user accounts.


**Live `student_leads` column names to use** (the table has not been renamed):

- **Identity and contact:** `whatsapp_number` (phone), `student_name`, `email_id`, `city`, `state`, `preferred_language`.
- **Interest:** `interested_course`, `interested_specialization`, `interested_university`, `university_preference`, `study_mode_preference`, `program_level`, `programme_segment`.
- **Profile:** `highest_qualification`, `academic_score_pct`, `work_experience_years_num`, `current_job_role`, `annual_budget_inr`, `enrollment_timeline`, `primary_motivation`.
- **Classification:** `lead_status` (Witty's HOT, WARM or COLD), `temperature`.
- **Source and attribution:** `lead_source`, `channel`, `campaign`, `utm_*`, `click_ids`.
- **Consent:** `consent_partner_share_at`, `consent_marketing_at`, `is_opted_out`.
- **Pipeline:** `stage`, `sub_stage`, `is_sales_ready`.
- **Allocation and partner sync:** `destination_type`, `partner_id`, `allocation_id`, `allocated_at`, `allocation_reason`, `partner_record_id`, `partner_stage_raw`, `partner_sub_stage_raw`, `partner_synced_at`, `duplicate_claim_count`.
- **Sales effort:** `first_contacted_at`, `last_contacted_at`, `contact_attempts`, `next_task_due_at`.
- **Application and enrollment:** `application_id`, `application_status`, `applied_at`, `fee_amount_inr`, `fee_paid_inr`, `enrollment_status`, `enrolled_program`, `enrolled_university`, `enrollment_date`, `enrollment_verified_at`.
- **Revenue:** `expected_net_revenue_inr`, `realised_net_revenue_inr`.
- **Outcome and housekeeping:** `lost_reason`, `lost_at`, `is_test`, `custom_fields`.

## B4. Lead intake

Every source writes through **`lead_intake()`**, directly or via the Intake API, so de-duplication, attribution and consent work the same everywhere. A trigger already catches direct inserts. Keep the existing de-duplication rules:

- one open lead per normalised phone (E.164);
- merge into an open lead;
- reopen a lead closed within 90 days;
- open a new cycle on the same row after that;
- flag (never auto-merge) same email with a different phone;
- close blocklisted numbers as junk at once; flag test numbers `is_test` (never junk them, so the test harness keeps working).

| Source | How it arrives | Becomes ready to route when |
| --- | --- | --- |
| **Witty (WhatsApp)** | Already calls `lead_intake()` on every gated turn. Witty sets name, email, course, specialization, the final programme choice (`interested_university` once the student confirms one), qualification, score, work, budget, mode and goal, plus `lead_status` HOT, WARM or COLD | Witty has **finished qualifying** it: name, email and a course or field known, `lead_status` HOT, WARM or COLD, **and** Witty's hand-off signal: Witty escalated the chat (HOT hand-off), or the student confirmed a final programme, or the chat has been idle for 30 minutes (configurable). This stops a lead being routed in the middle of Witty's discovery questions. University is **not** required. In Phase 0, agree with Vikas whether Witty should set an explicit flag (e.g. `is_sales_ready`) instead |
| **Website AI agent** | Same as Witty. A lead exists only after the phone is OTP-verified (`verifications`) | Same rule as Witty |
| **Meta Lead Ads** | Meta `leadgen` webhook → Intake API → fetch the lead from the Graph API → map form questions by a per-form mapping → `lead_intake()`. Store `leadgen_id`, form, ad, ad set and campaign IDs in `click_ids` and attribution | At intake (the form names the programme) |
| **Google Ads lead forms** | Google lead-form webhook (`google_key` verified) → Intake API. Store `gclid` and the lead ID | At intake |
| **Excel / CSV import** | Import wizard (B4.1) | Chosen per import: route now, hold for review, or send to the B2C CRM |
| **Manual entry** | "New lead" form (Admin) | When the creator routes it |

**Ready-to-route rule.** A lead routes when all of these hold:

1. It is not a test lead.
2. It has a verified or source-trusted phone.
3. Its interest has at least a course (or a field that maps to courses in the catalogue).
4. It has no open allocation.

A database trigger enqueues routing within 1 second of the lead becoming ready. Leads that aren't ready wait in a **pre-routing pool**, visible in the UI with what is missing.

**Partial interest.** A student who wants "MBA in AI/ML, any university" is routable. The engine considers every partner offering any programme matching course, specialization, level and mode (B7.1). University and mode narrow the match when known.

### B4.1 Excel and CSV import

A wizard with 5 steps:

1. **Upload.** Accepts .xlsx, .xls or .csv, up to 50,000 rows.
2. **Map columns** to lead fields, with saved mapping templates per file source and name-similarity suggestions.
3. **Validate.** Normalises phones, flags invalid rows, maps programme text to catalogue programmes with fuzzy matching and a confirm step for low-confidence matches.
4. **Preview de-duplication:** new, merge, reopen, blocked or test, with counts and a downloadable list.
5. **Confirm.** Requires the source label, the campaign, the **consent basis** (where and when the students agreed, with the consent text) and the routing choice.

Each import is a job with per-row results. An import can be rolled back within 24 hours for rows not yet pushed to a partner.

## B5. Partners, programmes and commission

### B5.1 Partner record

Extend `partners` (keep its existing columns) with:

| Field | Purpose |
| --- | --- |
| `display_name`, `logo_url`, `brand_color` | Student-facing brand used in notifications and the UI |
| `adapter_type` | `leadsquared`, `salesforce`, `zoho`, `meritto` (NoPaperForms), `hubspot`, `generic_rest`, `webhook`. Widen the existing check constraint. Drop `portal`, since partners do not log in |
| `dedupe_mode` | `sync` (the partner's create call refuses duplicates at once), `async` (duplicates arrive later by webhook or poll), or `none` |
| `hold_minutes` | Hold window after a successful push during which a duplicate or rejection still re-routes the lead (0 for `sync`, default 30 for `async`). The student is notified only after it (B7.5) |
| `duplicate_window_hours` | How long after the push a duplicate claim is still logged as a commission dispute (default 24) |
| `notify_enabled` | Student notification on or off for this partner |
| `test_endpoint` | The partner's sandbox or test pipeline, used for test leads |
| `working_hours` (JSON per weekday, IST), `holidays` | SLA clocks run only in working hours |
| `sla` (exists) | First attempt, status-update cadence, enrollment-proof deadline (B8.5) |
| `daily_cap`, `monthly_cap`, `contract_min_monthly` (exist) | Capacity and contractual minimums |
| `lead_criteria` (exists) | Lead rules agreed with the partner: geography, qualification, source exclusions |
| `live_mode` | Off until Vikas switches the partner live |

### B5.2 Programme Repository: one file per partner

Each partner sends Eduwit its own list of the programmes it offers, as an **Excel file or a Google Sheet, one file per partner**. The partners' files differ in layout and wording. The CRM has a dedicated **Programme Repository** tab where Eduwit keeps every partner's file current.

**The routing engine uses only the published repository to decide which partners can receive a lead** (B7.1 step 2). A partner with no published file, or a programme not in its file, never receives leads for it.

#### B5.2.1 Sources per partner

| Source type | How it works |
| --- | --- |
| **Excel or CSV upload** | Upload a new version of the partner's file (.xlsx, .xls, .csv); choose the sheet. Every upload is kept as a version with the original file in Storage |
| **Google Sheet link** | Connect the partner's sheet once (Google service account given view access, or OAuth). The CRM checks it for changes on a schedule (default every 6 hours, configurable) and on demand ("Sync now"). Each detected change creates a **draft version**; nothing goes live without publishing (B5.2.3), unless the Admin turns on auto-publish for that partner |

Each partner has exactly one active source at a time. Switching from Excel to a Google Sheet (or back) is logged.

#### B5.2.2 Column mapping per partner file

Each partner's file has its own column template, saved once and reused for every new version. It is mapped like the partner's CRM fields (B8.3), with suggestions and a preview.

| Repository field | Required | Notes |
| --- | --- | --- |
| University | Yes | Matched to `catalog_universities` (names, short names, synonyms) |
| Course / degree | Yes | MBA, BBA, BCA and so on, matched to the catalogue course key |
| Specialization | If the partner sells by specialization | "General" when none |
| Level | Inferred from course if missing | UG, PG, diploma, certificate |
| Mode | Yes | Online, ODL or regular |
| Partner's programme name and code | Recommended | Stored as `partner_course_code` and used in the push |
| Fees (total, yearly, semester, registration, exam) | Optional | The partner's quoted fees |
| Eligibility (minimum qualification, minimum %) | Optional | Overrides catalogue eligibility for this partner when stricter |
| Commission (%, fixed ₹ or tier reference) | Optional | Becomes a **proposed** partner-programme rate (B5.3); takes effect only when the Admin confirms it |
| Valid from / valid to, intake or session | Optional | For seasonal programmes |
| Active flag, notes | Optional | |

#### B5.2.3 Validate, match, preview, publish

1. **Normalise and validate.** Trim, fix case, convert currencies ("1.5 L" → 150000), check modes and levels, and flag rows with missing required fields.
2. **Match each row to the Eduwit catalogue** (`catalog_programs`), in this order:
   1. the saved row mapping from the partner's previous version;
   2. exact match on university + course + specialization + level + mode;
   3. synonym and fuzzy match;
   4. Claude (Haiku) suggestion with a confidence score.

   Each match is labelled **auto-matched**, **needs review** or **no match**. Low-confidence and no-match rows wait for a person.
3. **Programmes not in Eduwit's catalogue.** A partner may sell a programme Eduwit's catalogue does not have yet. The reviewer can add it to the catalogue as a new programme (marked "added from partner file", with the partner's fees and eligibility) or ignore the row with a reason. Leads can only be routed to programmes that exist in the catalogue, so they are never stranded.
4. **Compare with the live version.** The preview shows:
   - programmes **added**, **removed** and **changed** (fees, eligibility, commission, mode, dates);
   - unmatched and ignored rows;
   - **the routing impact.** Which segments gain or lose this partner, how many leads per week (from the last 30 days) that affects, and where those leads would go instead. Removing the only partner for a programme is flagged in red, because those leads would fall back to B2C.
5. **Publish.** One click creates the new active version. In the same transaction:
   - `partner_programmes` is updated: added rows inserted; removed rows ended with `valid_to`, never deleted; changed rows versioned;
   - proposed commission changes are listed for the Admin to confirm in the same publish dialog;
   - the routing engine's candidate cache is refreshed.

   Leads already allocated keep their partner. A removal affects only new routing.
6. **Roll back.** Any earlier version can be restored with the same preview.

**Audit.** Only the Admin uploads, reviews and publishes. Every version records when it was uploaded and published, by the Admin or by an automatic Google Sheet sync, and the source file or sheet revision.

#### B5.2.4 Data model

| Table | One row per |
| --- | --- |
| `partner_programme_sources` | Partner: source type (upload or Google Sheet), sheet ID and tab, column template, sync schedule, auto-publish flag, last checked and last changed time |
| `partner_programme_versions` | Uploaded or synced version: file path or sheet revision, status (draft, published, superseded, rolled back), row counts, uploaded by, published by, timestamps |
| `partner_programme_rows` | Row in a version: raw values, normalised values, matched `programme_id`, match method and confidence, review status, ignore reason |
| `partner_programmes` | **Live** partner × programme offer used by routing: `partner_id`, `programme_id`, `partner_course_code`, partner fees, partner eligibility, `active`, `valid_from`, `valid_to`, `source_version_id`. Unique on (`partner_id`, `programme_id`, `valid_from`) |

**Partner fees and CPE.** When a partner's file gives fees for a programme, that partner's CPE uses the partner's fee (B5.3), because commission percentages apply to what the partner charges. Otherwise the catalogue fee is used. Any gap of more than 10% between the partner's fee and the catalogue fee is highlighted for review.

#### B5.2.5 The Programme Repository tab (UI)

- **Partner list:** each partner with its source (Excel or Google Sheet), active version and date, number of live programmes, rows awaiting review, last sync status, and a "stale" warning when a Google Sheet has not been checked or an upload is older than 90 days (configurable).
- **Partner repository page:**
  - the live programme list (filter by university, course, specialization, mode; search);
  - version history with a diff between any two versions;
  - the upload or sync panel;
  - the review queue (needs review and no match);
  - the column template editor.
- **Upload or sync wizard:**
  1. choose the file or sync the sheet;
  2. map columns (pre-filled from the template);
  3. review matches;
  4. preview changes and routing impact;
  5. publish.
- **Coverage matrix** (across partners): programmes × partners, with each partner's CPE in the cell. It shows where partners compete (more than one offer), where only one partner covers a programme, and which catalogue programmes no partner offers (those leads go to B2C).
- **Alerts:**
  - a Google Sheet sync failing;
  - a published change that removes the last partner for a programme;
  - a partner file not updated within its refresh period.

### B5.3 Commission rates

Use `earning_rates` (versioned by date, GST-inclusive flag) and add scope `partner_programme` (partner + programme) beside the existing `university`, `programme` and `partner` scopes. The most specific rate in force wins: partner + programme, then partner, then programme, then university.

**CPE (commission per enrollment), net of GST**, for partner *p*, programme *g*, on date *t*:

- **Percent:** `value% × fee_base(g)`, using the partner's own fee for *g* from its Programme Repository file when given (B5.2.4), otherwise the catalogue fee. `fee_base` is the first-year fee (`fee_yearly`, or `fee_total ÷ years` when only the total is known), the total fee (`fee_total`), or the amount paid. Set per rate.
- **Fixed:** `value` (e.g. ₹35,000 per enrollment).
- **Tiered:** the tier percentage at the partner's projected lead-to-enrollment conversion for the current settlement period. Example: 22.42% below 7%, 20.42% from 7% to under 9%, 18.42% at 9% and above, so a better-converting partner can pay a lower percentage. Provisional until period close (`crm_tier_pct()`).
- **GST:** if `gst_inclusive`, then `CPE_net = CPE ÷ (1 + gst_rate)`, with `gst_rate` from `crm_settings.money` (0.18).

**When the student hasn't chosen a university,** a partner's CPE for the lead aggregates over the matching programmes that partner sells. The default aggregate is the **median**; the Admin can choose mean or maximum. Weight each programme by Eduwit's historical enrollment mix for that course when at least 30 enrollments exist.

**Rate controls.** Only the Admin edits rates. Every change is versioned with when and why, and never alters a booked commission unless the Admin re-books it explicitly.

## B6. Leads: lifecycle and the Master Lead Table

### B6.0 Lead lifecycle (Eduwit standard stages)

Use the stages in `crm_settings.stages`:

| Group | Stages |
| --- | --- |
| Before routing | `new`, `qualifying` |
| Routing | `allocated`, `sent_to_partner` |
| Partner pipeline | `contacted`, `counselled`, `applied`, `enrolled` |
| Money | `verified`, `commission_booked`, `paid` |
| Exits | `duplicate_at_partner`, `lost` |

`assigned` and `nurture` belong to the B2C CRM.

- Sub-stages and lost reasons come from settings.
- Stage rank prevents a stray partner update from moving a lead backwards, unless the mapping marks the pair as a genuine reopen.
- Each lead shows Eduwit's stage with the partner's raw stage and sub-stage beneath it.

### B6.1 Master Lead Table

One table shows **every lead, from every source, wherever it went**: partners, Eduwit's B2C CRM, the pre-routing pool, junk. From there the Admin can edit, delete, bulk delete and download leads. It is the home of the **Leads** tab and the system of record people look at, so it must be complete, fast and trustworthy.

#### B6.1.1 What every row shows

One row per lead (per enquiry cycle when "show all cycles" is on), built from a read model, `b2b_master_leads_v`, that joins:

- `student_leads`;
- the current and previous allocations;
- the partner;
- the partner-sync summary;
- `partner_activities` roll-ups;
- enrollments, earnings, invoices and receipts.

Every column below can be shown, hidden, reordered, pinned, sorted and filtered.

| Column group | Columns |
| --- | --- |
| Identity | Lead ID, `EDW-` reference, student name, phone, email, city, state, language, enquirer (self or parent) |
| Lead generation | **Lead generation date and time** (`created_at`), source (Witty WhatsApp, website agent, Meta, Google, Excel import, manual), sub-source, campaign, ad, form, UTM fields, influencer or referral code, import file, enquiry cycle number, first and last touch |
| Interest | **Programme name and university** (the routed or enrolled programme when known, otherwise the student's interest), course, specialization, level, mode, university preference, final choice confirmed (yes/no) |
| Profile and qualification | Qualification, score %, work experience, job role, budget, timeline, goal, Witty's `lead_status` (HOT, WARM, COLD), temperature, eligibility |
| Consent | Sales, partner-sharing and marketing consent with timestamps; opted out |
| Routing | **Partner given the lead** (with logo); destination (partner or Eduwit B2C); routing mode (commission-first, performance, exploration, rule, manual, fallback); allocated at; accepted at; attempt number; partners tried before with outcomes (duplicate, rejected, failed); fallback reason; CPE and NCPL at decision time; "Why this partner" link |
| Partner status | **Eduwit stage and sub-stage**, **partner's own status and sub-status** (raw), last synced at, partner record ID with a deep link to the partner CRM |
| Sales effort | Partner counsellor, first contact at, last contact at, call attempts, connected (yes/no), last call outcome, next follow-up, activities in the last 7 days, days since last update, SLA status (on time, at risk, breached) |
| Application and enrollment | Application ID and status, applied at, documents status, enrolled programme and university, enrollment date, fee amount, fee paid, enrollment status (reported, verified, refunded) |
| **Commission** (enrolled leads) | Rate applied (type and value), CPE, commission gross, GST, net, status (expected, realised, invoiced, received, reversed), invoice number and date, amount received, TDS, received date, clawback or refund |
| Notifications | WhatsApp and email notification status (sent, delivered, read, failed) |
| Housekeeping | Test flag, duplicate suspect, last updated at and by, custom fields (each partner-specific field available as its own column) |

**Default views shipped:** All leads, Today, Pre-routing pool, With partners, Eduwit B2C, Duplicates and rejections, SLA breaches, Enrolled, Commission due, Junk and deleted (Admin only).

#### B6.1.2 Working with the table

- **Search** across name, phone, email, `EDW-` reference and partner record ID; results in under 1 second across 1 million leads.
- **Filters:** a chip-style builder on any column, with AND/OR groups, relative dates ("last 7 days") and "is empty".
- **Group by** any column, with counts and sums (e.g. commission by partner).
- **Saved views,** named and pinned to the sidebar.
- **Paging and scrolling:** server-side pagination with keyset paging and a virtualised grid, so 100,000 rows scroll smoothly.
- **Layout:** frozen first columns; density toggle.
- **Lead drawer:** clicking a row opens it (B14.3), with the full timeline.
- **Live updates:** rows refresh in real time (Supabase Realtime) when a partner's status changes. A subtle highlight shows changed cells.

#### B6.1.3 Edit

- **Inline edit** of editable cells and a full **edit form** in the lead drawer. Validation applies: phone format and uniqueness, email format, catalogue picklists.
- **What is editable:** lead data. Money fields change only through the money workflows (B12), never by typing over a commission. System-owned fields (allocation, partner status, timestamps, commission amounts) are read-only in the grid.
- **Column ownership (A3).** Editing a Witty-owned field (for example a name or course Witty captured) is allowed for the Admin. The change is recorded as a human correction with the old value, and the lead is flagged so Witty does not overwrite it.
- **Already with a partner.** If the lead has been pushed, a changed contact or interest field asks "Also update in the partner's CRM?". When confirmed, it is sent through the adapter for fields mapped outbound (B8.3).
- **Bulk edit** for selected rows: set campaign, source, tag, test flag, or re-route. Re-routing goes through the engine's rules (B7.7), never a direct partner change.
- **Audit.** Every edit writes field history (who, when, old, new) and appears on the lead's timeline.

#### B6.1.4 Delete and bulk delete

Deleting must never break Witty, the partner sync or the money records. So "delete" in the UI is a **soft delete**, and the table already blocks hard deletes of more than 5 rows at once (`student_leads_bulk_delete_guard`).

- **Delete:**
  - sets `deleted_at` and a reason (junk, test, duplicate entry, spam, student request, other);
  - removes the lead from every view, queue, routing, analytics and notifications;
  - keeps it in a **Recycle Bin** for 30 days (configurable), from which the Admin can restore it.
- **Bulk delete:**
  - select rows (or "all rows matching this filter");
  - confirm with a typed confirmation showing the count;
  - give a reason.

  It runs as a background job with a progress bar and an undo for 30 days. The Admin only can bulk delete more than 500 rows.
- **Leads with a partner or money.**
  - A lead already accepted by a partner can be deleted only with the reason "junk/spam" or "student request". The partner is told through the adapter (or by email), and any open SLA timers stop.
  - A lead with an enrollment or commission lines cannot be deleted. It can only be closed. Money rows stay.
- **Student erasure request** (DPDP). A separate, Admin-only action, not delete:
  - it **anonymises** the student's personal fields in `student_leads`;
  - it sends deletion requests to every partner that received the lead;
  - it keeps money and analytics rows by ID only;
  - it is logged with the request reference.
- **Hard delete** happens only for test leads and only after the Recycle Bin period, through a privileged job that sets `crm.allow_bulk_delete` inside its transaction. It never runs from the UI.
- **Audit.** Every delete, restore and erasure is logged with who, when, why and the row count.

#### B6.1.5 Download (export)

- **Download** the current view (its filters, columns and sort) or only the selected rows as **Excel (.xlsx) or CSV**. Commission and sales columns are included when they are in the view.
- **Masking and permissions.**
  - The Admin exports with full contact details. An option to mask phone and email in the file is available, for sharing exports outside Eduwit.
- **Large exports.** Over 10,000 rows, the export runs in the background and the file is ready in the Downloads panel (and emailed as a link) within a few minutes. Links expire after 24 hours.
- **Audit and limits.** Every export is logged with who, when, filter, column list and row count. Exports include an "Exported by … on …" footer row in Excel.
- **Scheduled export:** any saved view can be emailed daily or weekly as a file (B13.3).

#### B6.1.6 Performance and correctness

- **Read model.** `b2b_master_leads_v` is a view over indexed tables, or a summary table kept current by the CRM's own triggers and events, whichever meets the speed target. It must not add load to Witty's writes (A3).
- **Totals and speed.** Totals show exact counts up to 100,000 rows and estimates above that. The first page loads in under 1.5 seconds.
- **Every number traces back.** Every commission value comes from `earnings` and enrollments; nothing in the grid is computed separately from the money ledger.

## B7. Routing engine

The engine works in three layers, each with one job:

1. **Rules layer (SQL, deterministic).** Consent, eligibility, duplicates, capacity, routing rules and every guardrail. Nothing above it can override these.
2. **Real-time scoring layer (machine learning).** For every lead, a model predicts each candidate partner's chance of enrolling *this* student, and the engine picks the partner with the highest expected net commission for this lead (B7.2, B7.8.1). It runs in milliseconds; no language model sits in the per-lead path.
3. **AI optimiser layer (Claude).** Claude continuously studies outcomes, partner effort and money, and tunes the engine's settings, finds segments where the flow should shift, explains anomalies and proposes routing rules, all inside hard bounds and with every change logged (B7.8.2).

The objective is always the same: **maximise Eduwit's net commission per lead**, subject to the rules layer. Every decision is stored in `engine_decisions` with every candidate, every number, the model version, the decision's selection probability, and the winner. The lead screen shows it as "Why this partner".

### B7.1 Order of steps for each lead

1. **Consent gate.** If there is no `consent_partner_share_at`, send to the B2C CRM (reason `no_partner_consent`).
2. **Candidates.** Find active partners with `live_mode` on (or test mode for test leads) whose **published Programme Repository** (`partner_programmes`, B5.2, valid today) includes a programme matching the lead's interest:
   - course and specialization (with catalogue synonyms);
   - level, mode and university when known.

   If there are none, send to the B2C CRM (reason `no_partner_offers_programme`).
3. **Exclusions.** Drop partners that already reported this student as a duplicate, partners paused automatically or manually, and partners outside their `lead_criteria`.
4. **Routing rules.** Apply Admin rules in priority order (`routing_rules`), for example "Meta leads for NMIMS MBA always to Partner X" or "Partner Y only gets leads from Delhi NCR". A rule may fix a partner, narrow candidates or exclude some. A rule can never name Eduwit's B2C CRM as a destination: B2C receives leads only through the fallback cases in B7.6.
5. **Capacity.** Skip partners at their daily or monthly cap. Serve contractual minimums first while they are behind schedule.
6. **Score.** Score every remaining candidate (B7.2, B7.8.1). In commission-first mode, the choice is between the highest CPE and the exploration lane (B7.3). In performance mode, it is the sampled best expected net commission for this lead.
7. **Commit.** In one transaction: write the allocation (`reference` = `EDW-<allocation id>`, `mode`, `attempt_no`, `cpe_net_inr`, `ncpl_inr`, `engine_decision_id`), update the lead's allocation columns, set stage `allocated`, and enqueue the push.

The decision must take under 1 second from the lead becoming ready.

### B7.2 Scoring: commission first, then net commission per lead

The engine compares every candidate in the same unit, **expected rupees per lead**:

```
NCPL(p, s) = P̂(enroll | p, s) × CPE_net(p, lead) × (1 − refund_rate(p, s))
```

| Factor | How it is estimated |
| --- | --- |
| P̂(enroll) | Beta-binomial estimate of partner *p*'s lead-to-enrollment rate in segment *s*:<br>• **Data:** matured leads only (allocated at least `maturity_days` ago, default 60), weighted by recency (`half_life_days`, default 30).<br>• **Leading indicators:** blended in from younger leads (contacted, counselled and applied rates × historical stage-to-enrollment rates), so a change in a partner's effort shows within days.<br>• **Prior:** the segment's average conversion across all partners, with a strength of `prior_weight` leads (default 20). With no segment data at all, the prior is `default_p_enroll` (0.05).<br>• **Thin data:** if the partner has fewer than 30 leads in the segment, use the roll-up segment (course × level × mode, then course). |
| CPE_net | B5.3 |
| refund_rate | Share of the partner's verified enrollments refunded or cancelled within the refund window, shrunk toward the global average. 0 until data exists |

**Commission-first mode (cold start).** While a segment is immature, the engine ranks candidates by **CPE_net only**: the partner paying the highest commission wins, exactly as Eduwit's rule requires. Leading indicators, roll-up segments and the ML model are ignored in this mode, so early noise cannot override the commission rule. The only exceptions are the exploration lane (B7.3) and contractual minimums the Admin has entered.

**Performance mode.** A segment switches to performance mode once at least 2 candidates each have `min_matured_leads` (default 30) matured leads in it. From then on, the engine ranks by NCPL using P̂, the per-lead model (B7.8.1) when it is live, and leading indicators. The partner with the highest net commission per lead for *this* student wins.

The current mode per segment is shown in the UI, and the Admin can pin a segment to either mode.

**Optional factors,** off by default and Admin-configurable:

- a **speed** multiplier (0.85–1.15) from time to first contact and time to enrollment against the segment median;
- a **reliability** multiplier (0.7–1.0) from SLA breaches and sync errors in the last 7 days.

Each is shown separately in the explanation when on.

**Ties.** Higher CPE, then better SLA compliance, then fewer leads this week (round robin).

### B7.3 Exploration lane

A lower-commission partner never gets leads under a pure highest-commission rule, so its conversion could never be learned. The engine therefore reserves an **exploration share** of each segment's leads, default 20%, configurable from 0 (strict highest commission) to 50%. While any candidate in the segment has fewer than `min_learning_leads` (default 30) leads:

1. A seeded random draw, stored in `engine_decisions.seed` so it can be reproduced, sends the lead to the exploration lane with the configured probability.
2. In the lane, the lead goes to the under-sampled candidate with the highest CPE.

Exploration stops for a segment once every candidate has reached `min_learning_leads`. Exploration allocations carry `mode = 'exploration'` and are reported separately. In performance mode, exploration comes from sampling (B7.8.1) instead of this lane.

### B7.4 Guardrails and protections

- **Share cap (optional, off by default):** when the Admin sets `share_cap` for a segment, no partner gets more than that share of its leads in a rolling week while another eligible candidate exists. It is off by default because it would override the highest-commission rule; the UI shows the commission cost of any cap that is on.
- **Auto-pause:**
  - 5 consecutive first-contact SLA breaches;
  - sync failing for 30 minutes;
  - a duplicate rate above 25% over the last 20 leads.

  Each pauses the partner and alerts the Admin on WhatsApp and email.
- **Drop alert:** P̂ or NCPL falling by more than a third against its 30-day value.
- **Kill switch:** per segment or globally. Falls back to a fixed split between partners set by the Admin (B2C cannot be part of the split), and turns off the ML model and the AI optimiser's automatic changes.
- **Versioned settings:** every engine setting change is versioned with who, when and why, so results before and after can be compared.

### B7.5 Allocation state machine, duplicates and rejections

Every allocation moves through one state machine, enforced by the database (a check constraint plus a transition function). The UI, workers and partner events can only call the transition function.

```
queued ─► pushing ─► pushed ─► accepted ─► closed
             │          │          └─► recalled (manual re-route, B7.7)
             │          ├─► duplicate ─► (engine re-runs: next partner, or B2C)
             │          └─► rejected  ─► (engine re-runs: next partner, or B2C)
             └─► failed (technical, after retries) ─► (engine re-runs)
handed_off  (allocation to Eduwit's B2C CRM, B10)
```

| State | Meaning |
| --- | --- |
| `queued` | Decision committed; push job enqueued |
| `pushing` | Adapter call in progress (with retries) |
| `pushed` | The partner's CRM created the lead and returned a record ID; the **hold window** is running |
| `accepted` | The hold window passed with no duplicate or rejection. The lead is the partner's |
| `duplicate` | The partner showed the student was already its own lead, during the push or within the hold window |
| `rejected` | The partner refused the lead for a reason other than a duplicate (for example "outside our criteria"). Partners agree not to do this, so it also raises a contract alert |
| `failed` | A technical failure persisted after all retries |
| `recalled` | Taken back by a manual re-route |
| `handed_off` | Sent to Eduwit's B2C CRM |
| `closed` | The lead's outcome is final (enrolled and verified, or lost) |

**The hold window decides when the lead is final.** `hold_minutes` is set per partner:

- **0 for `sync` partners,** whose CRM refuses duplicates in the create call itself.
- **Default 30 for `async` partners.** The partner agreement must commit them to reporting duplicates within this window.

Only after the window does the allocation become `accepted` and the student get the notification (B9). So the student is told about a partner only once that partner's claim to the lead is settled.

| Event | What the system does |
| --- | --- |
| Create succeeds | `pushed`; lead stage `sent_to_partner`. When `hold_minutes` passes with no claim: `accepted`, notification sent |
| **Duplicate during push or hold window** (with the partner's existing record ID and created date) | `duplicate`; `duplicate_claim_count` + 1. No notification is sent for this partner. The engine re-runs at once **excluding that partner**, and the lead goes to the next-best eligible partner |
| **Second duplicate,** or a first duplicate with no other eligible partner | Lead goes to the **B2C CRM** (B10), reason `duplicate_cascade` |
| **Rejected** (non-duplicate) during push or hold window | `rejected` with the reason; contract alert to the Admin; the engine re-runs excluding that partner. Counts as an attempt |
| **Technical failure** (4xx other than duplicate or rejection, 5xx, timeout) | Retry with backoff: 10 s, 1 min, 5 min, 15 min, 1 h. Alert on the first failure. After the last retry: `failed`, and the engine re-routes excluding that partner. A mapping error also enters the mapping queue. Does **not** count as a duplicate or rejection attempt |
| **Duplicate claim after acceptance** (within `duplicate_window_hours`, default 24) | **No cascade.** The student has already been told who will call, and the partner has the lead either way. The claim is logged as a *commission dispute* with its proof for the Admin, who can uphold it (no commission on this lead, excluded from conversion stats) or reject it. The lead stays with the partner |
| Duplicate claim after `duplicate_window_hours` | Rejected automatically and logged |
| **Returning student** (new enquiry cycle, B4) whose previous cycle went to a partner | If that partner claims a duplicate and the existing record is Eduwit's own earlier push (matched by the `EDW-` reference or the stored `partner_record_id`), it is **not** a duplicate: the allocation is accepted, and the partner is told it is a returning Eduwit lead. If the previous cycle closed less than 90 days ago, the engine prefers the same partner (configurable) |

**Attempt limits.** At most **2 partner attempts** per enquiry cycle that end in `duplicate` or `rejected` before the B2C fallback (configurable). Technical failures do not count toward that limit. Separately, at most **3 partners in total** are tried per cycle, so a run of technical failures still reaches B2C.

**Duplicate audit.**

- A duplicate earns nothing and is left out of the partner's conversion and speed figures.
- It counts in the partner's duplicate rate.
- Every claim stores its proof (the partner's record ID and created date).
- A random 5% are flagged for spot checks.
- A duplicate rate above 15% in a week raises an alert.

### B7.6 When a lead goes to Eduwit's B2C CRM

Only in these cases. Each is recorded as an allocation with `destination_type = 'in_house'`, `mode = 'fallback'`, status `handed_off` and a reason code:

1. `duplicate_cascade`: the attempt limit was reached through duplicates or rejections, or no other eligible partner remains after one.
2. `no_partner_offers_programme`: no partner sells the programme the student wants.
3. `no_partner_consent`: the lead has no partner-sharing consent.
4. `no_capacity`: every eligible partner is at capacity, paused or excluded.
5. `partners_unreachable`: the 3-partner total was reached through technical failures, or no partner is left to try.
6. `import_choice`: an Excel or CSV import chose "send to B2C" (B4.1).
7. `manual`: a manual re-route by the Admin, with a reason (B7.7).

### B7.7 Manual re-route

The Admin can re-route a lead with a reason, but only before the partner's first contact attempt or after an SLA breach.

- **Recall.** The lead is recalled from the partner through the adapter (where the API allows; otherwise the partner is told by email). It earns that partner nothing, and it is logged as an override, never as the engine's choice.
- **Telling the student.** If the student was already notified, a short **update message** goes out on the same channels: "Update: an academic counsellor from {{new partner}} will now call you about {{programme}}." It has its own approved template, with the same quiet-hours and idempotency rules as B9.


### B7.8 AI and machine learning: maximising commission per lead in real time

Eduwit wants the allocation engine to use AI and machine learning in real time, with Claude, so that it always maximises commission per lead. The design splits the work so each part does what it is best at:

| Layer | Job | Why this tool |
| --- | --- | --- |
| Rules (SQL) | Consent, eligibility, duplicates, attempt limits, caps, B2C fallback, test-lead exclusion | Must be exact and impossible to bypass |
| ML model (per lead, real time) | Predict, for this student and each candidate partner, the chance of enrollment; pick the partner with the highest expected net commission for this lead | Must answer in milliseconds, cheaply, reproducibly, for every lead |
| Claude (optimiser agent) | Watch outcomes, partner effort and money; tune the engine; find where flow should shift; catch anomalies; explain; propose rules | Reasoning across many signals, explaining trade-offs in plain language |

No language model sits in the per-lead decision path. The decision stays under 1 second and fully reproducible, while Claude continuously steers the policy that makes those decisions.

#### B7.8.1 Real-time per-lead model

- **Target.** `P(enroll | lead, partner, programme)`. The engine's per-lead score is:

  ```
  NCPL(p, lead) = P(enroll | lead, p) × CPE_net(p, lead) × (1 − refund_rate(p))
  ```

  The highest score wins, subject to the rules layer and exploration.
- **Model.** Gradient-boosted trees (LightGBM or XGBoost) with partner × lead interaction features, calibrated with isotonic regression. Trained nightly on matured outcomes (enrolled vs not, after `maturity_days`), with censoring handled for leads still open.
- **Features used.**
  - Lead: source and campaign type, channel, Witty's `lead_status` and temperature, qualification, score, work experience, job-role category, budget ÷ programme fee, enrollment timeline, mode preference, city tier and state, language, whether a parent is enquiring, intake hour and weekday, and how quickly the student answered Witty.
  - Programme: university, course, level, fee band.
  - Partner, live: the partner's 7- and 30-day speed to first contact, connect rate, current open-lead backlog, SLA compliance, and whether it is inside working hours right now.
- **Features never used.** Name, phone, email, raw chat text, or anything that could act as a proxy for a protected attribute.
- **Serving.** The trained model is exported (ONNX or tree JSON) and loaded by the worker. Scoring all candidates takes under 50 ms. Each decision stores the model version, feature snapshot hash and every candidate's prediction.
- **Exploration with learning built in.** In performance mode, the engine samples from each candidate's uncertainty (contextual Thompson sampling over a bootstrapped ensemble) instead of always taking the point estimate. It also **logs the selection probability of every decision**, so any new model or setting can be evaluated offline on past decisions (inverse-propensity and doubly-robust estimates) before it touches a real lead.
- **Activation gate.** The model decides only after:
  1. at least 500 matured outcomes exist, across at least 2 partners;
  2. it beats segment-level P̂ on a time-based holdout (log loss, calibration error);
  3. offline policy value shows higher net commission per lead.

  Until then, performance mode uses segment-level P̂ (B7.2).
- **Promotion path for a new model version:**
  1. **Shadow:** it scores but does not decide.
  2. **Challenger:** it decides 10% of eligible leads.
  3. **Champion:** promoted only when realised net commission per lead is higher with statistical confidence.

  Rollback is one click.
- **Monitoring.**
  - Calibration (predicted vs actual by decile).
  - Feature drift and prediction drift.
  - Automatic fallback to segment-level P̂ when calibration error passes a threshold, with an alert.

#### B7.8.2 Claude as the allocation optimiser

A worker runs a Claude agent through the Anthropic API with tool use and structured JSON outputs.

**Models.** All configurable:

- `claude-sonnet-5` for the regular optimisation passes;
- `claude-opus-5-5` for the nightly deep review and weekly report;
- `claude-haiku-4-5-20251001` for quick classification tasks.

**When it runs.**

- Every 15 minutes: a light check (anomalies, SLA and sync trouble, partner drift).
- Hourly: an optimisation pass.
- Nightly: a deep review. Weekly: a partner-performance report.
- On events: a partner auto-paused, an NCPL drop, a new partner going live, a commission rate change, a model promotion.

**What it can read (tools; aggregated and pseudonymised data only):**

- segment and partner scorecards;
- conversion cohorts;
- sales-effort and SLA metrics;
- commission rates and CPE per programme;
- engine settings and their history;
- model metrics;
- recent decisions without personal data;
- alerts;
- `run_simulation(settings_change, period)`, which replays logged decisions under the proposed change and returns the estimated net commission per lead with a confidence interval.

**What it can change (bounded tools):**

| Lever | Bounds |
| --- | --- |
| Exploration share per segment | 0–50% |
| Maturity window | 30–90 days |
| Recency half-life | 14–60 days |
| Prior strength | 5–50 leads |
| Segment mode pin (commission-first or performance) | Any segment; expires after 30 days unless renewed |
| Optional speed and reliability factors | On or off, within their bounds |
| Temporary partner weight | ±10% for up to 14 days, with a reason |
| Share cap per segment | Optional, 50–100% |
| Routing rules, partner pauses | **Draft only:** always need human approval |

**What it can never do:**

- touch consent, duplicate or attempt rules, the B2C fallback, capacity contracts, commission rates or live switches;
- see or use individual students' personal data;
- message students or partners.

**Two operating modes, set by the Admin:**

1. **Advisory (default at launch).** Each change is a recommendation in the AI Optimiser inbox. It shows the rationale, the evidence (linked metrics), the simulated impact with confidence, the risk and an expiry. The Admin approves, edits or rejects it.
2. **Autopilot (bounded).** Changes inside the bounds apply automatically when the simulation shows at least a set gain in net commission per lead (default 3%) with confidence. Limits:
   - a maximum number of changes per day (default 3);
   - every applied change is re-checked after 7 days and **rolled back automatically** if realised net commission per lead fell below its baseline.

   Changes outside the bounds always fall back to advisory.

**Measuring AI uplift honestly.** A holdout, default 10% of eligible leads chosen at random, keeps running the baseline policy (commission-first or segment P̂ with Admin settings, no AI changes). The dashboard shows realised net commission per lead for AI-steered vs holdout leads, so the AI's value is measured continuously and not assumed.

**Reliability rules for Claude's output:**

- **Every number comes from a tool.** Every number in Claude's narratives must come from a tool result; a validator checks numbers against the tool outputs before anything is shown or applied.
- **Every run is logged** in `ai_runs`: trigger, model, prompt version, input snapshot hash, tool calls, output, tokens, cost and the linked changes.
- **Every change is versioned** in `engine_settings_versions`, with the AI run that proposed it and the person who approved it (or "autopilot").
- **Spend is capped.** A daily budget and prompt caching keep the cost predictable.

**Other places Claude helps:**

- **Interest normalisation.** Free-text programme interest from imports and ad forms is mapped to catalogue programmes (Haiku, with a confidence score; low confidence goes to a human).
- **Mapping suggestions** in the mapping studio (B8.3.3). They are always confirmed by a person.
- **Anomaly narratives.** For example: "Partner X's connect rate fell from 62% to 41% since Tuesday; 80% of misses are evening calls."
- **Ask the CRM.** Natural-language questions are answered through the metric layer's read-only tools, never through free SQL on tables.

**Privacy.** Only aggregated or pseudonymised data goes to Claude: no names, phones or emails. Use the organisation's Anthropic data-retention controls (confirm the zero-retention option in Phase 0). The API key lives in Vault.


## B8. Partner push and live sync

### B8.1 Adapters

One adapter per partner CRM type, written as a plug-in module in the worker service with this interface:

| Operation | Does |
| --- | --- |
| `createLead(allocation, mappedPayload)` | Idempotent on `EDW-<allocation id>`, which is also written to the partner's lead-source or reference field. Returns the record ID, `duplicate` with the partner's existing record ID and created date, or an error |
| `fetchUpdates(since)` | Records and activities changed since the last poll |
| `verifyWebhook(headers, body)` | Signature or shared-secret check |
| `recallLead(recordId)` | Where supported |
| `describeSchema()` | Fields, stages and picklists, to pre-fill the mapping studio |

Build `generic_rest` and `webhook` first, then adapters for the first two real partners' CRMs. Common Indian edtech CRMs are LeadSquared, Meritto (NoPaperForms), Salesforce, Zoho and HubSpot. Each partner's API capabilities are confirmed at onboarding.

**Data sent to partners:** only what they need to sell:

- **Sent:** name, phone, email, city and state, programme interest (university when chosen, course, specialization, level, mode, the partner's course code), qualification, score, work experience, enrollment timeline, preferred language, and a short summary note.
- **Never sent:** budget, source, campaign, lead score, other partners' data, or Witty conversation text.

### B8.2 Status and activity sync

Partners report back in two ways:

- by webhook to `POST /v1/partners/{slug}/events` (HMAC per partner, `crm_partner_verify()`), or to an adapter-specific native webhook URL;
- by polling, every 5 minutes by default, for partners without webhooks.

**Every inbound payload is stored raw in `partner_events`** before mapping, so a corrected mapping can be re-applied to past events.

Events are idempotent by the partner's event ID and processed in order per lead. Event types:

- duplicate;
- contact attempted or connected;
- note;
- follow-up scheduled;
- counselled;
- application created or updated;
- documents status;
- fee paid;
- enrolled (fee, date, proof URL);
- lost (reason);
- refund or cancellation;
- reassignment to another partner counsellor.

**Every sales activity becomes a row in a new `partner_activities` table:**

- **Columns:** `allocation_id`, `lead_id`, `partner_id`, `kind` (call, whatsapp, email, sms, meeting, note, task, stage_change), `direction`, `outcome`, `duration_sec`, `counsellor_name`, `counsellor_external_id`, `occurred_at`, `raw`, `mapped`.
- **Rolled up onto the lead.** The same transaction updates the lead's summary columns in `student_leads`:
  - effort: `first_contacted_at`, `last_contacted_at`, `contact_attempts`, `next_task_due_at`;
  - pipeline: `stage`, `sub_stage`, `partner_stage_raw`, `partner_sub_stage_raw`, `partner_synced_at`;
  - application: `application_id`, `application_status`, `applied_at`;
  - fees: `fee_amount_inr`, `fee_paid_inr`;
  - enrollment: `enrollment_status`, `enrolled_program`, `enrolled_university`, `enrollment_date`;
  - outcome: `lost_reason`, `lost_at`.

  Also write the stage change to `crm_activities`.

**Targets.** Status visible in the CRM within 1 minute by webhook, or within one polling interval.

### B8.3 Mapping layer: making every partner's stages and fields mappable

Every partner names its stages, sub-stages, statuses, lead properties and sales properties differently, and some run several pipelines. The mapping layer is a hard requirement. Any field or status a partner CRM can send or receive must be mappable to Eduwit's model and back, and no partner value may ever be dropped. Routing, SLAs, analytics and commissions read only Eduwit's canonical values, which keeps partners comparable. Each partner's own wording is kept beside them and stays reportable.

#### B8.3.1 The canonical Eduwit model (the "right-hand side" of every mapping)

Keep one registry, `canonical_fields`, of everything a partner value can map to. It is seeded from:

| Group | Canonical targets |
| --- | --- |
| Lead stage | The stages in B6, each with a rank for "never move backwards" |
| Lead sub-stage | Sub-stages per stage, from `crm_settings.sub_stages`, extendable by the Admin |
| Lost reason | `crm_settings.lost_reasons`, extendable |
| Lead properties | Every relevant `student_leads` column (B3 list): identity, contact, interest, profile, qualification, score, work, budget, timeline, city, state, language, guardian, consent flags |
| Sales properties | Counsellor (name, external ID, email, phone), call outcome, call attempts, last call time, next follow-up time, counselling done (yes/no, time), application ID, application status, documents status, fee amount, amount paid, payment date, enrollment ID, enrollment date, refund (amount, date, reason), lost reason, remarks |
| Activity types | call, whatsapp, email, sms, meeting, note, task, stage_change |
| Picklists | Qualifications, study modes, levels, courses and specializations (catalogue), call outcomes, lost reasons, application statuses, document statuses, sources |

**Registry entries.** Each entry stores its data type, allowed values, whether it is required for go-live, and its owner. Every write follows the column-ownership rules in A3. A partner field cannot change a column Witty owns: partner data never overwrites Witty-owned interest or profile columns except where the mapping marks the partner as trusted for that field and Eduwit's value is empty. Conflicting values are kept as history in `partner_activities.mapped` and shown on the lead.

#### B8.3.2 Mapping types the studio must support

| Type | Example | How it works |
| --- | --- | --- |
| **Stage only** | Partner "Dead" → `lost` | One partner stage → one Eduwit stage |
| **Stage + sub-stage** | "Attempted / RNR" → `contacted` / "no answer" | The pair maps to an Eduwit stage, sub-stage and lost reason where relevant |
| **Wildcard with overrides** | "Not Interested / *" → `lost`, except "Not Interested / Budget" → `lost` / "over budget" | The most specific rule wins |
| **Conditional** | Partner stage "Follow-up" means `counselled` if `counselling_done = yes`, else `contacted` | Rules on other fields of the same payload, evaluated in order |
| **Many-to-one** | "Hot", "Warm" and "Prospect" all → `counselled` | Allowed |
| **One-to-many by context** | Same status means different things in two partner pipelines | Each mapping profile can hold several **pipelines** (by partner pipeline ID, lead type, programme or university); rules are scoped to a pipeline |
| **Field ↔ field** | `mx_Highest_Education` ↔ `highest_qualification` | Direction per field: out (sent at push), in (synced back) or both |
| **Field ↔ several fields** | Partner "Full Name" ↔ `student_name` (split or join); partner "Course" ↔ course + specialization | Split or join transform |
| **Value maps (picklists)** | "Graduate" → "Bachelor's"; "PGDBA" → catalogue course code | One table per field per partner, both directions; synonyms allowed |
| **Transforms** | Phone to E.164; dates and time zones to IST; "2.5 L" → 250000; CGPA → %; text to boolean; constants (source = "Eduwit"); lookups (Eduwit programme → partner course code) | Chainable and previewed live |
| **Activity mapping** | Partner "Call Log" with "Connected" → activity `call`, outcome `connected` | Partner activity type + outcome → Eduwit activity kind + outcome |
| **Custom / unmapped partner fields** | Partner's "Lead Quality Score" | Kept in `custom_fields` under the partner's namespace, or promoted to a new column by an Admin-approved tracked migration. Never dropped |

#### B8.3.3 Building a mapping

1. **Discover.** Pull the partner's fields, stages, sub-stages, pipelines and picklist values through `describeSchema()`. Where the API cannot list them, upload the partner's field list and status export (CSV or Excel). Store the discovered schema as a versioned snapshot.
2. **Suggest.** Pre-fill matches in this order:
   1. exact and synonym matches;
   2. name similarity;
   3. matches learned from other partners on the same CRM (e.g. LeadSquared's `mx_` fields);
   4. optionally, AI-assisted suggestions that are clearly labelled and need human confirmation.
3. **Review in the studio.** Partner on the left, Eduwit canonical on the right. Each row shows its confidence, direction toggle, transform chips and sample values seen from the partner.
4. **Test.** The test panel runs real or sample partner records through the profile, in both directions, and shows the before and after and any value that would be unmapped.
5. **Publish.** Saving creates a new **version** with who, when and why. Activation is explicit, and the previous version can be restored in one click.

#### B8.3.4 Coverage gates (a partner cannot go live without these)

- Every partner stage and sub-stage seen in the schema and in the test leads is mapped (or explicitly marked "ignore", with a reason).
- Every required canonical lead field for the push (name, phone, programme or course code, and whatever the partner's API requires) is mapped outbound.
- Every required canonical sales field (stage, counsellor, last call outcome, follow-up date, application, fee, enrollment and lost reason, where the partner has them) is mapped inbound.
- Every picklist value seen in the 10 test leads is mapped both ways.
- A **coverage score** (% of partner fields, stages and values mapped) is shown on the partner page and must reach 100% of required items before go-live.

#### B8.3.5 Mapping at runtime

- **Raw first.** Every inbound payload is saved raw in `partner_events` before mapping. Every outbound payload is saved with the mapping version that produced it.
- **Unknown values never move a lead.** A new stage, sub-stage, field or picklist value is stored raw, flagged "unmapped" on the lead, and added to the **mapping queue** with a count of affected leads.
- **Re-processing.** Once someone maps the value, held events re-process automatically and in order.
- **Drift detection.** A scheduled `describeSchema()` comparison and the live unmapped stream detect:
  - new stages;
  - renamed fields;
  - removed picklist values;
  - type changes.

  Each raises an alert and a mapping task. Drift on a required field pauses outbound pushes to that partner until it is resolved, while inbound events keep being stored raw.
- **Backfill.** Publishing a corrected mapping can re-apply it to past raw events (with a preview of how many leads' stages and metrics will change), then recalculate stages, SLAs and analytics.
- **Both views everywhere.** Lead screens show the Eduwit stage with the partner's raw stage and sub-stage beneath. Reports and the dashboard builder can group by either canonical values or a partner's raw values.

#### B8.3.6 Mapping tables (data model)

Extend `partner_mapping_profiles` (versioned) or normalise it into these tables, whichever the Phase 0 audit recommends:

| Table | One row per |
| --- | --- |
| `canonical_fields` | Eduwit target (stage, sub-stage, field, picklist) with type, allowed values, required flags |
| `partner_schema_snapshots` | Discovered partner schema version |
| `mapping_profiles` | Partner × version, with status (draft, active, retired) |
| `mapping_pipelines` | Partner pipeline or context inside a profile |
| `status_rules` | Partner stage + sub-stage (+ conditions) → Eduwit stage + sub-stage + lost reason, with priority, and an `is_reopen` flag |
| `field_rules` | Partner field ↔ canonical field, with direction, transform chain, trusted flag, required flag |
| `value_rules` | Partner value ↔ canonical value, per field, both directions |
| `activity_rules` | Partner activity type + outcome → Eduwit activity kind + outcome |
| `mapping_queue` | Unmapped item, first seen, last seen, count, affected leads, resolution |

#### B8.3.7 Mapping tests

- **Unit tests** for every transform.
- **Golden-file tests** per partner: sample raw payloads → expected canonical result, run in CI on every mapping change.
- **Round-trip test:** Eduwit → partner → Eduwit for every outbound field returns the same value.
- **Contract test:** the adapter's real sandbox, where one exists.

#### B8.3.8 Go-live checklist per partner

1. Agreement and data-processing terms uploaded.
2. The partner's programme file published in the Programme Repository (B5.2), with no rows left in review, and its rates approved.
3. Credentials stored in Vault.
4. Mapping published with every coverage gate at 100% and golden-file tests passing.
5. SLAs and working hours set.
6. Notification branding previewed.
7. 10 test leads pass end to end, including one forced duplicate and one lead taken through every partner stage.
8. `live_mode` switched on by the Admin.

### B8.4 Health and reconciliation

- **Sync health panel per partner:** last event received, event lag (p50/p95), error rate, queue backlog, webhook failures, dead-letter count.
- **Nightly full comparison** per partner: leads missing on either side, status disagreements, stale records. Each mismatch becomes a task.
- **Retries and dead letters:** failed jobs retry with backoff and then land in a dead-letter list the Admin can inspect, retry or discard with a reason.

### B8.5 SLAs (defaults; editable per partner; clocks run in the partner's working hours)

| SLA | Default | On breach |
| --- | --- | --- |
| First contact attempt | 2 working hours from the push | Alert. Counts in the scorecard and the optional speed factor |
| First connected conversation | 1 working day | Scorecard |
| Status update while open | Every 7 days | Lead flagged stale |
| Counselling outcome recorded | 5 working days | Scorecard |
| Enrollment proof | 7 days after `enrolled` | Commission stays *expected* until proof arrives |
| Duplicate claim window | 24 hours | Later claims rejected |

## B9. Student notification after a successful push

Once a partner accepts a lead, the student immediately learns who will call.

**Trigger.** The allocation becomes `accepted`: the hold window after the push has passed with no duplicate or rejection (B7.5). A partner that reports a duplicate or rejects inside the window is never named to the student. A duplicate claim after acceptance does not move the lead (it becomes a commission dispute), so the student is never told about two partners, except through the explicit update message after a manual re-route (B7.7).

**Channels.** Both, independently:

- **WhatsApp:** an approved utility template from Eduwit's WhatsApp Business number, through a provider adapter (Meta Cloud API, or the existing Chatwoot inbox Witty uses; configurable).
- **Email:** a branded HTML email from Eduwit's sending domain (SPF, DKIM, DMARC), through a provider adapter (e.g. Amazon SES, Resend or Brevo).

**Content.** Names the partner's brand (`display_name`, logo in email), the programme the student asked about, and what happens next. Only promise timing that matches the partner's SLA. Template variables:

| WhatsApp placeholder | Variable |
| --- | --- |
| `{{1}}` | `student_first_name` |
| `{{2}}` | `programme_label`: university + course + specialization when chosen, otherwise course + specialization |
| `{{3}}` | `partner_display_name` |
| `{{4}}` | `expected_contact_window`, from the partner's SLA and working hours (e.g. "within 2 working hours" or "tomorrow morning") |
| `{{5}}` | `eduwit_support_contact` (a support phone or email that is staffed) |

The email also uses `partner_logo_url`.

Templates exist in English and Hindi (Hinglish for WhatsApp), chosen by `preferred_language`. An example WhatsApp body for template approval:

> Hi {{1}}, thank you for your interest in {{2}}. An academic counsellor from {{3}} will call you on this number {{4}} to guide you on admission and next steps. If you need help in the meantime, contact Eduwit at {{5}}. — Team Eduwit

The email has the same message, the partner's logo, a short "what to keep ready" list (marksheets, ID), Eduwit's support contact and a footer with an unsubscribe link.

**Rules.**

| Rule | Detail |
| --- | --- |
| Quiet hours | Send between 08:00 and 21:00 IST. Otherwise schedule for 09:00 the next day, unless the partner works those hours and has opted to call immediately |
| Consent and opt-out | Never to opted-out students. Never to test leads or 910000 numbers on a live channel |
| One per acceptance | Idempotent per allocation and channel |
| Records | Log every send in a new **`student_notifications`** table: `lead_id`, `allocation_id`, `partner_id`, `channel`, `template_id`, `variables`, `provider_message_id`, `status` (queued, scheduled, sent, delivered, read, failed, cancelled), `scheduled_for`, `sent_at`, `error`. Delivery and read receipts come back by provider webhook. **Never** write to `w2_messages` |
| Failures | Retry once after 5 minutes. Then alert and show it on the lead. An email bounce sets `email_bounced_at` |
| Replies | Replies to the WhatsApp notification must reach a person. If it is sent from Witty's number, Witty answers once with a fixed line ("Your counsellor from {{3}} will call you; for help contact {{5}}") and alerts the Eduwit support inbox. This needs an agreed change on Witty's side, so it is a Phase 0 decision. Otherwise use a separate support number staffed by Eduwit |
| Witty | Witty must stop selling once a lead is allocated, so the student never hears two voices. Witty reads the allocation columns in `student_leads`; the B2B CRM never writes Witty's tables. In Phase 0, agree with Vikas whether the B2B CRM also sets `student_leads.is_bot_paused` |

A **counsellor follow-up message** (phase 3, optional per partner): when the partner's CRM assigns a named counsellor, send "Your counsellor is {{name}}" with the counsellor's number, if the partner allows it.

## B10. Hand-off to Eduwit's B2C CRM

The B2C CRM is a separate application designed separately. The B2B CRM's contract with it:

1. **Allocation and lead update.** Write an allocation with `destination_type = 'in_house'`, `mode = 'fallback'`, a `reason`, and status `handed_off`. Set the lead's `destination_type = 'in_house'`, `allocation_id` and `allocation_reason`.
2. **Outbox event.** Emit `b2c.lead_handed_off` into a new `integration_outbox` table (`event_type`, `payload`, `target`, `status`, `attempts`, `delivered_at`) and through `pg_notify`. A configurable webhook URL also receives the event, signed with HMAC. The payload carries the lead ID, reason, the partners tried and their duplicate proofs.
3. **Ownership.** From then on the B2C CRM owns the lead's pipeline. The B2B CRM shows it read-only as "With Eduwit B2C" and keeps it in analytics as a destination.
4. **Notification.** The B2B CRM sends an Eduwit-branded version of B9 ("an Eduwit academic counsellor will call you"), unless the setting `b2c_sends_own_notification` is on.

## B11. Conversion feedback to Meta and Google (CAPI)

Eduwit's ads optimise on real outcomes, not just form fills. A worker sends conversion events, gated by the student's consent, for every lead with an ad identifier:

| Platform | Identifier | Method |
| --- | --- | --- |
| Meta | `leadgen_id` (Lead Ads), or `fbclid` / `fbp` / `fbc` (website and Witty leads from Meta ads, in `click_ids` or `w2_clicks`) | Conversions API: CRM events for Lead Ads (`action_source = system_generated`, `lead_event_source = "Eduwit CRM"`, `user_data.lead_id`), website events with hashed phone and email |
| Google | `gclid`, `gbraid` / `wbraid`, or lead-form ID | Google Ads API offline conversion upload, plus enhanced conversions for leads with hashed email and phone |

- **Stage-to-event map** (configurable per platform):
  - `ready_to_route` when the lead becomes ready to route;
  - `partner_accepted` when a partner accepts it;
  - `contacted`, `applied`;
  - `enrolled`, with value = expected net commission (₹);
  - `verified`, with value = realised net commission.
- **Event IDs** are deterministic (`<lead id>:<stage>:<cycle>`) so retries never double count.
- **Hashing:** phone and email are hashed with SHA-256 after normalisation; raw PII never leaves.
- **Logging:** every send is logged in a new `conversion_events` table (`lead_id`, `platform`, `event_name`, `event_id`, `value_inr`, `status`, `response`, `sent_at`). Failures retry and then dead-letter.
- **Live switch:** test leads are never sent. Each platform has its own `LIVE_MODE` switch.

## B12. Commission and money

The B2B CRM tracks what partners owe Eduwit. Sales-manager payouts belong to the B2C CRM.

1. **Enrollment.** A partner's `enrolled` event creates an `enrollments` row (status `reported`) and an *expected* earning line from the rate in force on the enrollment date (`crm_compute_earning()`).
2. **Verification.** The Admin verifies against proof (partner statement line, university confirmation or fee receipt). The status becomes `verified`, the earning becomes *realised*, and the lead's `realised_net_revenue_inr` updates.
3. **Tiers.** For tiered rates, tiers are provisional during the period and settled at period close (`crm_period_close()`) from verified enrollments ÷ leads accepted.
4. **Invoicing.** At period close (monthly by default), the CRM lists verified, uninvoiced enrollments per partner and generates a GST invoice for the Admin to approve and send. The invoice carries sequential numbering, Eduwit's and the partner's GSTIN, the SAC code, and one line per enrollment.
5. **Receipts.** Record payments with TDS and bank reference and auto-match them to invoices. Ageing buckets are 0–30, 31–60, 61–90 and 90+ days, with reminders for overdue invoices.
6. **Statement reconciliation.** The Admin uploads a partner's statement (Excel or CSV). Rows auto-match by Eduwit reference, partner record ID, phone, or name plus programme, into four piles:
   - matched;
   - partner only (possible leakage);
   - Eduwit only;
   - amount mismatch.

   Each pile exports as a dispute list.
7. **Refunds and clawbacks.** A refund inside the window reverses the earning with a new negative line.
8. **Export.** CSV exports for the accounting tool (Tally or Zoho Books).

GST rate, SAC code, TDS rates and refund windows are settings to be confirmed by Eduwit's CA.

## B13. Analytics and dashboards

Every number answers "show me the leads behind this" with one click. Data is never more than 1 minute old.

### B13.1 Metric catalogue

Every metric can be cut by any dimension in B13.2.

| Area | Metrics |
| --- | --- |
| Intake | Leads by source, campaign, form, city; merged, reopened and junk; ready-to-route rate; intake-to-routing time; pre-routing pool size and what each lead is missing; import results |
| Routing | Leads routed per partner and segment; share of flow and its change; mode per segment (commission-first or performance); exploration share; CPE and NCPL per candidate; overrides; fallbacks to B2C by reason |
| Duplicates | Duplicate rate per partner; cascade outcomes (2nd partner accepted vs B2C); disputes and their results |
| Lead stages | Stage counts and stage-to-stage conversion (contacted → counselled → applied → enrolled → verified), each against the segment average; time in each stage; lost by reason and stage |
| **Sales effort** | Time to first attempt (median, p90); attempts in the first 24 h and 72 h; connect rate; attempts before first connect; days between touches; follow-up adherence (scheduled follow-ups done on time); activities per open lead per week; stale share (no update in 7 days); counsellor-level breakdown inside each partner |
| SLAs | Compliance per SLA per partner; breaches by day and hour; current open breaches with live timers |
| Conversion | Lead-to-enrollment by allocation cohort (7, 30, 60 and 90 days); time to enroll; refund rate |
| Commission | CPE by partner and programme; NCPL realised and expected; revenue velocity (net commission per lead in the first 30 days); expected vs realised commission; receivables and ageing; invoices; collection rate; tier watch (current conversion vs thresholds, projected tier); statement variance and leakage |
| Notifications | Sent, delivered, read and failed per channel and partner; time from acceptance to notification |
| AI and ML | AI-steered vs holdout net commission per lead (uplift, with confidence interval); model calibration and drift; share of decisions by model version; recommendations made, approved, rejected, auto-applied and auto-rolled-back, and their realised impact; AI cost per day and per 1,000 leads |
| CAPI | Events sent per platform and event; match quality; failures |
| System and mapping | Sync lag and errors per partner; dead letters; unmapped values (count, age, affected leads); mapping coverage per partner; schema drift events; intake API errors |

### B13.2 Dimensions

Date (created, routed, accepted, enrolled), source, sub-source, campaign, UTM, form, city, state, university, programme, course, specialization, level, mode, segment, partner, partner counsellor, routing mode, attempt number, `lead_status`, temperature, stage, sub-stage, lost reason, language.

### B13.3 Dashboard builder

- **Grid:** drag, resize and reorder widgets.
- **Widgets:**
  - KPI tile with delta and sparkline;
  - line or area chart;
  - bar chart (grouped or stacked);
  - funnel;
  - Sankey (source → partner → stage);
  - cohort heatmap;
  - table with conditional formatting;
  - leaderboard;
  - India map by state;
  - gauge or target;
  - live SLA timer list;
  - text or note.
- **Building a widget:** pick a metric, a breakdown, filters and a comparison period. The Admin can define calculated metrics (e.g. commission ÷ attempts) once in `metric_definitions` and reuse them.
- **Dashboard-wide controls:** filters and date range, with period-over-period comparison.
- **Drill-down:** every number opens its lead, enrollment or event list. A list can be saved as a view.
- **Home dashboard:** any dashboard can be set as the home screen.
- **Scheduled delivery:** any dashboard by email as a PDF, or a table as CSV, daily, weekly or monthly.
- **Metric alerts:** a threshold on any metric sends a WhatsApp or email alert.

### B13.4 Default dashboards shipped

1. **Command Center:** today's leads, routed, accepted, duplicate rate, SLA compliance, expected and realised commission this month; live lead stream; Sankey of the last 7 days; alerts; partner health strip.
2. **AI Optimiser:** uplift vs holdout, open recommendations, recent changes and their realised effect, model health.
3. **Partner League Table:** all partners side by side for a chosen segment or overall, sorted by NCPL, with conversion, effort, SLA, duplicate rate and commission.
4. **Partner Deep-Dive:** one partner's funnel, effort, SLA, cohorts, counsellor breakdown, commission and sync health.
5. **Routing & Flow:** segment explorer, mode per segment, shares over time, decision log, fallbacks.
6. **Sales Effort & SLAs:** effort metrics and live breaches across partners.
7. **Commission & Receivables:** expected vs realised, invoices, ageing, tier watch, statement variance.
8. **Sources & Ads:** leads and outcomes by source and campaign, with CAPI health and cost per enrollment where ad spend is imported.
9. **Data Quality & Sync:** unmapped queue, sync lag, dead letters, missing fields.

Analytics never slow down operational screens. They read rollup tables or materialized views refreshed every minute (`pg_cron`) from an append-only `b2b_events` log.

## B14. UI and UX: design direction and screens

### B14.1 Aesthetic

The aesthetic is **ultra-modern, calm and data-dense**: the quality bar of Linear, Attio and Vercel's dashboard, not a generic admin template. Every screen should be attractive at first glance, and every element should earn its place by helping a decision.

**Design principles.**

- **Logic first.** Every screen answers one question ("Which partner is underperforming this week?"), and its layout follows that question's order.
- **Show the why.** Routing choices, commissions and SLA states always show the reasoning on hover or in a side panel.
- **Live, but calm.** Real-time updates animate gently (a 150–250 ms ease-out fade or count-up), never flash or jump the layout.
- **Progressive disclosure.** Summaries first; details in drawers and tabs; raw payloads one click deeper.

**Design tokens** (define them as CSS variables in a Tailwind theme):

| Token | Choice |
| --- | --- |
| Typeface | Geist Sans for UI, Geist Mono with tabular numerals for every number, ID and currency |
| Base palette | Neutral zinc/slate surfaces with fine 1 px borders instead of heavy shadows; light and dark themes, both first-class, following the system setting with a toggle |
| Accent | One accent (electric indigo, around `#5B5BF7`) for primary actions and focus. Semantic colours: emerald (success), amber (warning, SLA at risk), rose (breach, failure), sky (info) |
| Partner colours | A fixed categorical palette assigned per partner and reused in every chart, so each partner keeps the same colour everywhere |
| Shape and spacing | 8 px grid; 10–12 px radius on cards; generous whitespace in summaries; dense, compact tables |
| Elevation | Flat surfaces. A soft blur on overlays only (command palette, modals) |
| Motion | Framer Motion; shared-layout transitions for drawers and tabs; reduced-motion respected |
| Accessibility | WCAG 2.2 AA contrast, full keyboard use, visible focus rings, colour never the only signal (icons and labels too) |

**Stack for the UI:**

- **Framework and components:** Next.js (App Router) with TypeScript, Tailwind CSS and shadcn/ui (Radix primitives).
- **Data:** TanStack Query for fetching, TanStack Table for tables (virtualised, column resize, pin, reorder).
- **Charts:** Apache ECharts with a custom theme matching the tokens. It covers Sankey, funnel, heatmap, map and gauge in one library.
- **Dashboard grid:** react-grid-layout.
- **Command palette:** cmdk.
- **Toasts:** sonner.
- **Live updates:** Supabase Realtime.

### B14.2 Layout and interaction patterns

**Layout.**

- **Shell:** a collapsible left rail (icons + labels), a top bar with global search and the command palette (⌘K / Ctrl K), a period picker, a live-status pill (sync health), notifications and the profile menu.
- **Lead drawer:** opens from any list or chart without leaving the page. Each lead has its own shareable URL.

**Lists and tables.**

- **Saved views** on every list: filters, columns, sort and grouping, private or shared.
- **Inline filter builder:** field, operator and value chips, with AND/OR groups.
- **Bulk actions** with an undo toast where reversible.

**Keyboard shortcuts.**

| Keys | Action |
| --- | --- |
| ⌘K | Command palette |
| `/` | Search |
| `g l` | Leads |
| `g p` | Partners |
| `g r` | Routing |
| `g d` | Dashboards |
| `j` / `k` | Move through rows |
| `Enter` | Open |
| `Esc` | Close |
| `?` | Shortcut sheet |

**States and density.**

- **Empty states** explain what will appear and offer the next action. **Skeleton loaders** match the final layout. **Errors** say what happened and what to do.
- **Density:** comfortable or compact toggle per user. Every screen is responsive and usable on a phone for monitoring.

### B14.3 Screens

| Screen | Purpose and key elements |
| --- | --- |
| **Command Center** (home) | Live KPI row with deltas; AI insight cards (the 3 most valuable current recommendations or anomalies); Sankey (source → partner → stage); live lead stream (new, routed, accepted, duplicate, enrolled) as an animated feed; alerts rail with one-click actions; partner health strip (colour-coded cards: lag, SLA, today's leads) |
| **Leads (Master Lead Table)** | Every lead with all its data, routing, partner status, sales effort and commission; edit, delete, bulk delete and download (B6.1). Virtualised table with saved views; status chips for Eduwit stage and partner raw stage. **Lead drawer** tabs:<br>• **Overview:** profile, interest, consent, verification badges.<br>• **Journey:** one vertical timeline of intake, routing decision, push, duplicate claims, partner activities, notifications sent and their delivery, and CAPI events.<br>• **Why this partner:** the candidates table with CPE, P̂, NCPL, mode, exploration flag and rules applied.<br>• **Partner sync:** raw payloads and mapping results.<br>• **Money:** enrollment and commission lines.<br>Actions: re-route (with reason, guarded), resend notification, open in partner CRM (deep link), mark test |
| **Pre-routing pool** | Leads not yet routable, grouped by what is missing, with counts and age |
| **Routing** | **Segment explorer:** every segment with its candidates, mode badge (commission-first or performance), flow shares over time and the maturity progress toward performance mode.<br>**Rules builder:** visual conditions → action, drag to reorder priority, live count of matching leads in the last 30 days.<br>**Decision log:** searchable.<br>**Simulator** (phase 3): replays the last 30 days under changed settings and shows the projected commission difference.<br>**Engine settings:** versioned, with a diff view |
| **Partners** | Grid or list of partners with logo, status, health and this month's NCPL. **Partner page** tabs:<br>• Overview: scorecard and trend.<br>• Programmes & Commission: the partner's programmes, rates and CPE per programme.<br>• Funnel & Effort.<br>• SLAs: live timers and breach history.<br>• Leads.<br>• Sync & Mapping.<br>• Notifications: branding and preview of the WhatsApp message and email.<br>• Settings: caps, hours, SLAs, dedupe mode, live switch with a confirmation dialog that names what will happen |
| **Programme Repository** | A tab of its own (B5.2.5): every partner's programme file (Excel upload or connected Google Sheet), version history and diffs, the upload or sync wizard with column mapping, row matching to the catalogue, a change and routing-impact preview, and publish and roll back. Also holds the coverage matrix of programmes × partners with each partner's CPE, highlighting where partners compete, where only one partner covers a programme, and programmes no partner offers |
| **Mapping studio** | Tabs for Stages, Lead fields, Sales fields, Picklists, Activities and Pipelines. Partner on the left and Eduwit canonical on the right, with suggestion confidence, sample partner values, direction toggles and transform chips. Conditional-rule editor for stage mapping. Test panel (both directions, before and after). Coverage score with the required items still open. Version history with diff and one-click restore. Mapping queue (unmapped values with affected-lead counts, "map and re-process"). Drift alerts. Backfill preview |
| **Intake** | Source cards (Witty, website agent, Meta, Google, imports) with volume, errors and last event; import wizard; intake log; per-form field mapping for Meta and Google |
| **Notifications** | Templates per channel and language with live preview per partner; send log with delivery funnel; provider health |
| **CAPI** | Stage-to-event map per platform; event log; match-quality and failure stats |
| **Commission & Finance** | Enrollment verification queue (proof viewer side by side); earnings ledger; invoices; receipts; statement reconciliation (four piles); tier watch |
| **Dashboards** | Gallery of defaults and saved dashboards; builder (B13.3) |
| **Reports** | Tabular, summary and matrix reports; save, share, schedule, export |
| **AI Optimiser** | Recommendations inbox (rationale, evidence links, simulated impact with confidence, risk, expiry; approve, edit or reject); Advisory or Autopilot switch with its bounds; change log with before and after realised effect and one-click rollback; uplift vs holdout chart; model registry (shadow, challenger, champion) with calibration plots; "Ask the CRM" chat that answers from the metric layer and shows its sources |
| **Admin** | Users and roles; API keys; webhooks; outbox and dead letters; audit log; system health (queues, lag, error rates); settings (GST, TDS, quiet hours, defaults) |

## B15. Architecture

```
Sources (Witty WA, website agent, Meta, Google, Excel)
   │  lead_intake() / Intake API
   ▼
Supabase Postgres (shared with Witty) ── business rules as SQL functions, RLS, pg_cron, Realtime, Vault, Queues (pgmq)
   ▲            │ jobs: route, push, poll, notify, capi, reconcile, rollup
   │            ▼
Next.js web app + API (/v1)        Worker service (Node 20, TypeScript)
   ▲                                   │ adapters ──► Partner CRMs (push, poll, recall)
   │ Auth: Google or email+password    │ comms    ──► WhatsApp provider, email provider
Eduwit Admin                           │ capi     ──► Meta CAPI, Google Ads API
                                       └ outbox   ──► Eduwit B2C CRM (webhook / pg_notify)
Partner webhooks ──► /v1/partners/{slug}/events ──► partner_events (raw) ──► mapping ──► leads + activities
```

| Component | Recommendation |
| --- | --- |
| Web app and API | Next.js (App Router, TypeScript); route handlers for `/v1`; server actions for UI mutations, which call SQL functions |
| Database | The existing Supabase project (Postgres 17): business rules as SQL functions and constraints; row-level security as a second line of access control; `pg_cron` for timers and rollups |
| Queue | Supabase Queues (`pgmq`) so jobs live in the same database and are transactional with the writes that create them. Idempotent job keys; dead-letter queue visible in Admin |
| Workers | One Node 20 TypeScript service with job handlers: route, push, poll, sync-apply, notify, capi, reconcile, rollup, alert. Loads the current champion ML model (ONNX or tree JSON) for real-time scoring |
| ML training | A Python job (Cloud Run Jobs, nightly): feature extraction from the CRM's tables, LightGBM or XGBoost training, calibration, offline policy evaluation, model registry. Artefacts in Supabase Storage |
| AI optimiser | A worker job using the Anthropic TypeScript SDK with tool use and JSON-schema outputs; scheduled and event-triggered runs (B7.8.2); every tool reads the metric layer or calls a bounded SQL function |
| Hosting | Google Cloud Run in an India region (asia-south1 or asia-south2, where Eduwit's n8n already runs): web app and worker as separate services; staging and production projects |
| Files | Supabase Storage: enrollment proofs, statements, imports, invoices |
| Observability | Structured logs, metrics and traces (OpenTelemetry); alerts on queue backlog, sync lag, error rates and dead letters; in-app system health page |
| Testing | Vitest for units, pgTAP for SQL functions, Playwright for end-to-end, a contract-test suite per adapter, a mock partner server, and k6 for load |

## B16. Data model changes

These are proposed. Confirm each against the Phase 0 audit. **Every new table goes in the `b2b` schema** (A5); existing empty B2B tables move there in Phase 0 if Vikas agrees. Shared objects (`student_leads`, `lead_intake()`, the catalogue) stay where they are.

| Change | Detail |
| --- | --- |
| `partners` | Add the fields in B5.1. Widen the `adapter_type` check |
| Programme Repository (new) | `partner_programme_sources`, `partner_programme_versions`, `partner_programme_rows`, `partner_programmes` (B5.2.4) |
| `earning_rates` | Add scope `partner_programme`. Use the existing `partner_id` + `programme_id` columns |
| `allocations` | Add `mode` (`commission_first`, `performance`, `exploration`, `rule`, `manual`, `fallback`), `attempt_no`, `cpe_net_inr`, `ncpl_inr`, `accepted_at`, `notify_status`. Replace the `status` check with the full state machine in B7.5: `queued`, `pushing`, `pushed`, `accepted`, `duplicate`, `rejected`, `failed`, `recalled`, `handed_off`, `closed`. Map the existing values (`pending` → `queued`; `assigned` → `handed_off`) in the migration. Also add `hold_until`, `selection_probability`, `model_version`. Keep `destination_type` values `partner` and `in_house` (= B2C CRM) so existing constraints and Witty's reads still work |
| Mapping tables (new or normalised from `partner_mapping_profiles`) | `canonical_fields`, `partner_schema_snapshots`, `mapping_profiles`, `mapping_pipelines`, `status_rules`, `field_rules`, `value_rules`, `activity_rules`, `mapping_queue` (B8.3.6) |
| `partner_activities` (new) | B8.2 |
| `student_notifications` (new) | B9 |
| `conversion_events` (new) | B11 |
| `integration_outbox` (new) | B10 |
| `import_jobs`, `import_rows`, `import_mappings` (new) | B4.1 |
| `partner_statements`, `statement_lines`, `statement_matches` (new) | B12 |
| `receipts` (new) | B12 |
| `b2b_events` (new, append-only) | Source for analytics and audit |
| `b2b.app_users` (new) | The B2B CRM's own allowlist: one row, `connect@eduwit.in` (B3) |
| `b2b_referral_outcomes` (new view) | Masked, read-only referral progress for the influencer dashboard (A5) |
| Master Lead Table (new) | `b2b_master_leads_v` read model; `lead_field_history`; `lead_deletions` (soft delete, restore, erasure log); `lead_exports` (export log and files) (B6.1) |
| `rollup_*` tables or materialized views | Analytics (B13) |
| `metric_definitions`, `dashboards`, `dashboard_widgets`, `metric_alerts`, `report_schedules` (new) | B13 |
| `engine_settings_versions` (new) | Versioned copy of `crm_settings.engine` with who, when and why (person, autopilot, or the AI run that proposed it) |
| `ml_models` (new) | Model version, features, training window, metrics, status (shadow, challenger, champion, retired), artefact path |
| `ai_runs` (new) | Every Claude run: trigger, model, prompt version, input snapshot hash, tool calls, output, tokens, cost |
| `ai_recommendations` (new) | Proposed change, rationale, evidence, simulated impact, confidence, status (open, approved, rejected, auto-applied, rolled back), realised impact after 7 days |
| `ai_holdout` (new or a column on `allocations`) | Marks leads routed by the baseline policy for uplift measurement |
| `student_leads` | No new columns needed: the partner, sync, application, enrollment and revenue columns exist |

**Integrity rules enforced by the database:**

- At most one open allocation per lead.
- At most 2 partner attempts per enquiry cycle before the B2C fallback (configurable).
- Stage moves follow the allowed transitions.
- An earning line always points to an enrollment and a rate version.
- Money rows are reversed, never deleted.
- Nothing is pushed, messaged or sent to ads for a test lead.

## B17. API surface

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `POST /v1/leads` | API key with `intake` scope + `Idempotency-Key` | Intake for outside sources; calls `lead_intake()`; returns `{lead_id, action, routing}` |
| `GET` and `POST /v1/webhooks/meta/leadgen` | Meta verify token + app secret signature | Lead Ads intake |
| `POST /v1/webhooks/google/leadform` | `google_key` | Google lead-form intake |
| `POST /v1/partners/{slug}/events` | HMAC per partner | Status and activity events (B8.2) |
| `POST /v1/partners/{slug}/webhook/{adapter}` | Adapter-specific verification | Native webhooks from partner CRMs |
| `POST /v1/webhooks/whatsapp/status`, `POST /v1/webhooks/email/events` | Provider signature | Delivery and read receipts, bounces |
| Outbound `b2c.lead_handed_off` | HMAC | Hand-off to the B2C CRM (B10) |
| Outbound `lead.allocated`, `lead.accepted`, `lead.status_changed`, `lead.enrolled` | HMAC | Subscribable by Eduwit's other products (A5) |
| `GET /v1/referrals/{code}/outcomes` | Per-product API key | Masked referral progress for the influencer dashboard (A5) |

Internal UI endpoints are server actions that call SQL functions. All public endpoints are rate-limited and log request IDs.

## B18. Security, privacy and compliance

- India's DPDP Act 2023 applies: lawful purpose, consent records per purpose (sales contact, sharing with partners, marketing, ads measurement), data minimisation to partners, erasure on request (anonymise the `student_leads` row and send deletion requests to every partner that received the lead, keeping money rows by ID), and a breach runbook.
- Every partner signs a data-processing agreement before going live.
- **Consent wording.** Witty's, the website agent's, the Meta forms' and the Google forms' consent lines must cover sharing with partner edtechs and ads measurement. Store `consent_text_version`.
- **AI data handling:** only aggregated or pseudonymised data reaches Claude; no names, phones or emails in prompts; the ML model uses no personal identifiers; the Anthropic API key lives in Vault.
- **Access:** RLS on every table the B2B CRM creates (shared tables stay as they are, A3); the single-Admin allowlist in B3, checked on the server for every request; every action, human or system, in the audit log.
- **Secrets and webhooks:** secrets in Vault; signed webhooks both ways.
- **Platform:** HTTPS only; daily backups with point-in-time recovery and a quarterly restore test; dependency scanning in CI; a penetration test before go-live.
- **WhatsApp:** approved templates only, utility category for B9, opt-out honoured at once across channels.

## B19. Non-functional requirements

| Area | Target |
| --- | --- |
| Routing | Decision under 1 s after a lead becomes ready (p95) |
| Push | Partner record created under 5 s after the decision (p95, excluding partner downtime) |
| Notification | Sent within 60 s of acceptance (outside quiet hours and the async delay) |
| Sync | Partner changes visible within 1 minute by webhook, or one polling interval |
| Dashboards | Data under 1 minute old; render under 2 s; lists under 1.5 s on 4G |
| Scale | 10,000 leads per day, 50 partners, 2 million partner activities per month, without redesign. One Admin user; the load comes from integrations, not people |
| Reliability | 99.9% monthly; zero lead loss (written before acknowledgement); idempotent workers that recover on restart without double-pushing or double-messaging |
| Explainability | Any routing decision, notification or commission explained from stored records |

## B20. Build phases and acceptance tests

| Phase | Builds | Exit test (all must pass) |
| --- | --- | --- |
| **0. Audit and foundations** | Inventory and verdicts (A4); dependency map of shared objects (A3); how many leads carry `consent_partner_share_at` today and which sources set it; decisions on Witty's hand-off signal, reply path and `is_bot_paused`; the `b2b` schema and moving the empty B2B tables into it; the contracts with the other five products (A5); gap report; migration plan; repository, CI, environments; design system and app shell; Admin-only auth (Google and email/password, allowlist) and RLS | Vikas approves the audit report and plan. App shell deployed to staging: connect@eduwit.in signs in as Admin with Google and with email and password (with TOTP); an uninvited account sees "Access pending"; a B2C-only user cannot open the B2B CRM |
| **1. Route, push, notify** | Master Lead Table with edit, soft delete and bulk delete, Recycle Bin, and Excel/CSV download (B6.1); Partners; Programme Repository (Excel upload and Google Sheet sync, column templates, catalogue matching, diff and routing-impact preview, publish and roll back) and rates; CPE calculation; routing engine in commission-first mode with exploration, guardrails and explanation; generic REST and webhook adapters; mock partner server; push with retries; duplicate cascade; B2C hand-off; student WhatsApp and email notifications; Leads list, lead drawer, pre-routing pool, Partners pages, basic Command Center | The Master Lead Table shows every test lead from every source with its partner, both status layers, programme, university and generation date; edits are audited; bulk delete is soft, undoable and blocked for leads with money; a 20,000-row download completes in the background. Two partner files (one Excel, one Google Sheet) with different layouts publish correctly, a removed programme stops routing at once, and a rollback restores it. Partner-sharing consent is being captured by Witty, the website agent and every ad form (otherwise every lead falls back to B2C). Then 50 test leads end to end against 3 mock partners covering: highest commission wins; exploration lane; sync and async duplicates; second duplicate → B2C; no partner offers programme → B2C; no consent → B2C; technical failure → retry → re-route; notification sent once per accepted lead, only after the hold window, and never for a partner that claimed a duplicate or rejected; a duplicate after acceptance becomes a dispute, not a re-route; a returning student is not cascaded; no message to any real number; every decision explained |
| **2. Live sync and intake** | Full mapping layer (B8.3): canonical registry, schema discovery, all mapping types including conditional and multi-pipeline, coverage gates, golden-file tests, drift detection, backfill; status and activity sync (webhook and polling); `partner_activities` and lead roll-ups; SLAs with working hours; nightly reconciliation; adapters for the first 2 real partners; Excel/CSV import; Meta and Google intake; CAPI | Each real partner reaches 100% required mapping coverage; its golden-file and round-trip tests pass; a lead driven through every partner stage and sub-stage lands on the right Eduwit stage. 2 real partners live: 10 test leads each through the partner's sandbox or test pipeline (`test_endpoint`), then real leads. Status lag within target for 7 days. Nightly reconciliation clean for 7 days. CAPI events accepted by Meta and Google test tools |
| **3. Performance routing, AI and money** | P̂ estimation, maturity, roll-ups, performance mode switch per segment, optional factors; decision logging with selection probabilities; ML training pipeline, model registry, shadow scoring; Claude optimiser in Advisory mode with simulation and the holdout; enrollments, verification, earnings, invoices, receipts, statement reconciliation, tier watch | Engine unit tests reproduce hand-computed NCPL on fixtures. Offline policy evaluation reproduces known results on synthetic data. The Claude optimiser's recommendations cite only tool-sourced numbers (validator passes) and stay inside bounds. One month of commissions matches a manual check by the Admin |
| **4. Analytics depth, autopilot and polish** | ML model as challenger then champion once its activation gate passes; Autopilot mode with automatic 7-day review and rollback; Ask the CRM; dashboard builder, metric definitions, default dashboards, alerts, scheduled reports, report builder, simulator, mobile polish | Each default dashboard's numbers match SQL spot checks. Every widget drills down to its rows. AI-steered leads beat the holdout on net commission per lead over 4 weeks before Autopilot is switched on |

**Test suite (minimum).**

- **Unit tests:** CPE for percent, fixed and tiered rates, with and without GST; median aggregation for partial interest; NCPL; mode switch; seeded exploration reproducibility; share cap; capacity; consent gate; stage rank; quiet hours; idempotent notification.
- **pgTAP tests:** every routing and money SQL function.
- **Contract tests:** one suite per adapter.
- **Mapping tests:** golden-file and round-trip tests per partner mapping (B8.3.7).
- **End-to-end:** from intake through push, sync, enrollment and verification, to the invoice.
- **Load:** 2× the scale figures.

## B21. Open decisions (defaults in force until Vikas decides)

| Decision | Default used |
| --- | --- |
| Google Sheet check interval | Every 6 hours, plus "Sync now"; changes stay as drafts until published (auto-publish off) |
| Commission in partner files | Treated as a proposal; live only after the Admin confirms it |
| AI optimiser mode | Advisory at launch. Autopilot only after AI-steered leads beat the 10% holdout for 4 weeks, and only when Vikas switches it on |
| AI holdout | 10% of eligible leads routed by the baseline policy |
| Claude models | `claude-sonnet-5` for optimisation passes, `claude-opus-5-5` for nightly and weekly reviews, `claude-haiku-4-5-20251001` for quick classification; configurable |
| ML model activation | 500 matured outcomes across at least 2 partners, beating segment P̂ on a holdout and in offline policy value |
| Exploration share while learning | 20% of a segment's leads, until each partner has 30 leads in it. Set 0 for strictly highest commission |
| Switch to performance mode | When at least 2 candidates each have 30 matured leads (allocated more than 60 days ago) in the segment |
| CPE for a lead without a university | Median across the partner's matching programmes |
| Partner attempts before B2C fallback | 2 |
| Notification sender | Eduwit's WhatsApp Business number and Eduwit's email domain. **Decide:** the same number as Witty, or a separate one |
| Witty's hand-off wording | Witty currently says "one of our Academic Counselors". **Align it** with the partner-named notification so students hear one story |
| B2C notification | The B2B CRM sends the Eduwit-branded version unless the B2C CRM takes it over |
| Quiet hours | 08:00–21:00 IST |
| Duplicate window | 24 hours |
| Optional speed and reliability factors | Off |
| First two live partners and their CRMs | To be confirmed before Phase 2 |
| GST rate, SAC code, TDS, refund windows | Confirmed by Eduwit's CA |
| Consent text covering partners and ads measurement | Approved by Eduwit's lawyer before go-live |

---

*End of prompt. Claude Code: begin with Phase 0, write the audit report to `docs/phase0-audit.md`, and stop for review.*
