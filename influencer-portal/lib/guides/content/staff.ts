import type { Guide } from "../types";

export const ALL_STAFF: Guide = {
  slug: "getting-started",
  audience: "all_staff",
  title: "Getting started (all staff)",
  summary:
    "Signing in, finding your way around the admin console, notifications, and keeping your account safe.",
  sections: [
    {
      id: "sign-in",
      title: "Signing in",
      blocks: [
        {
          p: "The admin console is for Eduwit staff only. Creators and agencies use their own portal.",
        },
        {
          steps: [
            "Open the staff sign-in page and enter your work email and password, or use **Continue with Google** with your Eduwit Google account.",
            "Enter the **6-digit code** we email you. Every staff sign-in is confirmed this way, even after Google.",
            "Tick **Trust this device for 30 days** on your own laptop to skip the code there. Never tick it on a shared computer.",
          ],
        },
        {
          tip: "First time, or forgot your password? Use **First time, or forgot your password?** on the sign-in page. A Super Admin must have invited you first.",
        },
        {
          p: "You are signed out after a period of inactivity (set by the Super Admin under Settings → Security). Your work is saved as you go, so just sign in again.",
        },
      ],
    },
    {
      id: "layout",
      title: "Finding your way around",
      blocks: [
        {
          list: [
            "**Sidebar**: the modules your role can use. Items you cannot use are hidden, not greyed out.",
            "**Command palette**: press **Ctrl K** (⌘K on a Mac) to jump to any page or creator by name.",
            "**Overview**: your setup checklist, your open tasks and the health of background jobs.",
            "**Help**: these guides. Each role has its own guide; you can read the others too.",
          ],
        },
        {
          table: {
            head: ["Area", "What it is for"],
            rows: [
              [
                "[Creators](/admin/creators)",
                "The creator CRM: pipeline, profiles, outreach, KYC, approvals, imports",
              ],
              [
                "[Campaigns](/admin/campaigns)",
                "Campaign builder, invitations and the creator marketplace",
              ],
              ["[Applications](/admin/applications)", "Creator applications and negotiation"],
              [
                "[Deals](/admin/deals)",
                "Compensation terms: builder, simulator, proposals, amendments",
              ],
              ["[Tasks](/admin/tasks)", "Follow-ups assigned to you and your team"],
              ["[Agencies](/admin/agencies)", "Talent agencies and the creators they manage"],
              ["[KYC](/admin/kyc)", "PAN and bank details waiting for verification"],
              [
                "[Settings](/admin/settings)",
                "Business rules: attribution, compensation, finance, security…",
              ],
              ["[Audit log](/admin/audit)", "Who changed what, and when"],
            ],
          },
        },
      ],
    },
    {
      id: "privacy",
      title: "Privacy rules everyone must know",
      blocks: [
        {
          list: [
            "Students' phone numbers and email addresses are **never** shown to creators or agencies. The system masks them; do not copy them into messages.",
            "Creators' PAN and bank details are encrypted. Most staff see them masked. Finance can reveal them with a reason, and every reveal is recorded.",
            "Everything you create, change or delete is written to the audit log.",
          ],
        },
      ],
    },
    {
      id: "account",
      title: "Your account and devices",
      blocks: [
        {
          p: "Open [Account](/admin/account) to see where you are signed in. Sign out any device you do not recognise, or **Sign out all other devices**. Trusted devices are listed there too; **Forget** one to require the code again.",
        },
        {
          warning:
            "If you think your password leaked, change it and sign out all other devices at once. Then tell a Super Admin.",
        },
      ],
    },
    {
      id: "notifications",
      title: "Notifications",
      blocks: [
        {
          p: "You get in-app and email notifications for work assigned to you: new applications on campaigns you own, creators accepting or declining deal terms, tasks assigned to you. Until the Super Admin turns on live sending, emails stay inside the system.",
        },
      ],
    },
  ],
};

export const SUPER_ADMIN: Guide = {
  slug: "super-admin",
  audience: "super_admin",
  title: "Super Admin: setting up and running the portal",
  summary:
    "First-time setup, staff and roles, business settings, monitoring, and what to check before go-live.",
  sections: [
    {
      id: "first-setup",
      title: "First-time setup checklist",
      blocks: [
        {
          p: "The [Overview](/admin) page shows this checklist with live status. Work through it in order:",
        },
        {
          steps: [
            "**Organisation details**: Settings → Organisation. Enter the legal name, address, GSTIN and PAN. They are printed on contracts, statements and payout advice.",
            "**Invite your team**: [Staff](/admin/staff) → **Invite staff**. Pick each person's roles (see the table below).",
            "**Name an Authorised Signatory**: edit a staff member and tick **Authorised Signatory** with their designation. Contracts cannot be countersigned without one.",
            '**Review business settings**: go through every group in [Settings](/admin/settings). Items marked "confirm with CA" or "confirm with counsel" stay flagged until someone confirms them.',
            "**Confirm tax defaults with your CA**: the TDS sections (194H 2% on commission, 194J 10% on fees, 20% without PAN, 194R on barter) are defaults until confirmed.",
            "**Connect providers** (done by the developer at deployment): an email provider, WhatsApp, and then **live mode** so notifications actually leave the system.",
          ],
        },
      ],
    },
    {
      id: "roles",
      title: "Roles and what they can do",
      blocks: [
        {
          table: {
            head: ["Role", "Can"],
            rows: [
              ["Super Admin", "Everything, including staff, settings, audit and system status"],
              [
                "Influencer Manager",
                "Creators, outreach, campaigns, applications, deals, agencies; reads leads, ledger and payouts",
              ],
              [
                "Content Reviewer",
                "Reviews submissions, overrides compliance checks with a reason, verifies live posts and edits the banned-claims list",
              ],
              [
                "Finance",
                "KYC verification and reveal, TDS and GST settings, ledger, payouts; read-only elsewhere",
              ],
              ["Viewer", "Analytics and scorecards, read-only"],
            ],
          },
        },
        {
          p: "A person can hold several roles; their permissions add up. **Authorised Signatory** is a separate flag that lets the person countersign contracts, whatever their role.",
        },
        {
          tip: "Suspending a staff member signs them out of every device at once. Use **Sign out everywhere** if a laptop is lost.",
        },
      ],
    },
    {
      id: "settings",
      title: "Business settings",
      blocks: [
        {
          p: "Everything the business might change is a setting, not code. Each setting is validated, versioned (you can see who changed what and when), and some need a confirmation before they count as final.",
        },
        {
          table: {
            head: ["Group", "Examples"],
            rows: [
              [
                "Attribution",
                "Attribution window (default 90 days), first-touch model, duplicate and self-referral rules",
              ],
              [
                "Lead visibility",
                "Which lead fields creators see (phone and email are always masked)",
              ],
              [
                "Compensation",
                "Hold days, refund window, penalty cap, default commission base, GST on Eduwit's commission",
              ],
              [
                "Contracts",
                "Signing code channels and limits, negotiation reminders, legal-review gate",
              ],
              [
                "Finance",
                "Payout cycle, two-person approval, KYC needed for payout, GST rate and SAC, bank export columns",
              ],
              [
                "Creators",
                "Dormancy, auto-approval of sign-ups, course pass mark, KYC required to submit onboarding",
              ],
              [
                "Content",
                "Revision limit, disclosure terms and platforms, metric checkpoints, reminder and escalation days, upload sizes",
              ],
              ["Security", "Idle sign-out, trusted-device length"],
              ["Retention and privacy", "How long records are kept"],
            ],
          },
        },
        {
          warning:
            "Changing compensation defaults affects new calculations only; agreed deal terms are never changed by a setting.",
        },
      ],
    },
    {
      id: "contracts-setup",
      title: "Contracts: clause library, legal review and signing",
      blocks: [
        {
          p: "Contracts are assembled from the [Clause library](/admin/contracts/clauses) by [templates](/admin/contracts/templates), with every number filled in from the deal. The library ships with 20 professionally structured **draft** clauses, each starting with “DRAFT — requires legal review before use”.",
        },
        {
          steps: [
            "Have counsel review each clause. Edit the wording (remove the draft marker once approved) and save: every save is a new version, and contracts already generated keep the version they used.",
            "On each clause, click **Mark as legally reviewed**. Only Super Admins can. The library's **Not reviewed** filter shows what is left.",
            "While the **legal-review gate** is on (Settings → Contracts → Signing and reminders), a contract containing any unreviewed clause cannot be sent. Leave it on.",
            "Check the default template in [Templates](/admin/contracts/templates): clause order, conditions (for example exclusivity only when the deal has an exclusivity fee) and the preview for each sample deal type.",
            "Make sure an **Authorised Signatory** is named (Staff → edit → Authorised Signatory, with designation). Only they can countersign.",
            "In Settings → Contracts, choose the signing-code channels (email, WhatsApp or both), code expiry and attempts, negotiation reminder days and expiry reminders (30, 15 and 7 days by default).",
          ],
        },
        {
          warning:
            "Stamp duty and the enforceability of electronically signed contracts depend on the state and the type of contract. Confirm both with counsel; each contract has an optional stamp duty reference.",
        },
      ],
    },
    {
      id: "countersign",
      title: "Countersigning (Authorised Signatory)",
      blocks: [
        {
          steps: [
            "When a creator signs, you are notified. Open the contract from the notification or [Contracts](/admin/contracts) (status **Signed by creator**).",
            "Read the document, tick each section, type your full name, accept the statement and click **Send code**. Enter the 6-digit code from your email and click **Countersign**.",
            "The contract becomes **Active**, the deal becomes active, and the signed PDF with its signature certificate is stored and emailed to every party.",
          ],
        },
        {
          p: "Every download of a signed PDF re-checks two hashes: the document against the hash each signature recorded, and the PDF against the hash stored when it was made. If either differs the contract is flagged as invalid and nothing is served.",
        },
      ],
    },
    {
      id: "monitoring",
      title: "Monitoring and the audit log",
      blocks: [
        {
          list: [
            "[System status](/admin/system): the job queue (notifications, deal creation after accepted offers…), scheduled tasks and sending providers. A job that keeps failing is retried with back-off; you can retry a dead job by hand.",
            "[Audit log](/admin/audit): filter by person, entity and date. PAN and bank numbers are redacted in the log itself.",
          ],
        },
      ],
    },
    {
      id: "go-live",
      title: "Before go-live",
      blocks: [
        {
          p: "The portal is built and tested against a local copy of the database. Going live (applying the database changes to the shared Supabase project, connecting attribution, deploying) is done by the developer from the go-live runbook, and only after your written approval.",
        },
        {
          list: [
            "Legal review of the platform terms, privacy notice and the compliance course.",
            "CA confirmation of the TDS sections and GST settings.",
            "Email and WhatsApp providers, the domain, hosting and error monitoring accounts.",
          ],
        },
      ],
    },
  ],
};

export const INFLUENCER_MANAGER: Guide = {
  slug: "influencer-manager",
  audience: "influencer_manager",
  title: "Influencer Manager: creators, campaigns, deals and contracts",
  summary:
    "Running the creator pipeline, onboarding and approving creators, building campaigns, negotiating, setting up deals, and contracts.",
  sections: [
    {
      id: "pipeline",
      title: "The creator pipeline",
      blocks: [
        {
          p: "[Creators](/admin/creators) shows every creator as a table or a kanban board. Stages run Prospect → Contacted → Negotiating → Contracted → Onboarding → Active, with Paused, Dormant and Archived. Drag cards between columns, or change the stage from the creator's page.",
        },
        {
          list: [
            "**Filters**: platform, followers, topic, language, city or state, tier, owner and status. Save a filter as a view and share it with the team.",
            "**Bulk actions**: select rows to tag, assign an owner, move stage or invite.",
            "**Import**: [Import prospects](/admin/creators/import) from a CSV (up to 5,000 rows). The file is checked first; duplicates by handle, phone, email or platform handle are skipped and listed in a downloadable report.",
            "**Dormant**: active creators with no activity for the configured number of days are flagged automatically and return to active when they do something.",
          ],
        },
      ],
    },
    {
      id: "creator-360",
      title: "A creator's page (Creator 360)",
      blocks: [
        {
          p: "Open a creator to see the overview, profile, KYC (masked), outreach timeline, tasks, deals, linked agencies and history. From here you can:",
        },
        {
          list: [
            "**Log outreach** (channel, outcome, notes) and set a follow-up date; overdue follow-ups appear on your Overview.",
            "**Add tasks** for yourself or a colleague.",
            "**Invite** the creator to sign up; they get an email and land in the onboarding wizard.",
            "**Start a deal** from the Deals tab.",
            "Download the **media kit** (PDF) to share with partners.",
          ],
        },
      ],
    },
    {
      id: "onboarding",
      title: "Onboarding and approval",
      blocks: [
        {
          p: "Creators complete a wizard: profile, platforms, KYC (PAN and bank, encrypted), terms, and a short compliance course with a quiz. When they submit, they appear in [Approvals](/admin/creators/approvals).",
        },
        {
          steps: [
            "Open the creator from the approvals queue and check the profile and platforms.",
            "Choose **Approve**, **Ask for changes** (with a note) or **Decline** (with a reason). The creator is told in every case.",
          ],
        },
        {
          tip: "Settings → Creators can auto-approve self sign-ups above a follower count. Invited creators are still reviewed.",
        },
      ],
    },
    {
      id: "campaigns",
      title: "Campaigns, invitations and applications",
      blocks: [
        {
          steps: [
            "[New campaign](/admin/campaigns/new): name, objective, dates, budget and slots, programmes from the catalogue, eligibility (followers, platforms, topics, languages, geography) and deliverables.",
            "Pick a **default deal preset**: accepted applications become deals starting from it.",
            "**Open** the campaign for the marketplace, or make it invite-only and **invite** creators.",
            "Review [Applications](/admin/applications): shortlist, reject with a reason, or **make a counter-offer**. One offer is open at a time and only the other side can accept it.",
          ],
        },
        {
          p: "When an offer is accepted, the deal is created at once with the agreed terms (version 1, already accepted by both sides). Open it from the application with **Open deal**.",
        },
        { warning: "Creators never see the budget or internal notes of a campaign." },
      ],
    },
    {
      id: "deals",
      title: "Deals: building compensation",
      blocks: [
        {
          p: "A deal holds a creator's compensation terms. Start one from [New deal](/admin/deals/new) (or a creator's Deals tab): pick the creator, an optional campaign, the dates and a **preset** to start from. You then land in the **builder**.",
        },
        {
          table: {
            head: ["Section", "What you can set"],
            rows: [
              [
                "Fixed fees and milestones",
                "Lump sum, per deliverable, per unit or retainer; milestones by % or amount, each paid on a trigger (signing, brief, concept, draft, live, N days after live, a metric threshold, campaign end, a date, or manual release), with payment terms and what happens if a deliverable is cancelled",
              ],
              [
                "Commission",
                "Flat per lead, qualified lead, application or enrolment; % of programme fee; % of Eduwit's commission (gross or net of GST). Scope (programmes, universities, levels, links, deliverables), slabs (marginal or retroactive), caps, confirmation (immediate, after a hold, or when Eduwit is paid), clawback window and dates",
              ],
              [
                "Minimum guarantees",
                '"At least ₹X per month or per deal", topped up against commission',
              ],
              [
                "Recoupment",
                "Commission pays out only after it exceeds all or part of the fixed fee",
              ],
              [
                "Bonuses",
                "Targets on enrolments, leads, views, on-time delivery or leaderboard rank, per deal, month, campaign or dates",
              ],
              [
                "Penalties",
                "Late delivery, missed deliverable, disclosure, breach clawback. Always proposals that a manager approves",
              ],
              ["Additional fees", "Usage rights, exclusivity, whitelisting, reimbursements"],
              ["Non-cash", "Barter value for reporting; never paid out"],
            ],
          },
        },
        {
          p: "The **earnings simulator** next to the builder updates as you type: enter a scenario (leads, enrolments, views, days late…) and see each component, TDS, GST and the net payout, plus Eduwit's revenue, cost per enrolment and margin. Creators never see the Eduwit figures.",
        },
        {
          tip: "Use **Save as preset** to reuse a set-up. Manage presets under [Deal presets](/admin/deals/presets); system presets are fixed, copy one to change it.",
        },
      ],
    },
    {
      id: "deal-flow",
      title: "Deals: proposing, negotiating, activating",
      blocks: [
        {
          steps: [
            "**Save terms**, then **Send terms to creator** (add a note if useful). The deal moves to Proposed and the creator is notified.",
            "The creator, or their agency with the negotiate grant, **accepts** or **declines with a reason**. A decline puts the terms back in your builder (status Negotiating); revise and send again.",
            "Once accepted, the deal is **Agreed** and the terms are locked as a version.",
            "The countersigned contract makes the deal **Active** (see Contracts below). For a contract signed outside the portal, use **Activate** and give the reason.",
            "Close a deal with **Mark completed**, or **Terminate** with a reason.",
          ],
        },
      ],
    },
    {
      id: "amendments",
      title: "Amendments and the dry run",
      blocks: [
        {
          p: "Agreed terms never change in place. To change them, click **Amend terms**: the current terms open in the builder as a draft amendment while the old terms stay in force.",
        },
        {
          steps: [
            "Edit and **Save terms**.",
            "Open the **Dry run** tab, choose when the amendment takes effect and a scenario, and run it. You see the creator's earnings under the current terms, with the amendment, and every line that changes.",
            "**Propose amendment**. When the creator accepts, the new version applies from the chosen time; everything earned before it keeps the old terms.",
          ],
        },
        { p: "The **Versions** tab lists every version with its terms, who answered and why." },
      ],
    },
    {
      id: "contracts",
      title: "Contracts: generating and sending",
      blocks: [
        {
          p: "A contract is generated from a deal's agreed terms. For an accepted campaign application the draft is created automatically; otherwise open the deal and click **Generate contract**.",
        },
        {
          steps: [
            "Choose the template (the campaign's template is preselected, else the default), who is paid (the creator, or an agency the creator allowed to negotiate and sign), the dates and, if counsel asked for it, a stamp duty reference.",
            "**Generate draft**. Every amount, milestone, commission rule, bonus, penalty and fee is written from the deal: you never type numbers into a contract.",
            "If details are missing (for example the creator's legal name or address) a banner lists them. Fix them on the creator's profile or KYC, then **Regenerate**.",
            "**Send to creator**. The creator (and their negotiating agency) is notified and has until the negotiation deadline to respond; reminders go out automatically.",
          ],
        },
        {
          table: {
            head: ["Status", "Meaning"],
            rows: [
              ["Draft", "Only Eduwit sees it"],
              [
                "Sent / In negotiation",
                "The creator is reviewing, commenting or asking for changes",
              ],
              ["Ready to sign", "Every request answered; this version is final"],
              ["Signed by creator", "Waiting for the Authorised Signatory"],
              ["Active", "Both signed; the deal is active and the signed PDF is stored"],
              ["Completed / Terminated / Expired", "Ended (a reason is recorded for termination)"],
              ["Void / Superseded", "Withdrawn before signing, or replaced by a signed amendment"],
            ],
          },
        },
      ],
    },
    {
      id: "contract-negotiation",
      title: "Contracts: negotiating",
      blocks: [
        {
          list: [
            "**Comments**: anyone can comment on any clause; reply and resolve threads under each clause on the Document tab.",
            "**Suggested wording**: the creator can propose new wording for clauses flagged **negotiable**. On the Change requests tab you see a word-by-word diff.",
            "**Compensation counter-offers**: the creator proposes new numbers (fee, rates, bonus amounts) through a structured form. You see each number from → to.",
          ],
        },
        {
          p: "For each request choose **Accept**, **Counter** (your own wording or numbers, with a message) or **Decline** (with a reason). Accepting or countering creates a new contract version straight away; for compensation, the deal's terms change first and the contract is regenerated from them, so the deal stays the single source of truth.",
        },
        {
          p: "The **Versions** tab compares any two versions section by section. When every request is answered, click **Mark ready to sign**.",
        },
        {
          tip: "Wording already agreed for a negotiable clause is kept when you regenerate the contract after other changes.",
        },
      ],
    },
    {
      id: "contract-changes",
      title: "Contracts: amendments, renewals and expiry",
      blocks: [
        {
          list: [
            "**Amendment**: first amend the deal's terms (Amend terms → propose → creator accepts). Then on the active contract click **Create amendment**: a new contract linked to the original. When both parties sign it, the original becomes **Superseded**.",
            "**Renewal**: on an active or ended deal click **Renew**, pick the new dates, and send the copied terms to the creator. Once accepted, generate its contract; it is marked as a renewal.",
            "**Expiry**: contracts with an expiry date send reminders 30, 15 and 7 days before (Settings → Contracts) and move to **Expired** after the date.",
            "**Void** a contract that should not be signed, or **Terminate** / **Mark completed** an active one; each needs a reason.",
          ],
        },
      ],
    },
    {
      id: "briefs",
      title: "Briefs",
      blocks: [
        {
          p: "Every deal gets one brief. For a deal from an accepted application, a draft brief and its deliverables are created at once; for other deals open the deal's **Content** tab and click **Create brief**.",
        },
        {
          steps: [
            "The draft is filled from the campaign's brief template (or the default), the agreed deliverables and the catalogue: approved claims are written from the programmes' fees, mode, recognitions and eligibility.",
            "Edit it in [Briefs](/admin/briefs): objective, audience, key messages, disclosure rules, do's and don'ts, tone, languages, hashtags, references, files and FAQs. **Save** as you go.",
            "**Publish brief**. The creator (and their agency with the deliverables permission) is told and must acknowledge it before starting. Acknowledging starts the deliverables and can trigger a milestone.",
            "To change it later, edit and **Publish new version** with a note on what changed; the creator acknowledges the new version.",
            "Answer the creator's questions in the **Questions** panel; open questions show on the briefs list.",
          ],
        },
        {
          p: "[Templates](/admin/briefs/templates) hold the defaults copied into new briefs, plus the stages and due-date offsets for new deliverables. Each campaign can pick its template in the campaign builder.",
        },
      ],
    },
    {
      id: "deliverables",
      title: "Deliverables",
      blocks: [
        {
          p: "Deliverables move through: brief acknowledged → concept → draft → (scheduled) → live → verified → metrics → completed. Each stage can be switched off per deliverable before work starts, under the deliverable's **Settings** tab.",
        },
        {
          list: [
            "**Due dates** come from the template's offsets and can be changed per deliverable. Reminders go out before each date; overdue work is flagged to the creator on day 1 and to you after 2 days (Settings → Content).",
            "**Rule id**: if the deal's compensation names a deliverable (a milestone paid when it goes live, or a late-delivery penalty), enter that id so the right rules apply.",
            "**Extra revision rounds** a reviewer requests come to you (any role with deal editing) to approve or reject.",
            "**Complete** a deliverable when everything is in, or **Cancel** it with a reason.",
          ],
        },
      ],
    },
    {
      id: "penalties",
      title: "Penalty proposals",
      blocks: [
        {
          p: "When a deliverable goes live late, is cancelled or fails its disclosure check, the deal's penalty rules are worked out and appear as proposals in [Penalties](/admin/content/penalties) and on the deal's Content tab. Nothing is charged automatically.",
        },
        {
          list: [
            "**Approve** a proposal you agree with; it is applied with the deal's ledger and the creator is told.",
            "**Reject** with a reason when there is a good explanation.",
            "If the facts change (for example the due date is moved), the proposal is updated or withdrawn while it is still open.",
          ],
        },
      ],
    },
    {
      id: "agencies",
      title: "Agencies",
      blocks: [
        {
          p: "[Agencies](/admin/agencies) lists talent agencies. Create one, invite its owner, and the owner can request links with creators. Each creator decides what the agency may do: view, act on deliverables, negotiate and sign, view earnings. Payouts always go to the creator's own bank account.",
        },
      ],
    },
  ],
};

export const CONTENT_REVIEWER: Guide = {
  slug: "content-reviewer",
  audience: "content_reviewer",
  title: "Content Reviewer: reviewing content and verifying posts",
  summary:
    "The review queue, compliance checks and overrides, comments on videos and images, revision limits, live verification and the banned-claims list.",
  sections: [
    {
      id: "queue",
      title: "Your queue",
      blocks: [
        {
          p: "[Content](/admin/content) lists every open deliverable as a list or a board. The tabs along the top filter it:",
        },
        {
          table: {
            head: ["Tab", "Shows"],
            rows: [
              ["Deliverables", "Everything open, sorted by the next due date"],
              ["Review queue", "Concepts and drafts waiting for you, and live posts to verify"],
              [
                "Overdue",
                "Work past its due date (the creator is reminded on day 1; the deal owner after 2 days)",
              ],
              ["Live posts", "Everything that has gone live"],
              ["Banned claims", "The list every submission is scanned against"],
              ["Penalties", "Penalties the deal rules propose, for a manager to approve"],
            ],
          },
        },
        {
          tip: "You're notified when work is submitted to a deal you own (or to any deal without an owner).",
        },
      ],
    },
    {
      id: "review",
      title: "Reviewing a submission",
      blocks: [
        {
          p: "Open a deliverable from the queue. The **Review** tab shows the latest concept or draft: the script or caption, the files and any link, with the checks and the decision panel beside it.",
        },
        {
          steps: [
            'Read the **checks**. Every submission is scanned when it is sent: **banned claims** (a blocking match stops approval; a warning is for you to judge) and, for drafts, the **disclosure** (for example #ad or "paid partnership" on platforms that require it).',
            "Watch or look through the files. Tick **At the current video time** to pin a comment to a moment; drag on an image to mark an area. Comments are numbered on the image; click one to jump to it.",
            "To approve, every failed check must be fixed or **overridden** (you give a reason; it is recorded). The last approval before posting also needs the **ASCI checklist** ticked.",
            "Or **Request changes** with a note saying what to change. Each request uses one revision round.",
          ],
        },
        {
          list: [
            "The revision limit is set per deliverable (2 by default, Settings → Content). At the limit, **Request an extra round** with a reason and an optional fee for the creator; a manager approves it.",
            "If the scan did not run (the panel says so), use **Run the check again**. Run it again after changing the banned-claims list, too.",
            "Earlier rounds stay below, each with its comments and decision.",
          ],
        },
        {
          warning:
            "Override a check only when you are sure the content is fine in context, for example a banned phrase quoted to debunk it.",
        },
      ],
    },
    {
      id: "live",
      title: "Verifying live posts",
      blocks: [
        {
          p: "When the creator submits the live link (validated for the platform; YouTube links show the video's title and thumbnail), it appears in the review queue and the **Live** tab.",
        },
        {
          steps: [
            "Open the link and check: it is live and public, the disclosure is there and clear, and it matches the approved version.",
            "**Verify** if all three are true. Otherwise untick what is wrong, say why, and **Ask for a fix**: the creator submits a corrected link.",
          ],
        },
        {
          p: "A missing disclosure is recorded on the deliverable and, if the deal has a disclosure penalty, a penalty is proposed for a manager to approve.",
        },
      ],
    },
    {
      id: "metrics",
      title: "Metrics",
      blocks: [
        {
          p: "After going live the creator reports views, reach, likes and more at the checkpoints (24 hours, 7 days and 30 days by default, Settings → Content), with screenshots of their insights. They appear on the **Metrics** tab. Missing metrics are flagged to the deal owner after the grace period.",
        },
      ],
    },
    {
      id: "claims",
      title: "The banned-claims list",
      blocks: [
        {
          p: '[Banned claims](/admin/content/claims) is the list every concept and draft is scanned against. It starts with common problem phrases for education promotion (guaranteed placements, "no exams", unverifiable superlatives): review it and make it yours.',
        },
        {
          list: [
            "A **phrase** matches as whole words, in any case and with any spacing.",
            "A **pattern** is a regular expression for variations (for example `100\\s*%\\s*placement`). Patterns that could be slow are refused.",
            "**Blocks approval** stops approval until fixed or overridden; **Warning** only flags it.",
            "Use **Try a sentence** to see what the scan would flag before saving.",
          ],
        },
      ],
    },
  ],
};

export const FINANCE: Guide = {
  slug: "finance",
  audience: "finance",
  title: "Finance: KYC, tax settings and payouts",
  summary:
    "Verifying creators' KYC, the TDS and GST set-up, and the ledger and payouts that arrive in Phase 7.",
  sections: [
    {
      id: "kyc",
      title: "KYC verification",
      blocks: [
        {
          steps: [
            "Open [KYC](/admin/kyc) to see creators waiting for review.",
            "Check the PAN, the name on the PAN and the bank account against the uploaded proof.",
            "Use **Reveal** to see a full number when you need it. You must give a reason; every reveal is recorded in the audit log.",
            "**Verify**, or send it back with a note. If a creator later changes their PAN or bank details, the KYC returns to the queue.",
          ],
        },
        { warning: "Never copy full PAN or bank numbers into messages, tasks or notes." },
      ],
    },
    {
      id: "tax",
      title: "TDS and GST set-up",
      blocks: [
        {
          table: {
            head: ["Section", "Applies to", "Default rate", "FY threshold"],
            rows: [
              ["194H", "Commission", "2% (20% without PAN)", "₹20,000"],
              [
                "194J",
                "Fixed fees, milestones, bonuses, usage and exclusivity fees",
                "10% (20% without PAN)",
                "₹50,000",
              ],
              [
                "194R",
                "Barter / in-kind value (Eduwit's liability, not deducted)",
                "10%",
                "₹20,000",
              ],
            ],
          },
        },
        {
          list: [
            "TDS is computed on amounts **excluding GST**.",
            "When a creator's total for the financial year first crosses a threshold, TDS also covers that year's earlier untaxed amounts.",
            "GST is added for creators with a verified GSTIN (rate and SAC under Settings → Finance); reimbursements are not subject to it.",
          ],
        },
        {
          warning:
            'All of these are defaults marked "confirm with CA". Until confirmed, the simulator shows a banner, and payouts can be held (Settings → Finance → Payouts).',
        },
      ],
    },
    {
      id: "simulator",
      title: "Reading the deal simulator",
      blocks: [
        {
          p: "On any deal in [Deals](/admin/deals), the simulator shows gross earnings, TDS per section, GST and the net payout for a scenario, using the current TDS table. Use it to check how a deal will be taxed before it is proposed.",
        },
      ],
    },
    {
      id: "coming",
      title: "Coming with the ledger (Phase 7)",
      blocks: [
        {
          list: [
            "The creator ledger: accrued → confirmed → payable → in payout batch → paid, plus reversals, holds and clawbacks.",
            "Recording Eduwit's commission receipts and reconciliation against accrued commission.",
            "Payout batches with a gross / TDS / GST / net summary, optional two-person approval, bank bulk-upload export, UTR marking and payment advice PDFs.",
            "Quarterly TDS summaries and Form 16A uploads for creators to download.",
          ],
        },
      ],
    },
  ],
};

export const VIEWER: Guide = {
  slug: "viewer",
  audience: "viewer",
  title: "Viewer",
  summary: "Read-only access to analytics and scorecards.",
  sections: [
    {
      id: "access",
      title: "What you can see",
      blocks: [
        {
          p: "The Viewer role is read-only. Analytics dashboards and creator scorecards arrive in Phase 9; until then your sidebar shows the Overview, your account and these guides.",
        },
      ],
    },
  ],
};
