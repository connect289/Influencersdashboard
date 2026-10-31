# Eduwit Influencer Portal: staff guide

<!-- Generated from lib/guides/content by npm run gen:sql. Do not edit by hand. -->

Everything staff do in the admin console, by role. The same text is in the console under Help, where each screen links to its section.

## Contents

- Getting started (all staff)
- Super Admin: setting up and running the portal
- Influencer Manager: creators, campaigns, deals and contracts
- Content Reviewer: reviewing content and verifying posts
- Finance: KYC, tax, ledger and payouts
- Viewer

## Getting started (all staff)

Signing in, finding your way around the admin console, notifications, keeping your account safe, and reading the analytics dashboards.

### Signing in

The admin console is for Eduwit staff only. Creators and agencies use their own portal.

1. Open the staff sign-in page and enter your work email and password, or use **Continue with Google** with your Eduwit Google account.
2. Enter the **6-digit code** we email you. Every staff sign-in is confirmed this way, even after Google.
3. Tick **Trust this device for 30 days** on your own laptop to skip the code there. Never tick it on a shared computer.

> **Tip:** First time, or forgot your password? Use **First time, or forgot your password?** on the sign-in page. A Super Admin must have invited you first.

You are signed out after a period of inactivity (set by the Super Admin under Settings → Security). Your work is saved as you go, so just sign in again.

### Finding your way around

- **Sidebar**: the modules your role can use. Items you cannot use are hidden, not greyed out.
- **Command palette**: press **Ctrl K** (⌘K on a Mac) to jump to any page or creator by name.
- **Overview**: your setup checklist, your open tasks and the health of background jobs.
- **Help**: these guides. Each role has its own guide; you can read the others too.

| Area | What it is for |
| --- | --- |
| Creators (`/admin/creators`) | The creator CRM: pipeline, profiles, outreach, KYC, approvals, imports |
| Campaigns (`/admin/campaigns`) | Campaign builder, invitations and the creator marketplace |
| Applications (`/admin/applications`) | Creator applications and negotiation |
| Deals (`/admin/deals`) | Compensation terms: builder, simulator, proposals, amendments |
| Tasks (`/admin/tasks`) | Follow-ups assigned to you and your team |
| Agencies (`/admin/agencies`) | Talent agencies and the creators they manage |
| KYC (`/admin/kyc`) | PAN and bank details waiting for verification |
| Settings (`/admin/settings`) | Business rules: attribution, compensation, finance, security… |
| Audit log (`/admin/audit`) | Who changed what, and when |

### Privacy rules everyone must know

- Students' phone numbers and email addresses are **never** shown to creators or agencies. The system masks them; do not copy them into messages.
- Creators' PAN and bank details are encrypted. Most staff see them masked. Finance can reveal them with a reason, and every reveal is recorded.
- Everything you create, change or delete is written to the audit log.

### Your account and devices

Open Account (`/admin/account`) to see where you are signed in. Sign out any device you do not recognise, or **Sign out all other devices**. Trusted devices are listed there too; **Forget** one to require the code again.

> **Important:** If you think your password leaked, change it and sign out all other devices at once. Then tell a Super Admin.

### Notifications

The bell at the top shows how many notifications you haven't read; it updates on its own. Open it for the notification centre (`/admin/notifications`): newest first, **Unread** to filter, and **Mark all read**. Opening a notification takes you to the page it is about.

- You are told about work that is yours: applications on campaigns you own, creators' replies on your deals, messages on your deals and contracts, @mentions, tasks, fraud flags (if you review them) and the daily queues (reviews waiting more than a day, negotiations with no answer for three days).
- In notification settings (`/admin/notifications/settings`) choose email per notification, and how often you get the **digest** of the queues (every morning by default; weekly or off if you prefer).
- Until the Super Admin turns on live sending, emails and WhatsApp messages stay inside the system.

### Messages

Every application, deal, contract, brief, deliverable and payout has a conversation with the creator (and their agency, if the creator gave it the matching permission). Each creator also has a support conversation, and each campaign has a private conversation per creator for questions before they apply. A creator (and an agency they let negotiate) can use it while the campaign is open to them in the marketplace or they were invited, applied, have a deal in it or already have a conversation about it; an archived campaign's conversations stay readable but take no new messages.

- Messages (`/admin/messages`) lists every conversation you can read, newest first. Search by words, filter by type, **Unread** or **Mentions me**.
- You can read a conversation if you have the messages permission and can read what it is about (a deal conversation needs deal access, a payout conversation payout access).
- **@mention** a colleague with the mention picker: they get a notification. Creators and agencies can't mention staff.
- Attach PDFs, images or CSV files (up to 5 per message, 25 MB each). They are stored privately; only people who can read the conversation can open them.
- **Seen** under your last message means the creator side has read it. Creators see your first name and "(Eduwit)".
- On a lead, the conversation is a set of **staff-only notes**: the creator and agencies never see them.

> **Important:** Never put a student's phone number or email in a message: creators and agencies read these conversations. Use the lead's reference instead.

### Analytics: the programme at a glance

Analytics (`/admin/analytics`) shows how the creator programme is doing. Every number has an info button with its definition; the full definitions and formulas are in METRICS.md (docs folder).

- Pick a period (today, the last 7, 30 or 90 days, this month, last month, this financial year or a custom range). **Compare with previous period** shows each figure's change against the same number of days just before; green is good news for that figure, red is not.
- **Programme health**: active, new and dormant creators and the creator pipeline.
- **Lead funnel**: clicks → leads → qualified → allocated → applied → enrolled. Stages are cumulative, so a lead that applied also counts as qualified.
- **Spend**: committed (fixed fees, milestones and guarantees on agreed and active deals, even with no leads), accrued (what creators earned in the period) and paid, by deal model and by campaign with budget used.
- **Unit economics**: cost per lead, per qualified lead and per enrolment, Eduwit's revenue, net ROI and ROAS, broken down by creator, campaign, platform, content type, programme or deal model. Commission follows its lead's post; fixed fees are deal-level and shown as not split.
- **Lead quality**, **operations** (each card opens the matching screen) and **leaderboards**.
- Test leads (Witty's test numbers) are left out unless you tick **Include test leads**.
- **Export CSV** downloads the breakdown you are looking at (counts and amounts only, never student details).

> **Tip:** Staff dashboards are refreshed every 15 minutes (the time is shown next to Refresh). Press **Refresh** after a big change; a creator's own home dashboard is always live.

### Campaign dashboards and the creator 360

- Campaigns (`/admin/analytics/campaigns`) lists every campaign's leads, enrolments, spend, revenue, cost per enrolment, ROI and budget used. Open one for its funnel, trend, a comparison of every creator in it, and a breakdown by platform, content type or programme.
- On a creator's page, the **Analytics** tab shows their trend, results by deal and by content type, and how the quality of their leads has changed over time.

### The finance dashboard

Finance (and anyone with ledger access) also sees Analytics → Finance (`/admin/analytics/finance`): what Eduwit owes creators now, payouts due, payouts by week or month with TDS and GST, TDS by quarter and section, and the reconciliation status of creator commission waiting on Eduwit's own commission.

## Super Admin: setting up and running the portal

First-time setup, staff and roles, business settings, monitoring, and what to check before go-live.

### First-time setup checklist

The Overview (`/admin`) page shows this checklist with live status. Work through it in order:

1. **Organisation details**: Settings → Organisation. Enter the legal name, address, GSTIN and PAN. They are printed on contracts, statements and payout advice.
2. **Invite your team**: Staff (`/admin/staff`) → **Invite staff**. Pick each person's roles (see the table below).
3. **Name an Authorised Signatory**: edit a staff member and tick **Authorised Signatory** with their designation. Contracts cannot be countersigned without one.
4. **Review business settings**: go through every group in Settings (`/admin/settings`). Items marked "confirm with CA" or "confirm with counsel" stay flagged until someone confirms them.
5. **Confirm tax defaults with your CA**: the TDS sections (194H 2% on commission, 194J 10% on fees, 20% without PAN, 194R on barter) are defaults until confirmed.
6. **Connect providers** (done by the developer at deployment): an email provider, WhatsApp, and then **live mode** so notifications actually leave the system.

### Roles and what they can do

| Role | Can |
| --- | --- |
| Super Admin | Everything, including staff, settings, audit and system status |
| Influencer Manager | Creators, outreach, campaigns, applications, deals, agencies; reads leads, ledger and payouts |
| Content Reviewer | Reviews submissions, overrides compliance checks with a reason, verifies live posts and edits the banned-claims list |
| Finance | KYC verification and reveal, TDS and GST settings, ledger, payouts; read-only elsewhere |
| Viewer | Analytics and scorecards, read-only |

A person can hold several roles; their permissions add up. **Authorised Signatory** is a separate flag that lets the person countersign contracts, whatever their role.

> **Tip:** Suspending a staff member signs them out of every device at once. Use **Sign out everywhere** if a laptop is lost.

### Business settings

Everything the business might change is a setting, not code. Each setting is validated, versioned (you can see who changed what and when), and some need a confirmation before they count as final.

| Group | Examples |
| --- | --- |
| Attribution | Attribution window (default 90 days), first-touch model, duplicate and self-referral rules |
| Lead visibility | Which lead fields creators see (phone and email are always masked) |
| Compensation | Hold days, refund window, penalty cap, default commission base, GST on Eduwit's commission |
| Contracts | Signing code channels and limits, negotiation reminders, legal-review gate |
| Finance | Payout cycle, two-person approval, KYC needed for payout, minimum payout, agency-payee handling, GST rate and SAC, bank export columns, reconciliation flag |
| Creators | Dormancy, auto-approval of sign-ups, course pass mark, KYC required to submit onboarding |
| Content | Revision limit, disclosure terms and platforms, metric checkpoints, reminder and escalation days, upload sizes |
| Security | Idle sign-out, trusted-device length |
| Retention and privacy | How long records are kept |

> **Important:** Changing compensation defaults affects new calculations only; agreed deal terms are never changed by a setting.

### Contracts: clause library, legal review and signing

Contracts are assembled from the Clause library (`/admin/contracts/clauses`) by templates (`/admin/contracts/templates`), with every number filled in from the deal. The library ships with 20 professionally structured **draft** clauses, each starting with “DRAFT — requires legal review before use”.

1. Have counsel review each clause. Edit the wording (remove the draft marker once approved) and save: every save is a new version, and contracts already generated keep the version they used.
2. On each clause, click **Mark as legally reviewed**. Only Super Admins can. The library's **Not reviewed** filter shows what is left.
3. While the **legal-review gate** is on (Settings → Contracts → Signing and reminders), a contract containing any unreviewed clause cannot be sent. Leave it on.
4. Check the default template in Templates (`/admin/contracts/templates`): clause order, conditions (for example exclusivity only when the deal has an exclusivity fee) and the preview for each sample deal type.
5. Make sure an **Authorised Signatory** is named (Staff → edit → Authorised Signatory, with designation). Only they can countersign.
6. In Settings → Contracts, choose the signing-code channels (email, WhatsApp or both), code expiry and attempts, negotiation reminder days and expiry reminders (30, 15 and 7 days by default).

> **Important:** Stamp duty and the enforceability of electronically signed contracts depend on the state and the type of contract. Confirm both with counsel; each contract has an optional stamp duty reference.

### Countersigning (Authorised Signatory)

1. When a creator signs, you are notified. Open the contract from the notification or Contracts (`/admin/contracts`) (status **Signed by creator**).
2. Read the document, tick each section, type your full name, accept the statement and click **Send code**. Enter the 6-digit code from your email and click **Countersign**.
3. The contract becomes **Active**, the deal becomes active, and the signed PDF with its signature certificate is stored and emailed to every party.

Every download of a signed PDF re-checks two hashes: the document against the hash each signature recorded, and the PDF against the hash stored when it was made. If either differs the contract is flagged as invalid and nothing is served.

### Lead stage rules

Stage rules (`/admin/leads/stages`) decide how CRM data becomes the stage creators see. Rules run by priority (lowest first) and the first match wins.

- A rule matches when all its conditions hold: the CRM stage, lost reason, enrolment status, applied date, whether Witty qualified the lead, the B2C stage or closed reason, or the attribution status.
- **Only add the flag** marks a lead (cancelled or under review) and keeps evaluating, so a later rule still sets the stage.
- Changes apply on the next sync. Stages never move backwards for creators; closed outcomes can always follow.
- When a new CRM stage appears, the leads list shows a banner until a rule maps it.

> **Important:** The attribution links settings (Witty's number, the message, UTM source, short-link base and website address) change every new link, so check them before creators start sharing.

### Notification templates

Communication → Templates (`/admin/communication/templates`) lists every notification the portal sends. Without a custom template, the notification's own title and text go out by email; WhatsApp needs a template.

- Write the email subject and text with **variables** such as `{{name}}`, `{{amount}}` or `{{campaign}}`. Only the variables listed for that notification are allowed; anything else is refused when you save.
- For WhatsApp, enter the **approved template name** from the WhatsApp Business account and one variable per line, in the template's order. Approval of templates happens in that account (an external step before go-live).
- Each save is a new **version**; the history shows who changed what. **Use built-in text** goes back to the default; old versions stay.
- The **preview** uses sample values. **Send me a test** emails the draft to you, only once live sending is on.

> **Important:** Notifications about contracts, payments and KYC are required: people can't turn them off, so keep their wording precise.

### Webhooks

Communication → Webhooks (`/admin/communication/webhooks`) sends events to other systems: a lead credited or enrolled, a contract signed, a post live, a payout paid, a creator approved.

- Add a **public HTTPS** address and choose events. Private, internal and cloud-metadata addresses are refused, also when a name resolves to one.
- The **signing secret** is shown once: store it in the receiving system. Each request has an `X-Eduwit-Signature` header (`t=` timestamp, `v1=` HMAC-SHA256 of `timestamp.body`); receivers should reject anything older than 5 minutes. **New secret** replaces it at once.
- Payloads carry ids, handles, amounts and references only, never students' phone numbers or emails.
- Failed deliveries retry after 1, 5 and 30 minutes, then 2, 6 and 24 hours (7 tries). The last 20 deliveries show status, HTTP code and error. **Send test event** queues a sample.
- Nothing leaves the system until live sending is on; deliveries are logged as not sent.

### Monitoring and the audit log

- System status (`/admin/system`): the job queue (notifications, deal creation after accepted offers…), scheduled tasks and sending providers. A job that keeps failing is retried with back-off; you can retry a dead job by hand.
- Audit log (`/admin/audit`): filter by person, record type, action, record id and date; select a record id to see that record's whole history. PAN and bank numbers are redacted in the log itself.

### Tiers and scorecards

Settings → Tiers (`/admin/settings/tiers`) defines the creator tiers. The scorecard weights and thresholds are in the **Tiers and scorecard** group of Settings (`/admin/settings`).

- Each tier has a **rank** (higher is better; each active tier needs its own), **entry rules** (minimum composite score, enrolments in the last 90 days, months since approval, compliance score) and **benefits** (commission uplift suggested for new deals, early access to open campaigns, a payout cycle shown to Finance, and a note for the creator).
- Scorecards run on the 1st of each month for every approved creator. A creator moves **up** at once to the highest tier whose rules they meet and moves **down** only after missing their tier's rules for the set number of months in a row (2 by default).
- Early access: an open campaign is shown to creators in a tier with early access at once and to everyone else after that many days.
- Turning a tier **inactive** stops new creators from reaching it; creators already in it move at the next monthly evaluation.

### Privacy requests (DPDP)

Privacy requests (`/admin/privacy`) (needs the privacy permission) lists every data export and deletion request. Exports are ready for the creator at once and need nothing from you.

- **Review** a deletion request to see what would be erased now (profile, platforms, media kit, photo, preferences and the creator's message text) and what is kept until the legal retention period ends (earnings ledger, payouts, invoices, TDS, signed contracts and the KYC they need).
- A request is **blocked** while a deal is still open or money is owed either way: end the deals or settle the balance first.
- **Approve and erase** needs a note to the creator; the account is erased, signed out and can no longer sign in. **Reject** also needs a note. Both are recorded in the audit log and the creator is notified.
- Retention runs nightly: click details are anonymised, old sign-in records and audit entries removed, and kept KYC removed on the purge date (Settings → Retention and privacy).

> **Important:** Erasing cannot be undone. Check the creator has no dispute or open claim before approving.

### Before go-live

The portal is built and tested against a local copy of the database. Going live (applying the database changes to the shared Supabase project, connecting attribution, deploying) is done by the developer from the go-live runbook, and only after your written approval.

- Legal review of the platform terms, privacy notice and the compliance course.
- CA confirmation of the TDS sections and GST settings.
- Email and WhatsApp providers, the domain, hosting and error monitoring accounts.

## Influencer Manager: creators, campaigns, deals and contracts

Running the creator pipeline, onboarding and approving creators, building campaigns, negotiating, setting up deals, and contracts.

### The creator pipeline

Creators (`/admin/creators`) shows every creator as a table or a kanban board. Stages run Prospect → Contacted → Negotiating → Contracted → Onboarding → Active, with Paused, Dormant and Archived. Drag cards between columns, or change the stage from the creator's page.

- **Filters**: platform, followers, topic, language, city or state, tier, owner and status. Save a filter as a view and share it with the team.
- **Bulk actions**: select rows to tag, assign an owner, move stage or invite.
- **Import**: Import prospects (`/admin/creators/import`) from a CSV (up to 5,000 rows). The file is checked first; duplicates by handle, phone, email or platform handle are skipped and listed in a downloadable report.
- **Dormant**: active creators with no activity for the configured number of days are flagged automatically and return to active when they do something.

### A creator's page (Creator 360)

Open a creator to see the overview, profile, KYC (masked), outreach timeline, tasks, deals, linked agencies and history. From here you can:

- **Log outreach** (channel, outcome, notes) and set a follow-up date; overdue follow-ups appear on your Overview.
- **Add tasks** for yourself or a colleague.
- **Invite** the creator to sign up; they get an email and land in the onboarding wizard.
- **Start a deal** from the Deals tab.
- Download the **media kit** (PDF) to share with partners.
- Check the **Scorecard** and **Compliance** tabs before a renewal (see Scorecards).

### Scorecards, compliance and recommendations

Every approved creator gets a scorecard on the 1st of each month for the month before: delivery, content, lead quality, economics and compliance, each 0–100, and a weighted composite. A part with no data is left out rather than scored zero.

- The creator's **Scorecard** tab shows the latest scores, the figures behind them, the monthly trend and tier changes. **Run scorecard now** calculates a fresh one (it doesn't change the tier).
- **Set tier by hand** (with a reason and an end date) for special cases; the monthly evaluation takes over again after that date. The tier history lists every change and why.
- The **Compliance** tab lists each deliverable's obligations: live on time, disclosure, metrics reported and brief acknowledged, each met, missed, open or waived.
- Analytics → Scorecards (`/admin/analytics/scorecards`) lists every creator's monthly scorecard and tier change for a chosen month.
- When you draft a new deal, the **Terms** tab shows **Recommendations** from the latest scorecard (for example a hybrid deal with a higher commission when enrolments are strong, or concept approval when deliverables run late) and, for a tier with a commission uplift, a button to apply it. They are suggestions; nothing changes until you save.

### Onboarding and approval

Creators complete a wizard: profile, platforms, KYC (PAN and bank, encrypted), terms, and a short compliance course with a quiz. When they submit, they appear in Approvals (`/admin/creators/approvals`).

1. Open the creator from the approvals queue and check the profile and platforms.
2. Choose **Approve**, **Ask for changes** (with a note) or **Decline** (with a reason). The creator is told in every case.

> **Tip:** Settings → Creators can auto-approve self sign-ups above a follower count. Invited creators are still reviewed.

### Campaigns, invitations and applications

1. New campaign (`/admin/campaigns/new`): name, objective, dates, budget and slots, programmes from the catalogue, eligibility (followers, platforms, topics, languages, geography) and deliverables.
2. Pick a **default deal preset**: accepted applications become deals starting from it.
3. **Open** the campaign for the marketplace, or make it invite-only and **invite** creators.
4. Review Applications (`/admin/applications`): shortlist, reject with a reason, or **make a counter-offer**. One offer is open at a time and only the other side can accept it.

When an offer is accepted, the deal is created at once with the agreed terms (version 1, already accepted by both sides). Open it from the application with **Open deal**.

> **Important:** Creators never see the budget or internal notes of a campaign.

### Announcements

Communication → Announcements (`/admin/communication/announcements`) sends a message to every active creator or a segment: by tier, platform, campaign (creators with a deal or a live application) or language. The count of creators updates as you choose.

- Announcements always appear in the portal and on creators' home page; tick email or WhatsApp to send those too (creators who turned announcements off for a channel aren't messaged there).
- **Save draft**, **Schedule** for a time in IST, or **Send now**. Drafts and scheduled ones can be edited or cancelled until they go out; scheduled ones are sent within five minutes of their time.
- Sent announcements show how many creators received them.

### Deals: building compensation

A deal holds a creator's compensation terms. Start one from New deal (`/admin/deals/new`) (or a creator's Deals tab): pick the creator, an optional campaign, the dates and a **preset** to start from. You then land in the **builder**.

| Section | What you can set |
| --- | --- |
| Fixed fees and milestones | Lump sum, per deliverable, per unit or retainer; milestones by % or amount, each paid on a trigger (signing, brief, concept, draft, live, N days after live, a metric threshold, campaign end, a date, or manual release), with payment terms and what happens if a deliverable is cancelled |
| Commission | Flat per lead, qualified lead, application or enrolment; % of programme fee; % of Eduwit's commission (gross or net of GST). Scope (programmes, universities, levels, links, deliverables), slabs (marginal or retroactive), caps, confirmation (immediate, after a hold, or when Eduwit is paid), clawback window and dates |
| Minimum guarantees | "At least ₹X per month or per deal", topped up against commission |
| Recoupment | Commission pays out only after it exceeds all or part of the fixed fee |
| Bonuses | Targets on enrolments, leads, views, on-time delivery or leaderboard rank, per deal, month, campaign or dates |
| Penalties | Late delivery, missed deliverable, disclosure, breach clawback. Always proposals that a manager approves |
| Additional fees | Usage rights, exclusivity, whitelisting, reimbursements |
| Non-cash | Barter value for reporting; never paid out |

The **earnings simulator** next to the builder updates as you type: enter a scenario (leads, enrolments, views, days late…) and see each component, TDS, GST and the net payout, plus Eduwit's revenue, cost per enrolment and margin. Creators never see the Eduwit figures.

> **Tip:** Use **Save as preset** to reuse a set-up. Manage presets under Deal presets (`/admin/deals/presets`); system presets are fixed, copy one to change it.

### Deals: proposing, negotiating, activating

1. **Save terms**, then **Send terms to creator** (add a note if useful). The deal moves to Proposed and the creator is notified.
2. The creator, or their agency with the negotiate grant, **accepts** or **declines with a reason**. A decline puts the terms back in your builder (status Negotiating); revise and send again.
3. Once accepted, the deal is **Agreed** and the terms are locked as a version.
4. The countersigned contract makes the deal **Active** (see Contracts below). For a contract signed outside the portal, use **Activate** and give the reason.
5. Close a deal with **Mark completed**, or **Terminate** with a reason.

### Amendments and the dry run

Agreed terms never change in place. To change them, click **Amend terms**: the current terms open in the builder as a draft amendment while the old terms stay in force.

1. Edit and **Save terms**.
2. Open the **Dry run** tab, choose when the amendment takes effect and a scenario, and run it. You see the creator's earnings under the current terms, with the amendment, and every line that changes.
3. **Propose amendment**. When the creator accepts, the new version applies from the chosen time; everything earned before it keeps the old terms.

The **Versions** tab lists every version with its terms, who answered and why.

### Contracts: generating and sending

A contract is generated from a deal's agreed terms. For an accepted campaign application the draft is created automatically; otherwise open the deal and click **Generate contract**.

1. Choose the template (the campaign's template is preselected, else the default), who is paid (the creator, or an agency the creator allowed to negotiate and sign), the dates and, if counsel asked for it, a stamp duty reference.
2. **Generate draft**. Every amount, milestone, commission rule, bonus, penalty and fee is written from the deal: you never type numbers into a contract.
3. If details are missing (for example the creator's legal name or address) a banner lists them. Fix them on the creator's profile or KYC, then **Regenerate**.
4. **Send to creator**. The creator (and their negotiating agency) is notified and has until the negotiation deadline to respond; reminders go out automatically.

| Status | Meaning |
| --- | --- |
| Draft | Only Eduwit sees it |
| Sent / In negotiation | The creator is reviewing, commenting or asking for changes |
| Ready to sign | Every request answered; this version is final |
| Signed by creator | Waiting for the Authorised Signatory |
| Active | Both signed; the deal is active and the signed PDF is stored |
| Completed / Terminated / Expired | Ended (a reason is recorded for termination) |
| Void / Superseded | Withdrawn before signing, or replaced by a signed amendment |

### Contracts: negotiating

- **Comments**: anyone can comment on any clause; reply and resolve threads under each clause on the Document tab.
- **Suggested wording**: the creator can propose new wording for clauses flagged **negotiable**. On the Change requests tab you see a word-by-word diff.
- **Compensation counter-offers**: the creator proposes new numbers (fee, rates, bonus amounts) through a structured form. You see each number from → to.

For each request choose **Accept**, **Counter** (your own wording or numbers, with a message) or **Decline** (with a reason). Accepting or countering creates a new contract version straight away; for compensation, the deal's terms change first and the contract is regenerated from them, so the deal stays the single source of truth.

The **Versions** tab compares any two versions section by section. When every request is answered, click **Mark ready to sign**.

> **Tip:** Wording already agreed for a negotiable clause is kept when you regenerate the contract after other changes.

### Contracts: amendments, renewals and expiry

- **Amendment**: first amend the deal's terms (Amend terms → propose → creator accepts). Then on the active contract click **Create amendment**: a new contract linked to the original. When both parties sign it, the original becomes **Superseded**.
- **Renewal**: on an active or ended deal click **Renew**, pick the new dates, and send the copied terms to the creator. Once accepted, generate its contract; it is marked as a renewal.
- **Expiry**: contracts with an expiry date send reminders 30, 15 and 7 days before (Settings → Contracts) and move to **Expired** after the date.
- **Void** a contract that should not be signed, or **Terminate** / **Mark completed** an active one; each needs a reason.

### Briefs

Every deal gets one brief. For a deal from an accepted application, a draft brief and its deliverables are created at once; for other deals open the deal's **Content** tab and click **Create brief**.

1. The draft is filled from the campaign's brief template (or the default), the agreed deliverables and the catalogue: approved claims are written from the programmes' fees, mode, recognitions and eligibility.
2. Edit it in Briefs (`/admin/briefs`): objective, audience, key messages, disclosure rules, do's and don'ts, tone, languages, hashtags, references, files and FAQs. **Save** as you go.
3. **Publish brief**. The creator (and their agency with the deliverables permission) is told and must acknowledge it before starting. Acknowledging starts the deliverables and can trigger a milestone.
4. To change it later, edit and **Publish new version** with a note on what changed; the creator acknowledges the new version.
5. Answer the creator's questions in the **Questions** panel; open questions show on the briefs list.

Templates (`/admin/briefs/templates`) hold the defaults copied into new briefs, plus the stages and due-date offsets for new deliverables. Each campaign can pick its template in the campaign builder.

### Deliverables

Deliverables move through: brief acknowledged → concept → draft → (scheduled) → live → verified → metrics → completed. Each stage can be switched off per deliverable before work starts, under the deliverable's **Settings** tab.

- **Due dates** come from the template's offsets and can be changed per deliverable. Reminders go out before each date; overdue work is flagged to the creator on day 1 and to you after 2 days (Settings → Content).
- **Rule id**: if the deal's compensation names a deliverable (a milestone paid when it goes live, or a late-delivery penalty), enter that id so the right rules apply.
- **Extra revision rounds** a reviewer requests come to you (any role with deal editing) to approve or reject.
- **Complete** a deliverable when everything is in, or **Cancel** it with a reason.

### Penalty proposals

When a deliverable goes live late, is cancelled or fails its disclosure check, the deal's penalty rules are worked out and appear as proposals in Penalties (`/admin/content/penalties`) and on the deal's Content tab. Nothing is charged automatically.

- **Approve** a proposal you agree with; it is applied with the deal's ledger and the creator is told.
- **Reject** with a reason when there is a good explanation.
- If the facts change (for example the due date is moved), the proposal is updated or withdrawn while it is still open.

### A deal's earnings

The **Ledger** tab on a deal shows what the deal has posted for the creator: each fee, milestone, commission, bonus, penalty and clawback with its status, and the totals.

- The ledger updates by itself when something changes what the deal earns. **Next run** previews what would change; **Run now** applies it at once.
- **Release** pays a milestone whose trigger is a manual release. **Record a breach** proposes the deal's breach penalties for approval. Both need a reason and cannot be undone.
- Approved penalties appear here as debits. Questions about holds or payouts go to Finance.

### Leads and attribution

Leads (`/admin/leads`) lists every lead attributed to a creator, across all creators. Every minute the portal reads new and changed leads from the CRM (read-only), applies the attribution rules and updates the stage creators see.

- The rules (in Settings, Attribution): self-referral first, then duplicates (a student who already enquired), then the attribution window (90 days by default). The default model credits the first creator and records later ones as assisted.
- A campaign can override the attribution model and the pre-filled WhatsApp message (its Edit tab, Tracking for this campaign). The message must keep {code}. The campaign of a lead's earliest touch decides which model applies.
- Switch between table and board views; the board groups leads by the stage creators see.
- Every deliverable gets its own tracking link and code when it is created; creators see it on the post and in the brief, and can make extra links. Staff can make links for a creator from the Links tab on the creator's page.
- Open a lead to see its attribution history: every decision with the rule, the reason and who made it.
- **Credit this creator** or **Reject this attribution** with a reason to override the rules. Manual decisions stick: re-runs never undo them. Rejecting moves the credit to the next eligible creator, if any.
- Staff see the same masked contacts as creators. Only Super Admins see a student's phone and email, in the lead drawer.
- A banner warns when leads carry a CRM stage no stage rule maps; a Super Admin should add a rule.
- Tools (`/admin/leads/tools`) shows when the sync last ran and re-runs attribution for a date range (up to 400 days) after a rule change.

### Fraud review

Fraud review (`/admin/leads/fraud`) lists unusual patterns. Nothing is rejected automatically.

| Signal | Meaning |
| --- | --- |
| Lead spike | More leads from one creator in an hour than the limit |
| Same device | Several leads from one device |
| Never answered Witty | The student never replied to the WhatsApp bot |
| Off-hours burst | Many leads in the middle of the night |
| High junk rate | A large share of the creator's closed leads are junk |

- Lead-level signals (same device, never answered) hold the credit and show **Under review** to the creator until you decide.
- **Clear** keeps the credit; **Confirm** rejects the attribution and the creator sees "rejected after review". Both need a reason and are audited.
- Thresholds are in Settings, Attribution (fraud signals).

### Agencies

Agencies (`/admin/agencies`) lists talent agencies. Create one, invite its owner, and the owner can request links with creators. Each creator decides what the agency may do: view, act on deliverables, negotiate and sign, view earnings. Payouts always go to the creator's own bank account.

## Content Reviewer: reviewing content and verifying posts

The review queue, compliance checks and overrides, comments on videos and images, revision limits, live verification and the banned-claims list.

### Your queue

Content (`/admin/content`) lists every open deliverable as a list or a board. The tabs along the top filter it:

| Tab | Shows |
| --- | --- |
| Deliverables | Everything open, sorted by the next due date |
| Review queue | Concepts and drafts waiting for you, and live posts to verify |
| Overdue | Work past its due date (the creator is reminded on day 1; the deal owner after 2 days) |
| Live posts | Everything that has gone live |
| Banned claims | The list every submission is scanned against |
| Penalties | Penalties the deal rules propose, for a manager to approve |

> **Tip:** You're notified when work is submitted to a deal you own (or to any deal without an owner).

### Reviewing a submission

Open a deliverable from the queue. The **Review** tab shows the latest concept or draft: the script or caption, the files and any link, with the checks and the decision panel beside it.

1. Read the **checks**. Every submission is scanned when it is sent: **banned claims** (a blocking match stops approval; a warning is for you to judge) and, for drafts, the **disclosure** (for example #ad or "paid partnership" on platforms that require it).
2. Watch or look through the files. Tick **At the current video time** to pin a comment to a moment; drag on an image to mark an area. Comments are numbered on the image; click one to jump to it.
3. To approve, every failed check must be fixed or **overridden** (you give a reason; it is recorded). The last approval before posting also needs the **ASCI checklist** ticked.
4. Or **Request changes** with a note saying what to change. Each request uses one revision round.

- The revision limit is set per deliverable (2 by default, Settings → Content). At the limit, **Request an extra round** with a reason and an optional fee for the creator; a manager approves it.
- If the scan did not run (the panel says so), use **Run the check again**. Run it again after changing the banned-claims list, too.
- Earlier rounds stay below, each with its comments and decision.

> **Important:** Override a check only when you are sure the content is fine in context, for example a banned phrase quoted to debunk it.

### Verifying live posts

When the creator submits the live link (validated for the platform; YouTube links show the video's title and thumbnail), it appears in the review queue and the **Live** tab.

1. Open the link and check: it is live and public, the disclosure is there and clear, and it matches the approved version.
2. **Verify** if all three are true. Otherwise untick what is wrong, say why, and **Ask for a fix**: the creator submits a corrected link.

A missing disclosure is recorded on the deliverable and, if the deal has a disclosure penalty, a penalty is proposed for a manager to approve.

### Metrics

After going live the creator reports views, reach, likes and more at the checkpoints (24 hours, 7 days and 30 days by default, Settings → Content), with screenshots of their insights. They appear on the **Metrics** tab. Missing metrics are flagged to the deal owner after the grace period.

### The banned-claims list

Banned claims (`/admin/content/claims`) is the list every concept and draft is scanned against. It starts with common problem phrases for education promotion (guaranteed placements, "no exams", unverifiable superlatives): review it and make it yours.

- A **phrase** matches as whole words, in any case and with any spacing.
- A **pattern** is a regular expression for variations (for example `100\s*%\s*placement`). Patterns that could be slow are refused.
- **Blocks approval** stops approval until fixed or overridden; **Warning** only flags it.
- Use **Try a sentence** to see what the scan would flag before saving.

## Finance: KYC, tax, ledger and payouts

Verifying creators' KYC, the TDS and GST set-up, the creator ledger, payout batches, GST invoices, Form 16A and Eduwit's commission receipts.

### KYC verification

1. Open KYC (`/admin/kyc`) to see creators waiting for review.
2. Check the PAN, the name on the PAN and the bank account against the uploaded proof.
3. Use **Reveal** to see a full number when you need it. You must give a reason; every reveal is recorded in the audit log.
4. **Verify**, or send it back with a note. If a creator later changes their PAN or bank details, the KYC returns to the queue.

> **Important:** Never copy full PAN or bank numbers into messages, tasks or notes.

### TDS and GST set-up

| Section | Applies to | Default rate | FY threshold |
| --- | --- | --- | --- |
| 194H | Commission | 2% (20% without PAN) | ₹20,000 |
| 194J | Fixed fees, milestones, bonuses, usage and exclusivity fees | 10% (20% without PAN) | ₹50,000 |
| 194R | Barter / in-kind value (Eduwit's liability, not deducted) | 10% | ₹20,000 |

- TDS is computed on amounts **excluding GST**.
- When a creator's total for the financial year first crosses a threshold, TDS also covers that year's earlier untaxed amounts.
- GST is added for creators with a verified GSTIN (rate and SAC under Settings → Finance); reimbursements are not subject to it.

> **Important:** All of these are defaults marked "confirm with CA". Until confirmed, the simulator shows a banner, and payouts can be held (Settings → Finance → Payouts).

### Reading the deal simulator

On any deal in Deals (`/admin/deals`), the simulator shows gross earnings, TDS per section, GST and the net payout for a scenario, using the current TDS table. Use it to check how a deal will be taxed before it is proposed.

### The creator ledger

Finance (`/admin/finance`) lists every ledger line: what each creator has earned and what was deducted or paid. Lines are never edited or deleted; a correction is a new line (a reversal or an adjustment), so the history always adds up.

| Status | Meaning |
| --- | --- |
| Accrued | Earned under the deal, not yet confirmed (for example commission waiting for Eduwit's own commission) |
| Confirmed | Approved, due on a later date (payment terms or the end of a hold) |
| Payable | Due: it goes into the next payout batch |
| In batch | Part of a payout batch that is being paid |
| Paid | Settled by a payout |
| Reversed / clawed back | Cancelled; anything already paid is recovered from later payouts |

- Deals post to the ledger by themselves: the compensation engine replays each deal when a lead moves, an enrolment is confirmed, a deliverable goes live, a milestone is released or a penalty is approved, and nightly for dates and holds.
- **Adjustment** posts a credit or a debit for a creator, with a reason and an optional deal and due date.
- **Hold** stops a line (or all of a creator's open lines) from being paid until you release it. Holds need a reason and are audited.
- Filter by status, type or month; open a creator's name to see only their ledger.

### Payout batches

1. Open Payouts (`/admin/finance/payouts`) and **Prepare batch**. Every creator with payable lines becomes a payout: gross, TDS per section (with the financial-year threshold catch-up), GST for creators with a verified GSTIN, and the net amount.
2. Creators who cannot be paid yet are listed as skipped with the reason: KYC not verified, below the minimum payout, waiting for tax confirmation, or a contract that names an agency as payee. Debits net against credits; a negative total is carried forward.
3. Remove any payout you don't want in this run (its lines go back to payable).
4. **Approve** the batch. With two-person approval on (Settings → Finance → Payouts) a second, different person must approve too. Payouts that need a GST invoice must have an accepted invoice first.
5. Download the **bank file** and upload it to the bank's bulk payment portal. The file is built when you download it and never stored.
6. When the bank confirms, **Mark paid** one payout with its UTR and date, or upload the bank's response file to mark many at once. A failed payment is marked **Failed** and its lines return to payable.

- If tiers have a payout cycle (Settings → Tiers), the prepare card lists them, so you can run batches for faster-cycle tiers more often. Nothing is paid automatically.
- Marking paid posts the TDS, GST and payout lines, records TDS for the quarter, and sends the creator a payment advice PDF and a notification.
- A draft or approved batch can be **cancelled** with a reason until it is sent to the bank.
- References: batches `PB-<FY>-0001`, payouts `PO-<FY>-00001`.

> **Important:** Bank details are decrypted only to build the bank file, and each download is recorded in the audit log. Never save the file anywhere shared.

### GST invoices and payout statements

- A creator with a verified GSTIN uploads a tax invoice for each payout from their Earnings page. The portal checks the number, the date, the GSTIN and that the taxable value and GST match the payout (within ₹1).
- Review them in Invoices (`/admin/finance/invoices`): open the file, then **Accept**, or **Reject** with a note the creator sees. They can upload again.
- Creators without GST get a payout statement (`PS-…`) instead; there is nothing to review.

### TDS and Form 16A

- TDS is deducted when a payout is paid, using the creator's total for the financial year (so earlier untaxed amounts are caught up when a threshold is crossed).
- TDS (`/admin/finance/tds`) shows TDS by quarter and section, per creator, ready for your return.
- After filing, upload each creator's Form 16A for the quarter (PDF). The creator is notified and downloads it from Earnings.

> **Important:** When TDS is deducted (at payout rather than when earnings are credited) is a default to confirm with your CA.

### Eduwit's commission receipts and reconciliation

Commission that is confirmed "when Eduwit is paid" waits for Eduwit's own commission from the university. Receipts (`/admin/finance/receipts`) shows each enrolment's receipt as the CRMs record it (B2B enrolments and B2C enrolment money), with the creator commission waiting on it.

- **Record receipt** overrides the CRM for one enrolment (`b2b:<id>` or `b2c:<id>`) with a reason, for example a payment the CRM does not show yet. **Update** on an enrolment's row fills in the enrolment for you. Withdraw the override to go back to the CRM's figures.
- A received commission confirms the creator lines waiting on it; a reversal claws them back.
- Lines still waiting after the reconciliation period (90 days by default, Settings → Finance) are flagged for follow-up.

## Viewer

Read-only access to the analytics dashboards.

### What you can see

The Viewer role is read-only. You can open Analytics (`/admin/analytics`): programme health, spend, unit economics, lead quality, operations, leaderboards and the campaign dashboards (see Getting started → Analytics). Creator scorecards arrive with Phase 10.
