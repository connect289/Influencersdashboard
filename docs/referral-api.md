# Referral outcomes API (influencers and referral partners)

Who referred which student, and what became of it, without any personal data. For the influencer dashboard and for
referral partners who want to check their numbers. Built by migration `m33d`.

## The view

`public.b2b_referral_outcomes` (one row per lead carrying a referral code; `security_invoker`, so a signed-in reader sees
only the leads their row-level policies allow):

| Column | Meaning |
|---|---|
| `referral_code` | The code the student used, as entered (compare case-insensitively) |
| `lead_ref` | 12-character hash of the lead; stable, never the id, never reversible |
| `enquired_on` | Date of the enquiry |
| `stage` | Eduwit stage (`new` … `enrolled`, `lost`) |
| `enrolled` | `true` once the stage is enrolled or an enrolment is reported or verified |
| `programme` | The course enquired about |
| `enrolled_program` | The programme enrolled in, when known |
| `updated_on` | Date of the last change |

Deleted, merged and erased leads are not listed. No name, phone, email or city.

## The endpoint

```
GET https://crm.eduwit.in/v1/referrals/{code}/outcomes?after=<cursor>&limit=<1..500>
Authorization: Bearer <API key with scope referrals>
```

Answer `200`:

```json
{ "ok": true, "referral_code": "INF001", "outcomes": [ { "lead_ref": "e2bebff65567", "enquired_on": "2026-10-15", "stage": "contacted",
  "enrolled": false, "programme": "MBA", "enrolled_program": null, "updated_on": "2026-10-15" } ], "next_after": 338 }
```

Page with `after=<next_after>` until `outcomes` is empty. `400` for a blank code, `401` for a key without the scope,
`429` with `Retry-After` over the key's rate limit (60 requests a minute by default for this scope). Codes match
case-insensitively; an unknown code answers an empty list, never an error.

Keys are created on System health → Webhooks and API keys with the scope **referrals** only; give each influencer
platform its own key with an expiry.
