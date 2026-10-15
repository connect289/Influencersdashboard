# Eduwit B2C CRM: Phase 4 plan ("Telephony and depth")

Version 15 October 2026 · Spec B19.2 row 4, B8.4 (telephony later), B7.3 (performance-weighted), B17 (Connectors),
B13.2 (inflow and money metrics) · Builds on Phases 1–3 (b1–b24 on staging)

## Decisions (Vikas, 15 October)

- **Approved.** Exotel is the provider for now; it may change later, so it sits behind an adapter.
- **For now counsellors dial from their own phones** and log calls by hand: telephony ships switched off
  (`provider = none`) and no call is recorded. When Exotel (or another service) is switched on, **every call is
  recorded**; there is no per-call or per-person choice.
- **Students' numbers stay visible to counsellors**, with or without telephony.
- **No Hindi.** The whole CRM stays in English; the Hindi part (b29 and the message files) is dropped.

## Rules for the whole phase

The same as Phases 1–3:

- Staging only (`mplbspysxmtohnlwpbti`). Test leads only.
- Never touch `w2_*`, `lead_intake()`, the n8n workflows, the B2B CRM or `student_leads`.
- Every business rule is a `b2c.*` function with rolled-back checks in `tests/test_phase4.sql`.

New for this phase:

- **No real call is placed in a test.** Every provider sits behind an adapter with a **mock provider** that plays the
  provider's webhooks (ringing, answered, completed, no answer, missed inbound) with a sample recording. Test leads are
  never dialled by a real provider, whatever the setting. A live check with a real phone needs your explicit go-ahead
  and your own number (see "What I need from you").
- **Recordings are personal data.** Stored in a private bucket, opened only by people who may see the lead, every
  play logged, deleted after a retention period you set.
- **Calendar events carry no phone number or email**: the student's first name, the task and a link to the lead.

## Database, in migration order

| File | Contents |
| --- | --- |
| `b25_telephony` | **The adapter's tables (B8.4):** `calls` gains direction (outbound, inbound), provider status, `bridged_at`, `ended_at`, recording path and status, cost; `call_events` keeps every provider event once (idempotent by provider event id). `call_start(lead)` checks the person may call the lead, the lead is not opted out and not a test lead (test leads go to the mock), then returns what the provider needs. `call_event(p)` applies an event: a completed bridged call is **logged by itself** (outcome from the provider status, real talk time, `contact_attempts`, first and last contact, the automatic stage moves of B5.2, the next task suggestion), so the log sheet becomes optional. **Missed inbound calls** from a known number become a callback task for the owner (or the Unassigned queue), with a phone alert. Unknown numbers become a "missed call" item on the Admin's home. Settings `telephony`: provider (`none` until you switch Exotel on, `mock` for tests, `exotel`), caller ID, retention days. Every bridged call is recorded; numbers stay visible. |
| `b26_ad_spend` | **Return on ad spend (B13.2 inflow and money):** `ad_spend_daily` (date, platform Meta or Google, account, campaign id and name, ad set, spend, impressions, clicks, leads the platform reported, currency), loaded by CSV import first (the standard exports of Meta Ads Manager and Google Ads), upsert per day and campaign, so a re-import replaces rather than doubles. `ad_campaign_map` ties a platform campaign to the lead's source and campaign values, with a suggested match by name. New metrics and dimensions in the catalogue: spend, cost per lead, cost per qualified lead, cost per enrolment, **ROAS** (university commission net, expected and realised, of the leads from those campaigns ÷ spend), by platform, campaign and month. A standard "Ad spend" dashboard for the Admin and Marketing. |
| `b27_performance_allocation` | **Performance-weighted allocation (B7.3, phase 4):** today `performance` behaves like weighted round robin. It becomes: each counsellor's conversion over the rule's window (30 or 90 days: enrolments ÷ leads assigned), smoothed towards the team's rate when the sample is small (so two lucky enrolments do not dominate); turns in proportion to it, with a **floor** (default: half an equal share) and a **cap** (default: twice an equal share), so nobody is starved or flooded. New joiners use the team rate until they have 20 leads. Every decision records the window, each person's rate and share, the floor and cap, so it stays explainable, and the **simulation** shows the expected shares before the Admin turns it on. |
| `b28_calendar` | **Google Calendar sync of follow-ups (B17 Connectors, personal):** per person on/off (Connectors → Calendar), one-way CRM → Calendar. Creating, moving, completing or cancelling a follow-up creates, moves or removes an event in the counsellor's own calendar through domain-wide delegation (scope `calendar.events`), through an outbox with retries. `calendar_events` keeps the Google event id and etag per task. Events: "Call Asha (Online MBA)", the due time, a 10-minute reminder, the lead link. Edits made in Google Calendar are not read back in this phase (said on the Connectors screen). |

## App

| Area | What |
| --- | --- |
| Telephony | A provider adapter in `lib/telephony/` with `startCall`, `parseEvent`, `fetchRecording`: **Exotel** (click-to-call that rings the counsellor's phone first and then the student, status callbacks, recording download), ported from the old CRM's Exotel code (`crm/web/lib/comms/exotel`, read only, never edited) and the **mock**. `POST /v1/webhooks/telephony/[provider]` (a secret key in the URL, as Exotel does not sign webhooks, plus an allow-list of Exotel's addresses). The Call button bridges the call when telephony is on and still falls back to `tel:` when it is off. Recordings play on the lead's timeline. Connectors → Telephony: status, last event, a test call to the mock. |
| Ad spend | `/w/money` → "Ad spend" tab (Admin, Marketing): CSV upload with a preview, the campaign map, and the Ad spend dashboard in Analytics. |
| Allocation | The Lead Allocation page explains the performance logic (window, floor, cap) and shows each counsellor's current rate and share in the simulation. |
| Calendar | Connectors → "Show my follow-ups in Google Calendar" per person; the Admin sees who has it on and any sync errors. |

## Exit test

The spec's: **calls are bridged and recorded and appear on the timeline without manual logging.** In detail, on staging
with the mock provider and test leads:

1. Tapping Call on a test lead starts a bridged call; the provider's ringing, answered and completed events log the
   call by themselves with the real duration and outcome, move the stage as B5.2 says, and attach the recording, which
   plays on the timeline within 2 minutes.
2. A no-answer call logs "no answer", moves New Lead to Could Not Connect and suggests the retry task; no "call not
   logged" flag appears.
3. A missed inbound call from a test lead's number creates a callback task for its owner with a phone alert.
4. A repeated webhook changes nothing; a webhook without the key is refused; a recording opens only for someone who may
   see the lead, and the play is logged.
5. An imported Meta CSV and Google CSV give spend, cost per lead and ROAS that match a manual calculation; importing
   the same file again changes nothing.
6. Performance allocation: over 200 simulated leads every counsellor's share is within the floor and cap, and the
   decision record explains each pick.
7. A follow-up created, moved and completed creates, moves and removes the event (against a mock calendar in the test;
   once against a real calendar with your go-ahead).

Phases 1–3 checks keep passing.

## What I need from you (none blocks the build; all block going live)

1. **Exotel, when you switch it on:** the account (KYC done), a virtual number for caller ID, the API key, token, SID
   and subdomain, and each counsellor's mobile number in Teams.
2. **Recording:** the retention period (180 days unless you say otherwise) and the announcement the student hears
   ("this call is recorded for quality and training"), set in Exotel's call flow.
3. **Ad spend:** which ad accounts (Meta, Google) and who exports the CSVs. API pulls later need a Meta system-user
   token and a Google Ads developer token.
4. **Calendar:** add the scope `https://www.googleapis.com/auth/calendar.events` to the service account's domain-wide
   delegation.
5. **A live call test:** once Exotel is set up, permission to place one bridged call between two numbers you own.

## As built (15 October 2026)

- **b25 telephony.** Settings `telephony` starts at `provider: none`, so the Call button works exactly as before. With
  `exotel` (or `mock`) `call_start` returns a bridged call; `call_event` takes the provider's events once each, logs a
  finished call through the same `call_record` the manual sheet uses, and handles missed incoming calls (call-back task)
  and unknown numbers (listed under Connectors). If the provider refuses a call (keys missing, LIVE_MODE off, an API
  error) it is marked "not placed" and no attempt is counted; if the counsellor's own phone does not answer, likewise.
  Recordings go to the private `b2c-recordings` bucket and are removed after `retention_days`. The unlogged-call flag
  now applies to manual calls only. Students' numbers stay visible.
- **b26 ad spend.** CSV imports per day and campaign (re-import replaces), the campaign map, the `ads` analytics source
  and nine metrics, the Ad spend dashboard. Spend rows have no lead, so `analytics_exec` now counts them in test mode
  too (the only change to it).
- **b27 performance-weighted allocation.** `perf_shares` (the maths, tested on its own) and `perf_weights` (real leads
  only); `decide` uses them for the `performance` logic and records each counsellor's share in the decision.
- **b28 Google Calendar.** One-way sync of follow-ups per person, through an outbox with retries.
- **b29** six guide articles. Hindi was dropped by decision.
- Exit test `supabase/tests/test_phase4.sql`: 47 checks pass locally (bridged calls log themselves, the timeline without
  manual logging, repeated webhooks ignored, missed and unknown calls, recordings and their access, ROAS against a
  manual calculation, drill-down of ad leads, shares within floor and cap over 200 simulated leads, calendar events with
  no phone or email). Phases 1–3 still pass (99, 45, 91). App: 90 unit tests, typecheck and the production build.
- Not yet tried against the real services: an Exotel call, Google Calendar with a Workspace account, a real ad export.
