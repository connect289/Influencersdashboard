# Eduwit Spark: completing the spec

Version 16 October 2026. Vikas asked on 16 October to build Spark completely before the production steps
(go-live plan steps 1, 3–10 wait until then). A section-by-section audit of the spec (B3–B19) against the code found the
gaps below. Each is built as migration `b39` onward plus app changes, with rolled-back checks in
`supabase/tests/test_completion.sql`. The hard limits stand: staging only, test leads only, never `w2_*`,
`lead_intake()`, the n8n workflows, the B2B CRM or `student_leads_v2_rename.sql`.

Status: `[ ]` to do, `[x]` built and checked.

Built 15–16 October 2026 as migrations `b39` (nurture), `b40` (leads table and Admin tools), `b41` (counsellor workspace),
`b42` (access, stages, allocation), `b43` (money, analytics, connectors, templates, platform) and `b44` (programme facets),
with the matching screens. Checks: `test_completion.sql` (209 database checks) and every earlier SQL suite on a clean local
database; 174 unit tests; typecheck and production build; the browser walkthrough of every screen per role on staging
(`web/e2e/walkthrough.spec.ts`, see the note at the end). Two items are built but switched off until outside parties act:
E14 (the B2B write API must accept the fields) and D6 (needs the Google OAuth client, handover step 4.2).

## A. Nurture pool and re-engagement (B6, B9)

- [x] A1 Not-qualified leads that re-engage while still missing details are not assigned for selling: first an
      automated qualification step (Witty invitation or a 3-question form link), then after 48 h a task in the Admin's
      **To qualify** queue; once complete the lead goes back to B2B routing (B6.3, L294–298)
- [x] A2 Opt in again after a full opt-out (B6.5, L339)
- [x] A3 Scoring rules that never fire: Witty conversation resumed, form filled; fit "qualification meets the
      programme minimum" (B9.5)
- [x] A4 Partner-lost first message delayed by the mapped lost sub-stage (3/7/30/60/90 days) when the B2B payload has
      no time (B6.4, L332)
- [x] A5 Partner's history (calls made, last outcome, raw status) on the timeline and the lead header (B6.4, L334)
- [x] A6 Pool health: outflow (dormant, opted out, closed, re-engaged) per day; reason and age buckets by lost reason;
      last message and last student activity across WhatsApp and email; deliverability on the Overview (B6.2, B9.0)
- [x] A7 Journey triggers: a field changes, a date arrives, email opened or clicked, WhatsApp reply; step "update a
      field or score" (B9.4)
- [x] A8 WhatsApp spend per journey beside its re-engagements and enrolments (B9.7)
- [x] A9 Segment fields: partner lost reason, last activity, last reply, engagement (B9.1)
- [x] A10 Campaign results: sent, replies split positive and negative, email replies (B9.3)
- [x] A11 A designated counsellor may answer the Replies inbox (B6.3, L311)
- [x] A12 Templates: media headers on WhatsApp templates, import templates already on the account, version history,
      preview with a real test lead, performance figures, a block editor for marketing email (B9.2, B9.2a)

## B. Leads table and Admin tools (B8.2, B10)

- [x] B1 Views: every lead property and sales activity as a filter, AND/OR groups, "this month", column chooser and
      order, group-by with totals, list or kanban, density, pinned default, shared by link, standard views published
      to Sales (B8.2, B10.1)
- [x] B2 Table columns from B10.1: lead date, source, campaign, lane and reason, partner history, calls and last
      outcome, journey, application and enrolment, university and counsellor commission; live refresh
- [x] B3 Bulk: add to or remove from a journey (Marketing too), change stage, select all rows of a view across pages,
      bulk delete with typed confirmation as a background job (B10.3, B10.4)
- [x] B4 Student erasure request (DPDP): anonymise, delete message bodies and documents, keep money rows, emit
      `b2ccrm.erasure_requested`, logged with the request reference (B10.4)
- [x] B5 Export: selected rows, Excel as well as CSV, over 10,000 rows in the background with an expiring link (B10.5)
- [x] B6 The Admin edits any lead, pooled and closed included (B10.2)

## C. Counsellor workspace (B8)

- [x] C1 WhatsApp inside the window: images, documents and brochures out; inbound media viewable; attach an inbound
      document to the application checklist in one tap (B8.5, B8.8)
- [x] C2 Programme page complete: duration, exam and registration fees, EMI, scholarship, intakes, partners offering
      it and the partner and counsellor commission (Admin and Marketing only); filters (university, programme,
      specialization, level, mode, fee range, duration, intake, accreditation, eligible for this lead), sort; compare
      2–4 and send; Marketing access; `programme_cache` (B8.9). Redesigned 16 Oct: grouped by university, cards lead with
      the full fee (`b44` course facet)
- [x] C3 Pipeline: expected commission per column, SLA colour, priority order, filters, counsellor filter for the sales
      head (B8.2)
- [x] C4 Sales email library: recommended and hidden (Admin), delete, author name, reply rate, all merge fields,
      attachments from the Programme page, link-click tracking (B8.6)
- [x] C5 Inbox: search message text and template name; filters by counsellor, window open or closed, awaiting reply;
      Marketing sees every conversation read-only (B8.5)
- [x] C6 Programme fit by eligibility (qualification, budget) side by side with EMI and duration (B8.3)
- [x] C7 Follow-ups: the Admin's view of everyone with a counsellor filter; programme interest and note on rows; next one
      highlighted; upcoming grouped by day; optional WhatsApp reminder to the counsellor's own number (B8.2, B8.7)
- [x] C8 Call log sheet: talk time from the time away, the outcome's suggested next task offered (B8.4)
- [x] C9 Lead screen: lead score in the header; primary per channel; WhatsApp-only label; call any number; custom
      profile fields; done tasks (B8.3)
- [x] C10 Documents: checklist editor in Settings; counsellors open their leads' uploads (B8.8)
- [x] C11 SLA minutes by source as well as temperature; neglect flag after 48 h untouched (B8.7)

## D. Money, analytics, integrations and platform (B11–B18)

- [x] D1 Reconciliation feed `GET /v1/events?since=` for the B2B CRM (B17)
- [x] D2 Published view `public.b2c_lead_status_v` (B14, B17)
- [x] D3 Workspace inbox: every WhatsApp conversation, read-only for Marketing, with the Replies inbox (B15)
- [x] D4 Settings edits stages and sub-stages (with change history) and document checklists (B5.1, B15)
- [x] D5 Connectors: B2B test ping; WhatsApp health, quality and template sync; Claude key and spend; Gmail sends today;
      each connector's last success and last error; personal "WhatsApp to my own number" alerts (B17)
- [x] D6 Per-user Gmail connection by OAuth (`user_connections`), revocation detected and shown (B16, B17, B18)
- [x] D7 Metrics: the Eduwit stages with conversion and time per stage, B2C-created leads, duplicate cascades by partner,
      journey steps, suppression by cause, margin per university, receivables, targets against actuals, capacity (B13.2)
- [x] D8 Insights on demand, each with the chart behind it (B13.4)
- [x] D9 Metric alerts by WhatsApp (B13.3)
- [x] D10 Admin commission dashboard: by counsellor, status and month; run calendar; numbers open their enrolments (B11.3)
- [x] D11 Invoices emailed to the university with the PDF; run statements emailed to each counsellor (B11.1, B11.2)
- [x] D12 Guides can show screenshots (B15)
- [x] D13 "View as Sales" for a chosen counsellor, logged (B3.1, B15)
- [x] D14 Rate limits on the public `/v1` endpoints; breach runbook; dependency scanning in CI (B18)

## E. Access, intake, stages and allocation (B3, B4, B5, B7)

- [x] E1 Flagged leads: badge, an Admin review list with "close as junk / cannot be served" or "keep", journeys paused
      while flagged (B4.1)
- [x] E2 Stages and sub-stages editable by the Admin with a change history (B5.1) — with D4
- [x] E3 A counsellor hands a lead back with a reason; the sales head reassigns in the Sales app (B7.5, B3.1)
- [x] E4 Assignment message by email when WhatsApp fails or there is none; the Witty-idle wait checked at send time (B7.6)
- [x] E5 Hot leads outside hours go to the on-call counsellor when one is set, whatever the rule's fallbacks (B7.1, B7.3)
- [x] E6 Queues tab: unassigned, waiting for hours and manual queues apart, one-click allocate, pick a person for the
      manual queue; the manual queue is not re-decided every minute (B7.3, B7.4)
- [x] E7 Working calendar: shift roster, breaks and lunch (only hot leads then), holiday list import, week view with
      leave and holidays and "nobody on duty" warnings (B7.1, B7.4)
- [x] E8 Capacity: alerts to the Admin (90% of cap, hiring trigger), capacity on the Lead Allocation page with today's
      intake (B7.5)
- [x] E9 Teams lists every Workspace user not yet added (one-click role); invites by email that expire after 7 days
      (B3.2)
- [x] E10 Sessions: 7 days on a trusted device, a list of signed-in devices, remote sign-out (B3.2)
- [x] E11 Breached-password check (B3.2)
- [x] E12 Lead screen: "Lost by partner" with the partner's history, "Routing to partners…" (and no second request),
      "Already with {partner} since {date}" when a new lead's phone exists (B4.1–B4.3)
- [x] E13 Rules editor: "applies from" date and "any of these" conditions; simulation of disabled or future rules
      (B7.4)
- [x] E14 `team_id`, expected and realised net revenue written to `student_leads` through the B2B write API (B3.3)
- [x] E15 Sales head: their team's leads only; stage overrides requested by counsellors and approved by the sales head
      (B3.1)
