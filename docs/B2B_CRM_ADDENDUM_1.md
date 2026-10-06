# B2B CRM — Addendum 1: how leads reach Eduwit's B2C CRM

Version 6 October 2026 · Owner: Vikas Jha · Applies to `docs/B2B_CRM_PROMPT.md`

> **For Claude Code:** save this as `docs/B2B_CRM_ADDENDUM_1.md`. **Where it differs from the main prompt, this addendum wins.** It changes which leads the routing engine sends to partners. Read it before Phase 1, and list any conflict with work already done in your next report.

## Why this addendum exists

Eduwit has now designed its B2C CRM. It holds in-house sales and all nurture marketing, as a separate product with its own spec (`B2C_CRM_PROMPT.md`). Vikas has made five decisions that change the B2B routing rules:

1. **All paid-campaign leads** go to the B2C CRM for the in-house sales team.
2. **Every qualified lead is sales-ready.**
3. **Once a lead is with the B2C CRM, it never goes back to a partner automatically.** Only a manual action sends it to partner routing.
4. **Leads a partner marks lost** go automatically to the B2C CRM for nurture, not to a counsellor.
5. **Leads that are not qualified** go to the B2C CRM's nurture pool. The B2C CRM nurtures them and gives them to its own counsellors when they show interest again.

The B2B CRM remains **the one place that makes and records every routing decision**. It writes the allocation and the hand-off event; the B2C CRM owns the lead from then on.

## 1. The routing decision, revised (replaces B7.1 steps 1–2 and extends B7.6)

For every lead, in this order:

| # | Check | Destination | B2C lane | Reason code |
| --- | --- | --- | --- | --- |
| 0 | **The lead has ever been handed to the B2C CRM** (any enquiry cycle), and no later manual route-to-partners has moved it | **No partner routing.** The lead stays with B2C, in every later cycle too. If it is in B2C's pool and something new happens (a new paid enquiry, Witty qualifies it), B2B emits `b2c.lead_reenquired` (lead ID, what happened) so B2C can assign it | — | — |
| 0b | **Created by the B2C CRM** (`lead_source` `b2c_created` or `b2c_whatsapp`) | B2C at once, no partner routing | `sales` | `b2c_created` |
| 1 | **Paid campaign** (rule below) | B2C at intake | `sales` | `paid_campaign` |
| 2 | **Not qualified** when its qualification window ends (rule below) | B2C | `nurture` | `not_qualified` |
| 3 | No partner-sharing consent | B2C | `sales` | `no_partner_consent` |
| 4 | Qualified and none of the above | **Partner routing** (B7, unchanged), with its existing fallbacks to B2C: `duplicate_cascade`, `no_partner_offers_programme`, `no_capacity`, `partners_unreachable`, `import_choice`, `manual` | `sales` for every fallback | as in B7.6 |
| 5 | **Partner marks the lead lost** (mapped to Eduwit stage `lost`), or recalled as lost | B2C, automatically | `nurture` | `partner_lost` |

**Paid-campaign rule** (configurable list in Settings, with these defaults). A lead counts as paid if any of these hold:

- its source is Meta Lead Ads or a Google Ads lead form;
- its first touch carries a paid-ad click ID (`fbclid`, `gclid`, `gbraid`, `wbraid`), or a `utm_medium` of `cpc`, `ppc`, `paid`, `paid_social` or `paidsocial`;
- it came from a click-to-WhatsApp ad (Meta's referral data on the first Witty message, when Witty records it).

The Admin can add or exclude campaigns by name or ID. This replaces the earlier example rule "paid Meta leads for NMIMS MBA always to Partner X". **Paid leads never go to partners automatically.**

**Paid leads that start on Witty** (click-to-WhatsApp ads). These are handed to B2C lane `sales` when Witty finishes qualifying, or after the chat has been idle for 30 minutes, **not on the first message**, so Witty is never cut off mid-conversation.

**A paid enquiry from a student already with a partner.** It stays with that partner (intake merges it and records the touchpoint) and is shown on the lead; it is not moved to B2C.

**Qualification window.** When does an unqualified lead go to nurture?

- **Witty and website-agent leads:** when the chat has been idle for **24 hours** (configurable) and the lead is still not qualified. While the chat is active, the lead waits in the B2B pre-routing pool.
- **Every other source:** at intake, if the lead is not qualified.
- **"Qualified"** means the ready-to-route rule in B4: Witty's or the website agent's qualification complete, or for other sources the course plus valid contact known. Qualified equals sales-ready, with no separate score gate.

**Rules can now name B2C.** The main prompt said a routing rule can never name the B2C CRM. That changes: rules **may** send a lead to B2C, with lane `sales` or `nurture`. Paid campaigns are implemented as one such built-in rule. The kill-switch fixed split still covers partners only.

**Manual send to partners.** Partner-sharing consent is required. The B2B Admin can push a B2C-held lead into partner routing with a reason. The B2C CRM can also ask for it through `POST /v1/leads/{id}/route-to-partners` (B2C service key, reason required). This is the only way a B2C lead reaches a partner. It is recorded as `mode = 'manual'`. The previous B2C allocation becomes `closed`.

- **When a partner accepts it,** B2B emits `b2b.lead_routed_to_partner`, and the B2C CRM closes its pipeline for the lead.
- **If no partner accepts it** (duplicates, no partner offers the programme, failures), B2B hands it straight back to B2C, lane `sales`, reason `manual_route_failed`, and B2C returns it to its previous counsellor.

## 2. Hand-off contract, revised (replaces B10 items 1–2 and 4)

- **Allocation.** `destination_type = 'in_house'`, `mode` (`rule` for paid and B2C-created, `fallback` otherwise), `reason` (codes above), **`b2c_lane`** (`sales` or `nurture`; add this column to `allocations`), status `handed_off`. It stays `handed_off` while B2C holds the lead, and becomes `closed` only when a manual route-to-partners replaces it (add the transition `handed_off → closed`).
- **Codes.** `manual` now means only the Admin's re-route from partners to B2C. Leads created in B2C use `b2c_created`.
- **Event.** Emitted as `b2c.lead_handed_off` with this payload:
  - lead ID;
  - `b2c_lane` and `reason`;
  - the partners tried and their outcomes;
  - for `partner_lost`: the partner's lost reason, its raw status and sub-status, the partner's last activity, and the partner record ID.
- **Notification.** The B2B CRM sends **no student notification** for any B2C hand-off. The B2C CRM messages the student from its own WhatsApp number every time it assigns a counsellor (sales-lane hand-offs and re-engagements). Set `b2c_sends_own_notification = true` permanently, and remove the Eduwit-branded fallback message from Phase 1 and the matching lines in B9, B10 and B21.
- **Delivery.** By signed webhook to the B2C CRM's `POST /v1/handoffs`, plus a reconciliation API `GET /v1/handoffs?since=` (B2C service key). The B2C CRM never reads `b2b.integration_outbox` directly.
- **Partner-lost leads.** The partner keeps its lost status in its own CRM. The B2B allocation becomes `closed` with outcome `lost`, and the lead's partner-sync columns stay as history. If a partner later reports activity on that lead (a late enrollment, say), it is logged and alerted for a commission dispute review, not applied automatically.

## 3. Column ownership by holder (refines A3)

The sales-effort, application, enrollment and revenue columns of `student_leads` are written by **whichever product currently holds the lead**:

- the B2B CRM (from partner sync) while a partner holds it;
- the B2C CRM while B2C holds it.

Hand-over rule: when B2B hands a lead to B2C, the B2C CRM sets the next `stage` (`nurture` or `assigned`), and B2B writes no more pipeline columns for it. Add the B2C stages `nurture`, `assigned`, `dormant` and `routed_to_partner` to B2B's stage list as "held by B2C", outside the partner funnel rank. `lead_score` and `temperature` are written by the B2C CRM's scoring for B2C-held leads.

These columns are: `first_contacted_at`, `last_contacted_at`, `contact_attempts`, `next_task_due_at`, `stage`, `sub_stage`, `application_*`, `fee_*`, `enrollment_*`, `enrolled_*`, `lost_*`, `expected_net_revenue_inr`, `realised_net_revenue_inr`.

The allocation columns (`destination_type`, `partner_id`, `allocation_id`, `allocated_at`, `allocation_reason`) are written **only** by the B2B CRM. The B2C CRM writes its own assignment columns (`owner_user_id`, `assigned_at`, `team_id`).

## 4. Events from the B2C CRM (new consumer)

The B2C CRM emits `b2ccrm.lead_assigned`, `b2ccrm.stage_changed`, `b2ccrm.enrolled`, `b2ccrm.opted_out` and `b2ccrm.erasure_requested`. B2B receives them at `POST /v1/events/b2ccrm` (HMAC). It uses them to:

- update the Master Lead Table;
- send CAPI events;
- tell every partner that ever received the lead about opt-outs and erasure (through adapters, or by email).

## 4b. Witty contract for B2C leads

Agree this with Witty's developer in Phase 0.

- **Keep talking to nurture leads.** Witty stops selling only when a **partner has accepted** the lead or a **B2C counsellor is assigned** (`owner_user_id` set). It keeps talking to B2C nurture-lane leads, because Witty re-engagement is a key way those leads come back.
- **Explicit interest signal.** Witty emits one, so the B2C CRM need not infer it. An example: a new inbound message after the lead entered the pool, together with an interest intent (fees, admission, eligibility, apply, wants a call) or qualification complete.

## 5. Money ledgers stay separate

The existing empty tables `earning_rates`, `enrollments`, `earnings` and `invoices` move to the `b2b` schema as planned and hold **partner** commissions only. The B2C CRM keeps its own university-commission rates, enrollments, earnings, invoices and counsellor payouts in its `b2c` schema. The Master Lead Table (B6.1) shows commission for B2C-held enrollments by reading the B2C CRM's published read-only view, `b2c_enrollment_money_v`, so the B2B Admin still sees every lead's money in one place.

## 6. Unchanged hub duties

The B2B CRM still owns:

- **Intake:** the Intake API and the Meta and Google webhooks.
- **The Master Lead Table**, which shows B2C leads too, with their B2C stage, counsellor and lane.
- **CAPI**, which sends conversion events for **every** lead, including B2C-held ones, from stage changes in `student_leads` whoever wrote them.
- **Analytics across all destinations,** where B2C appears as one destination with lane `sales` or `nurture`.

## 7. Tests to add (Phase 1 exit)

1. A Meta Lead Ads lead and a website lead with a `gclid` both go to B2C lane `sales` with reason `paid_campaign`. Neither reaches a partner.
2. A Witty lead idle 24 hours and unqualified goes to B2C lane `nurture`.
3. A B2C-held lead that Witty later marks qualified is **not** routed to a partner.
4. A partner marks a lead lost: the lead goes to B2C lane `nurture`; no student message is sent by B2B; the allocation is closed with outcome `lost`.
5. A manual "route to partners" on a B2C lead reaches a partner, and the B2C CRM receives `b2b.lead_routed_to_partner`. When every partner claims a duplicate instead, the lead returns to B2C with reason `manual_route_failed`.
6. A lead once held by B2C, closed, then returning months later in a new cycle, goes to B2C, not to a partner.
7. A lead created in the B2C CRM (`b2c_created`) goes to B2C at once.
8. A paid click-to-WhatsApp lead is handed to B2C only after Witty finishes qualifying or the chat idles for 30 minutes.
