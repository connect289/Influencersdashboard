# B2B CRM — Addendum 4: the B2C CRM link, final shape

Version 14 October 2026 · Owner: Vikas Jha · Applies to `docs/B2B_CRM_PROMPT.md`, Addenda 1–3 and `docs/b2c-contract.md` (v3)

> **For Claude Code (B2B CRM):** save as `docs/B2B_CRM_ADDENDUM_4.md`. It changes how the B2B CRM exchanges data with the
> B2C CRM, which is now specified in `b2c-crm/docs/B2C_CRM_PROMPT.md` (final, 14 Oct) and audited in
> `b2c-crm/docs/phase0-audit.md`. Where this addendum and the contract differ, this addendum wins. Publish the result as
> **contract version 4** (`contract_version: 4` on every `b2c.*` / `b2b.*` envelope and record), with a "What changed in
> version 4" list at the top of `docs/b2c-contract.md`, like version 3's.
>
> Work the usual way: plan first, staging first, pgTAP inside `begin … rollback`, then production only with Vikas's
> approval per step. Every rule in `b2b-crm/README.md` still holds (no `DROP` in migrations, `search_path`, `(select
> b2b.is_admin())` in policies, settings only through `b2b.set_setting`, triggers on `student_leads` only enqueue). Do not
> change Witty's `w2_*` objects, `lead_intake()` or the n8n workflows.

## Decisions behind this addendum (Vikas, 14 October)

1. **B2B → B2C is real time, always.** Every hand-off, re-enquiry, consent request and every change to a lead B2C holds
   reaches the B2C CRM within seconds. The 15-minute batched delivery is not used for the B2C CRM.
2. **B2C → B2B is every 15 minutes.** The B2C CRM's activity (assignments, stages, field changes, calls, messages,
   notes, applications, enrolments, scores) reaches the B2B CRM, and through it `student_leads`, in one batch every
   15 minutes. Five things are sent at once because a delay would break a rule: the consent request send, the consent
   answer, an opt-out, an erasure request, and the Admin's route-to-partners. New students go through the Intake API at
   once.
3. **The B2C CRM keeps the records B2B pushes as a read-only cache** (contract §2, unchanged). It never reads
   `student_leads` or `b2b.*` directly. It does read, in the same Supabase project, Witty's transcripts (through its own
   `SECURITY DEFINER` function) and the shared `catalog` views (section 6).
4. **Re-engagement is the B2C CRM's decision.** It assigns a counsellor on its own triggers (B2C spec B6.3: Witty
   interest, positive reply, new enquiry, score rising to 60 after entering the pool). The `reactivation` flag on
   `b2c.lead_reenquired` stays as a hint.
5. **Counsellors work in Eduwit's own stages** (New Lead … Enrolled, Lost, ten in all, each with sub-stages and a comment), mapped to
   the canonical `stage`. The Master Lead Table shows both.

## 1. Real-time delivery to the B2C CRM

- Make `b2c_link.delivery = 'realtime'` the only mode for the B2C endpoint: remove the "Every 15 minutes" choice from
  **B2C CRM link** (or show it disabled with "B2C needs real time: Addendum 4"). Keep `b2b.b2c_batch_tick` and
  `b2c.leads_batch` in the code for other products, but never deliver `b2c.leads_batch` to the B2C endpoint.
- `GET /v1/b2c/schema` keeps returning `delivery: "realtime"`.
- **Echo suppression.** Do not deliver `b2c.lead_upserted` to the B2C endpoint when its only origin is the B2C CRM's own
  write (`origin` starts with `b2c:`). The B2C CRM learns the new version from the batch answer. Keep these entries in
  the change feed (`GET /v1/b2c/leads?after=`) as today. Any change by someone else (Witty, intake, the engine, the
  Admin, a partner event) is still delivered at once.
- Target: a change to a B2C-held lead is delivered within 5 seconds (p95), measured on **B2C CRM link**.

## 2. Accepting the 15-minute batch

The B2C CRM sends `POST /v1/b2c/leads/batch` every 15 minutes, in as many calls as it needs (each ≤ 200 items, ≤ 1 MB),
with **at most one `update` item per lead per batch** (it merges a lead's changes before sending) plus any number of
`activity` items.

Changes:

1. **`occurred_at` on every item.** Accept `occurred_at` (ISO 8601) on `update` items, the time the counsellor made the
   change. Use it for `stage_changed_at` (when the item changes `stage` and does not send `stage_changed_at`), for field
   history, and in the timeline, instead of the time the batch arrived. Activities already carry `at`; keep using it.
2. **Contact roll-ups from activity time.** `first_contacted_at` is the minimum and `last_contacted_at` the maximum of the
   contact activities' `at`, whatever order they arrive in; `contact_attempts` counts distinct activity `request_id`s.
   A late batch must never move `last_contacted_at` backwards.
3. **Stale-version rule for batched updates.** Batched items normally carry no `if_version` (15 minutes is long enough
   for Witty to touch the lead in between). Field-level last-write-wins is correct here because B2C only sends the
   fields it changed. Keep `if_version` support for the few items that send it.
4. **Order inside a call.** Apply items in the order given (the B2C CRM orders by `occurred_at`).
5. **Answer.** Keep the per-item answer; add the new `version` of each lead to `update` items (already there) and to
   `activity` items.
6. **Rate.** Allow at least 20 batch calls per minute per key, so a backlog after an outage clears quickly.

Immediate calls stay as they are: `POST /v1/events/b2ccrm` (`consent_request_sent`, `partner_consent`, `opted_out`,
`erasure_requested`), `POST /v1/leads/{id}/route-to-partners`, `POST /v1/leads`.

## 3. New writable fields

Add to `b2b.b2c_fields()` as B2C-writable, mapped to the existing `student_leads` columns (no new columns), and include
them in the record:

| Group | Field | Column | Notes |
| --- | --- | --- | --- |
| `marketing` (new group) | `active_journey_id` | `active_journey_id` | B2C journey id |
| `marketing` | `last_campaign_id` | `last_campaign_id` | |
| `marketing` | `last_marketing_message_at` | `last_marketing_message_at` | |
| `marketing` | `email_bounced_at` | `email_bounced_at` | |
| `enrolment` | `enrollment_verified_at` | `enrollment_verified_at` | Set when the B2C Admin verifies the proof |
| `pipeline` | `b2c_stage` | `custom_fields.b2c.stage` | Eduwit stage name, e.g. "Program Details Explained" (≤ 60) |
| `pipeline` | `b2c_sub_stage` | `custom_fields.b2c.sub_stage` | ≤ 120 |
| `pipeline` | `b2c_stage_comment` | `custom_fields.b2c.stage_comment` | ≤ 1,000 |
| `pipeline` | `owner_name` | `custom_fields.b2c.owner_name` | The counsellor's display name; `owner_user_id` is a B2C user id the B2B CRM cannot resolve |

Keep `custom_fields.b2c` out of the generic `custom_fields` merge so a B2C write of `custom_fields` cannot wipe it, and
refuse `custom_fields.b2c` keys sent through `custom_fields` (use the named fields).

**Master Lead Table:** for B2C-held leads show the Eduwit stage and sub-stage next to the canonical stage, the
counsellor's name, and the comment in the drawer.

## 4. New inbound events (`POST /v1/events/b2ccrm`)

| Type | `data` | What B2B does |
| --- | --- | --- |
| `b2ccrm.marketing_consent` | `lead_id`, `channel` (`whatsapp`, `email`), `given` (true/false), `text`, `text_version`, `source` (e.g. `wa_button`, `web_form`, `counsellor_call`), `at` | Sets or clears `consent_marketing_at` (any channel given → set; record the per-channel state in `custom_fields.b2c.marketing_consent`), audits it, emits `b2c.lead_upserted` |
| `b2ccrm.opted_out` (extended) | add optional `channels` (`["whatsapp"]`, `["email"]`; omitted = all) | Writes `opted_out_channels`; sets `is_opted_out` and `opted_out_at` only when all channels are out. The partner alert stays for an all-channel opt-out |
| `b2ccrm.contact_added` | `lead_id`, `kind` (`phone`, `email`), `value`, `label` (alternate, parent, office, whatsapp_only), `primary_for` ([]) , `actor` | Normalise; record in a new `b2b.lead_contacts` (lead, kind, value, label, origin `b2c`, added_at); fill `alternate_phone` if empty; **include these numbers and emails in duplicate detection and in `GET /v1/b2c/leads?phone=`**. Never changes `whatsapp_number` or `email_id` |
| `b2ccrm.stage_changed` (extended) | add `b2c_stage`, `b2c_sub_stage`, `comment`, `canonical_stage` | Timeline only (the fields themselves arrive by batch) |

Also accept and store (timeline only) `b2ccrm.lead_updated` and `b2ccrm.commission_booked`, so the B2C spec's event list
is not refused; the data itself travels in the batch.

All are idempotent on `event_id`, signed as today, and listed on **System health**.

## 5. Reads the B2C CRM needs

1. **Lookup of a lead outside B2C's scope** (`GET /v1/b2c/leads?phone=` / `?email=`): for a match with
   `held_by_b2c: false`, add `holder`: `{ destination: "partner" | "unrouted" | "not_passed", partner_name, since }`
   (no personal data). The B2C CRM shows "Already with {partner} since {date}" when a counsellor tries to add an
   existing student (B2C spec B4.3).
2. **Partner history** of a partner-lost lead: `GET /v1/b2c/leads/{id}/partner-history` →
   `[{ partner_name, kind, outcome, at, note? }]` from `b2b.partner_activities` (no partner counsellor names), plus the
   last raw status and sub-status. Only for leads B2C holds.
3. **Consent text check.** `GET /v1/b2c/schema` returns the registered consent texts (`text_version`, exact sentence),
   so the B2C CRM can refuse to send a template whose wording differs.

## 6. The shared `catalog` schema

The B2C CRM's Programme page and its counsellor-commission rule (the counsellor owes Eduwit the **highest partner
commission** for the programme) read the catalogue the B2B CRM maintains. Create, with Vikas's approval for the new
schema:

| Object | Contents |
| --- | --- |
| schema `catalog` | Read-only views only. Owner: the B2B CRM. Nothing in `public.catalog_*` moves; Witty is unaffected |
| `catalog.programmes_v` | One row per live programme: id, university id and name, programme name, specialization, level, mode, duration, eligibility (min qualification, min %), fees (per year, per semester, total, exam, registration), EMI available and typical EMI, scholarship notes, intakes and deadlines, accreditation, brochure URL, `offered_by_partner_count`, `updated_at` |
| `catalog.universities_v`, `catalog.synonyms_v` | Over the existing tables |
| `catalog.partner_rates_v` | One row per partner offer: partner id and name, university, programme (null for a university-wide rate), rate type (percent, fixed, tiered), value, fee base, tier table and current tier, valid from, valid to, and `is_highest_for_programme` / `is_highest_for_university` |
| `catalog.changes` | Append-only `(id, at, kind, ref_id)` written whenever a programme version is published or a rate changes, so the B2C cache refreshes |
| Grants | `select` on all of it to a new role `b2c_app` (the B2C CRM's database role). `partner_rates_v` is read by the B2C server for Admin and Marketing screens and for commission; the B2C CRM never shows it to counsellors |

Also create the role `b2c_app` (no login; the B2C app uses it through a server-side connection), with **no** grant on
`public.student_leads`, `b2b.*` or `w2_*` beyond what the B2C CRM's own `SECURITY DEFINER` functions need.

## 7. Reading what the B2C CRM publishes

The B2C CRM will publish (its Phase 3) `public.b2c_enrollment_money_v` (lead id, enrolment, university commission gross,
GST, net, status, invoice, counsellor commission total) and `public.b2c_lead_status_v` (lead id, Eduwit stage, sub-stage,
counsellor name, lane). When they exist:

- the Master Lead Table's money columns read `b2c_enrollment_money_v` for B2C-held enrolments (Addendum 1 §5);
- the referral view (`b2b_referral_outcomes`) uses `b2c_lead_status_v` for B2C-held leads, still masked.

Build the read side behind a check that the views exist, so nothing breaks before Phase 3.

## 8. Re-engagement and Witty

- `b2c.lead_reenquired`: keep `interest` and `reactivation`; document `reactivation` as a hint. The B2C CRM decides.
- **Witty interest signal** (Addendum 1 §4b) is still a Witty change and is **not** part of this addendum. When Witty
  records it (proposed: a `touchpoints` row `event_type = 'lead.interest'` with `{intent}`), forward it to the B2C CRM as
  `b2c.lead_reenquired` with `interest: true` and `what.intent`, in real time.
- `w2_crm_owned()` stopping Witty for B2C nurture leads stays open as a Witty change (stop only when `owner_user_id` is
  set). Note: with the 15-minute B2C batch, `owner_user_id` reaches `student_leads` up to 15 minutes after assignment.

## 9. Not changing

- Hand-off reasons, lanes, holds, the partner bar, consent requests and their flow (contract v3 §1) are unchanged.
  The B2C CRM routes every sales-lane hand-off through its own allocation engine and uses `handling` as a hint.
- `POST /v1/leads/{id}/route-to-partners` and its error codes are unchanged.
- The B2C CRM never writes `whatsapp_number`, `email_id`, consent columns, source columns or allocation columns.

## 10. Tests (staging, with the mock B2C endpoint)

1. A Witty update to a B2C-held test lead reaches the B2C endpoint within 5 s; switching **B2C CRM link** to batched is not
   possible.
2. A B2C batch of 150 updates and 300 activities is applied; no `b2c.lead_upserted` echo is delivered for them; the
   feed lists them.
3. An `update` with `occurred_at` 14 minutes ago sets `stage_changed_at` to that time; a later-arriving activity with an
   older `at` does not move `last_contacted_at` backwards; `contact_attempts` counts each activity once across retries.
4. `b2c_stage`, `b2c_sub_stage`, `b2c_stage_comment`, `owner_name` are written, shown on the Master Lead Table, and
   survive a B2C write of `custom_fields`.
5. `b2ccrm.marketing_consent` (WhatsApp given) sets `consent_marketing_at`; `b2ccrm.opted_out` with
   `channels: ["email"]` leaves `is_opted_out` false and `opted_out_channels = {email}`.
6. `b2ccrm.contact_added` with a second phone makes `GET /v1/b2c/leads?phone=<that number>` find the lead, and a new
   intake with that number is treated as the same student.
7. Lookup of a partner-held student answers `holder.partner_name` and `since`, and no personal data.
8. `GET /v1/b2c/leads/{id}/partner-history` returns the partner's activities for a partner-lost lead and 404 for a lead
   B2C does not hold.
9. `catalog.partner_rates_v` marks the highest rate for a programme offered by two partners; `b2c_app` can read it and
   cannot read `student_leads`.
10. Every new envelope and record carries `contract_version: 4`; `GET /v1/b2c/schema` lists the new fields, groups and
    event types.
