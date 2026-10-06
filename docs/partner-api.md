# Eduwit B2B CRM: partner integration (generic REST and webhook)

This is the contract for a partner whose CRM has no ready-made Eduwit adapter. Two kinds of calls are involved. Eduwit
sends each student to the partner (a push). The partner reports back what happens to that student (events).

## 1. Push: Eduwit → partner

`POST <your endpoint>` with a JSON body. Your test endpoint (sandbox) receives Eduwit's test leads only; your live
endpoint receives real students only.

**Headers**

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `Authorization` (or the header you choose) | Your API token: `Bearer <token>`, `<your header>: <token>`, or HTTP Basic |
| `Idempotency-Key` | The lead's Eduwit reference, e.g. `EDW-1234`. A repeated push with the same key must not create a second lead |
| `X-Eduwit-Reference` | The same reference. Store it on your lead (lead source or reference field) |
| `X-Eduwit-Timestamp` | Unix seconds |
| `X-Eduwit-Signature` | `sha256=` + hex HMAC-SHA256 of `<timestamp>.<raw body>` with your signing secret. Verify it to be sure the push came from Eduwit |

**Body**

```json
{
  "reference": "EDW-1234",
  "test": false,
  "student": { "name": "Ravi Kumar", "phone": "+919810000000", "email": "ravi@example.com", "city": "Delhi", "state": "Delhi", "preferred_language": "Hindi" },
  "programme": { "university": "Example University", "course": "MBA", "specialization": "Finance", "level": "PG", "mode": "Online", "partner_course_code": "EX-MBA-FIN" },
  "profile": { "highest_qualification": "B.Com", "academic_score_pct": 68, "work_experience_years": 2, "enrollment_timeline": "Jan 2027" },
  "note": "Interested in MBA (Finance). Mode: Online. Wants to start: Jan 2027",
  "returning_lead": false,
  "previous_reference": null,
  "sent_at": "2026-10-06T12:00:00+05:30"
}
```

Eduwit never sends the student's budget, lead source, campaign, lead score or chat transcript.

**Your answer**

| Situation | Status | Body |
| --- | --- | --- |
| Lead created | `200` or `201` | `{ "id": "<your record id>" }` (`record_id`, `lead_id` or `data.id` also work) |
| The student is already your lead | `409` (or `200` with `"duplicate": true`) | `{ "duplicate": true, "existing_id": "<your record id>", "created_at": "<when you created it>" }`. If the existing record is Eduwit's own earlier lead, send `"existing_reference": "EDW-…"` instead: Eduwit then treats it as a returning student, not a duplicate |
| You refuse the lead for another reason | `422` | `{ "rejected": true, "reason": "<why>" }`. Your agreement says you accept every lead you are sent, so a rejection raises a contract alert |
| Anything else (`5xx`, timeout, other `4xx`) | | Eduwit retries after 10 s, 1 min, 5 min, 15 min and 1 h, then gives the lead to another partner |

**Hold window.** A partner that checks duplicates in the create call (sync) answers `409` at once. A partner that checks
later (async) has its agreed hold window (default 30 minutes) to send a `duplicate` event. When the window passes with
no claim, the lead is final and Eduwit tells the student which partner will call.

## 2. Events: partner → Eduwit

`POST https://crm.eduwit.in/v1/partners/<your slug>/events`

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `X-Eduwit-Timestamp` | Unix seconds; must be within 5 minutes of Eduwit's clock |
| `X-Eduwit-Signature` | `sha256=` + hex HMAC-SHA256 of `<timestamp>.<raw body>` with the signing secret Eduwit gave you |

```json
{
  "event_id": "evt_001",
  "type": "duplicate",
  "reference": "EDW-1234",
  "record_id": "<your record id>",
  "occurred_at": "2026-10-06T12:05:00+05:30",
  "data": { "existing_id": "LS-998", "created_at": "2026-09-01T10:00:00Z" }
}
```

`event_id` must be unique per event: a repeated `event_id` is accepted once and ignored after that. Identify the lead
by `reference` (preferred) or `record_id`.

| `type` | `data` | What Eduwit does |
| --- | --- | --- |
| `duplicate` | `existing_id`, `created_at` (or `existing_reference`) | In the hold window: the lead moves to another partner. After acceptance (within 24 hours): logged as a commission dispute for review; the lead stays with you. Later: rejected |
| `rejected` | `reason` | In the hold window: the lead moves to another partner and a contract alert is raised |
| `contacted` | `connected` (true/false) | Records the contact attempt on the lead |
| `stage` | `stage`, `sub_stage` | Stores your stage (mapped to Eduwit's stages when your mapping is set up) |
| `lost` | `reason` | The lead goes to Eduwit's B2C nurture team; the student is not messaged by you or Eduwit's B2B CRM |

Other types are stored and applied once your mapping is set up.

**Answers:** `200` with `{ "ok": true, "result": … }`; `401` for a bad signature or an old timestamp; `404` for an
unknown partner or reference; `400` for a malformed body. A `500` means the event is stored and will be reviewed; do
not resend it with a new `event_id`.
