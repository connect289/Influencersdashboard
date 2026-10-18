# Eduwit Influencer Portal — Claude Code Build Prompt

> **How to use this file:** Save it in the repo as `docs/INFLUENCER_PORTAL_SPEC.md`. Start Claude Code in plan mode and say: *"Read docs/INFLUENCER_PORTAL_SPEC.md end to end. Do Phase 0 only, then stop and report."* After that, approve one phase at a time. Everything below the line is written for Claude Code.

---

## 0. Your role and the bar

You are the lead engineer building the **Eduwit Influencer Portal**. It is a production-grade web app that runs Eduwit's entire influencer and creator program in one place:

- creator discovery and outreach
- campaigns and applications
- deals with fully customisable compensation
- contracts with in-portal negotiation and OTP click-sign
- creator briefs
- the deliverable and content-approval pipeline
- lead attribution and a live lead pipeline for creators
- the earnings ledger, TDS and payouts
- dashboards, messaging and notifications
- scorecards and compliance

**The bar is industry-grade, not a prototype.** That means:

- typed end to end
- Row Level Security on every table
- tested business logic
- audit trails
- empty, loading and error states on every screen
- mobile-first creator UX
- no placeholder features

If a requirement here is ambiguous or conflicts with what you find in the existing codebase or database, **stop and ask**. Do not guess on money, attribution, or data visibility.

**Goal:** Eduwit and its creators should never have to leave the portal to negotiate, brief, approve, track, or get paid. No email or WhatsApp back-and-forth for core workflows.

---

## 1. Business context you must understand

**Eduwit Learning Services** is a GST-registered EdTech lead-generation marketplace in Ghaziabad (Delhi NCR).

- It is an authorised admission partner for UGC-DEB entitled universities offering online and ODL programmes (MBA, MCA, BBA, etc.).
- Leads come from Meta/Google ads, organic channels, the website, and **influencers/creators**.
- Leads are qualified by **Witty**, an AI WhatsApp assistant, and then allocated to partner edtechs or the in-house team.
- Eduwit earns a **commission per enrollment** from partners.

**The influencer portal is one of six separate but integrated products:**

1. **Witty**: the WhatsApp AI qualification agent. It runs on n8n and writes leads on every chat turn.
2. **B2B CRM**: allocates leads to partner edtech CRMs and syncs their status in real time.
3. **B2C CRM**: Eduwit's in-house sales and nurture CRM.
4. **Website**
5. **Website AI agent**
6. **Influencer Portal**: this build.

**Ground truths:**

- All six products share **one Supabase project** (Mumbai region, project ref `xlseqwgyjuqhktrguhyc`).
- The table `student_leads` is the **master lead table**. All intake goes through the function `lead_intake()`.
- Witty's tables are prefixed `w2_*`. The shared programme catalogue tables are prefixed `catalog_*`.
- Existing apps are **Next.js 15 on Vercel** with Supabase Auth.
- WhatsApp for staff runs through **Chatwoot** (`chat.eduwit.in`). Automations run on **n8n** (`n8n.eduwit.in`).
- **Click-to-WhatsApp entries count as influencer leads, not paid Meta leads.**
- Witty uses a **soft access gate**: every chat becomes a lead, and a creator code is used **only for attribution**. Never block a student for lacking a code.
- Keep the portal a **separate app** with its own deployment. It integrates only through the shared database (its own tables plus controlled reads), APIs, and webhooks.

---

## 2. Non-negotiable engineering rules

1. **Never break other products.**
   - All new tables use the `inf_` prefix (or a dedicated `influencer` schema if you recommend it; justify the choice in Phase 0).
   - Migrations are **additive only**. Never drop, rename, or change the type of any existing column in `student_leads`, `w2_*`, `catalog_*`, or CRM tables.
   - Any change to a shared object (a trigger on `student_leads`, or a new column) must be listed in Phase 0, justified, and approved before it is written.
2. **Phone and email are never exposed to creators.**
   - Creators and agency users must never be able to read a student's phone number or email address: not via the UI, the API, exports, Realtime, logs, or error messages.
   - Masking is enforced **in the database layer**, through `SECURITY DEFINER` functions or views that return masked values. UI masking alone is not enough.
   - Creators never get direct SELECT on `student_leads`.
3. **RLS on every `inf_` table**, with policies per role. Write automated tests (pgTAP or SQL-based) that prove each role can only see what it should.
4. **Money**
   - Store money as integer **paise** (`bigint`). Never use floats.
   - Rounding happens once, at the final line-item level, using banker's rounding. Document it.
   - Display in Indian format: ₹1,23,456.00.
5. **Time:** store in UTC (`timestamptz`) and display in **IST (Asia/Kolkata)**. All period logic (slabs, windows, months, quarters) runs in IST, with Indian financial year boundaries (1 April to 31 March).
6. **Immutability**
   - Signed contracts, ledger entries, signature records, and audit logs are append-only.
   - Corrections are new reversing entries, never updates.
7. **Audit log:** every create, update, or delete on business entities, and every status transition, writes to `inf_audit_log` (actor, role, entity, before/after JSON diff, IP, user agent, timestamp).
8. **Secrets** stay in env vars only. PAN and bank account numbers are encrypted at rest (Supabase Vault or pgsodium) and shown masked except to the Finance role.
9. **Everything that the business might change is configuration, not code.** This includes deal terms, milestone triggers, TDS rates, the attribution window, stage mappings, notification templates, clause library, tiers, and banned-claims list. Section 21 lists the settings.
10. **Idempotency:** every accrual, notification, and webhook handler must be idempotent, keyed on a deterministic event key.
11. **TypeScript strict**, no `any`. Validate all input with zod, on both server and client. Generate Supabase types.

---

## 3. Tech stack

Use this stack unless Phase 0 finds a strong reason otherwise.

- **App:** Next.js 15 (App Router, Server Components, Server Actions and route handlers), TypeScript strict, deployed on Vercel. Installable **PWA** for creators.
- **Data and backend:** Supabase Postgres, Auth, Storage, Realtime, Edge Functions, `pg_cron` for scheduled jobs, and Vault for encryption.
- **UI:**
  - Tailwind CSS and shadcn/ui (Radix)
  - TanStack Table for data grids (server-side pagination, sort, filter, column visibility, saved views)
  - dnd-kit for kanban
  - Recharts for charts
  - react-hook-form with zod for forms
  - Tiptap for the contract and brief editors (variables, conditional blocks, suggestion/track-changes mode)
- **Documents:** server-side PDF generation for contracts, signature certificates, statements, and payout advice (`@react-pdf/renderer`, or headless Chromium if fidelity needs it). Store PDFs in Supabase Storage.
- **Uploads:** Supabase Storage with **resumable (TUS) uploads** for large videos, with configurable size and type limits. Use signed URLs only, and never public buckets for private material.
- **Notifications:** a provider-agnostic adapter layer with three channels:
  - **Email:** SMTP or a transactional provider, chosen in Phase 0
  - **WhatsApp:** Cloud API template messages, with the number and provider chosen in Phase 0
  - **In-app:** a Realtime-backed notification centre
- **i18n:** `next-intl`, with English as the default and every string externalised so Hindi can be added without refactoring.
- **Quality:** Vitest (unit tests, mandatory for compensation, attribution, and ledger logic), Playwright (end-to-end tests for critical journeys), pgTAP or SQL tests for RLS, ESLint and Prettier, and a CI workflow.
- **Observability:** Sentry (or equivalent), structured logs, and a `/api/health` endpoint reporting database, storage, and queue status, which the future oversight system will poll.

---

## 4. Users, roles and permissions

There are two portals in one app, behind separate route groups and layouts:

- **Admin Console** at `/admin/*`
- **Creator Portal** at `/creator/*`

**Internal roles:**

| Role | Access |
|---|---|
| **Super Admin** | Everything, including settings, role management, and deleting drafts |
| **Influencer Manager** | Creators, prospects, campaigns, deals, contracts (except countersign unless also Signatory), briefs, deliverables, messaging. Sees lead pipelines and analytics. |
| **Content Reviewer** | Briefs and deliverables (review, comment, approve or reject), compliance checks. No finance. |
| **Finance** | Ledger, payouts, TDS, invoices, KYC (unmasked PAN and bank details), reconciliation. Read-only elsewhere. |
| **Authorised Signatory** | Can countersign contracts on behalf of Eduwit. This is a flag that can be combined with any role. |
| **Viewer / Analyst** | Read-only dashboards and reports |

**External roles:**

| Role | Access |
|---|---|
| **Creator** | Own profile, KYC, campaigns (open and invited), applications, deals, contracts, briefs, deliverables, attributed leads (masked), earnings, payouts, messages |
| **Agency / Manager** | Manages one or more linked creators. Each creator grants permissions individually: view only, act on deliverables, negotiate and sign contracts, view earnings. Payout bank details always belong to the creator unless the contract names the agency as payee. |

**Requirements:**

- Build a **permission matrix** in code as a single source of truth, used by both RLS policy generation and UI guards. Hide UI elements a role cannot use; never just disable them.
- **Staff auth:** Google sign-in or email and password, with an **email-code 2FA that stays required even after Google sign-in**, matching the B2C CRM decision.
- **Creator auth:** email OTP or Google sign-in, plus optional phone OTP. Creators join by invite link or self sign-up (Section 13).

---

## 5. Data model

Design the full schema in Phase 0 and present it as an ERD (Mermaid) for approval before writing migrations. The minimum set of entities is below. Add what's needed and don't drop any.

**Identity and profiles**
- `inf_staff_profiles`: links to `auth.users`; holds roles and the signatory flag.
- `inf_creators`
  - Identity: legal name, display name, handle, email, phone, city, state, languages, niches, bio, avatar
  - Status: `prospect | invited | onboarding | active | paused | blocked | archived`
  - Tier, owner (the staff member responsible), source, tags
- `inf_creator_platforms`
  - Platform (Instagram, YouTube, Facebook, LinkedIn, X, Telegram, Moj/Josh, other), URL, handle
  - Followers, average views, engagement rate
  - Audience demographics as JSON: age, gender, top cities and states
  - Last updated, and a source field (`manual | api`)
- `inf_creator_kyc`
  - PAN (encrypted), name on PAN, GSTIN (optional), GST registration status
  - Bank account (encrypted), IFSC, account holder name, cancelled-cheque or proof file
  - Verification status, with who verified it and when
- `inf_creator_rate_cards`: per platform and format, with a suggested price
- `inf_creator_portfolio`: past work links and media
- `inf_agencies`, `inf_agency_members`, `inf_agency_creator_links` (holding the permission grants)

**Prospecting (admin CRM for creators)**
- `inf_outreach_activities`: calls, DMs, emails, notes, with outcome and the next follow-up date
- `inf_tasks`: assignee, due date, related entity, status

**Campaigns**
- `inf_campaigns`
  - Name, objective, description, status (`draft | open | invite_only | active | paused | completed | archived`)
  - Start and end dates, budget, slots, visibility
  - Eligibility rules as JSON: minimum followers, platforms, niches, languages, geography
  - Default deal preset, default brief template, default contract template
- `inf_campaign_programmes`: links to `catalog_*` programme IDs
- `inf_campaign_applications`
  - Creator, pitch, proposed deal type and rates, sample links
  - Status (`submitted | shortlisted | countered | accepted | rejected | withdrawn`), with a negotiation thread
- `inf_campaign_invites`

**Deals and compensation** (see Section 6)
- `inf_deals`
  - Creator, campaign (nullable, so always-on deals are possible), status (`draft | proposed | negotiating | agreed | active | completed | terminated | expired`)
  - Start and end dates, a compensation config version, and the governing contract
- `inf_deal_versions`: an immutable snapshot of the full compensation config for each version. Any change after signing requires an amendment.
- Structured child tables, or a validated JSONB config with zod and a generated SQL check, to be decided in Phase 0:
  - fixed components
  - payment milestones
  - commission rules and slabs
  - bonus rules
  - penalty rules
  - additional fees
  - caps
  - recoupment settings

**Contracts**
- `inf_clause_library`
  - Category, title, body (rich text with variables), version
  - Flags: required, negotiable, locked
  - Applicable deal types and campaign types
- `inf_contract_templates`: ordered clause references, header and footer, variables, conditional blocks
- `inf_contracts`
  - Deal, template, status (Section 8), current version, parties, payee
  - Effective and expiry dates, and `parent_contract_id` for amendments
- `inf_contract_versions`: immutable rendered content (HTML plus a canonical JSON), a SHA-256 hash, and who created it
- `inf_contract_comments`: clause-anchored threads
- `inf_contract_change_requests`: proposed edits to a negotiable clause, with status `pending | accepted | rejected | countered`
- `inf_signatures`
  - Signer, role, contract version, document hash, typed name, consent text shown
  - OTP channel and verification ID, IP, user agent, timestamp, geo (optional)
  - Append-only

**Briefs**
- `inf_brief_templates`
- `inf_briefs`: one per deal or campaign, with a version
- `inf_brief_acknowledgements`
- `inf_brief_questions`: a Q&A thread

**Deliverables and content**
- `inf_deliverables`
  - Deal, brief, type (reel, story, post, YouTube video, short, live, carousel, blog, other), platform
  - Specs (duration, aspect ratio, language, count), due dates per stage
  - Revision limit, status (Section 10), linked fixed-fee milestone, tracking link
- `inf_deliverable_submissions`: concept, script, draft, or final; file or text; version number; creator note
- `inf_review_comments`: on a submission, with an optional `video_timestamp_ms` and optional image region coordinates; resolved flag
- `inf_published_posts`
  - Live URL, date posted, disclosure check
  - Verification status, with who verified it and when
- `inf_post_metric_snapshots`: views, reach, likes, comments, shares, saves, clicks, watch time; source `manual | screenshot | api`; screenshot file; captured at

**Attribution and leads**
- `inf_tracking_links`
  - Code (unique and human-friendly, e.g. `RAHUL-MBA-07`), creator, deal, deliverable, programme (nullable)
  - Destination type (`whatsapp_witty | website_landing | custom_url`), UTM params, active flag
- `inf_link_clicks`: hashed IP, user agent, referrer, UTM, device, timestamp. Never store raw IPs longer than needed.
- `inf_lead_attributions`
  - `student_lead_id` (FK to `student_leads`), creator, deal, deliverable, link, code
  - Touch type (`first | last | assisted`)
  - Status (`credited | duplicate | outside_window | self_referral | fraud_suspected | manually_rejected | manually_credited`), reason, decided by, and decision time
- `inf_lead_stage_events`: a mirror of lead stage changes relevant to creators, mapped to the creator-facing stage (Section 9)
- `inf_stage_mappings`: configurable mapping from CRM statuses to creator-facing stages

**Money**
- `inf_ledger_entries`
  - Append-only. Fields: creator, deal, type, amount in paise, direction, status, event key (unique), source reference, period, notes.
  - Types: `fixed_fee`, `milestone`, `commission`, `bonus`, `usage_fee`, `exclusivity_fee`, `penalty`, `clawback`, `tds`, `gst`, `adjustment`, `payout`, `reversal`
- `inf_payout_batches`, `inf_payouts`
  - Creator, gross, TDS, GST, net, and the entries included
  - Status (`draft | approved | processing | paid | failed | cancelled`), UTR, paid date, payment advice PDF
- `inf_invoices`: creator-uploaded GST invoices, or system-generated payout statements; number, date, amounts, file, status
- `inf_tds_records`: section, rate, base, amount, quarter, FY, Form 16A file
- `inf_eduwit_commission_receipts`: per enrollment, whether Eduwit has received its partner commission and how much. This drives commission confirmation. Source it from the B2B CRM if the data exists, otherwise use manual entry by Finance. Confirm which in Phase 0.

**Engagement and ops**
- `inf_threads`, `inf_messages`: entity-linked threads with attachments, read receipts, @mentions
- `inf_notifications`, `inf_notification_preferences`, `inf_notification_templates`
- `inf_announcements`: broadcasts to all creators or to a segment
- `inf_tiers`, `inf_scorecards`: periodic snapshots
- `inf_compliance_checks`, `inf_banned_claims`
- `inf_settings`: typed key-value with a JSON schema per key
- `inf_audit_log`
- `inf_webhook_endpoints`, `inf_webhook_deliveries`: outbound events
- `inf_jobs`: or use `pg_cron` plus a queue table, for scheduled and async work with retries

---

## 6. Compensation engine — fully customisable

This is the most important module. It must support **every combination** of commission only, fixed plus commission, and fixed only, plus anything in between, **without code changes**.

### 6.1 Deal composition

A deal's compensation is a list of **components**. Each deal can have zero or more of each type.

**A. Fixed fee components**
- Amount (paise), and a basis: `lump_sum | per_deliverable | per_unit (e.g. per reel) | retainer (monthly or weekly, for N periods)`.
- A **payment milestone schedule**: any number of milestones. Each milestone has:
  - A label, and either a percentage of the component or a fixed amount. The total must reconcile to 100% or to the full amount, with a validation error otherwise.
  - A trigger: `on_contract_signed | on_brief_acknowledged | on_concept_approved | on_draft_approved | on_deliverable_live | after_n_days_live | on_metric_threshold (views/reach/leads) | on_campaign_end | on_specific_date | manual_release`.
  - Optionally, a link to a specific deliverable.
  - Due offset in days after the trigger fires, and payment terms (e.g. Net 7).
  - A forfeit or partial-payment rule if the deliverable is cancelled.
- **Advance payments** are just milestones with an early trigger.

**B. Commission rules**
- Scope: all programmes, specific programmes, a university, a level (UG, PG, diploma), or specific tracking links or deliverables.
- **Basis**, one of:
  - Flat ₹ per enrollment.
  - % of the Eduwit commission received. Whether the base is **gross (GST-inclusive) or net of GST** is a per-rule setting. Eduwit's commission is GST-inclusive.
  - % of programme fee.
  - Flat ₹ per qualified lead (CPL).
  - Flat ₹ per lead (any non-junk, non-duplicate).
  - Flat ₹ per application.
- **Slabs**: count-based tiers within a period (deal lifetime, calendar month, campaign). Each slab can be **marginal** (only units above the threshold get the higher rate) or **retroactive** (all units get the new rate once the threshold is crossed, with automatic top-up entries).
- Caps: per lead, per period, per deal lifetime. Also floors and minimum guarantees, e.g. "₹X minimum per month, settled against commission."
- **Recoupment against fixed fees**: `none | full | partial %`. Example: commission accrues to the creator only after cumulative commission exceeds the recoupable advance.
- Effective dates, so rules can change mid-deal through an amendment.
- Accrual and confirmation:
  - **Accrue** when the trigger event happens (e.g. enrolled).
  - **Confirm** only when the configured condition is met: `on_eduwit_commission_received | after_hold_days | immediate`.
  - A refund or clawback window in days. If the enrollment is cancelled or refunded inside the window, auto-generate a clawback entry.

**C. Bonus rules**
- Conditions: enrollments ≥ X, qualified leads ≥ X, views ≥ X, all deliverables on time, or rank ≤ N on a leaderboard, all within a window. Conditions can be combined with AND/OR.
- Amount: fixed, % of fixed fee, or % of commission earned. Bonuses can be one-time or repeating.

**D. Penalty and deduction rules**
- Late delivery as ₹ per day or % per day, with a cap.
- Missed deliverable: forfeit the linked milestone, or apply a fixed penalty.
- Disclosure non-compliance penalty.
- Clawback on contract breach.
- Every penalty is **proposed** by the system and must be **approved by a human** (Influencer Manager or Super Admin) before it posts to the ledger.

**E. Additional fees**
- Usage rights (platforms and duration), exclusivity (category and duration), whitelisting/boosting rights, and travel or production reimbursements.

**F. Non-cash**
- Optionally record barter or in-kind value (e.g. a free course) for ROI accounting. This never goes into the payout.

### 6.2 Presets and simulator

- Ship **presets** for "Commission only", "Fixed + Commission", and "Fixed only". Each preset is just a pre-filled component set and stays editable. Admins can save new presets.
- A deal builder UI with a live **earnings simulator**:
  - Enter scenarios (e.g. "20 leads, 3 enrollments, 50k views, delivered 2 days late") and see a per-component breakdown, TDS, and net payout.
  - Show the **effective cost per enrollment to Eduwit** and the **projected Eduwit margin**, using catalogue commission data.
- Creators see a read-only simulator on their own deal, which **never shows Eduwit margin or the Eduwit commission amounts**, only their own earnings.

### 6.3 Engine implementation

- Write it as a **pure TypeScript module** (`/lib/compensation`) with no I/O. Input is the deal config plus an event stream; output is the ledger entries to post. It must be deterministic and fully unit-tested.
- Minimum test coverage: every basis type, both slab modes, recoupment, caps and floors, milestones per trigger, clawbacks inside and outside the window, retroactive top-ups, amendments mid-period, rounding, and the exact presets above.
- A server-side runner subscribes to domain events (deliverable status changes, lead stage events, commission receipts, scheduled time triggers) and posts ledger entries idempotently, keyed on `deal_version + rule_id + subject_id + event_type`.
- A **recompute/dry-run** tool for admins, which shows what would change if a deal is amended, before applying it.

---

## 7. Creator lifecycle and admin creator CRM

**Pipeline:** Prospect → Contacted → Negotiating → Contracted → Onboarding → Active → Paused → Dormant (auto-flagged after N days with no activity) → Archived. Blocked is a separate flag.

**Admin capabilities:**
- Kanban and table views with saved filters (platform, followers range, niche, language, city or state, tier, owner, status, deal type, performance).
- Creator 360° page:
  - Profile, platforms and stats
  - Deals, contracts, briefs and deliverables
  - Leads (here unmasked for authorised staff, per staff role), earnings and ledger
  - Scorecard, messages, outreach timeline, tasks, documents, audit history
- Bulk CSV import of prospects with validation, de-duplication by handle, phone and email, and an error report. Bulk invite, tag, and assign owner.
- Outreach log, follow-up reminders, and task assignment. "Overdue follow-ups" widget.
- **Auto-generated media kit** (a shareable PDF and a web page) from profile data, for internal use or the creator's own use.

---

## 8. Contracts — builder, negotiation, OTP click-sign

### 8.1 Clause library and templates
- Clause library CRUD with categories:
  - Parties and definitions
  - Scope and deliverables
  - Timelines
  - Compensation and payment terms
  - Taxes (TDS/GST)
  - Content approval and revisions
  - ASCI disclosure and advertising standards
  - Claims and accuracy (only approved programme claims)
  - Usage rights and IP
  - Exclusivity and non-compete (including other edtechs)
  - Confidentiality
  - Data protection (DPDP)
  - Conduct and morality
  - Penalties and clawback
  - Termination
  - Force majeure
  - Indemnity and limitation of liability
  - Dispute resolution and jurisdiction
  - Notices
  - Entire agreement
- Clause flags: `required`, `negotiable`, `locked`, applicable deal types. Clauses are versioned; editing a clause creates a new version and old contracts keep their version.
- Template editor (Tiptap):
  - Insert clauses from the library.
  - **Variables**: `{{creator.legal_name}}`, `{{creator.pan_masked}}`, `{{deal.start_date}}`, `{{deal.fixed_fee_total}}`, `{{deal.milestone_table}}`, `{{deal.commission_table}}`, `{{deliverables_table}}`, `{{eduwit.signatory_name}}`, and so on. Provide a variable picker.
  - **Conditional blocks**, e.g. `{{#if deal.has_commission}}…{{/if}}`, so one template adapts to any deal type.
- **Compensation sections are generated from the deal config.** Never retype amounts by hand; the deal is the source of truth for every number in the contract.
- Seed the library with professionally structured **draft** clauses, each clearly marked *"DRAFT — requires legal review before use"*, and a setting that blocks sending any contract containing unreviewed clauses until a Super Admin marks them reviewed.

### 8.2 Contract states
Draft → Sent → In negotiation → Ready to sign → Signed by creator → Countersigned (Active) → Completed | Terminated | Expired. Also Void and Superseded (for amendments).

### 8.3 In-portal negotiation
- The creator reviews the contract in the portal on mobile or desktop, and can:
  - comment on any clause
  - propose edits **only on negotiable clauses** (suggestion mode)
  - propose changes to compensation terms through a structured counter-offer form, not free text. This creates a proposed deal version.
- Admin accepts, rejects, or counters each change request. Every round creates a new contract version, with a visual **diff between versions**.
- A deadline and reminder schedule for pending negotiations.

### 8.4 OTP click-sign
- The signer reviews the final version and must scroll through, or explicitly confirm, each section. They then:
  - type their full legal name
  - tick the consent checkbox (the consent text is versioned and stored)
  - receive an OTP on the channel(s) set in settings (email, phone/WhatsApp, or both)
  - enter the OTP to sign
- On signing, capture: signer ID, role, contract version ID, **SHA-256 hash of the exact rendered document**, typed name, consent text version, OTP channel and verification reference, IP, user agent, and timestamp in UTC and IST.
- After the creator signs, the **Authorised Signatory** countersigns through the same flow.
- Generate the **final PDF** with a **signature certificate page** (all signature records and the document hash). Store it immutably and send a copy to all parties automatically.
- Re-verify the document hash on every download. If the version changed after signing, the contract is invalid and the system must flag it.
- OTP rules: 6 digits, 10-minute expiry, a maximum of 5 attempts, rate-limited resend, logged.
- **Amendments** are new contracts linked to the parent. Renewals clone the deal and contract with edits. Expiry reminders go out at 30, 15, and 7 days.
- Show a note in settings that stamp duty and enforceability depend on the state and contract type, and should be confirmed with counsel. Keep a nullable `stamp_duty_reference` field on contracts.

---

## 9. Attribution and lead pipeline

### 9.1 Tracking
- Every creator, deal, deliverable and (optionally) programme combination gets its own **tracking code and link**.
- Link types:
  - **Witty deep link**: `https://wa.me/<WITTY_NUMBER>?text=<prefilled message containing the code>`. The message text is configurable per campaign. Witty must parse the code and store it on the lead. In Phase 0, find out how and where Witty currently stores referral or source codes on `student_leads`, and propose the exact contract (column and format) for the Witty team. Do not modify Witty yourself.
  - **Website landing page**: `https://<website>/c/<creator-handle>?code=…` plus UTMs. The website is a separate product; expose a public read-only API that returns a creator's public landing data (name, photo, featured programmes, code) so the website can render co-branded pages.
  - **Custom URL** with appended UTMs.
- Short links come from a redirect route `/r/<code>` that logs the click and redirects. Generate a QR code (PNG and SVG download) for every link.
- Creators can generate links themselves for any programme in the campaigns they are part of.

### 9.2 Attribution rules (all configurable)
- **Attribution window**: N days from click or code use (default 90; setting).
- **Model**: first touch, last touch, or first touch with assisted credit recorded. Set globally, with optional overrides per campaign.
- **Duplicate rule**: if the phone number already existed in `student_leads` before the creator touch, mark it `duplicate` and give no credit. Show the reason to the creator without revealing any PII.
- **Self-referral**: the lead's phone or email matches the creator's own KYC or contact details, or a known family-linked number if flagged. Status `self_referral`.
- **Fraud signals** go to admin review, not automatic rejection:
  - velocity spikes
  - many leads from the same device or IP hash
  - leads that never respond to Witty
  - bursts outside normal hours
  - abnormally high junk rate
- **Manual override** by an admin, with a mandatory reason and an audit log entry.
- **Implementation:** prefer an `AFTER INSERT OR UPDATE` trigger on `student_leads` (or a hook from `lead_intake()`) that calls `inf_attribute_lead(lead_id)`. Choose the least invasive option after reading the existing function, and get approval first. Attribution must also be **re-runnable** for backfill.

### 9.3 Creator-facing lead pipeline
- **Visibility rule (fixed):** creators see **all lead information except phone number and email, which are always masked** (e.g. `98XXXXXX21`, `r****@gmail.com`).
  - Expose this only through a `SECURITY DEFINER` function or view (e.g. `inf_creator_leads(creator_id)`) that returns only leads attributed to that creator, with masked phone and email.
  - In Phase 0, list every `student_leads` column and propose the exact whitelist of fields shown to creators. Internal-only fields (e.g. internal notes, partner commission amounts, partner names if confidential, staff IDs) must be confirmed with the owner before exposure.
  - Exports follow the same masking.
- **Creator-facing stages** are mapped from CRM data via `inf_stage_mappings`:
  - New → Qualifying (Witty) → Qualified → Allocated → In counselling → Applied → **Enrolled** | Lost | Duplicate | Junk | Not attributed
  - Each terminal state shows a reason category.
- **Views:**
  - **Kanban** by stage.
  - **Table** with filters: campaign, deal, deliverable, link, programme, stage, HOT/WARM/COLD, city or state, date range. Includes saved views.
  - **Lead detail drawer** with a full stage timeline, source content piece, programme of interest, days in each stage, and earning status for that lead (pending, accrued, confirmed, paid, clawed back).
- **Realtime** updates via Supabase Realtime on the creator-safe projection only, never on raw tables.
- Admin and staff see the same pipeline across all creators, with full details per their role.

### 9.4 Stage sync
In Phase 0, find out how lead status flows today: Witty and B2C fields on `student_leads`, B2B partner sync tables, and so on. Then design the **least coupled** way to populate `inf_lead_stage_events`: database triggers, a sync job, or webhooks from the CRMs. The portal must never write to CRM-owned fields.

---

## 10. Briefs and deliverables

### 10.1 Brief builder
- Template-based with Tiptap. Fields:
  - Campaign objective, programme(s) (pulled live from `catalog_*`), target audience, key messages
  - **Approved claims** (pulled from catalogue facts: fees, duration, approvals and accreditations, eligibility)
  - **Banned claims** (from `inf_banned_claims`), mandatory disclosures (ASCI)
  - Do's and don'ts, tone, language(s)
  - Deliverables table (type, platform, count, duration, aspect ratio, due dates)
  - Reference links and moodboard (images and videos), brand assets (logos, fonts, b-roll), hashtags, mentions
  - CTA with **auto-inserted tracking link, code and QR** per deliverable, and FAQs
- Versioned. The creator must **acknowledge** the brief, which is a timestamped event and can trigger a milestone. There is a Q&A thread attached to the brief.
- Each brief links to its deal and contract. Generating a deal from a campaign auto-generates the brief from the campaign template.

### 10.2 Deliverable workflow (kanban plus list)
- States: Not started → Brief acknowledged → Concept/script submitted → Concept changes requested → Concept approved → Draft submitted → Draft changes requested → Draft approved → Scheduled → **Live** → Live verified → Metrics submitted → Completed. Also Cancelled and Overdue (a computed flag).
- Each stage can be switched on or off per deliverable. Some deliverables skip the concept stage, for example.
- **Submissions:** text (script and caption), files (video, image, PDF) via resumable upload, or links. Every submission is versioned.
- **Review tools:**
  - A video player with **timestamped comments**. Clicking a comment seeks to that time.
  - Image annotations (point or region).
  - Resolve and reopen comments.
  - Caption checks: an automated scan against banned claims and a disclosure check (the `#ad`/`#collab`/"paid partnership" presence rule, which is configurable).
- **Revision limit** per contract. Further revisions need admin approval and can carry a fee.
- **Go-live:** the creator submits the live URL and posting date.
  - The system validates the URL format per platform and attempts oEmbed or preview where available (e.g. YouTube).
  - A reviewer then verifies that the post is live, the disclosure is present, and the content matches the approved version.
- **Metrics:** the creator submits metrics with insight screenshots at configured checkpoints (e.g. 24 hours, 7 days, 30 days). Build `source` fields so platform APIs can replace manual entry later without schema changes.
- Due-date reminders and overdue escalations. Late delivery proposes penalty entries per the deal (Section 6.1 D).

---

## 11. Payments, ledger, TDS and payouts

- **Unified ledger per creator**, built from engine output plus manual adjustments (adjustments need Finance or Super Admin, with a reason).
- **Entry lifecycle:** Accrued → Confirmed → Payable (on or after the due date) → In payout batch → Paid. Also Reversed, On hold, and Clawed back.
- **TDS**
  - Configurable table of section, rate, threshold (per transaction and aggregate per FY), and a higher rate when PAN is missing.
  - Applicable per component type, since different income types may fall under different sections.
  - Ship sensible defaults clearly marked **"confirm with CA"**, editable by Finance only.
  - Track FY aggregates per creator for threshold logic.
  - Generate quarterly TDS summaries. Finance uploads Form 16A files, and creators can download them.
- **GST**
  - If the creator is GST-registered (GSTIN verified), GST is added on top per settings, and the creator must upload a valid tax invoice before payout. The system validates the GSTIN format and invoice amounts against the payout.
  - If the creator is not registered, generate a payout statement instead.
- **Payout batches**
  - Finance selects payable entries by filter, sees a gross, TDS, GST and net summary, and approves (optionally with two-person approval as a setting).
  - Export a **bank bulk-upload file** in a configurable column format, then mark payouts as paid with a UTR, individually or by CSV upload.
  - Generate a **payment advice PDF** per payout and notify the creator.
- **No automated money movement in v1.** Design a payment-provider adapter interface so a payout API (e.g. RazorpayX) can be added later.
- **Reconciliation:** match commission-based entries to `inf_eduwit_commission_receipts`, and flag accrued commission where Eduwit hasn't been paid after N days.
- **Creator earnings view:**
  - Totals for lifetime, this FY, this month, pending, confirmed, payable, and paid.
  - Next expected payout, per-deal breakdown, per-lead commission status, statements (monthly PDF), invoices, and TDS certificates.

---

## 12. Dashboards and analytics

Every metric needs a written definition in a `METRICS.md` and a tooltip in the UI. All dashboards support date range presets (today, 7, 30, or 90 days, this month, last month, this FY, custom), comparison to the previous period, drill-down to the underlying records, and CSV export (masked for creators).

**Creator home dashboard**
- Earnings cards: total earned, pending, payable, paid, next payout date
- Fixed fee: received vs remaining milestones
- Action centre: contracts to sign, briefs to acknowledge, deliverables due or overdue, changes requested, metrics due, invoice needed, KYC incomplete
- Lead funnel (clicks → leads → qualified → allocated → applied → enrolled) with conversion rates
- Leads over time, top content pieces by leads and enrollments, programme breakdown, platform breakdown
- Active campaigns and deals, tier status and progress toward the next tier or bonus, leaderboard position (if opted in)
- Announcements

**Admin overview**
- Program health: active creators, new this period, dormant, and the pipeline by stage
- **Spend:** committed, accrued, paid, by deal model (commission only vs hybrid vs fixed only), by campaign, by creator. Budget vs actual per campaign.
- **Unit economics:**
  - Cost per lead, cost per qualified lead, and **cost per enrollment**
  - **Eduwit revenue from creator leads**, **net ROI**, and ROAS
  - Each broken down by creator, campaign, platform, content type, programme, and **deal model**, so you can see which model performs best
- Lead quality: qualification rate, junk %, duplicate %, enrollment rate per creator
- Operations: overdue deliverables, pending reviews, pending negotiations, contracts expiring, payouts due, KYC pending, fraud flags
- Leaderboards: top creators by enrollments, ROI, and on-time delivery

**Campaign dashboard:** all the above, scoped to one campaign, with a per-creator comparison table.

**Creator 360° analytics:** trends, content performance, and lead-quality history for one creator.

**Finance dashboard:** liabilities, payouts by period, TDS by quarter, reconciliation status.

Use materialised views or summary tables refreshed by `pg_cron` for heavy aggregates. Dashboards must load in under 2 seconds at p95 at 100k leads and 1,000 creators.

---

## 13. Campaigns and marketplace

- **Campaign builder:** objective, programmes, budget, slots, dates, eligibility, deal preset(s) offered, brief template, contract template, deliverable template, visibility (`open | invite_only | both`).
- **Open campaigns:** eligible creators see them in a "Campaigns" marketplace (cards with programme, deliverables, compensation summary, deadline, slots left) and apply with a pitch, preferred deal type, proposed rates, and samples.
- **Invite-only campaigns:** admins invite specific creators, and invitees can accept, decline, or counter.
- **Application review:**
  - Shortlist, accept, reject (with a reason template), or counter.
  - Negotiation happens in a thread plus a structured counter-offer.
  - On acceptance the system **auto-generates** the deal (from the preset and negotiated terms), the contract (from the template), the brief, and the deliverables, then notifies the creator.
- **Creator self sign-up:** a public sign-up page leading to an onboarding wizard (profile, platforms, KYC, agreement to platform terms, and a compliance mini-course with a quiz). Then admin approval, with configurable auto-approval rules.

---

## 14. Communication and notifications

- **Threads attached to any entity**: campaign, application, deal, contract clause, brief, deliverable, payout, lead (staff only), and general creator-to-Eduwit support.
  - Attachments, @mentions for staff, read receipts, unread counts, and full-text search.
- **Notification centre** (in-app, Realtime) plus **email** and **WhatsApp** templates, with per-user channel preferences. Some events are mandatory and cannot be turned off, such as contract and payout events.
- **Event catalogue** (minimum):
  - invite received
  - application status changed
  - contract sent, changed, countered, ready to sign, signed, countersigned, expiring
  - brief published or updated
  - deliverable due, overdue, changes requested, approved
  - go-live verified, metrics due
  - lead attributed, lead enrolled (**"₹X earned"**), lead clawed back
  - milestone payable, payout processed (with UTR)
  - KYC action needed
  - announcement
  - fraud flag (staff), negotiation pending (staff), review pending (staff)
- Template editor with variables, preview, and test send.
- **Announcements** to all creators or a segment (tier, campaign, platform, language), with scheduling.
- **Daily or weekly digest** email or WhatsApp for creators (leads, earnings, due items) and for staff (operations summary).

---

## 15. Scorecards, tiers and recommendations

- **Periodic scorecard** per creator (monthly, plus on demand):
  - Delivery reliability: on-time %, average revisions, cancellations
  - Content performance: views and engagement vs their own baseline
  - Lead quality: qualification rate, junk %, duplicate %, enrollment rate
  - Economics: cost per enrollment, ROI
  - Compliance: disclosure misses, claim violations
- Weighted composite score (weights in settings).
- **Tiers** (e.g. Bronze, Silver, Gold, Platinum) with configurable entry rules and benefits. Benefits can include a default commission uplift for new deals, priority campaign access, and a faster payout cycle.
- **Rules-based recommendations** at deal renewal. Examples: "high conversion, so offer Hybrid with a higher commission"; "low conversion, high reach, so Fixed only for awareness campaigns"; "repeated delays, so require concept approval."
- Design the interface so AI recommendations can be plugged in later.

---

## 16. Compliance and risk

- ASCI influencer disclosure checklist per deliverable, required before approval.
- Approved-claims library sourced from the catalogue, and a banned-claims list (configurable) with automatic scanning of scripts and captions. Matches block approval unless a reviewer overrides with a reason.
- KYC verification workflow, with payouts blocked until KYC is verified (setting).
- Contract compliance tracker per creator: obligations met or missed.
- Platform terms and privacy policy acceptance for creators, versioned and re-accepted on change.
- **DPDP:**
  - purpose-limited display of student data (masked contact details)
  - creator data export and deletion request workflow (legal retention for financial records is respected)
  - consent records for creator communications
- Full audit log viewer with filters (Super Admin).

---

## 17. Navigation and UX

**Admin Console nav:** Overview · Creators (Pipeline / All / Prospects / Agencies) · Campaigns · Applications · Deals · Contracts (Contracts / Templates / Clause Library) · Briefs (Briefs / Templates) · Content (Deliverables / Review queue / Live posts) · Leads (Pipeline / Attribution review / Fraud flags) · Finance (Ledger / Payouts / TDS / Invoices / Reconciliation) · Analytics · Messages · Announcements · Tasks · Settings · Audit log.

**Creator Portal nav:** Home · Campaigns (Open / Invited / My applications) · My Deals · Contracts · Briefs · Deliverables · Leads · Earnings (Overview / Ledger / Payouts / Statements & TDS) · Links & QR · Messages · Profile & KYC · Help.

**UX requirements:**
- **Mobile-first** creator portal, since most creators will use phones. Installable PWA. Bottom navigation on mobile.
- Global search and a command palette (⌘K) in admin.
- Every list has empty, loading (skeleton), error, and no-results states.
- Optimistic UI where safe. Toasts for actions.
- Confirmation dialogs for destructive or irreversible actions.
- Keyboard accessible, **WCAG 2.1 AA**, colour-contrast compliant.
- Indian number formatting, IST times with relative times ("2 hours ago"), and DD MMM YYYY dates.
- Light theme default, with dark mode supported through design tokens.
- Clean, professional design: consistent spacing, typography scale, and status colour system (one colour per status family, reused everywhere).
- **Demo mode and seed data:** a seed script that creates realistic creators, campaigns, deals across all compensation combinations, contracts in each state, deliverables, attributed leads (synthetic, not real students), and ledger history. Use it for Playwright and stakeholder demos. Never run it against production.

---

## 18. Integrations and APIs

- **Reads:** `student_leads` (through approved functions and views only), `catalog_*` programmes and commission data, and CRM status sources (decided in Phase 0).
- **Writes to shared objects:** only the attribution trigger and function and any approved new columns. Nothing else.
- **Public API (read-only, rate-limited):** creator landing data for the website, by handle.
- **Internal API (service-key authenticated):** metrics and health for the future **oversight system**, which will monitor all six products from one UI. Expose `/api/health` and `/api/metrics/summary`.
- **Outbound webhooks** (signed with HMAC, with retries and a delivery log). Events include `lead.attributed`, `lead.enrolled`, `contract.signed`, `deliverable.live`, `payout.paid`, and `creator.activated`. They can feed n8n automations.
- **Future hooks (design interfaces now, don't build):** Instagram Graph and YouTube Data API metric sync, payout provider API, AI brief/caption assistant, AI recommendations.

---

## 19. Non-functional requirements

- **Security:**
  - OWASP Top 10 mitigations.
  - CSRF protection on mutations, strict CSP, and rate limiting on auth, OTP, redirect, and public endpoints.
  - File type and size validation, with signed URLs that expire.
  - Least-privilege service roles, and no service key in the client.
  - Session timeout setting, and device/session list with remote logout.
- **Performance:** p95 page load under 2 seconds on 4G for creator pages; lists paginated server-side; images optimised.
- **Reliability:** idempotent jobs with retries and dead-letter handling; scheduled-job monitoring; graceful degradation if a notification provider fails (queue and retry).
- **Backups and recovery:** rely on Supabase backups and document the restore procedure. Storage buckets are versioned or protected for signed documents.
- **Observability:** error tracking, structured logs with request IDs, job run logs, and an admin "System status" page.
- **Data retention:** configurable. Financial and contract records are kept for at least 8 years (setting); click logs are anonymised after N days.

---

## 20. Testing and acceptance

**Unit tests (Vitest):**
- compensation engine (exhaustive, per Section 6.3)
- attribution rules
- masking functions
- TDS and GST calculations
- milestone triggers
- slab and recoupment edge cases

**RLS tests:** for each role, prove allowed and denied reads and writes on every `inf_` table and every creator-facing function. Specifically prove that **no creator or agency path returns an unmasked phone or email**.

**End-to-end tests (Playwright) for these journeys:**
1. A prospect is invited, completes onboarding and KYC, and is approved.
2. An open campaign receives an application, which is countered and accepted; the deal, contract, brief and deliverables are auto-created.
3. Contract negotiation: comment, change request, counter, accept, OTP sign, countersign, and the signed PDF with its certificate.
4. The brief is acknowledged; concept, draft, timestamped review, approval, live and verification follow; the milestone becomes payable.
5. The tracking link is clicked, a lead arrives in `student_leads` (test fixture), is attributed, and progresses to enrolled; commission accrues, is confirmed on commission receipt, and is included in a payout batch marked paid with a UTR; the creator is notified.
6. Duplicate lead and self-referral cases are not credited, with the reason shown.
7. Clawback inside the refund window.
8. Deals of each kind (commission only, fixed only, hybrid with recoupable advance and retroactive slabs) produce exactly the expected ledgers.

**Acceptance per phase:** migrations applied cleanly on a fresh database and on a copy of the current schema; tests green; lint and typecheck clean; seed and demo working; docs updated.

---

## 21. Settings (all admin-configurable)

Group settings logically and validate each one with a schema. Each setting shows who changed it and when.

- **Organisation:** legal entity name, address, GSTIN, PAN (masked), authorised signatories, logo, brand colours.
- **Attribution:** window, model, duplicate rule, self-referral rule, fraud thresholds, Witty WhatsApp number, deep-link message template, UTM defaults.
- **Lead visibility:** the creator field whitelist (phone and email are locked masked and cannot be unmasked for creators), and the masking format.
- **Stage mapping:** CRM status to creator-facing stage.
- **Compensation:** deal presets, default milestone templates, rounding rule, hold days, refund window default, penalty caps, commission base (gross or net of GST) default.
- **Contracts:** OTP channels (email, phone, both), OTP expiry and attempts, consent text versions, reminder schedule, expiry reminders, legal-review gate.
- **Content:** revision limit defaults, banned-claims list, disclosure rules per platform, metric checkpoints, upload limits.
- **Finance:** TDS table, GST settings, payout cycle, two-person approval, bank export format, KYC-required-for-payout.
- **Tiers and scorecard:** tier rules and benefits, score weights.
- **Notifications:** provider credentials (references to env secrets), templates, digests, quiet hours.
- **Retention and privacy:** retention periods, anonymisation schedule.

---

## 22. Delivery plan — work in gated phases

Finish each phase completely before the next. At the end of every phase, **stop and report**: what was built, migrations, test results, screenshots or demo steps, open issues, and the next phase plan. Wait for approval.

**Phase 0 — Discovery and design (no app code yet)**
1. Inspect the existing Supabase project:
   - all tables, columns, functions (especially `lead_intake()`), triggers, RLS, and the `catalog_*` structure
   - how Witty stores source and referral codes
   - where CRM and partner lead statuses live
   - whether Eduwit commission received per enrollment is recorded anywhere
2. Inspect the existing Next.js apps for reusable conventions (auth, UI kit, folder structure, env handling).
3. Produce:
   - `docs/PHASE0_FINDINGS.md`
   - the proposed ERD (Mermaid)
   - the full list of changes to shared objects, with justification
   - the creator-visible lead field whitelist
   - the stage-mapping proposal
   - the integration contracts (Witty code format, CRM stage events, commission receipts)
   - a final tech decisions list
   - a risk register
4. Ask every open question (Section 23) that the codebase cannot answer.

**Phase 1 — Foundation:** project scaffold, CI, env, auth (staff 2FA, creator OTP and Google), roles and the permission matrix, layouts for both portals, settings framework, audit log, notification adapter skeleton, storage buckets, base schema and RLS with tests, design system and components, seed framework.

**Phase 2 — Creators and campaigns:** creator profiles, platforms, KYC, agencies, prospect CRM, outreach and tasks, onboarding wizard, campaigns, marketplace, invites, applications and negotiation threads.

**Phase 3 — Compensation engine and deals:** engine module with full tests, deal builder, presets, simulator, deal versions and amendments, recompute dry-run.

**Phase 4 — Contracts:** clause library, templates, variables and conditionals, generation from deals, negotiation and diffs, OTP click-sign, countersign, PDF with certificate, amendments, renewals, reminders.

**Phase 5 — Briefs and deliverables:** brief builder and templates, acknowledgement and Q&A, deliverable workflow, uploads, video and image review, compliance scan, go-live verification, metrics capture, overdue and penalty proposals.

**Phase 6 — Attribution and lead pipeline:** tracking links, redirect and QR, the attribution function and trigger (approved approach), fraud flags and review queue, stage sync, masked creator lead pipeline (kanban, table, drawer, realtime), admin attribution console, backfill tool.

**Phase 7 — Ledger and payouts:** engine runner and event wiring, ledger, TDS and GST, invoices, payout batches, bank export, UTR marking, payment advice, statements, reconciliation.

**Phase 8 — Dashboards and analytics:** creator home, admin overview, campaign, creator 360°, finance, materialised views, `METRICS.md`, exports.

**Phase 9 — Communication:** threads everywhere, notification centre, email and WhatsApp templates, preferences, announcements, digests, webhooks.

**Phase 10 — Scorecards, tiers, compliance and polish:** scorecards, tiers, recommendations, compliance tracker, DPDP workflows, audit viewer, accessibility pass, performance pass, security review, full end-to-end suite, production runbook (`docs/RUNBOOK.md`), and admin and creator user guides (`docs/ADMIN_GUIDE.md`, `docs/CREATOR_GUIDE.md`).

---

## 23. Open questions to resolve in Phase 0

Answer what you can from the codebase and database. Ask the owner for the rest.

1. Exact `student_leads` columns, and where and how Witty stores a creator or referral code today.
2. Which fields beyond phone and email (if any) must be hidden from creators, e.g. internal notes, partner name, counsellor name.
3. How lead stages from partner CRMs (B2B) and the in-house team (B2C) are stored and updated.
4. Whether per-enrollment Eduwit commission received is recorded anywhere, or whether Finance enters it manually.
5. Email and WhatsApp providers and sender numbers for portal notifications and OTP. Should the Witty number be used for deep links, and a different number for portal notifications?
6. Production domain, e.g. `creators.eduwit.in` for creators and `/admin` behind staff auth.
7. Authorised signatory name(s) and designation(s) for countersigning.
8. Bank bulk-upload file format for payouts.
9. Default TDS sections and rates per component type (to be confirmed by CA).
10. Whether `inf_` tables live in `public` or a separate schema.

**Do not start Phase 1 until Phase 0 is reviewed and approved.**
