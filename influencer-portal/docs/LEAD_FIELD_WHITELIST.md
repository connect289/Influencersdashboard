# Creator-visible lead fields: proposed whitelist

Status: **proposal, waiting for owner approval** (Phase 0, HARD STOP 1). Nothing is exposed until this is approved.

Source: `public.student_leads` on production `xlseqwgyjuqhktrguhyc`, read on 16 Oct 2026 (141 columns). Every column is
listed below. Nothing here is a schema change: creators get these values **only** through the `SECURITY DEFINER`
functions `inf.creator_leads(...)` / `inf.creator_lead(...)` and the creator-safe Realtime table `inf.creator_lead_feed`,
which hold only the whitelisted, already-masked values. Creators never get any grant on `student_leads`, `touchpoints`,
`w2_*`, `b2b.*` or `b2c.*`.

## How to read this

| Code | Meaning for creators and agency users |
| --- | --- |
| **SHOW** | Returned as stored (or lightly formatted) |
| **BAND** | Returned as a coarse band or label, never the raw value |
| **MASK** | Returned masked by the database (format below). Phone and email are **locked** to this and cannot be unmasked by any setting |
| **HIDE** | Never returned to creators. Staff see it according to their role |
| **ASK** | My recommendation is in the notes, but this needs the owner's decision before exposure (spec 9.3) |

The whitelist is stored in the setting `lead_visibility.creator_fields` (Section 21) so the owner can remove fields later
without code. The setting validator **refuses** to add any field marked HIDE here, and phone and email are hard-coded
as masked in the function itself, so neither a settings change nor a bug in the app can unmask them.

## Masking format (database functions `inf.mask_phone`, `inf.mask_email`)

- **Phone:** the national 10-digit number, first 2 and last 2 digits kept: `98XXXXXX21`. A number that is not 10
  digits after removing `+91`/`0` becomes `XXXXXXXXXX`. Never the country code, never more digits.
- **Email:** first character of the local part, then `****`, then the domain **only if the domain is a common public
  mailbox** (`gmail.com`, `yahoo.com`, `yahoo.co.in`, `outlook.com`, `hotmail.com`, `live.com`, `icloud.com`,
  `rediffmail.com`, `proton.me`; list in settings). Any other domain is masked too: `r****@****.in`. A college or
  employer domain can identify a person, so it is hidden by default.
- Masking is applied **inside** the definer function before the row leaves the database. The app never receives the
  raw value for a creator session, so it can't leak through the UI, exports, Realtime, logs or error messages.
- Existing helpers `crm_mask_phone` / `crm_mask_email` keep 4 leading digits and 2 email characters, which reveals more
  than the spec's example, so the portal uses its own.

## Lead identifier shown to creators

Creators never see `student_leads.id`. They see `lead_ref`: the first 10 characters of
`encode(hmac(id::text, <inf secret from Vault>, 'sha256'), 'hex')`, uppercased, shown as `L-3F9A2C71B0`. A keyed hash
can't be reversed or enumerated, unlike the internal id or the B2B view's unkeyed `sha256('b2b-ref-'||id)`.

## Column-by-column

### Identity and contact

| Column | Proposal | Notes |
| --- | --- | --- |
| `id` | HIDE | Replaced by `lead_ref` |
| `whatsapp_number` | **MASK (locked)** | `98XXXXXX21` |
| `email_id` | **MASK (locked)** | `r****@gmail.com` |
| `alternate_phone` | HIDE | A phone number. Spec masks phone; a second masked number adds no value, so it is hidden |
| `guardian_phone` | HIDE | Third party's phone number |
| `guardian_name` | HIDE | Third party's personal data; no purpose for the creator |
| `student_name` | **ASK** | Spec 9.3: "all lead information except phone and email". **Recommendation:** first name plus last initial (`Riya S.`), which lets a creator recognise a lead without building a contact list. Full name is a one-setting change |
| `name_confirmed`, `email_confirmed` | HIDE | Internal data-quality flags |
| `phone_verified_at`, `phone_verification_method`, `email_verified_at` | HIDE | Internal verification |
| `enquirer_relation` | SHOW | "self", "parent"… helps the creator understand the audience |
| `preferred_language` | SHOW | |

### Location

| Column | Proposal | Notes |
| --- | --- | --- |
| `city` | SHOW | Needed for the city/state filter in spec 9.3 |
| `state` | SHOW | |
| `country` | SHOW | |
| `current_city_country` | HIDE | Free text written by Witty; can contain addresses or other personal details. `city`/`state` cover the need |

### Interest and profile

| Column | Proposal | Notes |
| --- | --- | --- |
| `interested_course` | SHOW | Programme of interest (spec 9.3 drawer) |
| `interested_specialization` | SHOW | |
| `field_of_interest` | SHOW | |
| `interested_university` | SHOW | |
| `university_preference` | SHOW | |
| `program_level` | SHOW | UG / PG / diploma |
| `programme_segment` | SHOW | |
| `study_mode_preference` | SHOW | |
| `highest_qualification` | SHOW | |
| `current_study` | SHOW | |
| `academic_percentage_gpa` | HIDE | Free text; personal performance data with no creator purpose |
| `academic_score_pct` | **ASK** | Recommendation: HIDE (academic record is sensitive personal data) |
| `work_experience_years` | HIDE | Free text |
| `work_experience_years_num` | BAND | `0`, `1–3`, `3–5`, `5–10`, `10+` years |
| `current_job_role` | **ASK** | Recommendation: HIDE (free text, can name an employer) |
| `annual_budget` | HIDE | Free text |
| `annual_budget_inr` | **ASK** | Recommendation: HIDE (financial information). If shown, as a band |
| `enrollment_timeline` | SHOW | |
| `primary_motivation` | **ASK** | Free text from Witty. Recommendation: HIDE |
| `preferred_counseling_time` | HIDE | Operational |
| `eligibility_status` | SHOW | Shown as the mapped label (Eligible / Not eligible / Unknown) |

### Qualification signals (Witty)

| Column | Proposal | Notes |
| --- | --- | --- |
| `lead_status` | SHOW | Witty's HOT/WARM/COLD/UNQUALIFIED. Spec 9.3 asks for the HOT/WARM/COLD filter |
| `temperature` | SHOW | Lower-case copy of the same, used when `lead_status` is empty |
| `lead_classification` | HIDE | AI's raw classification; internal |
| `admission_readiness` | SHOW | Mapped label |
| `lead_stage` | HIDE | Witty's conversation phase; internal |
| `intent_type` | HIDE | Internal |
| `extraction_confidence` | HIDE | Internal |
| `lead_score`, `score_updated_at` | HIDE | Internal scoring |
| `is_sales_ready`, `sales_ready_at` | HIDE | Used only to derive the creator stage "Qualified" |

### Source and attribution (creators see their own attribution record instead)

| Column | Proposal | Notes |
| --- | --- | --- |
| `lead_source`, `channel`, `source_detail`, `campaign` | HIDE | Raw values can reveal other channels. The creator sees **their** link, content piece and campaign from `inf.lead_attributions` |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | HIDE | Same reason |
| `click_ids` | HIDE | Ad-platform identifiers |
| `landing_url`, `referrer_url` | HIDE | Can contain other parties' query strings |
| `referral_code`, `referred_by_code`, `activation_code` | HIDE | Codes of other sources; the creator sees their own code from the attribution record |
| `publisher_id` | HIDE | |
| `first_touch_at` | SHOW | Shown as "first contact" date |
| `last_touch_at`, `last_touch_source` | HIDE | Could reveal other channels |
| `ip_address`, `device`, `fingerprint` | HIDE | Personal data. Used only, hashed, for fraud checks |

### Consent and privacy

| Column | Proposal | Notes |
| --- | --- | --- |
| `consent_sales_at`, `consent_marketing_at`, `consent_partner_share_at`, `consent_text_version` | HIDE | |
| `is_opted_out`, `opted_out_at`, `opted_out_channels`, `email_bounced_at` | HIDE | |
| `anonymised_at` | HIDE | An anonymised lead is shown as `Removed at the student's request` with no other fields |
| `deleted_at`, `merged_into_id` | HIDE | Deleted leads are not returned. A merged lead shows on its surviving record |

### Pipeline (creators see the mapped creator stage, `STAGE_MAPPING.md`)

| Column | Proposal | Notes |
| --- | --- | --- |
| `stage` | BAND | Mapped to the creator-facing stage |
| `sub_stage` | HIDE | Partner and counsellor detail. The creator sees the stage and the reason category |
| `stage_changed_at` | SHOW | Drives "days in stage" |
| `lost_reason` | BAND | Mapped to a reason category (`not reachable`, `not interested`, `not eligible`, `budget`, `chose another option`, `duplicate`, `junk`) |
| `lost_at` | SHOW | |
| `cycle_no`, `reopened_at` | HIDE | Re-enquiries are shown as a new timeline entry, not as a counter |
| `is_duplicate_suspect`, `duplicate_claim_count` | HIDE | |
| `created_at` | SHOW | "Lead date" |
| `updated_at` | SHOW | "Last update" |

### Ownership and partner (internal)

| Column | Proposal | Notes |
| --- | --- | --- |
| `owner_user_id`, `team_id`, `assigned_at` | HIDE | Staff identity |
| `first_contacted_at`, `last_contacted_at`, `last_activity_at`, `contact_attempts`, `next_task_due_at` | HIDE | Counsellor performance data |
| `destination_type` | HIDE | Whether a partner or in-house team works the lead |
| `partner_id`, `allocation_id`, `allocated_at`, `allocation_reason` | HIDE | Partner identity is commercially confidential (spec 9.3). `allocated_at` drives the "Allocated" stage date only |
| `partner_record_id`, `partner_stage_raw`, `partner_sub_stage_raw`, `partner_synced_at`, `partner_stale_at` | HIDE | |
| `is_hot_sent_to_crm`, `zoho_lead_id` | HIDE | Legacy |
| `sla_alerted_at` | HIDE | |

### Application and enrollment

| Column | Proposal | Notes |
| --- | --- | --- |
| `application_id` | HIDE | Partner/university reference |
| `application_status` | BAND | Shown only as the creator stage "Applied" |
| `applied_at` | SHOW | |
| `enrolled_program` | SHOW | |
| `enrolled_university` | SHOW | |
| `enrollment_date` | SHOW | |
| `enrollment_status` | BAND | Enrolled / Cancelled (drives clawback status) |
| `enrollment_verified_at` | HIDE | Internal |
| `fee_amount_inr`, `fee_paid_inr` | **ASK** | Recommendation: HIDE. The creator's earning for that lead is shown instead (pending, accrued, confirmed, paid, clawed back). If a deal pays "% of programme fee", the creator sees the catalogue fee and their %, not the student's payment |
| `expected_net_revenue_inr`, `realised_net_revenue_inr` | HIDE | Eduwit revenue. Never shown to creators (spec 6.2) |

### Engagement and systems (internal)

| Column | Proposal | Notes |
| --- | --- | --- |
| `active_journey_id`, `last_campaign_id`, `last_marketing_message_at` | HIDE | |
| `first_agent_channel`, `chatwoot_conversation_id`, `web_session_id`, `is_bot_paused`, `last_agent_message_at` | HIDE | |
| `portal_user_id`, `open_ticket_count` | HIDE | |
| `Comments` | HIDE | Internal notes (spec 9.3 names these) |
| `custom_fields` | HIDE | Free-form; may hold anything |
| `updated_by` | HIDE | |
| `is_test` | HIDE | Test leads are shown only to creators flagged `is_test` (for demos and Playwright) |

## What a creator gets per lead (if approved as recommended)

`lead_ref`, display name (`Riya S.`), masked phone, masked email, city, state, country, preferred language, enquirer
relation, programme of interest (course, specialization, field, university, level, segment, mode), highest qualification,
current study, enrollment timeline, eligibility label, readiness label, HOT/WARM/COLD, experience band, creator stage,
reason category, stage timeline with days in each stage, first contact date, applied date, enrolled programme,
university and date, and from the portal's own tables: the tracking link, content piece, campaign, deal, attribution
status and reason, and the earning status for that lead.

## Exports

CSV exports for creators call the same function, so they carry the same fields and the same masking. Staff exports
follow the staff role (Super Admin and Influencer Manager see contacts only on the Creator 360° page and the staff
lead pipeline, spec 7).

## Open decisions for the owner

1. `student_name`: full name, or first name plus last initial (recommended)?
2. `academic_score_pct`, `current_job_role`, `annual_budget_inr`, `primary_motivation`, `fee_amount_inr`/`fee_paid_inr`:
   hide (recommended) or show?
3. Partner and university names before enrollment: hidden (recommended; spec 9.3 says "partner names if confidential").
   The enrolled university is shown once enrolled.
