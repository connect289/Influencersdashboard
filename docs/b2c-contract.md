# Eduwit B2B CRM ↔ B2C CRM: integration contract (version 3)

The B2B CRM is Eduwit's lead allocation engine. Every lead enters through it, and it decides where the lead goes: to a
partner university's CRM, or to Eduwit's own B2C CRM (in-house counsellors). The rules behind it are in
`B2B_CRM_ADDENDUM_3.md` (the final routing rules R1–R9, the partner bar, consent, the lost grace) on top of
`B2B_CRM_ADDENDUM_1.md` §1–4.

**Version 2 (7 Oct 2026): the B2B CRM is the only gateway to the lead table.** The B2C CRM never reads or writes
`public.student_leads` (or any `b2b.*` table) directly. Instead:
- it keeps its own copy of the leads it works, kept current in real time by signed webhooks (§1) and rebuildable at any
  time from the change feed (§2);
- it writes its counsellors' work back through the API (§3): stage, owner, contact, application, enrolment and lost
  fields, plus calls, messages and notes;
- its own tables (users, teams, tasks, notes, templates…) stay its own.

**Version 3 (7 Oct 2026, Addendum 3): one schema, `contract_version: 3` on every `b2c.*` envelope and on the record.**
What changed for you:
- partners get the bulk of the leads; B2C is the fallback. The hand-off tells you **why** (reason by lane, §1.1) and **how
  to handle it** (`handling`: job, assignment, first-contact script);
- the **permanent partner bar** (`partner_bar`): duplicate-cascade and partner-lost leads can never go to a partner again,
  not even by your route-to-partners call (422 `partner_barred`);
- the **"Already with other providers" badge** (`already_with_providers`) with the dates the partners first had the student;
- **qualification nurture** (`not_qualified`, `consent_no_answer`): your job is only to complete the missing details; the
  lead returns to partner routing as soon as it qualifies (`b2c.lead_requalified`); a re-engaged but still unqualified lead
  comes as `b2c.lead_reengaged`;
- the **explore-programmes welcome** (`b2c_actions: ["welcome_explore_programmes"]`): send the student a WhatsApp message
  from the B2C number prompting them to explore programmes (Amendment 1.2);
- **partner-sharing consent** (R8): `b2c.consent_requested` asks you to send the one-tap request; you report the send and
  the answer back (`b2ccrm.consent_request_sent`, `b2ccrm.partner_consent`); `b2c.consent_closed` closes the loop;
- **partner_lost** arrives only after the 7-day grace, unassigned, with `previous_owner` and the first nurture message delay;
- `paid_campaign` is retired (paid is an attribution label only); `no_partner_consent` means the student said **NO**;
- the record (§2.1) carries the same facts: bar, providers, hold, handling, qualification class and missing details,
  consent state and request, and the student's other courses (which you may write);
- scope *all* (§2.4) no longer carries Not passed leads or test leads.

This document is everything the B2C CRM's developer needs. The Admin follows the connection on **B2C CRM link** (`/b2c`).
`GET /v1/b2c/schema` (§3.7) returns every vocabulary below as data, so build your enums from it.

Base URL of the B2B CRM: `https://<b2b-crm-host>` (the Vercel production domain). All bodies are JSON in UTF-8.

## 0. What you receive from the Eduwit Admin

Both come once, through a secure channel (never by chat or plain email), from **System health → Webhooks and API keys**:

| Item | Looks like | Used for |
| --- | --- | --- |
| **Signing secret** of your webhook endpoint | `whsec_…` (54 characters) | Verifying the webhooks we send you, and signing the events you send us |
| **API key** with the scopes *B2C CRM link* (`b2c`), *Product integrations* (`events`) and *Lead intake* (`intake`) | `eb2b_…` | `b2c`: the lead API in §2–3. `events`: `GET /v1/handoffs` and `POST /v1/leads/{id}/route-to-partners`. `intake`: `POST /v1/leads` |

Give the Admin the HTTPS URL that should receive webhooks. The Admin registers it, sends a test event, and switches it on
once you confirm your signature check passes. Nothing is delivered before that, so use `GET /v1/handoffs` to catch up on
anything that happened earlier. **Routing cannot go live until your endpoint subscribes to `b2c.lead_handed_off` and
`b2c.consent_requested`** (the Admin's go-live gate), so subscribe to `b2c.*` and `b2b.*`.

If a secret or key leaks, the Admin replaces it on the same screen; the old one stops working at once.

## 1. Webhooks: B2B → B2C

`POST <your URL>`, one event per request.

**Headers**

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `X-Eduwit-Event` | The event type, e.g. `b2c.lead_handed_off` |
| `X-Eduwit-Delivery` | Our delivery number (for support) |
| `X-Eduwit-Timestamp` | Unix seconds when this attempt was sent |
| `X-Eduwit-Signature` | `sha256=` + hex HMAC-SHA256 of `<timestamp>.<raw body>` with your signing secret |
| `Idempotency-Key` | `<endpoint id>:<envelope id>`. The same on every retry of the same event |

**Verify every request** before using it: compute the HMAC over the exact raw bytes of the body (not a re-serialised
copy), compare in constant time, and refuse timestamps more than 5 minutes from your clock.

```js
import crypto from "node:crypto";
function verify(rawBody, timestamp, signature, secret) {
  if (!/^\d+$/.test(timestamp) || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const expected = "sha256=" + crypto.createHmac("sha256", secret).update(`${timestamp}.${rawBody}`, "utf8").digest("hex");
  return signature.length === expected.length && crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}
```

**Answer** `2xx` within 10 seconds once you have stored the event (do the work afterwards). Anything else, or no answer,
is retried after 30 s, 2 min, 10 min, 30 min, 1 h, 3 h and 6 h; after 8 attempts the delivery is given up and the Admin
is alerted. Retries carry the same envelope `id` and `Idempotency-Key`: **process each `id` once**. Order is not
guaranteed across retries; use `occurred_at` and the lead's current state.

**Envelope** (every event)

```json
{
  "id": "evt_6460",
  "type": "b2c.lead_handed_off",
  "occurred_at": "2026-10-06T19:45:53.465+00:00",
  "lead_id": 949,
  "test": false,
  "contract_version": 3,
  "data": { }
}
```

`lead_id` is the `student_leads.id` you share with us. `test: true` marks Eduwit test leads (phones starting `910000`
or `9190000000`); keep them out of counsellor queues and reports. `contract_version` is present on every `b2c.*` and
`b2b.*` envelope (3). `data` always carries `allocation_id`, `reference` (`EDW-…`), `partner_id` and `b2c_lane` when the
event has them.

### Events

| Type | When | `data` |
| --- | --- | --- |
| `b2c.lead_upserted` | A lead in your scope was created or changed, by anyone (Witty, the engine, a partner event, the Admin, your own write) | `version`, `seq`, `origin`, `record` (§2.1). **Store it if `version` is higher than your copy's** |
| `b2c.lead_released` | A lead left your scope: deleted, merged, anonymised, became Not passed, or (scope *held*) went to a partner | `version`, `seq`, `record` (only `id`, `held_by_b2c: false`, `deleted`, `merged_into_id`, `allocation`). Close your pipeline for it and keep only what your records need |
| `b2c.leads_batch` | Production cadence only (see *Sync cadence* below): every lead that changed since the last batch, once, at its newest version, up to 100 per call | `from_seq`, `to_seq`, `part`, `leads`: a list of `{ type, lead_id, version, seq, changed_at, origin, record }` exactly as in the change feed (§2.3). Apply each entry like a single webhook |
| `b2c.lead_handed_off` | The engine gives a lead to B2C | §1.2: `b2c_lane`, `reason`, `cause`, `handling`, `hold`, `partner_bar`, `already_with_providers`, `partners_tried`, `missing`, `b2c_actions`, `welcome`, `consent`, `lost`, `nurture_first_message_after_days`, `nurture_first_message_at`, `interests_tried`, `attribution`, `paid`, `reference`, `allocation_id`, `decision_id`, `test` |
| `b2c.lead_reenquired` | A lead you hold (R4 selling hold, or partner-barred) enquires again: a new Meta or Google form, Witty again, a new inbound message. It stays yours; no counsellor action is forced | `b2c_lane`, `reason` (the original hand-off reason), `hold`, `partner_bar`, `cycle_no`, `what` {`source_system`, `source`, `event_type`, `campaign`, `attribution`, `at`, `ref`}, `interest` (the student showed explicit interest), `reactivation` (a `partner_lost` lead showing interest or a score of 60+: assign a counsellor by round robin, PART 6.1) |
| `b2c.lead_requalified` | A lead in your qualification nurture became qualified and went back through the routing rules (R7 → R9). **Close your nurture pipeline for it**; if it ends with you again a new `b2c.lead_handed_off` follows | `closed_allocation_id`, `reference`, `decision_id`, `destination` (`partner`, `in_house`, `consent_requested`…), `reason`, `b2c_lane` |
| `b2c.lead_reengaged` | A lead in your qualification nurture re-engaged (Witty, a reply, a new form) but is still unqualified. At most once a day per lead. A counsellor may help qualify by phone; what is still missing is listed | `allocation_id`, `engaged_at`, `source`, `missing` [codes] |
| `b2c.consent_requested` | The engine needs the student's partner-sharing consent and asks you to send the one-tap request from the B2C number (§1.3) | `request_id`, `context` (`decision`, `nurture`, `admin`), `programme`, `text` (the sentence to send, programme filled in), `text_version` (`wa_partner_consent:v1`), `channel` (`b2c_crm`), `expires_at`, `student` {`name`, `phone`, `preferred_language`} |
| `b2c.consent_closed` | A consent request ended | `request_id`, `context`, `status` (`answered`, `expired`, `cancelled`), `answer` (`yes`, `no`, null), `answered_at`, `source`, `closed_at`, `why` |
| `b2c.lead_flagged` | A lead you hold needs attention (e.g. its classification changed) | `classification`, `allocation_id` |
| `b2c.lead_close_agreed` | A partner agreed it no longer works a lead you now hold | `classification` |
| `b2b.lead_routed_to_partner` | A lead you sent to partners (§3.2), or a requalified nurture lead, was accepted by a partner. **Close your pipeline for it** | `allocation_id`, `reference`, `partner_id`, `origin` (`to_partners`, `requalify`) |
| `ping` | The Admin pressed *Send test* | `{}`, with `test: true` |

Other subscribable types (`lead.allocated`, `lead.accepted`, `lead.status_changed`, `lead.enrolled`) cover every lead,
including partner-held ones; the B2C endpoint does not need them.

**What B2B does not do for B2C leads:** it sends the student no message except the consent request through you (§1.3) and
the partner acceptance notice when a lead you routed is accepted; you message students from your own number. It writes
none of the pipeline columns while you hold the lead.

### 1.1 Reasons, lanes and handling

Every `b2c.lead_handed_off` names a `reason` and a `b2c_lane`, and `handling` tells you what to do. `job` is what the
hand-off is for, `assignment` how to staff it, `first_contact_script` which opening to use.

| `b2c_lane` | `reason` | Why the lead is with you | `handling.job` | `handling.assignment` | script |
| --- | --- | --- | --- | --- | --- |
| sales | `b2c_created` | Created in the B2C CRM (walk-in, call, your WhatsApp number): recorded only (R6) | sell | counsellor_choice | standard |
| sales | `duplicate_cascade` | Two proof-backed duplicate claims by partners, or one with no other eligible partner (PART 5.4). **Partner-barred for ever** (`partner_bar.reason = duplicate`) | sell | **round_robin_now** (assign at once) | **neutral_adviser** ("Eduwit can help you compare options"; see `already_with_providers`) |
| sales | `partner_barred` | A barred student came back as a new lead (R2) | sell | round_robin_now | neutral_adviser if the bar is `duplicate`, else standard |
| sales | `no_partner_consent` | The student explicitly said **NO** to sharing with partners (R8) | sell | counsellor_choice | standard |
| sales | `no_partner_offers_programme` | No live partner offers any of the student's interests | sell | counsellor_choice | standard |
| sales | `no_capacity` (+ `cause`) | Partners offer it but none is eligible now: `cause` caps, paused, criteria, rule, duplicate_history | sell | counsellor_choice | standard |
| sales | `partners_unreachable` | 3 partners tried, or every eligible partner failed technically (PART 5.7) | sell | counsellor_choice | standard |
| sales | `partner_attempts_exhausted` | 2 duplicate-or-rejection attempts (PART 5.7) | sell | counsellor_choice | standard |
| sales | `manual_route_failed` (+ `cause`) | Your route-to-partners call (§3.2) or the Admin's manual route found no partner; `cause` says why. **Return it to its previous counsellor** (`handling.previous_owner`) | sell | **previous_counsellor** | standard |
| sales | `b2c_held` | A lead you already held (R4) was decided again and stays with you | sell | counsellor_choice | standard |
| sales / nurture | `rule` | An Admin routing rule sent it to B2C (the lane is the rule's) | sell / nurture | counsellor_choice | standard |
| sales / nurture | `import_choice` | An Excel/CSV import chose B2C | sell / nurture | counsellor_choice | standard |
| sales / nurture | `manual` | The Admin moved it from a partner to B2C (not barred: the Admin may route it to partners again) | sell / nurture | counsellor_choice | standard |
| nurture | `not_qualified` | Qualification nurture (R7): a detail is missing (`missing`). Get the details; the moment the lead qualifies it returns to partner routing (`b2c.lead_requalified`). Witty keeps chatting with it | **qualify** | unassigned | standard |
| nurture | `consent_no_answer` | Qualification nurture (R8): no answer to the consent request in 48 hours; `missing: ["partner_consent"]`. Repeat the request in your journeys; a later YES sends the lead to partners | **qualify** | unassigned | standard |
| nurture | `partner_lost` | A partner marked the lead lost and the 7-day grace ended (PART 6.1). **Partner-barred for ever** (`partner_bar.reason = lost`), unassigned; the first nurture message waits `nurture_first_message_after_days` (3–90 by the lost reason). Assign a counsellor (round robin) only on `b2c.lead_reenquired` with `reactivation: true` | **nurture** | **unassigned_until_interest** | standard |
| sales | `test_handoff` | The Admin sent a test lead to you for testing (§6); `test: true` | sell | counsellor_choice | standard |

`paid_campaign` is no longer produced: paid Meta/Google leads go to partners like any qualified lead; `attribution` and
`paid` are labels only.

**Holds** (`hold`, also on the record): `kind` `barred` (never to partners), `selling` (R4: stays with you until the Admin
or your route-to-partners call moves it), `qualification_nurture` (returns to routing on its own once qualified). `open`
says whether the hold is the lead's current allocation.

### 1.2 The `b2c.lead_handed_off` payload

```json
{
  "lead_id": 949, "allocation_id": 5501, "reference": "EDW-5501", "decision_id": 8812, "contract_version": 3,
  "b2c_lane": "sales", "reason": "duplicate_cascade", "cause": null,
  "hold": { "kind": "barred", "open": true, "allocation_id": 5501, "lane": "sales", "reason": "duplicate_cascade", "owner_assigned": false },
  "handling": { "job": "sell", "assignment": "round_robin_now", "first_contact_script": "neutral_adviser",
                "nurture_first_message_after_days": null, "previous_owner": null },
  "partner_bar": { "reason": "duplicate", "barred_at": "…", "lead_id": 949, "allocation_id": 5501, "providers": [ ], "set_by": "engine", "via": "lead" },
  "already_with_providers": [
    { "partner_id": 20, "partner_name": "Down Edu", "first_had_at": "2026-08-28T00:00:00+00:00", "existing_record_id": "LS-77001", "claimed_at": "…" },
    { "partner_id": 21, "partner_name": "Sync Edu", "first_had_at": null, "existing_record_id": null, "claimed_at": "…" } ],
  "partners_tried": [ { "partner_id": 20, "partner_name": "Down Edu", "status": "duplicate", "outcome": "duplicate", "at": "…" }, { "partner_id": 21, "…": "…" } ],
  "missing": [], "b2c_actions": [], "welcome": null,
  "consent": null, "lost": null,
  "nurture_first_message_after_days": null, "nurture_first_message_at": null,
  "interests_tried": [ { "rank": 1, "course_key": "mba", "course_text": "MBA", "segment": "mba|PG|Online", "outcome": "routed" } ],
  "attribution": { "paid": true, "platform": "meta", "signal": "meta_lead_form", "label": "Meta Lead Ads", "campaign_id": "120210001", "origin": "meta_lead_form" },
  "paid": "Meta Lead Ads", "test": false
}
```

| Field | Meaning |
| --- | --- |
| `reason`, `cause`, `b2c_lane`, `handling` | §1.1. `handling.previous_owner` is your counsellor's `owner_user_id` for `manual_route_failed` and the owner cleared by `partner_lost` |
| `hold` | The hold this hand-off opens (`kind`, `open`, `lane`, `reason`, `owner_assigned`) |
| `partner_bar` | null, or `{reason: duplicate \| lost, barred_at, providers, set_by, via}`. **Show it as a badge; hide your route-to-partners action** |
| `already_with_providers` | PART 5.4 badge: the partners that proved the student was already their lead, oldest claim first. `first_had_at` is the date the partner first had the student (`null` = date not given); `existing_record_id` their record id |
| `partners_tried` | Every partner tried in this enquiry before the hand-off, with its outcome |
| `missing` | Codes of what qualification still needs: `no_name`, `no_email`, `no_course`, `witty_unconfirmed`, `no_valid_contact`, `phone_not_verified`, `partner_consent`. Empty for selling hand-offs |
| `b2c_actions`, `welcome` | `["welcome_explore_programmes"]` asks you to send the explore-programmes WhatsApp (Amendment 1.2): every `not_qualified` hand-off of a Witty lead (or of every lead when the Admin switches it on). `welcome` = `{template_hint: "explore_programmes", last_inbound_at}`. **A message from the B2C number needs a Meta-approved template** (free-form only within 24 h of the student's last message, and only from the number they wrote to) |
| `consent` | null, or `{request_id, status, requested_at, expires_at, refused_at}`: the consent request of this enquiry (`no_partner_consent`, `consent_no_answer`) |
| `lost` | `partner_lost` only: `{partner_id, partner_name, partner_record_id, lost_reason, lost_at, grace_ended_at, partner_status, partner_sub_status, partner_last_activity}` |
| `nurture_first_message_after_days`, `nurture_first_message_at` | `partner_lost` only: when your first nurture message may go out (3–90 days by the lost reason; Admin setting) |
| `interests_tried` | The student's interests (primary first, then other courses) and what happened to each: `offered`, `no_offer`, `routed` |
| `attribution`, `paid` | Paid attribution (Meta/Google only): `{paid, platform, signal, label, campaign_id, origin}`; `paid` is the label or null. No routing effect |
| `test` | Test lead |

### 1.3 Partner-sharing consent (R8, PART 7)

A qualified lead without recorded partner-sharing consent is **asked** before it can go to a partner. Witty leads are asked
by Witty; every other lead is asked through you:

1. You receive `b2c.consent_requested` with `text` (PART 7.2: *"To connect you with the best admission counsellor for
   {{programme}}, may we share your details with our admission partner? Reply YES or NO."*), `text_version`, `expires_at`
   (48 hours from the request) and the student's number. Send it **from the B2C number with a Meta-approved template**
   (`wa_partner_consent:v1`), then report the send: `b2ccrm.consent_request_sent` `{request_id, sent_at, message_id}` (§4).
   The 48 hours then count from your send.
2. When the student answers, report `b2ccrm.partner_consent` `{lead_id, request_id, answer: "yes" | "no", answered_at,
   channel: "whatsapp", message_id, text_version}` (§4). **A YES must carry the student's WhatsApp `message_id`** (the
   evidence); without it the answer is refused (422).
   - YES: consent is recorded under `wa_partner_consent:v1` and the lead goes through the routing rules (normally to a
     partner: `b2b.lead_routed_to_partner`, or a `b2c.lead_handed_off` if partners fail).
   - NO: the lead is yours, `b2c.lead_handed_off` with `reason: no_partner_consent`.
   - No answer in 48 hours: `b2c.consent_closed` (`expired`) and a `b2c.lead_handed_off` with `reason: consent_no_answer`
     (qualification nurture). Repeat the request in your journeys; a later YES reported the same way requalifies the lead.
3. `b2c.consent_closed` tells you the request ended (`answered`, `expired`, `cancelled`). A request is cancelled when the
   consent arrived another way (a form, Witty), when the lead went to a partner, or when the student opted out.

The Admin can also record an answer given on a call (with written evidence); you then see `b2c.consent_closed` with
`source: admin`. Requests are rate-limited per hour; a request may stay `queued` for a few minutes before you receive it.

### Sync cadence

To keep paid API calls down, a connection runs in real time only while it is being integrated and tested:

| Mode | When | What you receive |
| --- | --- | --- |
| **Real time** (default) | Integration and testing | One `b2c.lead_upserted` / `b2c.lead_released` per change, within seconds |
| **Every 15 minutes** (production) | After the Admin switches it on B2C CRM link, once you have tested end to end | One `b2c.leads_batch` per interval, with every changed lead at its newest version. Test leads still come one by one in real time, so you can keep testing |

The interval is 15 minutes by default; the Admin can set 5 to 60. `GET /v1/b2c/schema` tells you the current `delivery` and
`interval_minutes`. Hand-offs, re-enquiries, consent and requalification events (§1) are never batched.

**Unchanged in production:**
- the change feed (§2.3);
- reads (§3.3);
- writes (§3.4–3.5), which take effect at once.

On your side, send your writes in batches too: queue them and post them every 15 minutes with
`POST /v1/b2c/leads/batch` (§3.8). A counsellor's urgent change can still go at once.

## 2. Your copy of the leads

### 2.1 The record

Every lead in your scope is one record with standard field names, grouped. `GET /v1/b2c/schema` lists them all with their
type and whether you may write them now.

```json
{
  "id": 949, "cycle_no": 1, "created_at": "…", "updated_at": "…", "is_test": false, "deleted": false, "merged_into_id": null,
  "held_by_b2c": true, "contract_version": 3,
  "student": { "name": "Asha Verma", "phone": "919876543210", "alternate_phone": null, "email": "asha@example.com", "city": "Pune", "state": "Maharashtra", "…": "…" },
  "education": { "highest_qualification": "B.Com", "academic_score_pct": 68, "work_experience_years": 3, "…": "…" },
  "interest": { "course": "MBA", "specialization": "Finance", "university": null, "programme_level": "PG", "study_mode": "Online", "other_courses": ["BBA"], "…": "…" },
  "consent": { "contact_consent_at": "…", "marketing_consent_at": null, "partner_share_consent_at": "…", "consent_text_version": "web-v3", "opted_out": false,
               "partner_share_given": true, "state": "given",
               "partner_share_request": { "id": 17, "status": "answered", "channel": "b2c_crm", "context": "decision", "created_at": "…", "expires_at": "…", "answer": "yes" } },
  "source": { "lead_source": "meta_lead_ad", "campaign": "Oct MBA", "utm_source": "facebook", "click_ids": { }, "…": "…" },
  "qualification": { "lead_status": "QUALIFIED", "classification": "WARM", "lead_score": 72, "temperature": "warm", "class": "qualified", "missing": [], "…": "…" },
  "pipeline": { "owner_user_id": null, "team_id": null, "stage": "nurture", "sub_stage": null, "contact_attempts": 0, "…": "…" },
  "application": { "application_id": null, "application_status": null, "applied_at": null, "fee_amount_inr": null, "fee_paid_inr": null },
  "enrolment": { "enrollment_status": null, "enrolled_program": null, "enrollment_date": null, "expected_net_revenue_inr": null, "…": "…" },
  "lost": { "lost_reason": null, "lost_at": null },
  "other": { "custom_fields": { } },
  "allocation": { "destination": "in_house", "allocation_id": 5501, "reference": "EDW-5501", "b2c_lane": "sales", "reason": "duplicate_cascade", "cause": null,
                  "allocated_at": "…", "status": "handed_off", "partner": null,
                  "partner_barred_at": "…", "partner_bar_reason": "duplicate",
                  "already_with_providers": [ { "partner_id": 20, "partner_name": "Down Edu", "first_had_at": "…", "existing_record_id": "LS-77001", "claimed_at": "…" } ],
                  "hold": { "kind": "barred", "open": true, "allocation_id": 5501, "lane": "sales", "reason": "duplicate_cascade", "owner_assigned": false },
                  "job": "sell", "assignment": "round_robin_now", "first_contact_script": "neutral_adviser",
                  "nurture_first_message_at": null, "b2c_actions": [] },
  "campaign": { "platform": "meta", "paid": true, "campaign_id": "120210001", "campaign_name": "Oct MBA · Lead form", "adset_name": "…", "ad_name": "…" }
}
```

New in version 3:
- `allocation`: `cause`, `partner_barred_at` / `partner_bar_reason` (`duplicate`, `lost`; null when not barred),
  `already_with_providers`, `hold`, `job` / `assignment` / `first_contact_script` (§1.1; null when you do not hold the lead),
  `nurture_first_message_at`, `b2c_actions`. The same values as the hand-off event, read live;
- `qualification.class` (`junk`, `mismatch`, `qualified`, `unqualified`) and `qualification.missing` (codes, §1.2);
- `consent.partner_share_given`, `consent.state` (`given`, `refused`, `withdrawn`, `requested`, `queued`, `expired`,
  `stamp_uncovered`, `none`) and `consent.partner_share_request` (the latest request of this enquiry, or null).
  `stamp_uncovered` means a consent was recorded under a text that does not name admission partners, so it does not count;
- `interest.other_courses`: the other courses the student asked about, in order (writable, §3.4);
- `held_by_b2c` is always a boolean; `contract_version` 3.

The record never carries commission rates, scores or routing candidates.

**Who owns which fields**

| Groups | Written by | Notes |
| --- | --- | --- |
| `student`, `education`, `interest` (incl. `other_courses`) | You (except `student.phone`) and the B2B CRM | A counsellor's correction goes through §3.4; the phone is the student's identity and changes only in the B2B CRM. Completing a nurture lead's name, email, course or other courses is what requalifies it |
| `pipeline`, `application`, `enrolment`, `lost`, `other.custom_fields`, `qualification.lead_score`, `qualification.temperature` | You | Your pipeline. `stage` must be one of the stage keys in the schema |
| `consent`, `source`, the rest of `qualification`, `allocation`, `campaign` | The B2B CRM only | Consent answers go through §4; opt-out and erasure through §4 |

The Admin can narrow the fields you may write (B2C CRM link → Fields and access). A refused field answers 422 and
names the field. `other_courses` is always writable while you hold the lead.

### 2.2 Versions

Every change to a lead's record gives it a new `version` (1, 2, 3…, per lead) and a new `seq` (one counter across all
leads). Keep the version with your copy and **apply a webhook or feed entry only when its version is higher**: deliveries
can arrive out of order and retries repeat. Your own writes come back as a `b2c.lead_upserted` with
`origin: "b2c:<request_id>"` and the new version; applying it is harmless.

After the version-3 upgrade the Admin re-syncs every shared lead once (`origin: "resync"`), so your copies gain the new
fields without any action on your side.

### 2.3 Building and repairing the copy: the change feed

`GET /v1/b2c/leads?after=<seq>&limit=<1–500>` (scope `b2c`) lists every lead whose record changed after `seq`, oldest
first, each with its **current** record:

```json
{ "ok": true, "result": { "leads": [
    { "type": "b2c.lead_upserted", "lead_id": 949, "version": 7, "seq": 18802, "changed_at": "…", "record": { } },
    { "type": "b2c.lead_released", "lead_id": 951, "version": 4, "seq": 18803, "changed_at": "…", "record": null } ],
  "next_after": 18803 } }
```

- **First build:** start with `after=0` and page until `leads` is empty.
- **Keep the cursor:** store `next_after` and poll every few minutes. A missed webhook can then never lose a change.
- **Size:** a lead appears once per page, at its latest change.

### 2.4 Scope

By default (*held*) you receive the leads you hold (the engine handed them to B2C, sales or nurture lane); a lead that
goes to a partner is released. The Admin can switch to *every lead, read-only* (*all*): you then also receive unrouted and
partner-held leads (`held_by_b2c: false`) for lookups and reporting, but you can write only the leads you hold. Under *all*
a lead that moves from you to a partner stays in scope: it arrives as a `b2c.lead_upserted` with `held_by_b2c: false`, not
as a release. **Scope *all* never carries Not passed leads** (junk, invalid phone, programme Eduwit does not offer: they
reach no CRM; a shared lead that becomes Not passed is released) **nor test leads**, except a test hand-off made for you.

## 3. Calls: B2C → B2B (API key)

Send the key as `Authorization: Bearer <key>` (or `x-api-key: <key>`). Every answer is
`{ "ok": true, … }` or `{ "ok": false, "error": "…" }` with a matching HTTP status. `401` means a missing, wrong or revoked
key; `503` means try again shortly.

### 3.1 `GET /v1/handoffs` — hand-off news feed

The same envelopes the webhooks carry (every `b2c.*` event and `b2b.lead_routed_to_partner`), oldest first. Poll it every
few minutes, and at start-up, so a missed webhook never loses a lead.

| Query | Meaning |
| --- | --- |
| `after` | The `next_after` from your previous call. Omit on the very first call |
| `since` | ISO 8601 time; only events at or after it (useful for the first call) |
| `limit` | 1–500, default 200 |

```json
{ "ok": true, "events": [ { "id": "evt_6460", "type": "b2c.lead_handed_off", "lead_id": 949, "contract_version": 3, "...": "..." } ], "next_after": 6460 }
```

Store `next_after` and send it as `after` next time. When nothing is new, `events` is empty and `next_after` repeats
the value you sent. A page can hold fewer events than `limit` (internal events are skipped); keep calling while
`events` is non-empty. Envelope ids are the same as on the webhooks, so one de-duplication table covers both.

### 3.2 `POST /v1/leads/{id}/route-to-partners`

Hands a lead you hold back to the engine to find a partner. The only way a B2C lead reaches a partner.

```json
{ "reason": "Student prefers a partner university's weekend batch" }
```

- `reason` is required (3–300 characters) and is kept in the audit log.
- The lead must not be **partner-barred** (duplicate cascade or partner lost): `422` `error_code: partner_barred`. Hide the
  action when `partner_bar` is set; the engine refuses it whatever the reason.
- The student must have **partner-sharing consent recorded** under a text that names admission partners (`consent.state`
  `given`), else `422` `error_code: no_consent`. Ask through §1.3 first (the Admin can request it from the lead's page).
- The lead must be **held by B2C** (sales hold or qualification nurture), else `422` `error_code: not_held`; a reason
  shorter than 3 characters is `422` `error_code: invalid`; an unknown lead is `404`.
- On success your allocation is closed and the engine decides at once:

```json
{ "ok": true, "result": { "destination": "partner", "reference": "EDW-187", "partner_id": 20, "b2c_lane": null, "reason": null, "outcome": "decided" } }
```

`destination: "partner"` means a partner was chosen and the lead is being sent; wait for `b2b.lead_routed_to_partner`
before closing your pipeline. If it comes back as `in_house` (or later a `b2c.lead_handed_off` with reason
`manual_route_failed` and a `cause` arrives), no partner took it and the lead is yours again: return it to its previous
counsellor (`handling.previous_owner`). A lead that ends in a duplicate or lost after your route becomes partner-barred too.

Errors: `{ "ok": false, "status": 422, "error": "partner_barred: partner-barred (duplicate) since 2026-10-07: this lead can never be sent to partners", "error_code": "partner_barred" }`.

### 3.3 `GET /v1/b2c/leads/{id}` and lookup

`GET /v1/b2c/leads/{id}` answers `{ "version": 7, "record": { … } }` for a lead in your scope (404 otherwise).
`GET /v1/b2c/leads?phone=9876543210` or `?email=…` finds leads (10-digit numbers are taken as Indian). Each match has
`lead_id`, `version` and `held_by_b2c`, plus `record` when it is in your scope. Use the lookup before creating a
student, to avoid a duplicate.

### 3.4 `PATCH /v1/b2c/leads/{id}`: write your fields

```json
{
  "request_id": "b2c-upd-7f3c2a",
  "if_version": 7,
  "actor": { "id": "u-17", "email": "priya@eduwit.in", "name": "Priya" },
  "set": { "stage": "assigned", "owner_user_id": "4c1e…", "assigned_at": "2026-10-07T11:00:00+05:30", "other_courses": ["BBA", "BCA"], "custom_fields": { "batch": "weekend" } }
}
```

- **`request_id`** (required, up to 100 characters) is unique per change. A repeat returns the first answer with
  `replayed: true` and changes nothing, so retry freely.
- **`if_version`** (optional) is the version your counsellor saw. If the lead changed since, the answer is `409` with the
  current `version` and `record`. Show the counsellor the new data and let them retry. Without it, the last write wins.
- **`actor`** is the B2C user who made the change. It is kept in the audit log and shown to the Admin.
- **`set`** holds only the fields to change. `null` clears a field. `custom_fields` is merged into the stored object: a
  key set to `null` is removed. `other_courses` (a list of course names, or comma text, at most 9) replaces the student's
  other courses; `null` or `[]` clears them.
- **Values:** timestamps in ISO 8601, dates as `YYYY-MM-DD`, numbers as numbers, `stage` from the schema's stage keys,
  `temperature` as hot, warm or cold. A new `stage` stamps `stage_changed_at` unless you send it.
- **Qualification nurture:** completing `name`, `email`, `course`, `programme_level`, `field_of_interest` or
  `other_courses` on a `not_qualified` lead is what qualifies it; the engine re-decides it within a minute and you receive
  `b2c.lead_requalified`.

| Answer | Meaning |
| --- | --- |
| `200` `{ "result": { "lead_id", "version", "changed": [fields], "record" } }` | Applied. `changed` is empty when nothing differed |
| `400` | No `request_id`, `set` is not an object, or `actor` is not a small object |
| `404` / `410` | Unknown lead / the lead was deleted or merged (`merged_into_id` given) |
| `409` | You do not hold the lead, or `if_version` is stale (with the current record) |
| `422` `{ "fields": { "phone": "is read-only for the B2C CRM", … } }` | Some fields were refused; nothing was written |

### 3.5 `POST /v1/b2c/leads/{id}/activities`: calls, messages, notes

```json
{ "request_id": "b2c-act-91a0", "kind": "call", "at": "2026-10-07T11:02:00+05:30", "outcome": "connected",
  "duration_seconds": 240, "note": "Wants the weekend batch", "actor": { "id": "u-17", "name": "Priya" } }
```

- **`kind`** is `call`, `whatsapp`, `sms`, `email`, `meeting` or `note`.
- **Contact kinds.** Anything but a note counts as a contact attempt. It updates `first_contacted_at`,
  `last_contacted_at`, `contact_attempts` and `last_activity_at`. A note updates only `last_activity_at`.
- **Timeline.** The activity shows on the lead's timeline in the B2B CRM.
- **Idempotency.** `request_id` works as in §3.4. The answer is the lead's new `version`.

### 3.6 New students: `POST /v1/leads`

New students that the B2C CRM creates (walk-ins, calls, your own WhatsApp number) go in through the Intake API
(`docs/intake-api.md`, scope `intake`) with `lead_source` `b2c_created` or `b2c_whatsapp`. The engine hands them
straight back to you (`reason: b2c_created`, sales lane), so they arrive as `b2c.lead_handed_off` plus `b2c.lead_upserted`.
Look the student up first (§3.3). Send `other_courses` when the student named more than one programme, and the consent
line's `consent_text_version` when the student consented to partner sharing (only a registered text that names admission
partners counts).

### 3.7 `GET /v1/b2c/schema`

The field catalogue (`field`, `group`, `kind`, `max`, `writable` now), the stage keys with their rank and group, the
activity kinds, and — version 3 — `contract_version`, `reasons` (`sales`, `nurture`, `test`, `retired`), `causes`,
`handling` (`job`, `assignment`, `first_contact_script` values), `hold_kinds`, `partner_bar_reasons`, `consent_states`,
`b2c_actions`, `events` (what we publish), `inbound` (what we accept, §4) and `route_to_partners_error_codes`. Read it at
start-up and build your forms, enums and checks from it.

### 3.8 `POST /v1/b2c/leads/batch`: many writes in one call

Up to 200 items (1 MB), each an update (§3.4) or an activity (§3.5) with `op` and `lead_id` added:

```json
{ "items": [
  { "op": "update", "lead_id": 949, "request_id": "b2c-upd-7f3c2a", "if_version": 7, "actor": { "name": "Priya" }, "set": { "stage": "assigned" } },
  { "op": "activity", "lead_id": 950, "request_id": "b2c-act-91a0", "kind": "call", "at": "2026-10-07T11:02:00+05:30", "outcome": "connected" } ] }
```

- **Items are independent.** Each item is applied on its own, so a refused item does not stop the others.
- **Answer.** `200` with `{ "applied": n, "items": [ { "lead_id", "request_id", "op", "ok", "status", "error"?, "fields"?, "version"?, "changed"? } ] }`, in the same order as the request.
- **Retries.** `request_id` makes each item safe to retry, as in the single calls.

## 4. Events: B2C → B2B (signed)

`POST /v1/events/b2ccrm`, signed exactly like our webhooks, with the **same signing secret**:

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `X-Eduwit-Timestamp` | Unix seconds (within 5 minutes of our clock) |
| `X-Eduwit-Signature` | `sha256=` + hex HMAC-SHA256 of `<timestamp>.<raw body>` |

```json
{ "event_id": "b2c-evt-000123", "type": "b2ccrm.partner_consent", "occurred_at": "2026-10-07T10:00:00+05:30",
  "data": { "lead_id": 949, "request_id": 17, "answer": "yes", "answered_at": "2026-10-07T09:58:12+05:30", "channel": "whatsapp",
            "message_id": "wamid.HBgMOTE5ODc2NTQzMjEwFQIAEhggQjRCN0E=", "text_version": "wa_partner_consent:v1" } }
```

`event_id` must be unique per event; a repeat is answered `200 "already received"` and not applied twice, so retry
freely. Body limit 100 KB.

| `type` | What B2B does | Put in `data` |
| --- | --- | --- |
| `b2ccrm.consent_request_sent` | Marks the consent request sent; the 48 hours now count from your send (§1.3) | `request_id`, `sent_at`, `message_id` (your WhatsApp message id) |
| `b2ccrm.partner_consent` | Records the student's answer to the partner-sharing request and acts on it: YES → consent recorded, the lead goes through the routing rules; NO → `b2c.lead_handed_off` `no_partner_consent`. Idempotent per `message_id` and per (request, answer) | `lead_id` (or `request_id`), `request_id`, `answer` (`yes` / `no`), `answered_at`, `channel`, **`message_id` (required for a YES: the student's own message)**, `text_version` |
| `b2ccrm.lead_assigned` | Timeline only (kept for compatibility; use `PATCH` §3.4 to write the owner) | `lead_id`, counsellor or team identifiers you want shown |
| `b2ccrm.stage_changed` | Timeline only (kept for compatibility; use `PATCH` §3.4 to write the stage) | `lead_id`, `stage`, `sub_stage` |
| `b2ccrm.enrolled` | Timeline only (use `PATCH` §3.4 for the enrolment fields) | `lead_id`, programme, `enrolled_at` |
| `b2ccrm.opted_out` | Marks the student opted out, cancels any B2B message still scheduled, alerts the Admin to tell every partner that ever received the lead | `lead_id` |
| `b2ccrm.erasure_requested` | Opens an erasure request for the Admin, who carries it out across B2B, Witty and partners | `lead_id`, `note` |

Answers: `200` applied (or already received, or an unknown type, which is stored and ignored); `400` not JSON or no
`event_id`/`type`; `401` bad signature or timestamp; `404` unknown `lead_id` / `request_id`; `413` too large; `422` the
event could not be applied as sent (`message_id is required for a YES`, `answer must be yes or no`, `no consent request to
answer`); `500` stored but could not be applied (the Admin sees it; do not resend); `503` the B2C connection is not set up yet.

Every event, applied or not, is listed on the Admin's System health screen.

## 5. Lead data: through the B2B CRM only

- **No direct access.** The B2C CRM reads no `public.student_leads` and no `b2b.*` table, and writes none. Its own
  tables (users, teams, tasks, notes, templates, call logs) are its own and stay in its database.
- **Its copy.** It keeps its copy of the leads (§2), keyed by `id`, with `version`.
- **Its writes.** It writes only through §3.4 and §3.5. The B2B CRM checks every value, writes the lead and audits who
  changed what.
- **Allocation.** The B2B CRM alone sets where a lead goes (`allocation`); the B2C CRM moves a lead to partners only
  with §3.2, and never a partner-barred one.
- **Consent.** The B2C CRM records no consent itself: it sends the request and reports the answer (§1.3, §4).

**Moving the current B2C CRM over.** Today it still reads and writes the lead table directly. The order is:
1. Build the copy from the change feed (§2.3).
2. Switch its screens to read the copy.
3. Point its writes at §3.4 and §3.5.
4. Subscribe the endpoint to `b2c.*` and `b2b.*` and keep the feed as a safety net.
5. Remove its database credentials for `student_leads`.

The Admin's B2C CRM link screen shows each step: deliveries, writes, refused writes and conflicts.

## 6. Testing

Ask the Admin for a staging connection (separate secret and key). Use test phones `9190000000NN`: they are flagged
`test: true`, are never routed by the engine, never reach a live partner and never get a message. The Admin sends a test
lead to you with **Test hand-off** on the lead's page (`reason: test_handoff`, sales lane). Check, in order:
1. The `ping` verifies.
2. A test hand-off arrives as `b2c.lead_handed_off` (`reason: test_handoff`, `contract_version: 3`, `test: true`, every
   §1.2 key present) and as `b2c.lead_upserted` version 1 with `held_by_b2c: true` and `allocation.job: "sell"`.
3. `GET /v1/b2c/leads?after=0` lists it with the same record. (While testing, the link is in real time; check the batch
   format too by asking the Admin to switch to the production cadence for a short test with a real, non-test lead.)
4. A `PATCH` with `stage: "assigned"` answers version 2, and the echo arrives as a webhook.
5. The same `request_id` answers `replayed: true`.
6. A stale `if_version` answers `409`.
7. A call activity raises `contact_attempts`.
8. Writing `student.phone` answers `422`; writing `other_courses: ["BBA"]` shows in the record's `interest.other_courses`.
9. A signed `b2ccrm.opted_out` answers `200` and shows on the System health screen.
10. Consent, on a real non-test lead the Admin creates without consent: `b2c.consent_requested` arrives; your
    `b2ccrm.consent_request_sent` answers `200`; a `b2ccrm.partner_consent` YES without `message_id` answers `422`; with
    it, `200` and `b2c.consent_closed` (`answered`, `yes`) follows.
11. `POST /v1/leads/{id}/route-to-partners` on a partner-barred lead answers `422` `partner_barred`; on a lead without
    consent `422` `no_consent`; on a lead you do not hold `422` `not_held`.

The Admin can follow every step on B2C CRM link → Inspect a lead.
