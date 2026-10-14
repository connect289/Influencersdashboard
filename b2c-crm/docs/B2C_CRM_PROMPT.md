# Eduwit B2C CRM — Build Prompt for Claude Code (FINAL)

Version 14 October 2026 (final, with Vikas's answers of 14 October; supersedes the 6 October draft) · Owner: Vikas Jha, Eduwit Learning Services

> **How to use this file.** Create a new repository (for example `eduwit-b2c-crm`). Save this file as `docs/B2C_CRM_PROMPT.md` and the Eduwit logo in `docs/brand/`. Then tell Claude Code:
> *"Read docs/B2C_CRM_PROMPT.md end to end. Start with Phase 0 and stop after the audit report and the clickable design for my review."*
> Part A tells Claude Code how to work. Part B is the product specification. **B21 records Vikas's decisions of 14 October, the points still open and the defaults in force; where B21 differs from an earlier section, B21 wins.**

---

# PART A — Brief to Claude Code

## A1. Your role

You are the lead engineer building **Eduwit's B2C CRM**: the in-house sales and marketing system of Eduwit Learning Services. It does two jobs:

1. **Nurture.** Every lead that is not yet qualified, and every lead a partner has lost, lands here. Marketing keeps it warm by WhatsApp and email until the student shows real interest again; then a counsellor takes over.
2. **Sell.** Eduwit's in-house counsellors (also called sales managers) work every lead routed to them, from first call to enrollment. Partners get the bulk of Eduwit's leads, including paid Meta and Google leads. B2C is the **fallback**: mainly leads partners report as duplicates or mark lost, plus leads no partner can take, and re-engaged leads.

Build it as an industry-grade product for a **small team** (the Admin, a marketing team of one or two, and up to about five counsellors at first). It must be fast and simple enough that a counsellor runs a whole working day on a phone, and rigorous enough that every rupee of commission can be traced.

**Three user types, three interfaces.** Admin, Marketing and Sales (counsellors and sales managers) each get their own interface, built for their work. Admin and Marketing share the same workspace layout (Marketing sees everything the Admin sees but can only act on marketing); Sales has a separate app. They never intermix (B15). Where this prompt says **"Admin"** for a marketing capability (templates, journeys, campaigns, nurture, analytics), read **"Admin and Marketing"**.

**The benchmark is LeadSquared and Salesforce.** Wherever this prompt describes nurture, templates, lead views, dashboards or lead allocation, the depth expected is what those products offer; build to that standard, not to a minimum.

## A2. How to work

1. **Plan before you build.** Write a short plan per phase (files, migrations, tests) and wait for approval before large or irreversible changes.
2. **Audit first (Phase 0).** The shared Supabase database already holds much of the B2C backend from an earlier combined design (A4). Inventory it, test it, and give each object a verdict (**keep**, **refactor** with how, or **not ours**) before writing new migrations. Reuse what fits and never build a parallel copy.
3. **Small, reviewable steps.** One feature per branch and pull request, each with tests and a short note on how it was verified.
4. **Business rules live in the database.** Assignment, stage moves, re-engagement, money and payouts run as SQL functions in transactions with constraints. The UI and workers call them.
5. **Test leads only until live.** Prove every flow on test leads with sandbox providers. A `LIVE_MODE` flag per channel (WhatsApp, email) defaults to off.
6. **Explain everything.** Every assignment, re-engagement, commission and payout must be traceable from stored records.
7. **Ask when a rule is ambiguous.** Use the defaults in B20 and list new questions in your phase report.

## A3. Hard guardrails (never break these)

- **Witty is live for every student,** on the same Supabase project, run from n8n.
  - Never change, drop or rename any `w2_*` table or function, `lead_intake()`, or the `student_leads` columns Witty writes.
  - Any trigger you add on `student_leads` only enqueues work: it is fast, never calls out, and catches its own errors.
  - Do not enable or change row-level security or policies on `student_leads` or `w2_*` tables. Read them through views and `SECURITY DEFINER` functions.
- **`student_leads` is the master database for all six Eduwit products** (A5). Never keep a copy of lead records. Your tables link to `student_leads.id`. Add columns only by tracked migration after Vikas approves; never rename, retype or drop one. Do **not** run `student_leads_v2_rename.sql`. Use the live column names (B3.3).
- **Column ownership.** The B2C CRM decides only the columns it owns (B3.3). It never writes the allocation columns: those belong to the B2B CRM, which makes every routing decision. **Every write to `student_leads` goes through the B2B CRM's write API (B17), never by a direct write from the B2C CRM.**
- **`w2_messages` belongs to Witty and the website agent.** The B2C CRM reads it (to show chat transcripts) and never writes it. Counsellor and marketing messages live in the B2C CRM's own tables.
- **Test leads stay out.** Rows with `is_test = true`, and phones whose digits match `910000xxxxxx`, are never messaged on a live channel, never assigned to a real counsellor, and never counted in analytics, commissions or payouts.
- **No secrets in code or tables.** Use Supabase Vault or the cloud secret manager. Flag `crm_settings.marketing.unsubscribe_secret`, which is stored in a table, and move it to Vault.
- **Consent first.** No marketing message to a lead without marketing consent for that channel. Opt-outs take effect at once, everywhere.
- **Money rows are never deleted,** only reversed.
- **Existing contact details are never edited or deleted by a counsellor.** A counsellor can add phone numbers and emails and choose which is primary; only the Admin can edit or delete a contact detail that already exists (B8.3).
- **The programme catalogue has one source:** the shared `catalog` schema, which the B2B CRM maintains from the per-partner Excel and Google Sheet files. Witty, the B2B CRM and the B2C CRM all read it; nobody keeps an editable copy (B8.9, B17).
- **Do not modify** n8n workflows, Witty's prompts, the B2B CRM's code or tables, or the influencer dashboard from this codebase.
- **Use a staging copy** (a Supabase branch or staging project) for development, never production.

## A4. What already exists (audit, then reuse or refactor)

Supabase project `xlseqwgyjuqhktrguhyc` (ap-south-1) contains a B2C backend built for an earlier combined CRM design. Almost all of it is empty, so changing it now is cheap.

| Area | Objects | State on 6 Oct 2026 |
| --- | --- | --- |
| Users and teams | `crm_users` (role, team, active, on shift, monthly cap, languages, skills, phone, monthly target), `crm_teams`, `crm_me()`, `crm_role()`, `crm_require()`, `crm_update_user()`, `crm_handle_new_auth_user()` trigger | 4 rows: `connect@eduwit.in` (admin, active) and 3 inactive Gmail sign-ups from July 2026 |
| Sales | `crm_activities`, `crm_tasks`, `calls`, `crm_assign_lead()`, `crm_auto_assign` trigger (fires when `is_sales_ready` turns true), `crm_set_stage()`, `crm_apply_stage_system()`, `crm_add_note()`, `crm_timeline()`, `crm_agenda()`, `crm_followup_tick()`, `crm_daily_digest()`, `crm_call_start()`, `crm_call_event()`, `crm_call_outcome_task()`, `crm_programme_fit()`, `crm_new_lead()`, `crm_update_lead()`, `crm_merge_leads()`, `crm_duplicate_candidates()` | Built, empty |
| Marketing | `segments`, `segment_members`, `message_templates`, `campaigns`, `campaign_sends`, `journeys` (**6 starter journeys exist**), `journey_runs`, and the functions `crm_save_segment()`, `crm_segment_*()`, `crm_save_template()`, `crm_render_template()`, `crm_save_campaign()`, `crm_campaign_*()`, `crm_save_journey()`, `crm_journey_*()`, `crm_marketing_allowed()`, `crm_whatsapp_window()`, `crm_unsubscribe()`, `crm_unsubscribe_token()`, `crm_send_job()`, `crm_score_lead()`, `crm_score_tick()`, `crm_update_scoring()` | Built, empty apart from journeys |
| Money | `payout_rates`, `payouts`, `payout_runs`, `crm_compute_payout()`, `crm_payout_rate()`, `crm_payout_run_create()`, `crm_payout_run_set_status()`, `crm_university_settings` | Built, empty. `payouts` references `enrollments`, which the B2B CRM is taking (A5) |
| Settings | `crm_settings`: stages, sub-stages, lost reasons, SLA minutes, scoring, marketing guardrails, follow-up rules, money | Populated |
| Platform | `crm_notifications`, `crm_saved_views`, `crm_alerts`, `crm_api_keys`, `verifications` (OTP, used by the website agent) | Built |
| Shared | `student_leads`, `lead_intake()`, `touchpoints`, `catalog_universities` (29), `catalog_programs` (715), `catalog_synonyms` | Live; not owned by B2C |

**What changed since these were built.** The earlier design had one CRM doing both B2C and partner allocation. Now:

1. **The B2B CRM is a separate product.** It makes every routing decision and hands leads to the B2C CRM through a contract (B4.1).
2. **The `crm_auto_assign` trigger must change.** Today it assigns a counsellor whenever `is_sales_ready` turns true, which would grab leads that belong to partners. Replace it with assignment driven by the B2C CRM's own lead state: a hand-off in lane `sales`, or a re-engagement (B6). The trigger is live, so plan the change with Vikas.
3. **Money ledgers split by product.** The empty tables `enrollments`, `earnings`, `earning_rates` and `invoices` are being moved to the B2B CRM's `b2b` schema for **partner** commissions. The B2C CRM creates its own (B14) for university commissions and payouts, and repoints `payouts`.

## A5. Eduwit's product ecosystem: separate products, connected seamlessly

Eduwit is building six separate products. Each has its own function, codebase, deployment, sign-in and tables. They connect through the master lead table and explicit contracts.

| Product | Its job | How it connects to the B2C CRM |
| --- | --- | --- |
| **Witty** (WhatsApp AI agent, n8n, its own WhatsApp number) | Talks to students, recommends programmes, qualifies leads | The B2C CRM shows Witty's transcripts (read-only from `w2_messages`) and treats renewed interest on Witty as a re-engagement signal (B6.3). It never writes Witty's tables or messages from Witty's number |
| **Website AI agent** | Witty-like programme-mapping agent on the website | Same as Witty: read-only transcripts; interest signals |
| **Website** | Marketing site, forms, ad landing pages | Its leads arrive through the B2B CRM's intake, then reach B2C by hand-off |
| **Influencer dashboard** (being redesigned separately) | Creators' referral progress | Reads masked outcomes through the B2B CRM's referral view. The B2C CRM publishes a read-only view of its stages and enrollments, which the B2B view includes |
| **B2B CRM** | Allocates every lead; syncs partner CRMs; partner commission; Programme Repository; Master Lead Table; CAPI | Sends leads to the B2C CRM (B4.1), decides partner routing, and is the only writer of allocation columns. Reads the B2C CRM's published money view for its Master Lead Table. **Maintains the shared `catalog` schema** (programmes, universities, partner commission rates) that the B2B CRM, the B2C CRM and Witty read (B8.9, B11.2). **Accepts every B2C write through its write API** and sends every change back as events (B17) |
| **B2C CRM** (this product) | Nurture and in-house sales, university commission, counsellor commission | Owns its schema `b2c`, its users, and the lead's pipeline once handed over |

**Boundary rules:**

- separate repositories and deployments (for example `crm.eduwit.in`);
- B2C-owned tables in a Postgres schema `b2c` (existing empty B2C tables move there in Phase 0 if Vikas agrees);
- its own sign-in allowlist (`crm_users` is the B2C CRM's user table);
- integration only through `lead_intake()`, versioned views, signed events and APIs;
- **real-time sync in both directions (B17):** the B2B CRM pushes hand-offs, re-enquiries, flags and routing results the moment they happen; the B2C CRM pushes every assignment, stage change, field change, enrollment and opt-out the moment it happens, and sends every write to `student_leads` through the B2B CRM's write API, so the master table and the B2B Master Lead Table are never more than a few seconds behind (B21, decision 11);
- failure isolation: the B2B CRM is always up by design, but every write and event is outboxed and retried, so nothing is lost and counsellors never wait on a write; if the B2C CRM is down, leads queue in the B2B outbox and arrive when it returns.

---

# PART B — Product specification

## B1. The product in one paragraph

**Every lead is passed to a CRM, qualified or not, except junk and programme-mismatch leads** (B2B Addendum 2). Those stay in `student_leads` but are never handed to the B2C CRM.

Leads reach the B2C CRM from the B2B CRM in two lanes:

- **Sales lane:** qualified leads that partners could not take (duplicate cascade, no partner offers the programme, no capacity, partners unreachable, the student declined partner sharing) and leads created in B2C. They are assigned to a counsellor at once.
- **Nurture lane:** leads not yet qualified, and leads a partner marked lost. They sit unassigned in the **Nurture Pool**, where automated WhatsApp and email journeys keep them warm.

A nurtured lead goes to a counsellor the moment it shows active interest again: it re-engages with Witty, replies positively to a nurture message, or reaches a lead score of 60. Counsellors call from their own phones, message students from Eduwit's B2C WhatsApp number and by email, log every call and follow-up, manage applications and documents, and record enrollments. The Admin verifies enrollments, books Eduwit's university commission, and records the counsellor commission each enrollment owes Eduwit (B11).

**Once a lead is in the B2C CRM, it never goes back to a partner automatically.** Only the Admin can send it to partner routing.

## B2. Glossary

| Term | Meaning |
| --- | --- |
| Counsellor | An in-house sales person (also called sales manager). Works leads assigned to them. "Sales" means this role |
| Admin | Vikas (`connect@eduwit.in`). Everything, including settings, money and team |
| Marketing | A member of Eduwit's marketing team. Sees everything the Admin sees; acts only on marketing: nurture, templates, segments, campaigns, journeys, marketing analytics |
| Sales head | Optional role for a future team lead: sees and reassigns the team's leads, monitors SLAs |
| Follow-up | A dated task on a lead (call, WhatsApp, email, document chase). Listed on the Follow-ups page (B8.2) |
| Sales template | An email template a counsellor writes for their own sales emails (B8.6). Distinct from marketing templates, which only Admin and Marketing create |
| Allocation engine | The rules that give an incoming or re-engaged lead to a counsellor, using each counsellor's working days, hours, holidays and capacity (B7) |
| Programme page | The read-only catalogue of every programme Eduwit can sell, fed by the B2B CRM's Programme Repository (B8.9) |
| Lane | How a lead arrived: `sales` (assign now) or `nurture` (pool first) |
| Nurture Pool | Unassigned leads being nurtured by journeys and campaigns |
| Re-engagement | The moment a nurtured lead shows active interest again (B6.3). It triggers assignment |
| Hand-off | The B2B CRM's event that gives a lead to the B2C CRM (B4.1) |
| Journey | An automated multi-step nurture flow (B9) |
| Lead score | Fit + engagement points, with decay (B9.5) |
| University commission | What a university pays Eduwit for an in-house enrollment |
| Counsellor commission | What the counsellor owes Eduwit for an in-house enrollment: the same commission the edtech partners pay Eduwit for that programme, the highest where several do (B11.2). Not a payout to the counsellor |

## B3. Users, access and data ownership

### B3.1 Roles

| Role | Does | Sees | Interface |
| --- | --- | --- | --- |
| **Admin** (`connect@eduwit.in`) | Everything: team and accounts, settings, allocation rules, all templates (marketing and sales WhatsApp templates), journeys, campaigns, nurture, commission rates, commission runs, exports, edit, delete and bulk delete of leads, "send to partners", connectors | Everything in the B2C CRM | Admin and Marketing workspace (desktop-first) |
| **Marketing** | Marketing only: nurture page, segments, marketing templates (email and WhatsApp), campaigns, journeys, scoring rules, marketing and sales analytics, Replies inbox. **Cannot:** edit, delete or reassign leads, change stages, change settings, manage the team, change rates, commission runs or invoices, create sales WhatsApp templates, send to partners | Everything the Admin sees, including all leads with full phone numbers and emails, all chats, all analytics and money (read-only where it is not marketing) | The same workspace as the Admin, with non-marketing actions hidden |
| **Counsellor** (sales manager) | Works their own leads: calls, WhatsApp (templates to open, free text once the student replies), email from their own Gmail, follow-ups, stages and sub-stages, cross-sell (change the programme or university of interest), add contact details, applications, documents, enrollments; writes and saves their own sales email templates; builds their own lead views and personal dashboards; sees their own enrollments and the commission each owes Eduwit | Their own leads only, and the Programme page. Cannot export, bulk delete, edit or delete existing contact details, or create WhatsApp templates | Sales app (mobile-first, also desktop) |
| **Sales head** (optional, off by default) | Reassigns leads, monitors SLAs and activity, approves stage overrides | Their team's leads and numbers | Sales app plus the team pipeline |

**No intermixing.** A user has exactly one role. The Admin can switch to "view as Sales" to check the counsellor experience, and that is logged.

### B3.2 Accounts, sign-in and the Teams section

- **Company accounts only.** Every user signs in with an `@eduwit.in` Google Workspace account. The **Teams** section (Admin) creates accounts for each marketing and sales role with the person's company email; nothing else grants access.
  - **Auto-sync with Google Workspace.** Connect the Workspace directory once (Admin SDK Directory API, read-only, domain-wide delegation; B16). The Teams section then lists every `@eduwit.in` user, the Admin assigns a role with one click, a user suspended in Workspace is deactivated in the CRM within 15 minutes, and name, photo and job title stay in sync. If the directory cannot be connected, fall back to invites by email that expire after 7 days.
  - There is no public sign-up. Any other account that authenticates sees "Access pending" and is logged. The 3 inactive Gmail accounts from July 2026 stay inactive; list them in the Phase 0 report.
- **Methods:** Supabase Auth with **Continue with Google** (restricted to the `eduwit.in` hosted domain) or **Eduwit email and password** (reset by email, minimum 12 characters, breached-password check, 15-minute lock after 5 failures).
- **Two-factor authentication, mandatory for everyone, using the company email.** On every sign-in from a device that is not yet trusted, a 6-digit code goes to the user's `@eduwit.in` inbox (10-minute validity, 5 attempts). A device can be trusted for 30 days. TOTP apps and passkeys can be added as extra factors later; email is the required one. With Continue with Google, the email code is still required (B21, decision 9).
- **Separate from the B2B CRM:** access to the B2C CRM is independent of the B2B CRM's allowlist, and the reverse.
- **Sessions:** 12 hours idle on desktop, 7 days on a trusted phone, with remote sign-out. Every sign-in is logged.
- **Offboarding:** deactivating a user signs them out everywhere, revokes their Gmail connection, and moves a counsellor's open leads to reassignment.

### B3.3 `student_leads` columns (live names) and who writes them

| Group | Columns | Writer |
| --- | --- | --- |
| Identity, contact, interest, profile, AI qualification | `whatsapp_number`, `student_name`, `email_id`, `interested_course`, `interested_specialization`, `interested_university`, `study_mode_preference`, `program_level`, `highest_qualification`, `academic_score_pct`, `work_experience_years_num`, `current_job_role`, `annual_budget_inr`, `enrollment_timeline`, `primary_motivation`, `lead_status`, `city`, `state`, `preferred_language` | Witty and the website agent. The B2C CRM may correct the **profile and interest** fields when a counsellor learns better (including a cross-sell change of `interested_course`, `interested_specialization` or `interested_university`, B8.3); the change is recorded as a human correction in field history. **Contact fields are different:** `whatsapp_number` and `email_id` are never edited by a counsellor; extra numbers and emails live in `b2c.lead_contacts`, and only the Admin may change the originals (B8.3). Stopping Witty from overwriting a correction needs a Witty-side change, so agree it with Witty's developer in Phase 0. Do not modify `lead_intake()` yourself |
| Source and attribution | `lead_source`, `channel`, `campaign`, `utm_*`, `click_ids`, `first_touch_at`, `last_touch_at` | Intake (B2B CRM, `lead_intake()`) |
| Allocation | `destination_type`, `partner_id`, `allocation_id`, `allocated_at`, `allocation_reason` | **B2B CRM only** |
| Assignment | `owner_user_id`, `assigned_at`, `team_id` | B2C CRM |
| Pipeline, effort, application, enrollment, revenue (while B2C holds the lead; on hand-off the B2C CRM sets the next stage and the B2B CRM stops writing these) | `stage`, `sub_stage`, `stage_changed_at`, `temperature`, `lead_score`, `first_contacted_at`, `last_contacted_at`, `contact_attempts`, `next_task_due_at`, `application_id`, `application_status`, `applied_at`, `fee_amount_inr`, `fee_paid_inr`, `enrollment_status`, `enrolled_program`, `enrolled_university`, `enrollment_date`, `enrollment_verified_at`, `expected_net_revenue_inr`, `realised_net_revenue_inr`, `lost_reason`, `lost_at` | B2C CRM |
| Marketing | `active_journey_id`, `last_campaign_id`, `last_marketing_message_at`, `consent_marketing_at`, `is_opted_out`, `opted_out_at`, `opted_out_channels`, `email_bounced_at` | B2C CRM (consent at intake is written by intake) |

**All writes go through the B2B CRM.** The writer column shows who decides each value. The write itself reaches `student_leads` through the B2B CRM's write API (B17), as one idempotent call that also emits the event announcing it. The B2C CRM runs no direct SQL writes against the master table. Witty's own writes are unchanged.

## B4. How leads arrive and leave

### B4.1 The hand-off contract from the B2B CRM

The B2B CRM decides routing and emits `b2c.lead_handed_off` by signed webhook to the B2C CRM's `POST /v1/handoffs`. See the B2B prompt and its Addendum 1, which defines the full rules.

**Payload:**

- lead ID;
- `b2c_lane` (`sales` or `nurture`);
- `reason`;
- the partners tried and their outcomes;
- for `partner_lost`: the partner's lost reason, its raw status and its last activity.

**Processing.** The B2C CRM consumes the event idempotently (by event ID) within 3 seconds:

| Reason | Lane | What the B2C CRM does |
| --- | --- | --- |
| `duplicate_cascade`, `no_partner_offers_programme`, `no_partner_consent`, `no_capacity`, `partners_unreachable`, `import_choice`, `manual`, `b2c_created` | sales | Assign a counsellor now. `duplicate_cascade` leads carry an **"Already with other providers"** badge (partners and dates), and the counsellor's first contact uses a neutral-adviser opening ("Eduwit can help you compare options") |
| `manual_route_failed` | sales | The Admin's route-to-partners found no partner: reopen in B2C and return the lead to its previous counsellor |
| `not_qualified` | nurture (**qualification nurture**) | Put in the Nurture Pool, unassigned. Start a qualification journey whose only goal is the missing details (course, name, email, partner-sharing consent). Witty leads arrive once their chat has been idle for 30 minutes without qualifying. **These leads are not B2C's to sell:** see B4.2 |
| `partner_lost` | nurture | Arrives after the partner's 7-day grace period has ended (B2B Addendum 3). Put in the Nurture Pool, unassigned. The partner's lost reason picks the journey, and the lead shows a "Lost by partner" badge with the partner's history |

A missed event is caught by a reconciliation job every 5 minutes, which calls the B2B CRM's `GET /v1/handoffs?since=`. The B2C CRM never reads B2B's tables.

**Re-enquiry.** If a lead already held by B2C enquires again (for example a new Meta or Google form, or Witty qualifies it), the B2B CRM sends `b2c.lead_reenquired` instead of routing it:

- if the lead is in the Nurture Pool, it is a re-engagement trigger (B6.3);
- if it is with a counsellor, the counsellor gets a "new enquiry" alert on the lead.

**Sticky across cycles.** A lead B2C holds **for selling** stays with B2C in every later enquiry cycle, unless the Admin routes it to partners. Selling leads are sales-lane leads and partner-lost leads. Qualification-nurture leads (`not_qualified`) are not sticky (B4.2).

**Flagged leads.** If Witty later re-classifies a B2C-held lead as junk or programme mismatch, the B2B CRM sends `b2c.lead_flagged`. The lead shows a "Flagged: junk / mismatch" badge and enters an Admin review list. It is closed only if the Admin agrees (lost reason `junk or test` or `cannot be served`). Journeys pause while it is flagged.

### B4.2 B2C keeps the lead

- **Partners get the bulk of leads.** Eduwit's in-house team is the fallback, mainly for leads partners report as duplicates or mark lost.
- **Partner-barred leads.** A lead that reached B2C through the **duplicate cascade** or **lost by a partner** is barred from partners **for ever**, by the B2B CRM's `partner_barred_at` flag. The B2C CRM shows a "Partner-barred" badge and hides "Send to partners" for these leads, and the B2B API refuses it.
- **Selling leads never return automatically.** A lead B2C holds for selling never goes back to a partner automatically, even if Witty later marks it qualified.
- **Qualification-nurture leads return to partners.** A `not_qualified` lead goes back to the B2B CRM's routing **the moment it becomes qualified**, whether through Witty, a form, a reply that supplies the missing details, or a counsellor's qualification call. The B2B CRM normally routes it to a partner and sends `b2b.lead_routed_to_partner`. The B2C CRM then closes it (stage `routed_to_partner`) and stops its journeys. If the B2B rules send it back (for example, no partner offers the programme), it arrives as a normal sales-lane hand-off.
- **Manual send to partners.** The Admin can **send a lead to partner routing**, as a lead action or bulk action, with a reason. Partner-sharing consent is required. It calls the B2B CRM's `POST /v1/leads/{id}/route-to-partners`, and the lead shows "Routing to partners…".
  - **When a partner accepts,** the B2B CRM sends `b2b.lead_routed_to_partner`. The B2C pipeline closes for that lead (stage `routed_to_partner`), open tasks are cancelled and journeys stop. The student hears from the B2B CRM's partner-named notification.
  - **If no partner accepts,** the lead comes back with reason `manual_route_failed` and returns to its previous counsellor.

  Counsellors cannot do this, and it is never available for partner-barred leads (duplicate cascade or lost by a partner).
- **Closing.** A lead leaves active work when it is enrolled and verified, lost (reason required, then it returns to the Nurture Pool, B6.4), deleted (soft, B10.4), or opted out.

### B4.3 Leads created inside the B2C CRM

A counsellor or the Admin can add a lead manually: a walk-in, a referral, or a call to Eduwit's number.

- **Intake.** Manual leads go through `lead_intake()` with `lead_source = 'b2c_created'`. `lead_intake()` accepts the source systems `witty`, `web_agent` and `crm`, so use `crm`; verify in Phase 0.
- **Routing.** The B2B CRM records them as B2C-held at once (lane `sales`, reason `b2c_created`), with no partner routing. The lead is assigned to the counsellor who created it.

**If the phone already exists:**

| The existing lead is | What happens |
| --- | --- |
| With a partner | Nothing is created. The screen shows "Already with {{partner}} since {{date}}". Only the Admin can act, through the B2B CRM |
| In the B2C Nurture Pool | It is re-engaged and assigned to the creator |
| With another counsellor | The creator is told who owns it; the Admin can reassign |

## B5. Lead lifecycle: Eduwit's sales stages

Counsellors work with **Eduwit's own stage names**. Each stage has **sub-stages** (why or where exactly), and every stage change carries an optional **free-text comment**. The B2C CRM stores the Eduwit stage and sub-stage as its own pipeline and **maps each one to the canonical stage** the B2B CRM and `student_leads.stage` use, so in-house and partner funnels stay comparable without the counsellor ever seeing the canonical names.

### B5.1 Stages, sub-stages and the canonical mapping

| # | Eduwit stage (what counsellors see) | Default sub-stages (Admin-editable in Settings) | Canonical `student_leads.stage` | Required to enter |
| --- | --- | --- | --- | --- |
| 1 | **New Lead** | Fresh assignment; Re-engaged from nurture; Re-enquiry; Created by me; Returned from partners | `assigned` | — |
| 2 | **Could Not Connect** | No answer; Busy; Switched off; Wrong number; Call back requested; Invalid number | `contacted` (an attempt was made) | A logged call attempt |
| 3 | **Contacted** | Spoke briefly; Asked to call later; Parent or guardian spoke; WhatsApp reply only | `contacted` | A logged call or an inbound reply |
| 4 | **Qualified** | Eligible and interested; Eligible, undecided; Budget confirmed; Timeline confirmed | `counselled` | Course, qualification and timeline on file |
| 5 | **Follow Up** | Call back on date; Awaiting parent decision; Comparing options; Awaiting documents; Awaiting fee arrangement or loan | `counselled` | A scheduled follow-up (date and time) |
| 6 | **Program Details Explained** | Brochure shared; Fee and EMI explained; Comparison shared; University call arranged | `counselled` | At least one programme shared or explained (logged) |
| 7 | **Applicant** | Application started; Application submitted; Application fee paid | `applied` | Application ID (or "started", with the university and programme) |
| 8 | **Docs Submitted** | Partial; Complete; Verification pending; Verification query | `applied` | Document checklist updated |
| 9 | **Enrolled** | Fee paid (partial); Fee paid (full); Enrollment confirmed by university; Verified by Admin | `enrolled` → `verified` (on Admin verification) | Fee amount, enrollment date and proof |
| 10 | **Lost** | Uncontactable; Not eligible; Not interested; Can't afford fee or EMI; Loan not approved; Document verification failed; Lost to competitor; Chose another provider; Not now, later; Wrong number; Junk or test; Enrolled elsewhere; Opted out; Other (comment required) | `lost` | Sub-stage (the lost reason) and a comment |

Hidden B2C states that are not counsellor stages: `nurture` (in the Nurture Pool, unassigned), `routed_to_partner` (closed in B2C after a manual send to partners) and `dormant`.

### B5.2 Rules

- **Sub-stage is required** at every stage change; the **comment** is optional except for Lost → Other. The comment box accepts free text and is shown on the timeline with the change.
- **Lost sub-stages drive nurture.** The lost sub-stage picks the nurture journey and the delay before the first message (B6.4): uncontactable → "we tried to reach you" after 3 days; can't afford fee or EMI and loan not approved → lower-fee and EMI options after 7 days; not eligible → eligible programmes after 7 days; not now, later → monthly update after 30 days; not interested → re-engage after 60 days; lost to competitor and chose another provider → long-term update after 90 days; document verification failed → a "fix and reapply" journey after 3 days. Wrong number, junk or test, enrolled elsewhere and opted out never return to the pool.
- **Forward by default.** Stage rank prevents accidental backward moves (except to Could Not Connect, Follow Up or Lost, which are reachable from any open stage). The Admin or sales head can override backward with a reason.
- **Next follow-up required.** Saving any stage other than Enrolled or Lost without a next follow-up is blocked (B8.2).
- **Automatic moves:** a logged call with outcome "no answer / busy / switched off" moves New Lead → Could Not Connect automatically; a logged connected call moves Could Not Connect → Contacted; recording an application moves to Applicant; Admin verification moves Enrolled to its Verified sub-stage. The counsellor can correct the sub-stage after an automatic move.
- **Everything is configurable:** stage names, order, sub-stages, required fields and the canonical mapping live in `crm_settings` (migrated to the new structure in Phase 0) and are editable by the Admin, with a change history. Renaming a stage never changes the canonical mapping unless the Admin says so.
- **The B2B CRM sees both.** `b2ccrm.stage_changed` carries the Eduwit stage, sub-stage, comment and the canonical stage, so the Master Lead Table can show the exact sub-stage.

## B6. Nurture Pool and re-engagement

The Nurture Pool exists to turn cold and lost leads back into conversations, automatically, without a counsellor spending time on them until the student is genuinely interested.

### B6.1 Who is in the pool

- Lane `nurture` hand-offs: `not_qualified` and `partner_lost`.
- Leads a B2C counsellor marked `lost` (B6.4).
- **Exclusions:** opted-out leads, junk or test, and leads currently assigned to a counsellor.
- **No marketing consent.** A pooled lead without `consent_marketing_at` for a channel receives no marketing on it. It can still re-engage through Witty or by messaging Eduwit. In Phase 0, report how many leads carry marketing consent today, and make sure Witty, the website agent and every form capture it.

### B6.2 What the pool screen shows (Admin and Marketing; part of the Nurture page, B9.0)

- **Every pooled lead:** what is missing (course, qualification, score, consent, timeline), lead score and its trend, current journey and step, last message sent and its status, last student activity, and "lost by" (partner name or counsellor) with the reason.
- **Segments by reason and age:** for example "partner lost: over budget, 0–30 days".
- **Pool health:** size, inflow and outflow per day, re-engagement rate, time to re-engagement, cost per re-engaged lead.

### B6.3 Re-engagement triggers (assignment to a counsellor)

A pooled lead is **assigned to a counsellor automatically** (B7) the moment **any** of these happens. The trigger is recorded on the lead's timeline and on the assignment.

| Trigger | How it is detected |
| --- | --- |
| **Active interest via Witty or the website agent** | A **new inbound message to Witty after the lead entered the pool**, together with Witty's interest signal: asks about fees, admission, eligibility or applying; asks for a human; qualification complete; or Witty escalates. A lead that was already HOT before it was lost still re-engages this way. The signal is defined with Witty's developer in Phase 0 (B2B Addendum 1, §4b). Never parse `w2_messages` text yourself. **Witty keeps talking to pooled leads** and stops only once a counsellor is assigned |
| **Positive reply to a nurture WhatsApp** | The student taps a positive quick-reply button ("Yes, call me", "I'm interested", "Share details"), or a free-text reply is classified as positive interest (B6.6) |
| **Positive reply to a nurture email** | A reply to a nurture email (threaded back through the connected mailbox) classified as positive interest, or a click on an "I'm interested — call me" link in the email |
| **Becomes qualified** | **Not a B2C assignment trigger for `not_qualified` leads.** When such a lead completes qualification (any temperature), the B2B CRM re-routes it, normally to a partner (B4.2). For partner-lost leads, qualification changes are ordinary profile updates |
| **New enquiry** | `b2c.lead_reenquired` from the B2B CRM (B4.1), for example a new Meta or Google form |
| **Very high engagement** | Lead score **rises** to 60 or more **after the lead entered the pool**, with at least one engagement event since then. A strong profile alone (fit points) never triggers assignment (B9.5) |

**Re-engaged qualification-nurture leads.** A `not_qualified` lead that re-engages but is **still missing details** is **not** assigned for selling.

1. It first gets an automated qualification step: an invitation to continue with Witty on WhatsApp, or a 3-question form link.
2. If it is still not qualified 48 hours later, the Admin's **To qualify** queue gets a qualification task. A counsellor may call only to collect the missing details.
3. Once the details are recorded, the lead goes back to B2B routing. It reaches a partner unless the rules send it back to B2C.

**What happens on re-engagement** (partner-lost leads and B2C's own lost leads):

1. The lead's journey stops.
2. It is assigned to a counsellor **as hot**, with the hot SLA.
3. The counsellor gets an instant notification (in-app and push; WhatsApp alert to the counsellor's own number if enabled) with a one-line summary of why it re-engaged.
4. The student gets the assignment message (B7.6) from the B2C WhatsApp number.

**Negative or neutral replies:**

- A **negative** reply ("not interested", "already joined") moves the lead to a long-gap journey or closes it as lost with that reason.
- **"STOP"** or any opt-out wording opts the lead out at once.
- A **question without clear interest** creates no assignment. It goes to a small **Replies** inbox for the Admin, or a designated counsellor, to answer, and answering may assign the lead.

### B6.4 Lost leads coming back

**Partner-lost leads** enter the pool immediately on hand-off.

**Counsellor-lost leads** also enter the pool immediately, unless the reason is wrong number, junk or test, enrolled elsewhere, or opted out (those never return).

The lost sub-stage (B5.1) picks the journey and **when its first message goes out**. Defaults, all editable:

| Lost sub-stage | First nurture message after | Journey |
| --- | --- | --- |
| Uncontactable | 3 days | "We tried to reach you" |
| Not now, later | 30 days | Long-term monthly update |
| Can't afford fee or EMI; Loan not approved | 7 days | Lower-fee programmes and EMI options for their interest |
| Not eligible | 7 days | Programmes they are eligible for |
| Not interested | 60 days | Re-engage after 60 days |
| Lost to competitor; Chose another provider | 90 days | Long-term update |
| Document verification failed | 3 days | "Fix and reapply" (what was missing, how to resubmit) |
| Other | 30 days | Long-term monthly update |

A partner's lost reason (from the hand-off payload) is mapped to the nearest sub-stage above by a table in Settings; unmapped reasons use "Other".

A **partner-lost** lead also carries the partner's history on its timeline: calls made, last outcome, raw status. So the counsellor who later takes it knows what the partner tried.

### B6.5 Leaving the pool

- After 12 months without any student response, a lead moves to **dormant**: no messages, still searchable.
- Opt-out removes it from all marketing permanently, unless the student opts in again.
- Never delete for inactivity.

### B6.6 Reply classification

Replies on WhatsApp and email are classified as positive interest, question, negative, opt-out or other:

1. **Keyword rules** in English, Hindi and Hinglish.
2. **Claude**, for free text the rules cannot decide: model `claude-haiku-4-5-20251001`, configurable. Only the reply text and the lead's course interest are sent: no name, phone or email.

Each classification stores its method and confidence. Below 0.8 confidence, the reply goes to the Replies inbox instead of triggering anything. The Admin can correct a classification, and corrections are kept to measure accuracy.

## B7. Lead allocation engine (who gets which lead)

Allocation runs in the database within 1 second of a sales-lane hand-off, a re-engagement, a B2C-created lead or a hand-back. It must be as capable as the allocation engines in LeadSquared and Salesforce: several allocation logics, each counsellor's working calendar, capacity, simulation and a full audit. The Admin configures it on a dedicated **Lead Allocation page** (B7.4).

### B7.1 Each counsellor's working calendar

Allocation never gives a lead to someone who is not working. For every counsellor and sales manager the Admin keeps, in Team settings:

- **Working days** (for example Monday to Saturday) and **working hours** per day (for example 10:00–19:00 IST), with a different pattern per weekday if needed;
- **Shifts**, if the team works in shifts (morning, evening), with a roster by week;
- **Holidays:** a company holiday calendar (Indian national and Eduwit's own; the Admin can import a list and add dates) plus each person's **leave** (dates, with "hold my leads" or "reassign after N hours");
- **Breaks and lunch** (optional) during which only non-hot leads are allocated;
- **On-call:** who, if anyone, takes hot leads outside hours;
- **Availability toggle:** a counsellor can set "away for 30 minutes / rest of the day" from the Sales app; the Admin sees it.

"**Working now**" is computed from these, in the counsellor's time zone (IST by default). The SLA clock (B8.7) uses the same calendar: it pauses outside the assigned counsellor's hours.

### B7.2 Eligibility (applies to every logic)

A counsellor is eligible for a lead when they are:

- active, with role counsellor or sales head (and the Admin, while "Admin takes leads" is on);
- **working now**, or the lead is not hot and "allow allocation outside hours for non-hot leads" is on (then the lead waits in their queue for their next working time);
- not on leave or away;
- under their **capacity**: a monthly cap (default **200 leads per month**) and an optional cap on **open leads** (default off) and on **new leads per day** (default off);
- and, when the chosen logic requires it, matched on language, programme skill, university skill, territory or source.

### B7.3 Allocation logics

The Admin builds an **ordered list of allocation rules**. Each rule has a **condition** (which leads it applies to: lane, hand-off reason, source, campaign, programme, university, programme level, city or state, language, temperature, lead score, time of day, anything on the lead) and a **logic** (how to pick among the eligible counsellors in the rule's **pool**, which is a named group of counsellors or "everyone"). The first rule whose condition matches is used; a final catch-all rule always exists.

| Logic | How it picks | Typical use |
| --- | --- | --- |
| **Round robin** (default) | Equal turns in a fixed order, skipping anyone not eligible; one rotation per rule | Fair distribution of duplicate-cascade, reactivated and other sales-lane leads |
| **Weighted round robin** | Turns in proportion to a weight per counsellor (for example senior 2, new joiner 1) | Ramping a new counsellor |
| **Least loaded** | The eligible counsellor with the fewest open leads (or fewest leads today) | Keeping queues level |
| **Capacity-based** | Fills each counsellor to a share of their cap before moving on | Teams with uneven caps |
| **Performance-weighted** | More turns to higher conversion over the last 30 or 90 days, with a floor so nobody is starved | Mature teams (phase 4) |
| **Skill or language match** | Restrict the pool to counsellors tagged with the lead's language, programme, university or level, then round robin within it | Hindi-speaking leads, executive programmes |
| **Territory** | Restrict the pool by the lead's city or state | Regional counsellors |
| **Source or reason pinning** | A named pool for a source, campaign or hand-off reason | All duplicate-cascade leads to two senior counsellors |
| **Returning student** | The counsellor who last worked the lead, if eligible; otherwise fall through to the next logic | Reactivated lost leads (off by default; B21) |
| **Manual queue** | Nobody: the lead waits in a queue for a named person to pick | Walk-ins the Admin wants to hand out by hand |

Every rule can add **fallbacks**: what to do when nobody in the pool is eligible (try the next rule; the Unassigned queue; the on-call counsellor; the Admin).

**Always true, whatever the logic:**

- an assigned lead that comes back as a re-enquiry stays with its current counsellor;
- a re-engaged lead is allocated **as hot**, with the hot SLA;
- hot leads outside hours go to the on-call counsellor if set, otherwise they are allocated at the next working time of the pool, with the SLA clock paused until then;
- **no eligible counsellor** (everyone at cap, on leave, off hours with no on-call, or no counsellors yet): the lead waits in the **Unassigned** queue on the Admin's home with an alert, and leaves it by the rules the moment someone is eligible. **"Admin takes leads"** is on by default, so while the team is just the Admin every lead goes to the Admin;
- test leads are never allocated to a real counsellor.

### B7.4 The Lead Allocation page (Admin)

- **Rules:** the ordered list with drag to reorder, enable or disable, condition builder, logic and pool, fallbacks, and "applies from" date.
- **Pools:** named groups of counsellors, with weights and skills.
- **Calendar view:** who is working now and this week; holidays and leave; a warning when a day has nobody on duty.
- **Capacity view:** leads this month vs cap per counsellor, open leads, today's intake.
- **Simulation:** pick a date range, replay the leads that arrived, and see how the current rules would have distributed them, per counsellor, before switching the rules on.
- **Queues:** Unassigned, waiting-for-hours, manual queues; one-click allocate.
- **Audit:** every allocation with the rule, logic, pool, turn, eligible candidates and why each ineligible one was skipped (`b2c.assignments`, `b2c.allocation_decisions`).

### B7.5 Manual control, leave and offboarding

- The Admin (and sales head, if enabled) can reassign one lead or many, with a reason, on the timeline.
- A counsellor can **hand back** a lead with a reason; the rules reassign it.
- During leave, a counsellor's leads are held or reassigned after N hours, as set on the leave. On deactivation, all open leads are reassigned by the rules at once.

**Capacity alerts to the Admin:**

- **Hiring trigger:** monthly enrollments reach **10 per counsellor**, Eduwit's hiring rule.
- The team passes **90% of total monthly capacity**.
- A sales-lane lead **waits unassigned** for more than 5 minutes in working hours.

### B7.6 Assignment message to the student

Every time a counsellor is assigned, both for sales-lane hand-offs and for re-engagements, the student gets a short WhatsApp from the B2C number, using an approved utility template:

- **Working hours:** "Hi {{first name}}, I'm {{counsellor first name}} from Eduwit. I'll call you shortly about {{programme interest}}."
- **Out of hours:** "Hi {{first name}}, I'm {{counsellor first name}} from Eduwit. I'll call you after {{next working time}} about {{programme interest}}."

**Fallback.** An email version goes out when WhatsApp fails or the lead has no WhatsApp.

**Never sent:**

- to test leads or opted-out leads;
- twice for the same assignment;
- during an active Witty chat (the message waits until the chat has been idle for 10 minutes).

## B8. The counsellor workspace

A counsellor should see the next lead to work, everything about that student on one screen, and finish any action in one or two taps. **Counsellors call from their own phones**, so the workspace is designed **mobile-first** (installable as a web app on Android and iOS) and works equally well on a laptop.

### B8.1 Home: "Today"

- **Queue order:** overdue follow-ups, then new assignments not worked yet (with SLA timers counting down), then follow-ups due today, then hot leads with no activity in 24 hours. The four follow-up cards (B8.2) appear in brief.
- **Today's numbers against target:** calls logged, connected, counselled, applications, enrollments, commission owed to Eduwit this month.
- **One tap** opens the lead.

### B8.2 Leads page, Pipeline view and Follow-ups page

**Leads page (every role; counsellors see only their own leads).** A dedicated page where the user builds their own lead views from any combination of filters, and saves them:

- **Filters on every lead property:** stage and sub-stage, lane and hand-off reason, source, campaign, programme, university, level, mode, city or state, language, qualification, score, budget, timeline, temperature, lead score, tags, dates (created, assigned, last contacted, next follow-up, stage changed), partner history, consent;
- **Filters on sales activity:** calls logged and outcomes, connected or not, attempts, last activity type and date, WhatsApp sent or replied, emails sent or opened, follow-ups overdue or due, SLA status, days in stage, untouched for N days, applications and documents status;
- **Build:** AND/OR groups, relative dates ("last 7 days", "this month"), column chooser and ordering, sort, group-by with totals, list or kanban (B5 stages, drag to move with the stage rules), density;
- **Save:** named personal views; the Admin can also publish **standard views** to everyone (Due now, New for me, Hot, Applicants, Waiting for documents, All mine, Not worked yet). A view can be pinned as the page's default and shared by link with others of the same role;
- **Bulk actions from a view:** counsellors can add a tag, create follow-ups and open the WhatsApp composer for a template send to several leads at once (within the sending rules, B8.5); the Admin additionally gets B10.3;
- **Search:** global search by name, phone (any of the lead's numbers), email, application ID.

**Personal dashboards.** From the Leads page or the Analytics page (B13), every user builds **their own dashboard** from widgets (KPI tile, funnel, bar, line, table, leaderboard) over their own data, saves several, and picks one as their home. Standard sales dashboards ship ready-made (My funnel, My follow-ups, My week, My enrollments and commission) and can be copied and changed.

**Pipeline view (Admin and Sales).** A kanban of the Eduwit stages (B5.1) with sub-stage chips, the value of each column (expected commission from programme fees, B11), SLA colour, and filters. A counsellor sees their own pipeline; the Admin and sales head see the whole team's and can filter by counsellor. Cards sort by priority: overdue follow-up, hot, SLA at risk, highest expected value. Dragging a card changes the stage under the stage rules and asks for the sub-stage and comment.

**Follow-ups page (Sales; the Admin sees everyone's).** Every follow-up (call back, WhatsApp, email, document chase, any task with a date and time) listed by date and time, in four cards at the top:

| Card | Contains |
| --- | --- |
| **Not worked yet** | New leads with no activity logged since assignment, oldest first, with the SLA timer |
| **Overdue** | Follow-ups whose time has passed, most overdue first |
| **Due today** | Today's follow-ups in time order, with the next one highlighted |
| **Upcoming** | Tomorrow onwards, grouped by day |

Each row shows the student, the programme interest, the follow-up type and note, and opens the lead in one tap. From a row the counsellor can call, WhatsApp, mark done (which asks for the outcome and the next follow-up), snooze or reschedule. **Reminders:** 10 minutes before each follow-up the counsellor gets a notification (push on the phone, in-app, and optionally WhatsApp to their own number) with the lead's name, the note and a **direct link to the lead**. Missed follow-ups escalate to the Admin after 2 hours (setting). The page also has a calendar view (day, week).

### B8.3 Lead screen (360° view)

| Panel | Contents |
| --- | --- |
| **Header** | Name, phone with **Call** button, WhatsApp and email buttons, stage, temperature, lead score, lane and reason (e.g. "Duplicate at Partners X and Y" or "Lost by Partner X: over budget"), and a "Partner-barred" badge where it applies, SLA timer, next task |
| **Brief before you call** | A 3–5 line summary: who the student is, what they want, what Witty learned, objections so far, and the partner's history if partner-lost. Written by Claude from the lead's fields and Witty transcript, with no phone or email sent to the model. Refreshed when key facts change. Each line links to its source |
| **Contact details** | Every phone number and email on the lead, with a **primary** marker for each. The original WhatsApp number and email from intake are shown locked. A counsellor can **add** numbers and emails (with a label: alternate, parent, office, WhatsApp-only) and **set any of them as primary** for calling, WhatsApp or email; a counsellor **cannot edit or delete** a number or email that already exists. The Admin can edit, delete and merge. Every change is in field history, and a new number is checked against existing leads for duplicates (B4.3) |
| **Profile** | Parent or guardian, education, score, work experience, budget, timeline, mode, city, custom fields. Editable with field history |
| **Interest (cross-sell)** | The programme, specialization, university, level and mode the student wants. A counsellor **may change these** after a conversation to cross-sell or upsell (for example from an online MBA to an executive MBA, or to another university). The change asks for a reason, is recorded as a human correction, is written to `student_leads` through the B2B CRM's write API, refreshes Programme fit, and is announced as an event. It never triggers partner routing (B4.2) |
| **Programme fit** | Eligible programmes from the Programme page (B8.9) for this profile and interest (eligibility, fees, EMI, mode, duration), side by side. One tap shares a brochure or a 2–3 programme comparison on WhatsApp or email |
| **Timeline** | Every call log, WhatsApp message (both directions), email, note, stage change, assignment, journey step, re-engagement trigger, and the Witty or website-agent chat (read live, read-only), newest first. Filter by type |
| **Applications** | One or more applications: university, programme, application ID, a per-university document checklist (marksheets, ID, photo, others), uploads, fee amount and payment status as recorded (the CRM does not collect money), enrollment confirmation and proof |
| **Tasks** | Open and done tasks, with due times |

### B8.4 Calling without a telephony provider (phase 1)

Counsellors use their own mobile phones. The CRM still records every call, and is ready for cloud telephony later.

**On a phone:**

1. The **Call** button opens the phone's dialler with the number (`tel:` link).
2. When the counsellor returns to the CRM, a **call log sheet** opens automatically. It records the outcome (connected, no answer, busy, switched off, wrong number, call back), the talk duration (approximate, prefilled from the time away), notes, the next step and the next task.

**On a laptop:**

- The **Call** button shows the number large, with a copy button and a QR code that opens the dialler on the counsellor's phone.
- The same log sheet opens.

**Logging rules.**

- **No call goes unlogged.** If a counsellor taps Call and does not log within 10 minutes, the lead shows "Call not logged" and the counsellor gets a reminder.
- **Outcomes suggest the next task:** for example, "no answer" suggests a retry in 3 hours, and 3 no-answers in 48 hours suggest a WhatsApp template.
- **Effort counts:** each logged call updates `contact_attempts`, `first_contacted_at` and `last_contacted_at`.

**Privacy.** Counsellors see students' phone numbers because they call from their own phones. Every reveal and every Call tap is logged. Counsellors cannot export or bulk-copy numbers.

**Telephony later.** Keep a **telephony adapter interface** (`startCall`, `onCallEvent`, `fetchRecording`) and the existing `calls` table, so a cloud telephony provider (e.g. Exotel, MyOperator, Knowlarity or Ozonetel) can be plugged in without redesign. With telephony, calls are bridged and recorded automatically, and the manual log sheet becomes optional.

### B8.5 WhatsApp: Eduwit's separate B2C number

The B2C CRM uses **its own WhatsApp Business number, separate from Witty's**, through the WhatsApp Business Platform. Use the Cloud API directly, or a provider; choose in Phase 0.

- **One centralised inbox, scoped by role.** A counsellor searches and opens conversations for their own leads only, and messages them. The Admin searches and opens every lead's conversation (and can reply), including replies to marketing from pooled leads (the Replies inbox, B6.3). Marketing sees every conversation read-only plus the Replies inbox. Search covers student name, number, text and template name; filters by counsellor, unread, window open or closed, awaiting reply.
- **Opening a conversation: templates only.** A counsellor **starts** every conversation (first message, or any message after the 24-hour window has closed) with a **pre-approved WhatsApp template** from the sales template library. Counsellors cannot write or submit templates; **the Admin creates templates for both marketing and sales** (B9.2) and marks each one as usable by Sales. The composer lists only sales-usable, approved templates, fills their variables from the lead (name, programme, counsellor name, follow-up time, brochure link), and previews before sending.
- **Once the student replies, free text.** When a reply arrives, the 24-hour customer-service window opens and the counsellor types freely: text, media, documents, brochures, comparisons, quick replies and saved snippets, with no approval. The composer shows clearly which mode applies and the time left, and switches back to templates when the window closes.
- **Read receipts** and delivery status on every message.
- **Logging:** every message is stored in the B2C CRM's tables, never in `w2_messages`.
- **Inbound routing:**
  - a message from an assigned lead goes to that counsellor;
  - from a pooled lead, to the Replies flow (B6.3);
  - from an unknown number, a new lead is created through `lead_intake()` (`lead_source = 'b2c_whatsapp'`; the B2B CRM records it as B2C-held, reason `b2c_created`, B4.3) and it goes to the Admin's inbox.
- **Opt-out keywords** (STOP, unsubscribe, "band karo") opt out at once on every channel.
- **Witty is separate.** The B2C number never impersonates Witty. If a student asks about Witty's conversation, the counsellor has the transcript on the lead screen.

### B8.6 Email: every user's own Gmail, and sales templates

**Who sends what, from where.**

| Email | Sent from | How |
| --- | --- | --- |
| **Sales emails** (one-to-one, to a counsellor's own leads) | The counsellor's own `@eduwit.in` Gmail | Gmail API with the counsellor's OAuth consent (B16). The email appears in their Sent folder, replies land in their inbox and are threaded back to the lead |
| **Marketing, nurture and campaign emails** | The Admin's Gmail (`connect@eduwit.in`) | Gmail API, paced within Gmail's daily allowance (see below). Replies arrive in the Admin's Gmail and are threaded back |
| **System emails** (assignment fallback, 2FA codes, statements, scheduled reports) | A system sender on `eduwit.in` (a Google Group or alias) | Gmail API, kept apart from marketing volume so that codes are never queued behind a campaign |

**The daily allowance.** Gmail limits how many messages a mailbox may send in a rolling 24 hours. Google's published figure for a standard Workspace account is 2,000 messages, and Google says it may change without notice. Vikas has accepted that limit for now. So marketing mail is queued and paced across the day inside the allowance; the Nurture page shows how much of today's allowance is used; a campaign that would not fit is flagged before it starts, with the option to spread it over more days; and WhatsApp carries nurture where it can. Google's published page describes no paid option to raise the cap. A higher allowance can come from more sending accounts or from a bulk provider behind the same adapter; both are configuration changes, not a redesign. The CRM reads the limit from settings, not from code.

**Connecting Gmail takes one click.** Each user connects their own Gmail once from Connectors (B16), with the Google OAuth scopes `gmail.send`, `gmail.readonly` (for reply threading) and `gmail.metadata`. If Vikas enables **domain-wide delegation** in Google Workspace for the CRM's service account, no user has to connect anything: every `@eduwit.in` mailbox is usable the moment the account is created in Teams. Offer both; recommend delegation.

**Reading replies.** A Gmail watch (Pub/Sub push) on each connected mailbox threads replies to the lead by `In-Reply-To` and the lead's known addresses; the Admin's mailbox watch feeds the Replies inbox and reply classification (B6.6).

**Tracking:** opens and clicks for marketing emails; link clicks for sales emails (opens are not tracked on one-to-one mail).

**Sales email templates (written by counsellors).**

- A counsellor writes, saves and edits **their own** email templates: subject, body with merge fields (student first name, programme, university, fee, EMI, counsellor name and number, brochure link, follow-up time), optional attachments from the Programme page, and a category (first email, after call, brochure, fee and EMI, documents checklist, reminder).
- **Every counsellor's template is visible to every other counsellor** in a shared library, with the author's name. Another counsellor can use it as it is, or **edit it and save their own version**. Saving creates a **new template owned by the second counsellor**, linked to the original as its parent; **the original stays exactly as its author left it**. Only the author (and the Admin) can change or delete an original; deleting it keeps the copies.
- The library shows usage and reply rates per template, so good templates surface. The Admin can mark a template "recommended" or hide one.
- Sales templates are never used by journeys or campaigns; marketing templates (B9.2) are never editable by counsellors.

### B8.7 Follow-up discipline and SLAs

- **Next task required.** Every open lead must have a next task; saving a stage or a call log without one is blocked.
- **Agenda:** a daily agenda and a calendar view.
- **Reminders and escalation:** reminders 10 minutes before a task, as in-app, push and optionally WhatsApp to the counsellor's own phone. Overdue tasks alert the counsellor, then the Admin.
- **First-contact SLAs** (defaults from `crm_settings.sla_minutes`, editable by source and temperature):
  - hot (and every duplicate-cascade lead): 15 minutes in working hours;
  - warm: 4 hours;
  - cold: 24 hours.

  A breach turns the lead red in queues and alerts the Admin.
- **Neglect alert:** leads untouched for 48 hours are flagged.
- The Follow-ups page (B8.2) is the counsellor's working list for all of this.

### B8.8 Applications, documents and enrollment

- **Documents.** A per-university document checklist, from settings. Uploads go to private storage with signed links. The student can also send documents on WhatsApp; the counsellor attaches them to the checklist in one tap.
- **Recording enrollment.** The counsellor records the application (ID, status) and the enrollment (fee amount, fee paid, enrollment date, proof: university confirmation or fee receipt).
- **Verification.** Enrollment moves to `verified` only when the Admin verifies the proof (B11).

### B8.9 Programme page (every role)

A live, read-only catalogue of **every programme Eduwit can sell**, so a counsellor pitching on a call has the exact details in front of them.

- **Source:** the **shared `catalog` schema**, which the B2B CRM loads from one Excel or Google Sheet file per partner (its Programme Repository). The B2C CRM reads the catalog views directly, read-only, and keeps a short cache (`b2c.programme_cache`) refreshed on each catalog change. Witty reads the same catalog. Nothing is editable here; "Suggest a correction" sends a note to the Admin. In Phase 0 the `catalog` views point at the existing `catalog_programs`, `catalog_universities` and `catalog_synonyms` tables, so nothing moves and Witty is unaffected (B21, decision 3).
- **Each programme shows:** university, programme name, specialization, level, mode (online, ODL, regular), duration, eligibility (minimum qualification and percentage), fees (per year, per semester, total, exam and registration fees), EMI availability and typical EMI, scholarship notes, intake dates and deadlines, accreditation and approvals, brochure, which partners offer it and the partner commission for it (**Admin and Marketing only**; counsellors never see partner commission), and the counsellor commission owed to Eduwit for it (**Admin and Marketing only**).
- **Filters and search:** type of programme, level, university, specialization, mode, **fee range** (slider), duration, eligibility met for the current lead (when opened from a lead), intake month, accreditation; full-text search; sort by fee, duration or popularity (enrollments).
- **Compare:** pick 2–4 programmes side by side; send the comparison or a brochure to the lead on WhatsApp or email in one tap.
- **From the lead screen:** Programme fit (B8.3) is this page filtered to the lead's profile and interest.

## B9. Marketing: nurture by WhatsApp and email (Admin and Marketing only)

Counsellors never see or use the Nurture page, the marketing template page, segments, campaigns or journeys. Marketing users have every capability in this section; the Admin has them too.

### B9.0 The Nurture page

One page, with the depth of LeadSquared's and Salesforce's nurture tooling, where Marketing runs every nurture programme for **every type of lead**: not-qualified, partner-lost, counsellor-lost, dormant, and, when a journey or campaign targets them, leads in active sales (subject to the "no automated marketing during active sales" rule, which the Admin can relax per journey).

- **Overview:** the Nurture Pool (B6.2): size, inflow and outflow, by reason and age; re-engagement rate and time; cost per re-engaged lead; messages today; the email allowance used today against Gmail's limit; deliverability and WhatsApp quality rating; today's replies by class.
- **Journeys:** the visual builder (B9.4) with live counts on every step, a per-journey funnel (entered, in progress, exited by reason, re-engaged, enrolled), versioning (edit a draft, publish, keep running leads on the old version or migrate), test mode on test leads, and clone.
- **Campaigns:** one-off and recurring broadcasts (B9.3) with scheduling, send windows, throttling, A/B tests, and results.
- **Segments:** dynamic and static (B9.1), with live counts and overlap analysis.
- **Replies inbox:** every reply to a nurture message with its class and confidence, actions (assign to counsellor, answer, mark negative, opt out, correct the class).
- **Lead-level control:** open any pooled lead, see its nurture history, pause or resume, move it to another journey, send a one-off message, or hand it to a counsellor.
- **Guardrails and consent** (B9.4, B9.6) and **frequency and quiet-hour settings** are shown on the page with their current effect ("1,240 leads suppressed today: 900 by frequency cap, 340 without consent").
- **Scoring rules** (B9.5) are edited here.

### B9.1 Segments

- **Dynamic segments** from rules on any field, stage, lane, reason, lost reason, score, source, campaign, activity or date. For example: "partner lost, over budget, MBA interest, no reply in 14 days".
- **Static lists** from a CSV or a filter snapshot.
- **Live count** before saving.

### B9.2 Marketing templates

- **Email:** drag-and-drop editor, merge fields, preview with a real lead, plain-text version, unsubscribe footer.
- **WhatsApp:**
  - templates synced from the B2C number's account;
  - new templates submitted for approval from the CRM, with their category (marketing or utility);
  - variables mapped to fields; media headers; **quick-reply buttons** (used for re-engagement, B6.3) and URL buttons;
  - the Admin alone creates the **sales** WhatsApp templates counsellors use to open conversations (B8.5, B9.2a).
- **Language:** Hindi and English versions, chosen by `preferred_language`.

### B9.2a The Template page

One page for all message templates, with the rules on who may do what:

| Template type | Created and edited by | Used by | Notes |
| --- | --- | --- | --- |
| **WhatsApp templates: marketing and nurture** | Admin and Marketing | Journeys, campaigns | Submitted to Meta for approval from the page; category marketing or utility; status synced |
| **WhatsApp templates: sales** (openers, follow-up nudges, brochure, fee and EMI, document reminders, appointment confirmations) | **Admin only** | Counsellors, to open or reopen a conversation (B8.5) | Marked "usable by Sales"; utility category where Meta allows; variables mapped to lead and counsellor fields |
| **Email templates: marketing and nurture** | Admin and Marketing | Journeys, campaigns | Drag-and-drop editor, merge fields, plain-text version, unsubscribe footer |
| **Email templates: sales** | Counsellors (their own), Admin | Counsellors | The shared library with fork-on-edit (B8.6). Not usable in journeys or campaigns |

Every template has versions, a preview with a real test lead, language variants (English, Hindi, Hinglish), tags, and usage and performance figures.

Marketing works the Nurture Pool and supports counsellors. By default a lead in active sales with a counsellor gets **no automated marketing**, only what the counsellor sends, which keeps the student's experience coherent. The Admin can allow a specific journey or campaign (for example an admission-deadline countdown) to reach leads in active sales; the counsellor sees it on the timeline.

### B9.3 Campaigns

- **Sending:** one-off broadcasts to a segment, now or scheduled, with a send window and throttling. Email is paced within the daily allowance (B8.6).
- **A/B tests** on subject or template with a sample; the winner goes to the rest.
- **Results:** sent, delivered, read, opened, clicked, replied (positive, negative), unsubscribed, bounced, **re-engaged**, enrolled, and WhatsApp cost.

### B9.4 Journeys (automated nurture)

A visual builder. The 6 starter journeys already in the database are reviewed in Phase 0 and adapted.

| Part | Options |
| --- | --- |
| **Triggers** | Enter the pool with a reason (`not_qualified`, `partner_lost` + lost reason, counsellor `lost` + reason); enter a segment; a field or tag changes; no activity for N days; a date arrives (admission deadline); email opened or clicked; WhatsApp reply |
| **Steps** | Send WhatsApp template or email; wait (a duration, or until a time of day); branch on any condition or reply class, with A/B splits; update a field or score; add a tag; create a task for the Admin; **assign to counsellor** (re-engage); exit |
| **Exits** | Re-engagement (B6.3), positive reply, assignment, opt-out, negative reply (moves to a long-gap journey), enrollment, dormancy, or "routed to partner" |

**Starter set:**

- new enquiry, never qualified (programme discovery);
- eligibility unknown;
- fee concern / over budget (lower-fee options);
- not eligible (programmes they qualify for);
- admission-deadline countdown;
- partner-lost re-engagement (by lost reason);
- not now (monthly update);
- not reachable ("we tried to reach you").

**Guardrails** (defaults from `crm_settings.marketing`):

- **Frequency:** at most 1 marketing WhatsApp per lead per day and 6 per 30 days; at most 2 emails a day.
- **Quiet hours:** outside 09:00–20:00 IST.
- **One journey at a time** per lead.
- **No marketing during an AI chat:** nothing while the student is in an active Witty or website-agent conversation (a message in the last 30 minutes).
- **Partner holds:** no marketing while the B2B CRM shows the lead as held by a partner, which can only happen after a manual send to partners.

### B9.5 Lead scoring

- **Fit points** (from `crm_settings.scoring`, editable):
  - timeline within 3 months;
  - budget stated ≥ ₹50,000 a year;
  - qualification known and meets the programme minimum;
  - working professional for executive programmes;
  - phone verified.
- **Engagement points:**
  - WhatsApp read and reply;
  - email open, click and reply;
  - brochure link opened;
  - Witty conversation resumed;
  - form filled.
- **Decay:** engagement points halve every 14 days without activity.
- **Re-engagement threshold:** a score of **60 or more** triggers re-engagement (B6.3). Temperature bands default to hot at 60 and warm at 30.
- **Logging:** every score change is logged with its rule.
- **Write discipline:** scores are computed in `b2c.score_events` and `b2c.leads_state`. The B2C CRM writes `student_leads.lead_score` and `temperature` only when the value changes by a whole band or crosses the 60 threshold. Decay is computed in small batches off-peak, never as a mass update that could slow Witty's writes.

### B9.6 Consent and preferences

- **Records:** opt-in status per channel, with the consent text, source and time.
- **Opt-outs:** an unsubscribe link in every email; STOP and equivalents on WhatsApp honoured at once.
- **Suppression:** a global suppression list.
- **Partners:** opt-outs emit `b2ccrm.opted_out`, so the B2B CRM informs partners.

### B9.7 WhatsApp cost control

Every outbound conversation is tagged by category (marketing, utility, service), and its cost is estimated from the rate card. Spend per campaign and journey shows next to the re-engagements and enrollments it produced.

## B10. Leads table and Admin tools

### B10.1 All B2C leads

A single table for the Admin: every lead the B2C CRM holds, in both lanes and every stage. Counsellors see the same table, filtered to their own leads. Each row shows:

- identity and contact;
- lead generation date and source, campaign, lane and hand-off reason;
- partner history if partner-lost;
- programme and university of interest;
- profile;
- stage, sub-stage, counsellor and assigned date;
- sales effort: calls logged, last outcome, next task, SLA status;
- journey and score;
- application and enrollment;
- for enrolled leads: university commission (gross, GST, net, status) and the counsellor's commission.

**Working with the table:** this is the Leads page of B8.2, with the Admin's extra columns and bulk actions:

- column chooser, filters on every property and every sales activity, group-by with totals, saved personal and standard views;
- select some or all rows (across pages) for bulk actions (B10.3), including **bulk delete**;
- a virtualised grid with server-side paging;
- live updates;
- search by name, any phone, email or application ID.

### B10.2 Edit

- **Admin:** edits any field of any lead, inline and in the lead form, with field history, including existing contact details; deletes and bulk deletes (B10.4).
- **Counsellors:** edit the profile and interest fields of their own leads (including cross-sell changes, B8.3) and add contact details; they never edit or delete an existing phone or email, and never delete a lead.
- **Marketing:** read-only on lead fields; edits tags, consent records and journey membership.
- **Corrections to Witty fields:** recorded as human corrections (B3.3).

### B10.3 Bulk actions (Admin; Marketing gets the two marked ✱)

- **Reassign** (by rules or to a named counsellor).
- **Add to a journey,** or remove from one. ✱
- **Add or remove a tag.** ✱
- **Change stage,** within the stage rules (sub-stage and comment apply to all selected).
- **Send to partner routing** (B4.2).
- **Export** (B10.5).
- **Delete** (B10.4): select some rows or all rows of a view, then bulk delete with typed confirmation.

### B10.4 Delete (soft) and erasure

- **Delete** sets `deleted_at` and a reason (junk, test, duplicate entry, spam, student request). The lead disappears from views, queues, journeys and analytics, and sits in a **Recycle Bin** for 30 days, restorable by the Admin.
- **Bulk delete:** typed confirmation, run as a background job, undo for 30 days.
- **Limits:**
  - leads with an enrollment or money lines cannot be deleted, only closed;
  - the database already blocks hard deletes of more than 5 rows (`student_leads_bulk_delete_guard`), and the UI never hard-deletes.
- **Student erasure request** (India's DPDP Act): an Admin-only action that **anonymises** the lead's personal fields, deletes its message bodies and documents, keeps money rows by ID, and emits `b2ccrm.erasure_requested` so the B2B CRM informs every partner that received the lead. Logged with the request reference.

### B10.5 Download

- **What:** the current view, or selected rows, as Excel or CSV. Admin only.
- **Large exports:** in the background over 10,000 rows, with an expiring link.
- **Log:** every export is logged with filter, columns and row count.

## B11. Money: university commission and counsellor commission

Two amounts are recorded on every in-house enrollment: Eduwit's **university commission**, which the university pays Eduwit (B11.1), and the **counsellor commission**, which the counsellor owes Eduwit (B11.2). Both are traced to the enrollment and to the rate that produced them.

### B11.1 Eduwit's university commission (receivable)

- **Rates** per university, with optional overrides per programme, versioned by date. Types:
  - **percent** of a fee base (first-year, total or amount paid);
  - **fixed** amount;
  - **tiered** by conversion (e.g. 22.42% below 7%, 20.42% from 7% to under 9%, 18.42% at 9% and above).
- **GST:** each rate has a GST-inclusive flag. Eduwit's commissions are GST-inclusive; reports show gross, GST and net.
- **Booking:** an enrollment books an *expected* commission line from the rate in force on its enrollment date. It becomes *realised* when the Admin verifies the proof.
- **Tiers:** provisional during the period, settled at period close from verified enrollments ÷ leads (the denominator is a setting).
- **Invoicing:** at period close, the CRM lists verified, uninvoiced enrollments per university and generates a GST invoice. It carries sequential numbering, Eduwit's and the university's GSTIN, the SAC code, and one line per enrollment. The Admin approves and sends it.
- **Receipts:** payments recorded with TDS and bank reference, auto-matched to invoices, with ageing and reminders.
- **University statements:** uploaded and reconciled into four piles: matched, university only, Eduwit only, amount mismatch.
- **Refunds:** a refund inside the university's refund window reverses the commission with a negative line.

### B11.2 Counsellor commission: owed to Eduwit at the highest partner rate

**The rule (Vikas, 14 October).** For every successful in-house enrollment, the counsellor or sales manager who closed it owes Eduwit the same commission per enrollment that the edtech partners pay Eduwit for that programme:

- where one partner offers the programme, the counsellor's rate is that partner's rate;
- where two or more partners offer the same programme, the counsellor's rate is the **highest** of their rates for that programme.

Other rules:

- **Source of the rates.** The shared `catalog` schema (B8.9, B17) holds each partner's commission per programme, or per university where a partner's rate is university-wide: rate type, value, fee base, tier and valid-from date. The B2C CRM reads them through the catalog views and never keeps an editable copy. Each enrollment stores a **rate snapshot**: the rate source, the partners considered, the rate used, the computed amount and the time it was read. A later rate change never alters a commission already booked; it applies to later enrollments.
- **Programme with no partner, but the university has one:** the highest partner rate for the university is used, and the line is flagged (`rate_source = 'university_highest'`).
- **University with no partner:** the line is created with status **needs rate**. Nothing is confirmed, due or settled until the Admin sets a rate for that university (`b2c.commission_fallbacks`). The Admin is alerted.
- **Computation.** Percent rates apply to the fee base carried in the catalog (first-year fee, total fee or amount paid); fixed rates copy the amount; tiered rates use the tier the partner is on, as carried in the catalog, unless the Admin sets "use the top tier". Deductions such as TDS are a setting, off until Eduwit's CA confirms them, and shown separately.
- **Overrides (Admin only, logged):** a per-counsellor or per-programme override, and a one-off adjustment, each with a reason. Any override is visible to the counsellor on the line.
- **Lifecycle:** *provisional* when the enrollment is recorded → *confirmed* when the Admin verifies the proof → *due* after the university's refund window → *settled* when it is recovered in a commission run.
- **Clawback:** a refund inside the window reverses the line, or moves it to the next run if already settled.
- **Commission run:** monthly. The Admin reviews per counsellor, applies clawbacks and approves. The CRM exports a CSV for Eduwit's finance team and sends each counsellor a PDF statement of what they owe and what is settled. How the amount is collected (deduction, invoice or payment) is Eduwit's decision (B21). The CRM moves no money.

Eduwit's two amounts for an enrollment (the university commission and the counsellor commission owed) appear together on the Admin's dashboards (B11.3).

### B11.3 Commission dashboards (one per counsellor, one for the Admin)

- **Counsellor's commission dashboard (own data only):**
  - this month's commission owed as four tiles (provisional, confirmed, due, settled) and the year to date;
  - **every enrollment** as a row: student, university, programme, enrollment date, fee, the rate applied and the partners it was taken from, commission owed, status, expected settlement date, clawbacks;
  - by university and by month; 12-month history;
  - target progress;
  - statements to download.
- **Admin's commission dashboard:**
  - Eduwit's university commission (expected vs realised; gross, GST, net) by month and university;
  - counsellor commission owed, by counsellor, status and month; the run calendar;
  - Eduwit's two amounts per enrollment and per university, side by side;
  - the partner-rate table per programme from the catalog, with the highest marked, and alerts when a rate changes;
  - enrollments waiting at **needs rate**;
  - receivables and ageing; tier watch; variance against university statements.
- **Marketing** sees both money dashboards **read-only**. It cannot change rates, overrides, runs or invoices.
- **Published view:** a read-only, versioned view `b2c_enrollment_money_v` (lead ID, enrollment, university commission gross, GST, net, status, invoice, counsellor commission total), which the B2B CRM's Master Lead Table reads.

Every number opens the enrollments behind it; nothing is typed by hand. GST rate, SAC code, TDS and refund windows are settings to be confirmed by Eduwit's CA.

## B12. Team performance

- **Targets** per counsellor per month: calls logged, connected, counselled, applications, enrollments, commission. A progress bar sits on each home screen.
- **Leaderboard** (opt-in visibility for counsellors).
- **Activity monitor (Admin):**
  - calls logged and connect rate;
  - WhatsApp and email sent;
  - first-contact time;
  - SLA breaches;
  - overdue tasks;
  - leads untouched for 48 hours;
  - "calls tapped but not logged".
- **Capacity panel:** leads assigned this month vs cap per counsellor, and the hiring trigger (B7).
- **Coaching notes:** the Admin can leave a note on a counsellor's lead; it shows on the timeline as internal.

## B13. Analytics: an AI-enabled, fully customisable analytics page for every role

Every number drills down to its leads. Data is under 1 minute old. The Analytics page is **pre-populated with standard dashboards** and **fully customisable**, and every role gets its own copy scoped to what it may see.

### B13.1 Who sees what

| Role | Analyses | Standard dashboards shipped |
| --- | --- | --- |
| **Admin** | Marketing and sales, the whole company, money | Admin overview (the complete sales funnel from hand-off to commission, with every possible metric); Nurture and re-engagement; Sales funnel; Fallback value; Team and capacity; Money and margin; Speed and effort; Quality |
| **Marketing** | Marketing **and** sales (to see what nurture produces), and money (read-only) | Nurture and re-engagement; Campaigns and journeys; Segments; Deliverability and WhatsApp cost; Sales funnel (read); Lead sources; Money (read-only) |
| **Sales** (counsellor) | Sales only, their own leads | My funnel; My follow-ups and SLAs; My activity (calls, connects, messages); My enrollments and commission; My week. A sales head sees the same for the team |

### B13.2 Metrics (all available to the builder, subject to role)

| Area | Metrics |
| --- | --- |
| Inflow | Hand-offs by lane and reason per day; duplicate-cascade leads by partner pair; partner-lost leads by partner and lost reason; fallbacks by source (including Meta and Google); B2C-created leads |
| Nurture | Pool size and age; journey entries, steps, exits by reason; messages sent, delivered, read, replied; reply classes; **re-engagement rate and time to re-engagement** by reason, partner and journey; cost per re-engaged lead; dormant and opted-out counts; suppression by cause |
| Sales funnel | Every Eduwit stage (B5.1): New Lead → Could Not Connect → Contacted → Qualified → Follow Up → Program Details Explained → Applicant → Docs Submitted → Enrolled, and Lost by sub-stage, with conversion per step, time per stage, and the canonical view for comparison with partners; by lane, reason, source, campaign, programme, university, counsellor |
| Speed and effort | First-contact time; SLA compliance; calls logged per lead; connect rate; attempts before connect; follow-up adherence (on time, late, missed); untouched leads; unlogged calls; template usage and reply rates (WhatsApp and email) |
| Fallback value | Enrollments and commission recovered from leads partners lost or reported as duplicates, by partner and by source |
| Money (Admin; Marketing read-only) | University commission expected and realised; counsellor commission by status; net margin per university; receivables; tier watch; partner-rate changes |
| Team (Admin, sales head) | Targets vs actuals; leaderboard; capacity; allocation fairness (leads per counsellor vs rule) |
| Quality | Classification accuracy (corrections), missing required fields, duplicate suspects, cross-sell changes and their outcome |

### B13.3 Dashboard builder

- **Widgets:** KPI tile with delta, line, bar, stacked bar, funnel, cohort grid, table, pivot, leaderboard, gauge, map (city or state), text note;
- **Any metric by any dimension**, with dashboard-wide filters, date ranges and comparison periods;
- **Save** personal dashboards, set one as home; the Admin can publish a dashboard to a role as a standard one; duplicate and edit any standard dashboard;
- **Schedule** by email (PDF or CSV) daily, weekly or monthly; **metric alerts** by WhatsApp or email when a number crosses a threshold or moves unusually;
- **Drill-down** from any number to the leads behind it, opening a Leads-page view with the same filters.

### B13.4 AI in analytics (Claude)

- **Ask in plain language:** "Which lost sub-stage grew most this month?", "Compare conversion for MBA leads from Meta vs organic for Priya and Rohan". Claude turns the question into a query over the role's permitted metrics and dimensions (never raw personal data), shows the chart and the query it ran, and lets the user save it as a widget.
- **Insights feed:** every morning, and on demand, a short list of what changed and why it matters (re-engagement dropped 20% after a template change; one counsellor's connect rate fell; a university's commission rate changed), each with the chart behind it.
- **Anomaly alerts** on the key series (hand-offs, replies, SLA breaches, enrollments).
- **Explain this chart** on any widget.
- **Rules:** only aggregated, de-identified data goes to the model; every query is logged with its SQL; a daily spend cap; role scoping is enforced in the query layer, not by the model.

**Default dashboards** are listed in B13.1. Analytics read the B2C CRM's own event log and roll-ups (refreshed every minute), never by scanning `student_leads` repeatedly.


## B14. Data model

Every new table goes in the Postgres schema **`b2c`**. Existing empty B2C tables in `public` move there in Phase 0 if Vikas agrees. Check what calls them first (`pg_depend` and the SQL in n8n workflows, which Vikas can export). Shared objects stay where they are, including `crm_settings`, `crm_find_lead()`, `crm_norm_phone()` and anything else `lead_intake()` uses.

| Table | One row per | Notes |
| --- | --- | --- |
| `crm_users` (existing; B2C's user table) | Admin, Marketing, counsellor, sales head | Add `role` values `marketing` and `sales_head`; `workspace_user_id` (Google directory ID), `job_title`, `photo_url`, `synced_at`, `invited_at`, `invite_token_hash`, `push_subscription`, `on_call`, `away_until`, `weight`, `skills` (languages, programmes, universities, territories), `tz` |
| `crm_teams` (existing) | Team | Optional for now |
| `b2c.work_schedules`, `b2c.shift_rosters`, `b2c.holidays`, `b2c.leaves` | A counsellor's weekly pattern; a week's shifts; a company holiday; a leave | Working days and hours per weekday; shift name and times; holiday date and name; leave dates with hold or reassign-after |
| `b2c.allocation_rules`, `b2c.allocation_pools`, `b2c.allocation_decisions` | An ordered rule; a named pool with weights; one allocation decision | Rule condition (JSON), logic, pool, fallbacks, enabled, applies-from; pool members and weights; for every decision the eligible candidates, skipped candidates with reasons, chosen counsellor, rule and turn |
| `b2c.leads_state` | Lead held by B2C | `lead_id`, `lane`, `handoff_reason`, `handoff_event_id`, `handed_off_at`, `pool_entered_at`, `reengaged_at`, `reengage_trigger`, `lost_by` (partner ID or user ID), `dormant_at`, `closed_at`, `routed_to_partner_at`, **`eduwit_stage`, `eduwit_sub_stage`, `stage_comment`** (the Eduwit pipeline of B5; the canonical stage is written to `student_leads.stage`). The B2C CRM's own lifecycle record, linked to `student_leads.id` |
| `b2c.stage_definitions`, `b2c.sub_stage_definitions` | An Eduwit stage; a sub-stage | Name, order, canonical mapping, required fields, colour, active; sub-stage name, stage, nurture journey and delay (for Lost) |
| `b2c.lead_contacts` | A phone number or email on a lead | `lead_id`, kind (phone, email), value (normalised), label, `is_primary_call`, `is_primary_whatsapp`, `is_primary_email`, `origin` (intake, counsellor, admin), added by, verified; the intake values are mirrored here as locked rows |
| `b2c.handoff_inbox` | Received hand-off event | Raw payload, processed flag, error. For idempotency and reconciliation |
| `b2c.assignments` | Assignment or reassignment | Lead, counsellor, rule applied, trigger, decision ID, by whom, at |
| `b2c.saved_views` | A saved lead view | Owner, role, name, filters (JSON), columns, sort, group, layout (list or kanban), is_standard, is_default, shared_with_role |
| `b2c.user_dashboards`, `b2c.user_widgets` | A personal or standard dashboard; a widget | Owner, role, name, is_standard, is_home; widget type, metric, dimensions, filters, position |
| `b2c.sales_email_templates` | A counsellor's sales email template | Owner, name, category, subject, body, attachments, `parent_template_id` (fork origin), version, recommended, hidden, usage and reply counts |
| `b2c.programme_cache` | A programme from the shared catalog | Cache of the catalog record: partners and commission columns (Admin and Marketing only), read at, catalog version |
| `b2c.partner_rate_cache` | A partner's commission rate for a programme or university, from the shared catalog | Partner, university, programme (nullable), rate type and value, fee base, tier, valid from, read at |
| `b2c.commission_lines` (replaces the use of `payouts` for new lines; keep `payouts` as the legacy name or rename in Phase 0) | A counsellor commission line, owed to Eduwit | Enrollment, counsellor, `rate_source` (programme_highest, university_highest, override, needs_rate), partners considered and the rate used, computed amount, deductions, status (provisional, confirmed, due, settled, reversed), run, reverses |
| `b2c.commission_fallbacks` | The Admin's rate for a university with no partner | University, rate type and value, valid from, set by, reason |
| `b2c.user_connections` | A user's connected account | User, provider (gmail, google_directory, whatsapp, b2b), scopes, token reference in Vault, status, connected at, last used, error |
| `b2c.user_guides`, `b2c.guide_progress` | A guide article per role; a user's progress | Role, section, title, body (Markdown with screenshots), order, version; user, article, done |
| `crm_activities` (existing) | Note, stage change, system event | Kept for the timeline |
| `calls` (existing) | Call | Phase 1 manual logs (`provider = 'manual'`, outcome, approximate duration, `tapped_at`, `logged_at`); later from telephony |
| `crm_tasks` (existing) | Task | Kind (call, WhatsApp, email, document, follow-up), due, done, reminders, escalation |
| `b2c.wa_conversations`, `b2c.wa_messages` | WhatsApp conversation or message on the **B2C number** | Direction, template or free text, media, status receipts, window expiry, category and cost, provider message ID |
| `b2c.emails` | Email sent or received | Thread ID, opens, clicks, bounce |
| `b2c.reply_classifications` | Classified inbound reply | Channel, class, confidence, method (rule or AI), corrected-by |
| `segments`, `segment_members`, `message_templates`, `campaigns`, `campaign_sends`, `journeys`, `journey_runs` (existing) | Marketing objects | Extend `journey_runs` with the trigger reason. Extend `campaign_sends` with reply class and re-engagement |
| `b2c.score_events` | Score change | Rule, points, decay |
| `b2c.applications`, `b2c.documents` | Application; uploaded document | University, programme, application ID, checklist status, storage path |
| `b2c.university_rates` | Eduwit's university commission rate version | Percent, fixed or tiered; fee base; GST-inclusive; valid from and to |
| `b2c.enrollments` | In-house enrollment | Lead, programme, university, fee, enrolled on, proof, status (reported, verified, refunded, cancelled), verified by and at |
| `b2c.earnings` | University commission line (receivable) | Gross, GST, net, status, tier provisional, reverses, invoice, receipt |
| `b2c.invoices`, `b2c.receipts`, `b2c.statement_imports`, `b2c.statement_matches` | Money documents | |
| `payout_rates`, `payouts`, `payout_runs` (existing) | Counsellor commission objects owed to Eduwit (B11.2); the names are legacy | Repoint `payouts.enrollment_id` to `b2c.enrollments` |
| `b2c.events` | Append-only event | Source of analytics and audit |
| `b2c.rollup_*` | Analytics roll-up | Refreshed every minute |
| `b2c.dashboards`, `b2c.widgets`, `b2c.metric_alerts`, `b2c.schedules` | Analytics config | |
| `b2c.audit_log`, `b2c.exports`, `b2c.deletions`, `b2c.field_history` | Platform records | |
| Published views | `b2c_enrollment_money_v` (for the B2B CRM), `b2c_lead_status_v` (stage, counsellor, lane; for the B2B CRM's referral view) | Versioned, read-only |

**Integrity rules enforced by the database:**

- A lead has at most one owner at a time, and only while B2C holds it.
- Stage moves follow the allowed transitions, and every stage change has a sub-stage.
- A commission or earning line always points to an enrollment and a rate snapshot.
- Money rows are reversed, never deleted.
- Intake contact rows in `b2c.lead_contacts` cannot be updated or deleted by a counsellor role (enforced by RLS and a trigger), and exactly one primary per kind exists per lead.
- A sales email template's `parent_template_id` is immutable, and updating a template never touches its forks.
- Test leads are never assigned to a real counsellor or messaged.

## B15. UI and UX

**Look and feel.** The design language is the same family as the B2B CRM, so Eduwit's products feel like one company, but it is its own app:

- calm, modern and uncluttered;
- **brand colours extracted from the logo** in `docs/brand/`: read SVG fills or sample PNG colours in code, propose a palette for Vikas to confirm, with WCAG AA contrast in light and dark modes;
- Geist Sans for UI and Geist Mono with tabular numbers;
- fine borders instead of heavy shadows;
- gentle motion; reduced-motion respected;
- full keyboard use on desktop.

**Three interfaces, no intermixing.** Each role signs into the interface built for it. Navigation, screens and vocabulary differ; the design language is shared.

| Interface | For | Shape |
| --- | --- | --- |
| **Sales app** | Counsellors, sales managers, sales head | Mobile-first, installable web app, fully usable one-handed on a phone and equally on a laptop. Bottom navigation: **Today**, **Leads**, **Follow-ups**, **Inbox**, **Me** (commission, templates, guide). Programme page and Pipeline from Leads. Large tap targets; the Call → log sheet flow (B8.4) designed for speed; swipe actions on lists (call, WhatsApp, snooze); push notifications |
| **Marketing workspace** | Marketing | Desktop-first: left sidebar with **Nurture**, **Templates**, **Segments**, **Campaigns**, **Journeys**, **Inbox (read-only + Replies)**, **Leads (read-only)**, **Money (read-only)**, **Analytics**, **Connectors**, **Guide**. Everything the Admin sees is visible; actions outside marketing are not rendered (and are refused by the API) |
| **Admin console** | Admin | The Marketing workspace plus **Pipeline**, **Lead Allocation**, **Teams**, **Money**, **Settings**, the lead-editing and bulk tools, and "view as Sales". Command palette (⌘K), dense tables, the journey builder canvas, dashboards |

**Built-in user guides, one per role.** Each interface has a **Guide** section inside the app (not a link to an external site):

- **Admin guide:** first-time setup in order (connect Google Workspace, create accounts in Teams, connect the WhatsApp number and the B2B CRM, set working calendars and allocation rules, stages and sub-stages, templates, commission settings, go live), then every function with a short walkthrough and screenshots;
- **Marketing guide:** nurture, segments, templates and WhatsApp approval, campaigns, journeys, consent and guardrails, replies, analytics;
- **Sales guide:** a day in the app, Today and Follow-ups, calling and logging, WhatsApp templates and the 24-hour window, email and sales templates, stages and sub-stages, cross-sell, applications and documents, recording an enrollment, commission.

Guides are searchable, open in a side panel next to the screen they describe (contextual "?" on every screen), track what the user has read, and are stored in `b2c.user_guides` so the Admin can edit them in the app. Generate the first version of all three from this prompt and the built screens, with real screenshots, in Phase 1.

**Screens:**

| Screen | Interface | Purpose |
| --- | --- | --- |
| **Today** (counsellor home) | Sales | Queue with SLA timers, the four follow-up cards in brief, targets, commission this month |
| **Leads** | All | Custom views, list and kanban, search (B8.2, B10.1); Admin tools on top |
| **Pipeline** | Sales, Admin | Kanban of Eduwit stages with value and priority (B8.2) |
| **Follow-ups** | Sales (Admin sees all) | Not worked yet, Overdue, Due today, Upcoming; calendar (B8.2) |
| **Lead screen** | Sales, Admin (Marketing read-only) | 360° view (B8.3), with Call → log sheet, WhatsApp, email, follow-ups, applications, contacts, cross-sell |
| **Inbox** | All, scoped | The centralised WhatsApp inbox and email threads (B8.5); Admin and Marketing also see the Replies inbox |
| **Programmes** | All | The Programme page (B8.9) |
| **Nurture** | Marketing, Admin | The Nurture page (B9.0) |
| **Templates** | Marketing, Admin (sales templates also in the Sales app under Me) | The Template page (B9.2a) |
| **Lead Allocation** | Admin | Rules, pools, calendar, capacity, simulation, queues, audit (B7.4) |
| **Teams** | Admin | Accounts from Google Workspace, roles, working days and hours, shifts, holidays, leave, caps, skills, weights, activity monitor, capacity |
| **Money** | Sales (own), Admin, Marketing (read-only) | Counsellor: my commission dashboard (B11.3). Admin: enrollments to verify (proof viewer side by side), university commission, counsellor commission and runs, invoices, receipts, statements, tier watch, partner-rate table |
| **Analytics** | All, scoped | Standard dashboards, the builder, AI questions and insights (B13) |
| **Connectors** | All (own), Admin (org) | Google Workspace directory, each user's Gmail, the WhatsApp number, the B2B CRM, the shared catalog (B16) |
| **Settings** | Admin | Stages and sub-stages, SLAs, document checklists, quiet hours, frequency caps, reply-classification threshold, providers, live switches, audit log, Recycle Bin, system health |
| **Guide** | All | The role's user guide |

**States.** Empty states explain what will appear. Skeletons match layouts. Errors say what to do. Every destructive action shows its impact and can be undone where possible.

## B16. Architecture

| Component | Recommendation |
| --- | --- |
| Web app and API | Next.js (App Router, TypeScript), PWA for counsellors; route handlers for the B2C API; server actions that call SQL functions |
| Database | The shared Supabase project: schema `b2c`, read-only views on the shared `catalog` schema, and the existing B2C tables; business rules as SQL functions; RLS on every B2C table (counsellors see only their own leads); `pg_cron` for timers (SLA, reminders, journeys, scoring decay, roll-ups) |
| Queue and workers | Supabase Queues (`pgmq`) and a Node 20 TypeScript worker: hand-off intake, assignment notifications, WhatsApp and email sending and receipts, journey steps, reply classification, payout runs, exports, reconciliation |
| Messaging | WhatsApp Business Platform for the **B2C number** (Cloud API or a provider, behind an adapter); **Gmail API** for every user's own sales email, and for marketing and system mail from the Admin's mailbox within Gmail's daily allowance (B8.6, B21 decision 8); a bulk provider can be added later behind the same adapter; web push for counsellors |
| Google Workspace | One Google Cloud project for the CRM with OAuth consent (internal, `eduwit.in`), scopes for Gmail send and read, and a service account with **domain-wide delegation** for the Directory API (Teams auto-sync) and, if Vikas enables it, for Gmail on behalf of every user. Tokens in Vault, never in tables |
| AI | Anthropic API for reply classification (Haiku), "Brief before you call" and analytics questions and insights (`claude-sonnet-5`), with only minimum, de-identified or aggregated data; daily spend cap; every call logged |
| Files | Supabase Storage (private buckets, signed URLs): documents, proofs, statements, exports |
| Hosting | Google Cloud Run in an India region (asia-south1 or asia-south2), separate staging and production |
| Testing | Vitest, pgTAP for SQL functions, Playwright end-to-end including mobile viewports, a WhatsApp and email sandbox, a mock B2B hand-off sender |

## B17. Integrations and API

| Direction | Endpoint or event | Purpose |
| --- | --- | --- |
| In | `POST /v1/handoffs` (HMAC from the B2B CRM): `b2c.lead_handed_off`, `b2c.lead_reenquired`, `b2c.lead_flagged`, `b2b.lead_routed_to_partner`. Reconciliation by B2B's `GET /v1/handoffs?since=` | Hand-offs, re-enquiries, route-to-partners confirmations (B4) |
| In | `POST /v1/webhooks/whatsapp` (provider signature) | Inbound messages and status receipts for the B2C number |
| In | `POST /v1/webhooks/email` | Opens, clicks, bounces, replies |
| In | Witty interest signal (agreed in Phase 0: a `student_leads` change or an event) | Re-engagement (B6.3) |
| Out | B2B `POST /v1/leads/{id}/route-to-partners` (B2C service key) | Admin's manual send to partners (B4.2) |
| Out | B2B CRM write API (`POST /v1/b2c/...`, signed, idempotent, outboxed) | Every B2C write to `student_leads` and to the B2B side: stage, sub-stage, field, contact and cross-sell changes, consent and opt-out, enrollment, and new leads made in B2C or from WhatsApp (B4.3; the B2B CRM takes them into `lead_intake()`) |
| Out | Events `b2ccrm.lead_assigned`, `b2ccrm.stage_changed` (Eduwit stage, sub-stage, comment and canonical stage), `b2ccrm.lead_updated` (field changes incl. cross-sell and new contact details), `b2ccrm.enrolled`, `b2ccrm.commission_booked`, `b2ccrm.opted_out`, `b2ccrm.erasure_requested`, signed webhooks to B2B's `POST /v1/events/b2ccrm`, sent within 2 seconds of the change, with retry and a reconciliation feed `GET /v1/events?since=` on the B2C side | Real-time sync to the B2B CRM's Master Lead Table and CAPI, and for telling partners about opt-outs and erasures |
| Read | Shared `catalog` schema: read-only views of programmes, universities, synonyms and partner rates, and a `catalog.updated` change feed | The Programme page (B8.9) and partner rates for counsellor commission (B11.2) |
| Google | Directory API (users list, suspended flag); Gmail API (send, threads, watch via Pub/Sub) per user | Teams auto-sync (B3.2); sales and marketing email (B8.6) |
| Read-only views | `b2c_enrollment_money_v`, `b2c_lead_status_v` | For the B2B CRM and the referral view |

**The Connectors section.** One screen per interface, designed so that everything connects with the least effort:

- **Admin (organisation-level, set once):** Google Workspace (directory sync, and the option of domain-wide delegation for all mailboxes), the WhatsApp Business number (Meta Cloud API or provider; health, quality rating, template sync), the B2B CRM (base URL, service key, signing secret, a "test connection" that exchanges a ping and shows the last events both ways), the Gmail sending allowance used today, Anthropic (key, spend cap), telephony later.
- **Every user (personal):** "Connect my Gmail" (one click, OAuth; shows as already connected when delegation is on), notification channels (push, WhatsApp to own number), calendar (optional, to show follow-ups in Google Calendar).
- **Status everywhere:** each connector shows connected or not, the last successful call, and the error if any; the Admin gets an alert when a connector breaks.

## B18. Security, privacy and compliance

- **DPDP Act 2023:**
  - consent per purpose and channel, with text and timestamp;
  - marketing only with consent;
  - erasure by anonymisation (B10.4);
  - a breach runbook;
  - Eduwit's lawyer approves consent wording and retention.
- **WhatsApp policy:** approved templates outside the 24-hour window, correct template categories, opt-outs honoured at once, and quality-rating monitoring with an alert if the B2C number's rating drops.
- **Access:**
  - company accounts only (`@eduwit.in`), mandatory email-code 2FA on untrusted devices (B3.2);
  - RLS on every B2C table, plus checks in the API, by role: Sales sees own leads; Marketing sees all but writes only marketing objects; Admin everything;
  - counsellors cannot export, bulk-copy, delete leads, or edit existing contact details;
  - Gmail and Google tokens live in Vault with the minimum scopes; a user's revocation is detected and surfaced;
  - every phone reveal and Call tap is logged.
- **Documents:** private storage, signed links that expire, no public URLs.
- **AI:** only the reply text and course interest go to Claude for classification. Only profile fields and the transcript, without phone or email, go to Claude for the brief.
- **Platform:** secrets in Vault; signed webhooks both ways; rate limits; an append-only audit log; daily backups with point-in-time recovery; dependency scanning; a penetration test before go-live.

## B19. Quality targets and build phases

### B19.1 Non-functional requirements

| Area | Target |
| --- | --- |
| Hand-off to assignment | Under 3 s from the B2B event for sales-lane leads |
| Re-engagement to assignment | Under 60 s from the trigger |
| Counsellor app | Lead screen under 1.5 s on 4G; call log sheet opens instantly on return |
| Messaging | WhatsApp and email send within 10 s of a counsellor's action; journey steps on schedule within 1 minute |
| Scale | 5,000 leads per day into the pool; 100,000 pooled leads; WhatsApp marketing at the rate the B2C number's Meta tier allows; email paced within Gmail's daily allowance (B8.6, B21); 50 counsellors, without redesign |
| Reliability | 99.9% monthly; zero lost hand-offs (reconciliation); idempotent sends, never double-messaging |
| Explainability | Every assignment, re-engagement, score, commission and payout traceable |

### B19.2 Phases

| Phase | Builds | Exit test |
| --- | --- | --- |
| **0. Audit and design** | Inventory with verdicts (A4); dependency map; the `b2c` schema plan including the Eduwit stage model (B5) migrated into `crm_settings`; the Witty interest-signal contract and "keep talking to pooled leads" rule (B2B Addendum 1, §4b); the plan for `crm_auto_assign`; marketing- and partner-consent coverage today; the B2B write API, the shared `catalog` views and the event contract (B17), agreed with the B2B developer; the Google Workspace setup (OAuth consent, service account, delegation) with Vikas; brand palette from the logo; app shell with the **three interfaces**; sign-in (Google, Eduwit email and password, email-code 2FA, Teams sync); **clickable mobile and desktop design** of Today, Leads (custom views), Follow-ups, Lead screen with the call log sheet and contacts, Inbox with template-first composer, Programmes, Nurture, Templates, Lead Allocation and the Admin dashboard, using sample data | Vikas approves the audit, the palette, the API contract and the clickable design |
| **1. Sell** | Hand-off intake and reconciliation; the allocation engine with working calendars, holidays, rules, pools, simulation and audit (B7); the Sales app (Today, Leads with custom views and personal dashboards, Pipeline, Follow-ups with reminders, lead screen, contacts, cross-sell, manual calling with log sheet, Eduwit stages and sub-stages with comments, applications and documents, enrollment); the centralised WhatsApp inbox on the B2C number with template-only openers; Gmail-connected sales email and the sales template library with fork-on-edit; the Programme page; the Admin's Leads page with edit, delete, bulk delete, export; manual send to partners; Admin verification of enrollments; Teams with Workspace sync; Connectors; every write through the B2B CRM's write API and real-time events both ways; the three user guides (first version) | 30 test leads: fallback hand-offs are allocated within 3 s by the rules, respecting a test calendar with a holiday and a counsellor on leave; simulation output matches live allocation; partner-barred leads show the badge and "Send to partners" is unavailable; every Call tap ends in a logged call or a "not logged" flag; a counsellor cannot open a WhatsApp conversation without a sales template, and can type freely once the test student replies; a counsellor can add a second number and make it primary but cannot edit the original; a cross-sell change is written to `student_leads` through the B2B write API and reaches the B2B mock within 2 s; a sales template forked by another counsellor leaves the original unchanged; a follow-up reminder fires 10 minutes early with a working lead link; nothing is ever sent to a real number in test; every assignment sends the right in-hours or out-of-hours message once; with no eligible counsellor the lead waits in Unassigned (or goes to the Admin when "Admin takes leads" is on); a manual send to partners closes the B2C pipeline only after `b2b.lead_routed_to_partner`, and returns to the previous counsellor on `manual_route_failed`; a Marketing user can see every lead, chat and money view, but every write outside marketing is refused by the API |
| **2. Nurture** | The Nurture page and Template page; segments, marketing templates (email and WhatsApp with approval), campaigns, journeys (starter set, versioning, test mode); lead scoring with decay; reply classification; re-engagement triggers (Witty, WhatsApp, email, score ≥ 60); lost sub-stage return rules; consent and opt-out; the Marketing workspace and guide | A partner-lost test lead enters the pool, receives its journey after the sub-stage's delay, and is allocated within 60 s of each trigger type (Witty interest, becoming qualified, new paid enquiry, positive WhatsApp button, positive email reply, score rising to 60). A lead entering the pool already scoring 60 from fit alone is **not** allocated. Opt-out stops everything at once. Guardrails hold (quiet hours, frequency caps, no messages during an AI chat, no automated marketing to leads in active sales unless the journey allows it) |
| **3. Money and analytics** | University commission rates, booking, tiers, invoices, receipts, statements; counsellor commission owed to Eduwit at the highest partner rate for the programme (B11.2), from the shared catalog, with the needs-rate queue, overrides, runs and statements; the counsellor and Admin commission dashboards; money views (including `b2c_enrollment_money_v`); the Analytics page with standard dashboards per role, the builder, scheduling, alerts and the AI questions and insights; "Brief before you call" | One month of university commission and counsellor commission matches a manual check by the Admin, and every counsellor commission line shows the programme, the partners considered and the rate it was computed from. Every dashboard number drills down to its leads. A Sales user's AI question cannot return another counsellor's data |
| **4. Telephony and depth** | Cloud telephony adapter (click-to-call, recording, missed-call tasks); ad-spend import for return on ad spend; performance-weighted allocation; Google Calendar sync of follow-ups; Hindi interface | Calls are bridged and recorded and appear on the timeline without manual logging |

**Test suite (minimum).**

- **Unit tests:** allocation rules and logics with calendars, holidays and leave; SLA clocks with working hours; score and decay; re-engagement triggers; reply-class thresholds; guardrails; stage and sub-stage transitions and the canonical mapping; contact-detail permissions; template fork semantics; highest-partner-rate computation by programme, with one, several and no partners, and with percent, fixed and tiered rates; commission with overrides, needs-rate lines and clawbacks; tiered university commission with GST; role scoping of analytics queries.
- **pgTAP tests:** every SQL function.
- **End-to-end:** from hand-off through allocation, calls, follow-ups, application, enrollment and verification to university commission and counsellor commission, in all three interfaces. Mobile viewports for the Sales flows.

## B20. Defaults in force until Vikas decides otherwise

| Decision | Default used |
| --- | --- |
| WhatsApp setup for the B2C number | Meta Cloud API directly, behind an adapter. A provider (e.g. Interakt, AiSensy, Gupshup, WATI) can replace it |
| Email for marketing and nurture | The Admin's Gmail, paced within the daily allowance; a bulk provider can be added later behind an adapter (B8.6; B21, decision 8) |
| Telephony | None in phases 1–3; counsellors use their own phones with manual logging. Adapter ready for a provider in phase 4 |
| Re-engagement score threshold | 60 |
| Reply classification confidence | 0.8; below that, the Replies inbox |
| First nurture message after a loss | By lost sub-stage (B6.4) |
| Dormancy | 12 months without response |
| Counsellor monthly cap | 200 leads; open-lead and daily caps off |
| Allocation logic | Round robin over everyone, one catch-all rule; refinements off (B7.3) |
| Working hours and days | Monday to Saturday, 10:00–19:00 IST, Indian national holidays loaded; the Admin edits per person |
| Hiring alert | 10 enrollments per counsellor per month |
| First-contact SLAs | Hot and duplicate-cascade 15 min; warm 4 h; cold 24 h (working hours) |
| Counsellor commission | **Decided (14 Oct):** owed to Eduwit at the highest partner rate for the programme, read from the shared catalog (B11.2). Programme with no partner: highest university rate, flagged. University with no partner: the line waits as "needs rate" until the Admin sets one |
| Device trust for 2FA | 30 days |
| Sales head role | Off until needed |
| Counsellors see the Nurture Pool | Off (they never see the Nurture page; the pool is not theirs) |
| Automated marketing to leads in active sales | Off; the Admin can allow it per journey or campaign |
| Witty interest signal | To be agreed with the Witty developer in Phase 0 |
| GST, SAC, TDS, refund windows | Confirmed by Eduwit's CA |

## B21. Decisions of 14 October 2026, conflicts resolved, and questions for Vikas

Vikas answered the six open questions on 14 October (money, email, sync, the catalogue, 2FA and Marketing). Those answers are built into the sections above and marked **Confirmed**. The other rows stand as written and are still open for Vikas to confirm before Phase 1; the defaults in B20 apply until then.

| # | Point | Earlier rule | Final rule in this prompt | Status and what to confirm |
| --- | --- | --- | --- | --- |
| 1 | **Lead stages** | Canonical stages shared with the B2B CRM (`new`, `contacted`, `counselled`, `applied`, …) | Counsellors use Eduwit's ten stages (New Lead … Enrolled, Lost) with sub-stages and a comment; each maps to a canonical stage written to `student_leads.stage` (B5.1) | Both are kept: the team gets its own vocabulary, and partner and in-house funnels still compare. **Open:** confirm the default sub-stage lists and that "Qualified" maps to canonical `counselled` |
| 2 | **Counsellor commission owed to Eduwit** | Payout base to be decided (% of fee, % of net, or fixed) | The counsellor **owes Eduwit** the same commission per successful in-house enrollment that the edtech partners pay Eduwit for that programme; where two or more partners offer it, the highest of their rates (B11.2). A receivable from the counsellor, not a payout | **Confirmed 14 Oct:** the counsellor pays Eduwit at the partner rate, using the highest rate where partners overlap. **Open:** (a) a programme no partner offers but its university does: this prompt uses the highest university rate, flagged; (b) a university no partner offers: the line waits as "needs rate" until the Admin sets one; (c) TDS or other deductions: off until Eduwit's CA confirms; (d) how the amount is collected (deduction, invoice or payment): Eduwit's decision |
| 3 | **Programme page and partner rates: one catalogue** | B2C reads `catalog_programs` (715 rows) | The **shared `catalog` schema** is the single source for both CRMs and Witty. The B2B CRM loads it from the per-partner Excel and Google Sheet files (its Programme Repository), including partner commission per programme. Both CRMs read it through read-only views (B8.9, B17) | **Confirmed 14 Oct:** both CRMs and Witty read a shared catalogue schema. **Open for the B2B developer:** expose the views and the partner-commission columns. Phase 0 puts `catalog` views over the existing `catalog_*` tables, so nothing moves and Witty is unaffected |
| 4 | **Contact details** | Counsellors could correct any Witty field | Counsellors add numbers and emails and set the primary; they never edit or delete an existing one; the Admin can (B8.3). Other profile fields stay editable with history | As instructed; protects intake data and duplicate detection |
| 5 | **Cross-sell** | Interest fields were Witty's | Counsellors change the programme, specialization, university, level or mode with a reason; recorded as a human correction; written through the B2B CRM; never triggers partner routing | **Open:** confirm that a cross-sell change must not send a B2C-held lead back to partner routing (the sticky rule, B4.2) |
| 6 | **Marketing role** | Marketing was the Admin's job | A separate Marketing role and workspace. Marketing **sees everything the Admin sees**, including all leads with full phone numbers and emails, all chats, all analytics and the money views. It **acts only on marketing**: no lead edits, no stage changes, no rates, runs or invoices, no sales WhatsApp templates, no partner routing (B3.1) | **Confirmed 14 Oct:** Marketing can see everything, so full phone numbers and chat transcripts are visible. I have read "everything" as including the money views, which Marketing can see but not change. Say if money should be hidden from Marketing |
| 7 | **Sales WhatsApp templates: Admin only** | Marketing templates existed; no sales template rule | Counsellors open every conversation with an Admin-created, Meta-approved sales template; free text once the student replies, inside the 24-hour window (B8.5). Counsellors cannot submit templates | This is also what Meta's rules require, so the two align. **Open:** confirm that Marketing may **not** create sales templates (the instruction says "Admin can create WhatsApp templates for both"; this prompt gives Marketing the marketing ones only) |
| 8 | **Email: each user's Gmail; the Admin's Gmail for marketing** | An email provider on Eduwit's domain | Sales email: each counsellor's own Gmail by API. Marketing and nurture: the Admin's Gmail, paced inside Gmail's daily allowance (B8.6). System mail from a system sender on `eduwit.in`. Replies arrive in the Admin's Gmail | **Confirmed 14 Oct:** accept Gmail's limits for now. The published allowance is 2,000 messages per mailbox over a rolling 24 hours, and Google's page describes no paid way to raise it. **Open:** nurture at 200,000 a day (B19.1) cannot run from one mailbox. Confirm whether to lower the target, or add sending accounts or a bulk provider later |
| 9 | **2FA using the company email** | 2FA required for the Admin only | Mandatory for every role: a code to the `@eduwit.in` inbox on untrusted devices, including after Continue with Google (B3.2) | **Confirmed 14 Oct:** the email code stays required even after Continue with Google |
| 10 | **Teams: accounts with auto-synced Eduwit email** | Invite-only by email | Google Workspace directory sync lists every `@eduwit.in` user; the Admin assigns roles; suspension in Workspace deactivates in the CRM. Invites remain as the fallback | **Open:** confirm Vikas can grant the CRM's service account domain-wide delegation in the Google Admin console (needed for directory sync and for zero-touch Gmail) |
| 11 | **Real-time sync through the B2B CRM** | B2C wrote its own columns in `student_leads` directly and exchanged events with B2B | B2C connects to Witty and Supabase **through the B2B CRM**, which is always up. Every B2C write to `student_leads` goes through the B2B CRM's write API, with an outbox so counsellors never wait. Events flow both ways within 2 seconds (B17) | **Confirmed 14 Oct.** **Build:** the B2B CRM exposes the write API and the event contract (agreed in Phase 0) |
| 12 | **Allocation engine "as good as LeadSquared or Salesforce"** | Round robin with optional refinements | A rule-based engine with ten logics, working calendars, holidays, leave, capacity, simulation and audit (B7); round robin remains the default | No conflict; a much larger build, placed in Phase 1 |
| 13 | **Nurture "as functional as LeadSquared or Salesforce"** | Journeys, campaigns, segments | The same, raised to that standard: the Nurture page (B9.0), versioned journeys, test mode, overlap analysis, lead-level control, visible suppression. Journeys may also target active-sales leads when the Admin allows | **Open:** confirm that nurture may touch leads in active sales when explicitly allowed |
| 14 | **AI-enabled analytics** | A dashboard builder | Plus natural-language questions, insights feed, anomaly alerts, and role scoping enforced in the query layer (B13.4) | No conflict |
| 15 | **Sales template sharing** | None | Shared library with fork-on-edit: others may use or copy and save their own version; the author's version never changes (B8.6) | As instructed |
| 16 | **Separate UIs, no intermixing** | One app with role-based screens | Three interfaces: Sales app, Marketing workspace, Admin console (B15); the Admin can "view as Sales" | **Open:** confirm the Admin should also be able to work leads as a counsellor ("Admin takes leads" default) using the Sales app |
| 17 | **Follow-up notifications 10 minutes before, with the lead link** | Reminders 10 minutes before | Unchanged, plus the Follow-ups page with the four cards (B8.2) and escalation after 2 hours | No conflict |

**Still open after 14 October:**

- Commission gaps (a) to (d) in row 2.
- Email volume against the 200,000 nurture target (row 8).
- Rows 1, 5, 7, 10, 13 and 16: confirm as written.
- From the 7 October Witty release (not B2C decisions, listed so they are not forgotten): how Witty records a later "don't share my details"; whether the Chatwoot counsellor brief is posted at every hand-off; whether Witty's 3-hour follow-up runs before the 18-hour hand-off; whether chats without an access code become leads.

---

*End of prompt. Claude Code: begin with Phase 0, write `docs/phase0-audit.md`, build the clickable design for all three interfaces, and stop for review.*
