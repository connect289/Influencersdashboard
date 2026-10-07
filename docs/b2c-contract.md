# Eduwit B2B CRM ↔ B2C CRM: integration contract (version 2)

The B2B CRM is Eduwit's lead allocation engine. Every lead enters through it, and it decides where the lead goes: to a
partner university's CRM, or to Eduwit's own B2C CRM (in-house counsellors). The rules behind it are in
`B2B_CRM_ADDENDUM_1.md` §1–4.

**Version 2 (7 Oct 2026): the B2B CRM is the only gateway to the lead table.** The B2C CRM never reads or writes
`public.student_leads` (or any `b2b.*` table) directly. Instead:
- it keeps its own copy of the leads it works, kept current in real time by signed webhooks (§1) and rebuildable at any
  time from the change feed (§2);
- it writes its counsellors' work back through the API (§3): stage, owner, contact, application, enrolment and lost
  fields, plus calls, messages and notes;
- its own tables (users, teams, tasks, notes, templates…) stay its own.

This document is everything the B2C CRM's developer needs. The Admin follows the connection on **B2C CRM link** (`/b2c`).

Base URL of the B2B CRM: `https://<b2b-crm-host>` (the Vercel production domain). All bodies are JSON in UTF-8.

## 0. What you receive from the Eduwit Admin

Both come once, through a secure channel (never by chat or plain email), from **System health → Webhooks and API keys**:

| Item | Looks like | Used for |
| --- | --- | --- |
| **Signing secret** of your webhook endpoint | `whsec_…` (54 characters) | Verifying the webhooks we send you, and signing the events you send us |
| **API key** with the scopes *B2C CRM link* (`b2c`), *Product integrations* (`events`) and *Lead intake* (`intake`) | `eb2b_…` | `b2c`: the lead API in §2–3. `events`: `GET /v1/handoffs` and `POST /v1/leads/{id}/route-to-partners`. `intake`: `POST /v1/leads` |

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
| `b2c.lead_upserted` | A lead you hold was created or changed, by anyone (Witty, the engine, a partner event, the Admin, your own write) | `version`, `seq`, `origin`, `record` (§2.1). **Store it if `version` is higher than your copy's** |
| `b2c.lead_released` | A lead left you: routed to a partner, deleted, merged or anonymised | `version`, `seq`, `record` (only `id`, `held_by_b2c: false`, `deleted`, `merged_into_id`, `allocation`). Close your pipeline for it and keep only what your records need |
| `b2c.leads_batch` | Production cadence only (see *Sync cadence* below): every lead that changed since the last batch, once, at its newest version, up to 100 per call | `from_seq`, `to_seq`, `part`, `leads`: a list of `{ type, lead_id, version, seq, changed_at, origin, record }` exactly as in the change feed (§2.3). Apply each entry like a single webhook |
| `b2c.lead_handed_off` | The engine gives a lead to B2C | `b2c_lane` (`sales` / `nurture`), `reason` (below), `cause` (for `manual_route_failed`: why), `reference` (`EDW-…`), `allocation_id`, `decision_id`, `partners_tried` (each partner and its outcome), `paid` (the paid-campaign signal or null), `test`. For `partner_lost` also `partner_id`, `partner_record_id`, `lost_reason`, `partner_status`, the partner's last activity |
| `b2c.lead_reenquired` | A lead you already hold enquires again (new paid enquiry, Witty qualifies it). It stays yours | `b2c_lane`, `cycle_no`, `decision_id`, `what` (`lead_status`, `source`, `paid`), `allocation_id`, `reference` |
| `b2c.lead_flagged` | A lead you hold needs attention (e.g. its classification changed) | `classification`, `allocation_id` |
| `b2c.lead_close_agreed` | A partner agreed it no longer works a lead you now hold | `classification` |
| `b2b.lead_routed_to_partner` | A lead you sent to partners (§3.2) was accepted by one. **Close your pipeline for it** | `allocation_id`, `reference`, `partner_id` |
| `ping` | The Admin pressed *Send test* | `{}`, with `test: true` |

`reason` codes on `b2c.lead_handed_off`: `paid_campaign`, `b2c_created`, `not_qualified` (nurture), `no_partner_consent`,
`duplicate_cascade`, `no_partner_offers_programme`, `no_capacity`, `partners_unreachable`, `partner_lost` (nurture),
`rule` (an Admin routing rule), `manual` (the Admin moved it from a partner to B2C), `manual_route_failed` (your
route-to-partners found no partner; return it to its previous counsellor).

Other subscribable types (`lead.allocated`, `lead.accepted`, `lead.status_changed`, `lead.enrolled`) cover every lead,
including partner-held ones; the B2C endpoint does not need them.

**What B2B does not do for B2C leads:** it sends the student no message (you message them from your own number when a
counsellor is assigned), and it writes none of the pipeline columns while you hold the lead.

### Sync cadence

To keep paid API calls down, a connection runs in real time only while it is being integrated and tested:

| Mode | When | What you receive |
| --- | --- | --- |
| **Real time** (default) | Integration and testing | One `b2c.lead_upserted` / `b2c.lead_released` per change, within seconds |
| **Every 15 minutes** (production) | After the Admin switches it on B2C CRM link, once you have tested end to end | One `b2c.leads_batch` per interval, with every changed lead at its newest version. Test leads still come one by one in real time, so you can keep testing |

The interval is 15 minutes by default; the Admin can set 5 to 60. `GET /v1/b2c/schema` tells you the current `delivery` and
`interval_minutes`.

**Unchanged in production:**
- the change feed (§2.3);
- reads (§3.3);
- writes (§3.4–3.5), which take effect at once.

On your side, send your writes in batches too: queue them and post them every 15 minutes with
`POST /v1/b2c/leads/batch` (§3.8). A counsellor's urgent change can still go at once.

## 2. Your copy of the leads

### 2.1 The record

Every lead you hold is one record with standard field names, grouped. `GET /v1/b2c/schema` lists them all with their
type and whether you may write them now.

```json
{
  "id": 949, "cycle_no": 1, "created_at": "…", "updated_at": "…", "is_test": false, "deleted": false, "merged_into_id": null,
  "held_by_b2c": true,
  "student": { "name": "Asha Verma", "phone": "919876543210", "alternate_phone": null, "email": "asha@example.com", "city": "Pune", "state": "Maharashtra", "…": "…" },
  "education": { "highest_qualification": "B.Com", "academic_score_pct": 68, "work_experience_years": 3, "…": "…" },
  "interest": { "course": "MBA", "specialization": "Finance", "university": null, "programme_level": "PG", "study_mode": "Online", "…": "…" },
  "consent": { "contact_consent_at": "…", "marketing_consent_at": null, "partner_share_consent_at": "…", "opted_out": false, "…": "…" },
  "source": { "lead_source": "meta_lead_ad", "campaign": "Oct MBA", "utm_source": "facebook", "click_ids": { }, "…": "…" },
  "qualification": { "lead_status": "QUALIFIED", "classification": "WARM", "lead_score": 72, "temperature": "warm", "…": "…" },
  "pipeline": { "owner_user_id": null, "team_id": null, "stage": "nurture", "sub_stage": null, "contact_attempts": 0, "…": "…" },
  "application": { "application_id": null, "application_status": null, "applied_at": null, "fee_amount_inr": null, "fee_paid_inr": null },
  "enrolment": { "enrollment_status": null, "enrolled_program": null, "enrollment_date": null, "expected_net_revenue_inr": null, "…": "…" },
  "lost": { "lost_reason": null, "lost_at": null },
  "other": { "custom_fields": { } },
  "allocation": { "destination": "in_house", "allocation_id": 5501, "reference": "EDW-5501", "b2c_lane": "sales", "reason": "paid_campaign",
                  "allocated_at": "…", "status": "handed_off", "partner": null },
  "campaign": { "platform": "meta", "paid": true, "campaign_id": "120210001", "campaign_name": "Oct MBA · Lead form", "adset_name": "…", "ad_name": "…" }
}
```

**Who owns which fields**

| Groups | Written by | Notes |
| --- | --- | --- |
| `student`, `education`, `interest` | You (except `student.phone`) and the B2B CRM | A counsellor's correction goes through §3.4; the phone is the student's identity and changes only in the B2B CRM |
| `pipeline`, `application`, `enrolment`, `lost`, `other.custom_fields`, `qualification.lead_score`, `qualification.temperature` | You | Your pipeline. `stage` must be one of the stage keys in the schema |
| `consent`, `source`, the rest of `qualification`, `allocation`, `campaign` | The B2B CRM only | Opt-out and erasure go through §4 |

The Admin can narrow the fields you may write (B2C CRM link → Fields and access). A refused field answers 422 and
names the field.

### 2.2 Versions

Every change to a lead's record gives it a new `version` (1, 2, 3…, per lead) and a new `seq` (one counter across all
leads). Keep the version with your copy and **apply a webhook or feed entry only when its version is higher**: deliveries
can arrive out of order and retries repeat. Your own writes come back as a `b2c.lead_upserted` with
`origin: "b2c:<request_id>"` and the new version; applying it is harmless.

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

By default you receive the leads you hold (the engine handed them to B2C, sales or nurture lane). The Admin can switch
to *every lead, read-only*: you then also receive partner-held leads (`held_by_b2c: false`) for lookups and
reporting, but you can write only the leads you hold.

## 3. Calls: B2C → B2B (API key)

Send the key as `Authorization: Bearer <key>` (or `x-api-key: <key>`). Every answer is
`{ "ok": true, … }` or `{ "ok": false, "error": "…" }` with a matching HTTP status. `401` means a missing, wrong or revoked
key; `503` means try again shortly.

### 3.1 `GET /v1/handoffs` — hand-off news feed

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

### 3.2 `POST /v1/leads/{id}/route-to-partners`

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
  "set": { "stage": "assigned", "owner_user_id": "4c1e…", "assigned_at": "2026-10-07T11:00:00+05:30", "custom_fields": { "batch": "weekend" } }
}
```

- **`request_id`** (required, up to 100 characters) is unique per change. A repeat returns the first answer with
  `replayed: true` and changes nothing, so retry freely.
- **`if_version`** (optional) is the version your counsellor saw. If the lead changed since, the answer is `409` with the
  current `version` and `record`. Show the counsellor the new data and let them retry. Without it, the last write wins.
- **`actor`** is the B2C user who made the change. It is kept in the audit log and shown to the Admin.
- **`set`** holds only the fields to change. `null` clears a field. `custom_fields` is merged into the stored object: a
  key set to `null` is removed.
- **Values:** timestamps in ISO 8601, dates as `YYYY-MM-DD`, numbers as numbers, `stage` from the schema's stage keys,
  `temperature` as hot, warm or cold. A new `stage` stamps `stage_changed_at` unless you send it.

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
straight back to you (`reason: b2c_created`), so they arrive as `b2c.lead_handed_off` plus `b2c.lead_upserted`.
Look the student up first (§3.3).

### 3.7 `GET /v1/b2c/schema`

The field catalogue (`field`, `group`, `kind`, `max`, `writable` now), the stage keys with their rank and group, and
the activity kinds. Read it at start-up and build your forms and checks from it.

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
{ "event_id": "b2c-evt-000123", "type": "b2ccrm.stage_changed", "occurred_at": "2026-10-07T10:00:00+05:30",
  "data": { "lead_id": 949, "stage": "assigned", "counsellor": "Priya" } }
```

`event_id` must be unique per event; a repeat is answered `200 "already received"` and not applied twice, so retry
freely. Body limit 100 KB.

| `type` | What B2B does | Put in `data` |
| --- | --- | --- |
| `b2ccrm.lead_assigned` | Timeline only (kept for compatibility; use `PATCH` §3.4 to write the owner) | `lead_id`, counsellor or team identifiers you want shown |
| `b2ccrm.stage_changed` | Timeline only (kept for compatibility; use `PATCH` §3.4 to write the stage) | `lead_id`, `stage`, `sub_stage` |
| `b2ccrm.enrolled` | Timeline only (use `PATCH` §3.4 for the enrolment fields) | `lead_id`, programme, `enrolled_at` |
| `b2ccrm.opted_out` | Marks the student opted out, cancels any B2B message still scheduled, alerts the Admin to tell every partner that ever received the lead | `lead_id` |
| `b2ccrm.erasure_requested` | Opens an erasure request for the Admin, who carries it out across B2B, Witty and partners | `lead_id`, `note` |

Answers: `200` applied (or already received, or an unknown type, which is stored and ignored); `400` not JSON or no
`event_id`/`type`; `401` bad signature or timestamp; `404` unknown `lead_id`; `413` too large; `500` stored but could not
be applied (the Admin sees it; do not resend); `503` the B2C connection is not set up yet.

Every event, applied or not, is listed on the Admin's System health screen.

## 5. Lead data: through the B2B CRM only

- **No direct access.** The B2C CRM reads no `public.student_leads` and no `b2b.*` table, and writes none. Its own
  tables (users, teams, tasks, notes, templates, call logs) are its own and stay in its database.
- **Its copy.** It keeps its copy of the leads (§2), keyed by `id`, with `version`.
- **Its writes.** It writes only through §3.4 and §3.5. The B2B CRM checks every value, writes the lead and audits who
  changed what.
- **Allocation.** The B2B CRM alone sets where a lead goes (`allocation`); the B2C CRM moves a lead to partners only
  with §3.2.

**Moving the current B2C CRM over.** Today it still reads and writes the lead table directly. The order is:
1. Build the copy from the change feed (§2.3).
2. Switch its screens to read the copy.
3. Point its writes at §3.4 and §3.5.
4. Subscribe the endpoint to `b2c.*` and keep the feed as a safety net.
5. Remove its database credentials for `student_leads`.

The Admin's B2C CRM link screen shows each step: deliveries, writes, refused writes and conflicts.

## 6. Testing

Ask the Admin for a staging connection (separate secret and key). Use test phones `9190000000NN`: they are flagged
`test: true`, never reach a live partner and never get a message. Check, in order:
1. The `ping` verifies.
2. A test lead without partner consent arrives as `b2c.lead_handed_off` (`reason: no_partner_consent`) and as
   `b2c.lead_upserted` version 1.
3. `GET /v1/b2c/leads?after=0` lists it with the same record. (While testing, the link is in real time; check the batch
   format too by asking the Admin to switch to the production cadence for a short test with a real, non-test lead.)
4. A `PATCH` with `stage: "assigned"` answers version 2, and the echo arrives as a webhook.
5. The same `request_id` answers `replayed: true`.
6. A stale `if_version` answers `409`.
7. A call activity raises `contact_attempts`.
8. Writing `student.phone` answers `422`.
9. A signed `b2ccrm.opted_out` answers `200` and shows on the System health screen.

The Admin can follow every step on B2C CRM link → Inspect a lead.
