# Eduwit B2B CRM: Intake API and ad-form webhooks

Use this contract to send leads into Eduwit from the website, landing pages, chat tools or any other system. Meta Lead
Ads and Google Ads lead forms are connected on the Intake screen; sections 5 and 6 cover them. Every source goes through
the same `lead_intake()`, so a phone number Eduwit already knows is merged into that lead. No duplicate is created.

## 1. Send a lead

`POST https://<crm host>/v1/leads`

| Header | Value |
| --- | --- |
| `Content-Type` | `application/json` |
| `Authorization` | `Bearer <API key>`. The key needs the **intake** scope; the Admin creates it under System → Webhooks and API keys. `x-api-key: <key>` also works |
| `Idempotency-Key` | 1 to 200 characters, unique per lead submission (for example the form submission ID). If you send the same key and the same body again, you get the stored answer back. The same key with a different body is refused |

**Body**

```json
{
  "lead": {
    "full_name": "Asha Verma",
    "phone": "+91 98765 43210",
    "email": "asha@example.com",
    "city": "Delhi",
    "course": "Online MBA",
    "specialization": "Finance",
    "highest_qualification": "B.Com",
    "work_experience": "3 years",
    "notes": "Wants weekend classes"
  },
  "source": "website_mba_page",
  "channel": "website",
  "campaign": "mba_oct",
  "utm": { "source": "google", "medium": "cpc", "campaign": "mba_oct" },
  "click_ids": { "gclid": "Cj0KCQ…" },
  "landing_url": "https://eduwit.in/mba",
  "consent": {
    "sales_at": "2026-10-07T10:15:00+05:30",
    "partner_share_at": "2026-10-07T10:15:00+05:30",
    "marketing_at": null,
    "text_version": "web-form-v3"
  },
  "phone_verified": true,
  "occurred_at": "2026-10-07T10:15:00+05:30",
  "route": "auto"
}
```

Only these top-level keys are accepted: `lead`, `source`, `channel`, `campaign`, `utm`, `click_ids`, `landing_url`,
`consent`, `phone_verified`, `occurred_at`, `route`, `b2c_lane`. Any other key is refused with 400, so a misspelt key
cannot drop data without anyone noticing.

**Lead fields** (all text; only `phone` is required):
`full_name`, `first_name`, `last_name`, `phone`, `email`, `alternate_phone`, `city`, `state`, `country`, `course`,
`specialization`, `university`, `programme_level`, `study_mode`, `highest_qualification`, `academic_score`,
`work_experience`, `annual_budget`, `enrollment_timeline`, `preferred_language`, `guardian_name`, `guardian_phone`,
`enquirer_relation`, `preferred_call_time`, `notes`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`,
`utm_term`, `campaign`, `source_detail`, `referral_code`.

- Phone: any common Indian format. A 10-digit mobile number gets the country code 91.
- An invalid email is dropped and the rest of the lead is stored.
- Values longer than 500 characters are cut.

**Consent.** Store the time the student ticked each box:
- `sales_at`: contact about courses.
- `partner_share_at`: share with partner institutions. Without it the lead is never sent to a partner and goes to Eduwit's own B2C team.
- `marketing_at`: marketing messages.

Put the version of the consent text in `text_version`.

**Routing.** `route` is one of:
- `auto` (default): the normal rules apply.
- `hold`: the lead waits in the pre-routing pool until the Admin releases it.
- `b2c`: the lead goes to Eduwit's B2C team. Also send `b2c_lane`: `sales` or `nurture`.

`phone_verified: true` means you checked the number with an OTP. The lead then counts as verified for routing.

## 2. Responses

| Status | Meaning |
| --- | --- |
| `201` | A new lead was created |
| `200` | The phone was known: the lead was merged or reopened, or this is a replay of an earlier request (header `Idempotent-Replayed: true`) |
| `400` | Missing `Idempotency-Key`, a body that is not JSON, an unknown key or lead field, or an invalid `route` |
| `401` | Missing or invalid API key, or a key without the intake scope |
| `409` | This `Idempotency-Key` was used before with a different body |
| `413` | Body over 64 KB |
| `422` | The lead was refused (for example the phone is missing or too short). A retry with the same key returns the same answer |
| `429` | More than 600 requests a minute with one key |
| `503` | Eduwit could not store it right now. Retry with the same `Idempotency-Key` (after 1 s, 5 s, 30 s, …) |

**Body on success**

```json
{
  "ok": true,
  "lead_id": 1342,
  "action": "created",
  "is_test": false,
  "routing": {
    "status": "queued",
    "destination": null,
    "outlook": "partners",
    "waiting_for": [],
    "missing": []
  }
}
```

- `action`: `created`, `merged` or `reopened`.
- `routing.status`:
  - `queued`: the lead routes on the next run, within a minute.
  - `waiting`: `waiting_for` lists what is missing, for example `course` or `held for review`.
  - `already_routed`: the lead had already been routed.
- `routing.outlook`: where the lead will most likely go: `partners`, `b2c_sales`, `b2c_nurture` or `not_passed` (junk or programme mismatch).

On an error the body is `{ "ok": false, "error": "…" }`.

**Test leads.** A phone starting with `910000` or `9190000000` is stored as a test lead and is never routed automatically.

## 3. Example

```bash
curl -sS https://<crm host>/v1/leads \
  -H "Authorization: Bearer $EDUWIT_INTAKE_KEY" \
  -H "Idempotency-Key: web-$(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{"lead":{"full_name":"Test Lead","phone":"910000000123","course":"MBA"},"source":"api_test",
       "consent":{"sales_at":"2026-10-07T10:00:00+05:30","text_version":"test"}}'
```

## 4. Good practice

- Generate the `Idempotency-Key` once per submission and reuse it on every retry.
- Send `consent` with real times. Leads without partner-sharing consent cannot go to partners.
- Send `click_ids` (`gclid`, `fbclid`, `msclkid`…) and `utm`. They decide paid-campaign routing and, later, conversion reporting.
- Never put the API key in browser code. Call the API from your server.

## 5. Meta Lead Ads (set up on the Intake screen)

1. Intake → Connections: set a verify token, the app secret and a long-lived Page access token with `leads_retrieval`.
2. In the Meta app: Webhooks → Page → subscribe to `leadgen`, with callback URL `https://<crm host>/v1/webhooks/meta/leadgen` and the same verify token. Subscribe the Page to the app.
3. Each webhook is checked against `X-Hub-Signature-256` (HMAC-SHA256 of the raw body with the app secret). Eduwit then fetches the lead from the Graph API within about 10 seconds and retries up to 3 times.
4. A form Eduwit has not seen before is added under Intake → Ad forms, and an alert asks you to map it. Its leads are still stored: standard questions (name, phone, email, city, state, country) map by themselves, and any other answer goes into the notes until the form is mapped.

## 6. Google Ads lead forms

1. Intake → Connections: set a key (any long random text).
2. In the lead form asset → Lead delivery → Webhook integration: URL `https://<crm host>/v1/webhooks/google/leadform` and the same key.
3. Use "Send test data": Google marks it `is_test` and Eduwit stores it as a test lead.
4. Google sends the key in the body as `google_key`. A wrong key gets 401 and raises an alert. A lead that fails to store is kept for review, and Eduwit still answers 200 so Google does not resend it.

## 7. Files

The Admin imports Excel (.xlsx) or CSV files of up to 50,000 rows on the Intake screen. The steps are:

1. Map the columns. A mapping can be saved for reuse.
2. Check the courses against the catalogue.
3. See the duplicates before anything is written.
4. Record the consent basis, then choose where the leads go: route now, hold for review, or send to B2C.

The leads an import created can be rolled back for 24 hours if nothing has routed them yet. Old .xls files must be saved as .xlsx or CSV first.
