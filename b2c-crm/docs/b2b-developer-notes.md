# Notes for the B2B CRM's developer (Spark b39–b43)

Version 16 October 2026. Spark is the B2C CRM. These are the changes since contract v3 that touch the B2B CRM. Nothing here
needs a B2B change to keep working: unknown events are already answered 200 "ignored", and the new writes stay off until
you confirm them.

## 1. New events Spark sends (`b2ccrm.*`)

| Type | When | `data` |
| --- | --- | --- |
| `b2ccrm.qualification_completed` | A not-qualified lead that came back gave its missing details (form, Witty or a counsellor) | `{ "answers": {…}, "via": "form" \| "counsellor" \| "witty" }`. The answers also go as a normal urgent update through the write API |
| `b2ccrm.opted_in` | A student who had opted out asked to hear from Eduwit again | `{ "source", "channels": ["whatsapp", "email"] }` |
| `b2ccrm.erasure_requested` | The Admin erased a student on request (DPDP) | `{ "reference", "note" }`. Spark has anonymised its copy; please erase or anonymise `student_leads` and the partner copies under your own process |

Until you handle them, they are harmless: you answer 200 "ignored".

## 2. Reconciliation feed: `GET /v1/events?since=<seq>&limit=<1–1000>`

Every event Spark has sent you, oldest first, after a sequence number. The answer:
`{ ok, events: [{ seq, event_id, type, lead_id, occurred_at, data, delivery }], next_after }`. Pass `next_after` as the
next `since`. Sign it as you sign the webhooks, over `<timestamp>.GET <path>?<query>` instead of a body (headers
`x-eduwit-timestamp` and `x-eduwit-signature`; see `web/lib/b2b-sign.ts`). Rate-limited per caller.

## 3. Published view: `public.b2c_lead_status_v` (service role only)

One row per B2C lead not deleted: `view_version` (1), `lead_id`, `lane`, `status`, Eduwit `stage`, `sub_stage`,
`canonical_stage`, `stage_changed_at`, `counsellor`, `counsellor_email`, `assigned_at`, `pool_reason`, `journey`,
`reengaged_at`, `reengage_trigger`, `closed_at`, `closed_reason`, `routing_requested_at`, `is_test`, `updated_at`.
Read it for the Master Lead Table next to `public.b2c_enrollment_money_v`.

## 4. Fields Spark will write through your write API once you accept them (B3.3)

`team_id` (on assignment), `expected_net_revenue_inr` and `realised_net_revenue_inr` (when the university commission is
booked or realised). They are **off** (`b2c.settings` key `b2b_writes.team_and_revenue = false`) because a refused field
would hold back the other changes queued in the same update. When your write API accepts them, tell Vikas and the Admin
switches the setting on in Settings.

## 5. The catalogue (read-only for Spark)

Spark caches `catalog_programs` in `b2c.programme_cache` every 15 minutes. The Programme page can show duration, EMI,
scholarship, intakes and the application deadline when your Programme Repository carries them in
`catalog_programs.fee_other` under these keys: `duration_months` (or `duration_years`), `emi_monthly`, `scholarship`,
`intakes` (a list, or a comma-separated text), `deadline`. Nothing else changes; Witty is unaffected.
Partners offering a programme and their commission are read from `b2b.partner_programmes` and `b2b.partners` (Admin and
Marketing only).

## 6. Erasure and deletes

A bulk delete in Spark is a soft delete (30-day undo) and only affects Spark's copy. Erasure (section 1) is final in
Spark and is the only case that asks you to act.

Contact: vikas@eduwit.in.
