# Eduwit B2B CRM ↔ B2C CRM: integration contract

The B2B CRM is Eduwit's lead allocation engine. Every lead enters through it, and it decides where the lead goes: to a
partner university's CRM, or to Eduwit's own B2C CRM (in-house counsellors). This document is everything the B2C CRM's
developer needs to connect. The rules behind it are in `B2B_CRM_ADDENDUM_1.md` §1–4.

Base URL of the B2B CRM: `https://<b2b-crm-host>` (the Vercel production domain). All bodies are JSON in UTF-8.

## 0. What you receive from the Eduwit Admin

Both come once, through a secure channel (never by chat or plain email), from **System health → Webhooks and API keys**:

| Item | Looks like | Used for |
| --- | --- | --- |
| **Signing secret** of your webhook endpoint | `whsec_…` (54 characters) | Verifying the webhooks we send you, and signing the events you send us |
| **API key** with the *Product integrations* (`events`) scope | `eb2b_…` | `GET /v1/handoffs` and `POST /v1/leads/{id}/route-to-partners` |

Give the Admin the HTTPS URL that should receive webhooks. The Admin registers it, sends a test event, and switches it on
once you confirm your signature check passes. Nothing is delivered before that, so use `GET /v1/handoffs` to catch up on
anything that happened earlier.

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
  "data": { }
}
```

`lead_id` is the `student_leads.id` you share with us. `test: true` marks Eduwit test leads (phones starting `910000`
or `9190000000`); keep them out of counsellor queues and reports.

### Events

| Type | When | `data` |
| --- | --- | --- |
| `b2c.lead_handed_off` | The engine gives a lead to B2C | `b2c_lane` (`sales` / `nurture`), `reason` (below), `cause` (for `manual_route_failed`: why), `reference` (`EDW-…`), `allocation_id`, `decision_id`, `partners_tried` (each partner and its outcome), `paid` (the paid-campaign signal or null), `test`. For `partner_lost` also `partner_id`, `partner_record_id`, `lost_reason`, `partner_status`, the partner's last activity |
| `b2c.lead_reenquired` | A lead you already hold enquires again (new paid enquiry, Witty qualifies it). It stays yours | `b2c_lane`, `cycle_no`, `decision_id`, `what` (`lead_status`, `source`, `paid`), `allocation_id`, `reference` |
| `b2c.lead_flagged` | A lead you hold needs attention (e.g. its classification changed) | `classification`, `allocation_id` |
| `b2c.lead_close_agreed` | A partner agreed it no longer works a lead you now hold | `classification` |
| `b2b.lead_routed_to_partner` | A lead you sent to partners (§2.2) was accepted by one. **Close your pipeline for it** | `allocation_id`, `reference`, `partner_id` |
| `ping` | The Admin pressed *Send test* | `{}`, with `test: true` |

`reason` codes on `b2c.lead_handed_off`: `paid_campaign`, `b2c_created`, `not_qualified` (nurture), `no_partner_consent`,
`duplicate_cascade`, `no_partner_offers_programme`, `no_capacity`, `partners_unreachable`, `partner_lost` (nurture),
`rule` (an Admin routing rule), `manual` (the Admin moved it from a partner to B2C), `manual_route_failed` (your
route-to-partners found no partner; return it to its previous counsellor).

Other subscribable types (`lead.allocated`, `lead.accepted`, `lead.status_changed`, `lead.enrolled`) cover every lead,
including partner-held ones; the B2C endpoint does not need them.

**What B2B does not do for B2C leads:** it sends the student no message (you message them from your own number when a
counsellor is assigned), and it writes none of the pipeline columns while you hold the lead.

## 2. Calls: B2C → B2B (API key)

Send the key as `Authorization: Bearer <key>` (or `x-api-key: <key>`). Every answer is
`{ "ok": true, … }` or `{ "ok": false, "error": "…" }` with a matching HTTP status. `401` means a missing, wrong or revoked
key; `503` means try again shortly.

### 2.1 `GET /v1/handoffs` — reconciliation feed

The same envelopes the webhooks carry, oldest first. Poll it every few minutes, and at start-up, so a missed webhook
never loses a lead.

| Query | Meaning |
| --- | --- |
| `after` | The `next_after` from your previous call. Omit on the very first call |
| `since` | ISO 8601 time; only events at or after it (useful for the first call) |
| `limit` | 1–500, default 200 |

```json
{ "ok": true, "events": [ { "id": "evt_6460", "type": "b2c.lead_handed_off", "lead_id": 949, "...": "..." } ], "next_after": 6460 }
```

Store `next_after` and send it as `after` next time. When nothing is new, `events` is empty and `next_after` repeats
the value you sent. A page can hold fewer events than `limit` (internal events are skipped); keep calling while
`events` is non-empty. Envelope ids are the same as on the webhooks, so one de-duplication table covers both.

### 2.2 `POST /v1/leads/{id}/route-to-partners`

Hands a lead you hold back to the engine to find a partner. The only way a B2C lead reaches a partner.

```json
{ "reason": "Student prefers a partner university's weekend batch" }
```

- `reason` is required (3–300 characters) and is kept in the audit log.
- The student must have consented to partner sharing (`consent_partner_share_at`), else `422`.
- The lead must be held by B2C, else `422`; unknown lead `404`.
- On success your allocation is closed and the engine decides at once:

```json
{ "ok": true, "result": { "destination": "partner", "reference": "EDW-187", "partner_id": 20, "b2c_lane": null, "reason": null } }
```

`destination: "partner"` means a partner was chosen and the lead is being sent; wait for `b2b.lead_routed_to_partner`
before closing your pipeline. If it comes back as `in_house` (or later a `b2c.lead_handed_off` with reason
`manual_route_failed` arrives), no partner took it and the lead is yours again.

## 3. Events: B2C → B2B (signed)

`POST /v1/events/b2ccrm`, signed exactly like our webhooks, with the **same signing secret**:

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `X-Eduwit-Timestamp` | Unix seconds (within 5 minutes of our clock) |
| `X-Eduwit-Signature` | `sha256=` + hex HMAC-SHA256 of `<timestamp>.<raw body>` |

```json
{ "event_id": "b2c-evt-000123", "type": "b2ccrm.stage_changed", "occurred_at": "2026-10-07T10:00:00+05:30",
  "data": { "lead_id": 949, "stage": "assigned", "counsellor": "Priya" } }
```

`event_id` must be unique per event; a repeat is answered `200 "already received"` and not applied twice, so retry
freely. Body limit 100 KB.

| `type` | What B2B does | Put in `data` |
| --- | --- | --- |
| `b2ccrm.lead_assigned` | Timeline and analytics (`b2c.counsellor_assigned`) | `lead_id`, counsellor or team identifiers you want shown |
| `b2ccrm.stage_changed` | Timeline and analytics (`b2c.stage_changed`) | `lead_id`, `stage`, `sub_stage` |
| `b2ccrm.enrolled` | Timeline and analytics (`b2c.enrolled`) | `lead_id`, programme, `enrolled_at` |
| `b2ccrm.opted_out` | Marks the student opted out, cancels any B2B message still scheduled, alerts the Admin to tell every partner that ever received the lead | `lead_id` |
| `b2ccrm.erasure_requested` | Opens an erasure request for the Admin, who carries it out across B2B, Witty and partners | `lead_id`, `note` |

Answers: `200` applied (or already received, or an unknown type, which is stored and ignored); `400` not JSON or no
`event_id`/`type`; `401` bad signature or timestamp; `404` unknown `lead_id`; `413` too large; `500` stored but could not
be applied (the Admin sees it; do not resend); `503` the B2C connection is not set up yet.

Every event, applied or not, is listed on the Admin's System health screen.

## 4. Shared data

Both products use the same Supabase database (`public.student_leads`). While B2C holds a lead, the B2C CRM writes:

- its assignment columns `owner_user_id`, `assigned_at`, `team_id`;
- the pipeline columns `first_contacted_at`, `last_contacted_at`, `contact_attempts`, `next_task_due_at`, `stage`,
  `sub_stage`, `application_*`, `fee_*`, `enrollment_*`, `enrolled_*`, `lost_*`, `expected_net_revenue_inr`,
  `realised_net_revenue_inr`, and `lead_score` / `temperature`.

It never writes the allocation columns (`destination_type`, `partner_id`, `allocation_id`, `allocated_at`,
`allocation_reason`); those belong to B2B. It never reads `b2b.integration_outbox` or other `b2b.*` tables directly.
New students the B2C CRM creates go in through the B2B Intake API (`POST /v1/leads`, the next build step) with
`lead_source` `b2c_created` or `b2c_whatsapp`, so the engine hands them straight back (`reason: b2c_created`).

## 5. Testing

Ask the Admin for a staging connection (separate secret and key). Use test phones `9190000000NN`: they are flagged
`test: true`, never reach a live partner and never get a message. Check, in order: the `ping` verifies; a test lead
without partner consent arrives as `b2c.lead_handed_off` with `reason: no_partner_consent`; the same envelope appears in
`GET /v1/handoffs`; a signed `b2ccrm.stage_changed` for it answers `200` and shows on the System health screen; a
repeated `event_id` answers `already received`.
