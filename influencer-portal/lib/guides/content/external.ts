import type { Guide } from "../types";

export const CREATOR: Guide = {
  slug: "creator",
  audience: "creator",
  title: "Creator guide",
  summary:
    "Getting set up, finding campaigns, agreeing your deal terms, briefs and deliverables, and working with an agency.",
  sections: [
    {
      id: "sign-in",
      title: "Signing in",
      blocks: [
        {
          steps: [
            "Go to the sign-in page and enter the email Eduwit invited (or the one you signed up with).",
            "We email you a one-time **6-digit code**. Enter it within 10 minutes. No password needed.",
            "You can also use **Continue with Google** with the same email address.",
          ],
        },
        {
          tip: "New here? Use **Sign up** on the sign-in page. Eduwit reviews new sign-ups before you can take part in campaigns.",
        },
      ],
    },
    {
      id: "onboarding",
      title: "Setting up your account",
      blocks: [
        {
          p: "The [onboarding wizard](/creator/onboarding) walks you through six steps. You can stop and come back at any time.",
        },
        {
          table: {
            head: ["Step", "What you do"],
            rows: [
              ["Profile", "Your name, bio, city, languages and topics"],
              ["Platforms", "Your Instagram, YouTube or other channels, with followers and average views"],
              [
                "KYC",
                "Your PAN and bank account for payouts. They are encrypted and only Eduwit's finance team can see them in full",
              ],
              ["Terms", "Read and accept the creator platform terms and privacy notice"],
              ["Compliance course", "A short course on honest claims and disclosing paid partnerships, with a quiz"],
              ["Submit", "Send your profile for review. You'll be told when you're approved, or what to change"],
            ],
          },
        },
        {
          p: "After approval you can keep your [profile](/creator/profile) and [KYC](/creator/kyc) up to date. If you change your PAN or bank account, Eduwit checks it again before the next payout.",
        },
      ],
    },
    {
      id: "campaigns",
      title: "Finding and joining campaigns",
      blocks: [
        {
          list: [
            "[Campaigns](/creator/campaigns) → **Open**: campaigns you are eligible for, with the programme, deliverables, how you are paid, the deadline and slots left.",
            "**Invited**: campaigns Eduwit invited you to. Accept, decline, or reply with your own terms.",
            "**My applications**: everything you applied for and where it stands.",
          ],
        },
        {
          steps: [
            "Open a campaign and write a short pitch: why your audience fits.",
            "Propose your terms (for example a fixed fee for the deliverables) and add links to sample work.",
            "Eduwit may shortlist you, make a counter-offer, or decline with a reason. You can counter back and message them in the application.",
            "When one side accepts the other's offer, your **deal** is created with exactly those terms. Open it with **View my deal**.",
          ],
        },
      ],
    },
    {
      id: "deals",
      title: "Your deals and how you earn",
      blocks: [
        {
          p: "[My deals](/creator/deals) lists your deals. A deal says exactly how you earn: fixed fees and when each part is paid, commission per lead or enrolment, bonuses, any penalties, and extra fees such as usage rights. Everything is written out in plain language.",
        },
        {
          steps: [
            "When Eduwit sends you terms, the deal shows **Needs your answer**.",
            "Read the terms. Use the **earnings simulator** to try a scenario (for example 20 leads and 3 enrolments) and see what you would earn, the TDS deducted and your net payout.",
            "**Accept terms**, or **Decline** and say what you would like changed. Eduwit will send revised terms.",
          ],
        },
        {
          list: [
            "Once you accept, those terms are locked as a version. Any later change is an **amendment** that you accept or decline the same way; earnings before the amendment keep the old terms.",
            "Commission is usually **confirmed when Eduwit receives its commission** from the university. If an enrolment is cancelled within the refund window, that commission is clawed back.",
            "Penalties are never deducted automatically: a manager reviews and approves each one.",
          ],
        },
        {
          tip: "The simulator is an estimate for planning. [Earnings](/creator/earnings) shows what you actually earn.",
        },
      ],
    },
    {
      id: "contracts",
      title: "Your contracts: review, negotiate and sign",
      blocks: [
        {
          p: "When your deal is agreed, Eduwit sends you its contract. [Contracts](/creator/contracts) lists them; **Your turn** marks the ones waiting for you. The numbers in the contract come straight from your deal.",
        },
        {
          steps: [
            "Read each clause. Tap **Comment** under any clause to ask a question.",
            "On clauses marked **Negotiable**, tap **Suggest wording** and edit the clause as you'd like it to read.",
            "To ask for different money (fee, rates, bonuses), open **Change requests** → **Propose different terms** and change the numbers.",
            "Eduwit accepts, counters or declines each request. Every change makes a new version; **Versions** shows exactly what changed.",
            "When the contract is **Ready to sign**, tick each section to confirm you've read it, type your full legal name (as on your PAN), accept the statement, tap **Send code**, and enter the 6-digit code we send you. That is your signature.",
            "After Eduwit countersigns, you receive the signed PDF by email and can download it from the contract at any time.",
          ],
        },
        {
          list: [
            "The signed PDF ends with a signature certificate: who signed, when (in IST and UTC), how the code was sent, and a fingerprint (SHA-256) of the exact document.",
            "If a contract changes after you open it, signing is refused and you're asked to review the new version.",
            "Respond before the deadline shown on the contract; you'll get reminders.",
          ],
        },
      ],
    },
    {
      id: "briefs",
      title: "Your briefs",
      blocks: [
        {
          p: "For each agreed deal, Eduwit sends a brief: what to make, the messages, the claims you may use, the rules (including how to disclose the partnership) and the due dates. [Briefs](/creator/briefs) lists them.",
        },
        {
          steps: [
            "Read the whole brief, tick the box and tap **Acknowledge brief**. Your deliverables start from here.",
            "Each post in the brief shows its own tracking link and QR code. Use exactly that link in the post so its leads are credited to you.",
            "Ask anything under **Questions**; Eduwit answers there.",
            "If Eduwit updates the brief, you'll be told what changed and asked to acknowledge the new version.",
          ],
        },
      ],
    },
    {
      id: "deliverables",
      title: "Your deliverables",
      blocks: [
        {
          p: "[Deliverables](/creator/deliverables) shows what to do next, what is with Eduwit and what is done. Open one to see **Your next step**.",
        },
        {
          steps: [
            "**Concept**: send your idea, script or storyboard (text, files or a link).",
            "**Draft**: send the edit and exactly the caption you will post, including the disclosure (for example #ad). Large videos upload in pieces and resume if your connection drops.",
            "Eduwit approves or asks for changes, with comments pinned to moments in your video or areas of your images. Reply to comments and send the next version.",
            "**Go live**: post it, then submit the public link and the date you posted.",
            "**Metrics**: at each checkpoint (for example 24 hours, 7 days and 30 days after posting) enter your numbers and add screenshots of your insights.",
          ],
        },
        {
          list: [
            "Every submission is checked automatically against the claims you must never make and, for drafts, the disclosure rules.",
            "You get reminders before due dates. Late or missing work, or a post without the disclosure, can carry a penalty under your deal, so tell Eduwit early if something is holding you up.",
            "Eduwit checks your live post. If something is wrong (for example the disclosure is missing), fix the post and submit the corrected link.",
          ],
        },
      ],
    },
    {
      id: "links",
      title: "Your links and QR codes",
      blocks: [
        {
          p: "Every post in your deals gets its own tracking link and code automatically: you'll find it on the post in [Deliverables](/creator/deliverables) and next to each post in the brief. [Links](/creator/links) lists them all and lets you make extra ones (for your bio, a story series or another programme). Every student who enquires through a link is credited to you.",
        },
        {
          steps: [
            "Pick the deal, and if you like the post and the programme. Choose where the link goes: WhatsApp (Eduwit's counsellor bot, with a ready-made message), your page on the Eduwit website, or another https page.",
            "Say where you'll share it (Instagram, YouTube and so on) and add a label only you see.",
            "Tap **Create link**. Copy the short link, or download the QR code as PNG or SVG for videos, stories and print.",
          ],
        },
        {
          list: [
            'Each link shows its clicks and leads. Switch a link off when a post comes down; visitors then see a polite "no longer active" page.',
            "You can make links once a deal is agreed.",
            "Clicks from link-preview bots are not counted.",
          ],
        },
      ],
    },
    {
      id: "leads",
      title: "Your leads",
      blocks: [
        {
          p: "[Leads](/creator/leads) shows every student who enquired through your links or code, usually within a minute. Phone numbers and emails are always masked (for example 98XXXXXX21); Eduwit's counsellors contact the student, not you.",
        },
        {
          list: [
            "The board groups leads by stage: new, qualifying (talking to the WhatsApp bot), qualified, allocated to a counsellor, in counselling, applied and enrolled. Closed leads (lost, duplicate, junk) sit in the last column.",
            "Stages only move forward. HOT, WARM and COLD show how ready the student is.",
            "Open a lead to see the stage timeline, which link and post it came from, the programme and your earning status. Filter by stage, campaign, deal, post, link, programme, city or date, and save filters as a view.",
            "Not every lead earns: if the student had already enquired, came through another creator first, enquired after the attribution window (90 days by default) or is your own contact, the lead says why.",
            "A lead marked **Under review** is being checked by Eduwit; most are cleared quickly.",
            "Export your list as a spreadsheet (contacts stay masked).",
          ],
        },
        {
          warning:
            "Never ask students to share their phone number or email with you, and never enquire through your own links: self-referrals are detected and not credited.",
        },
      ],
    },
    {
      id: "earnings",
      title: "Your earnings and payouts",
      blocks: [
        {
          p: "[Earnings](/creator/earnings) shows what you have earned and when it will be paid.",
        },
        {
          table: {
            head: ["Total", "Meaning"],
            rows: [
              ["Pending", "Earned, waiting for confirmation (for example until Eduwit receives its commission)"],
              ["Confirmed", "Approved, due on a later date"],
              ["Due to you", "Goes out in the next payout run"],
              ["Paid", "Already paid to your bank account (before TDS)"],
            ],
          },
        },
        {
          list: [
            "**By deal** shows what each deal has earned, net of any penalties or clawbacks. The earning status of each lead is in [Leads](/creator/leads).",
            "Each payout shows the gross amount, TDS and GST deducted or added, and the net paid. When it is paid you get a notification and a **payment advice** PDF with the bank reference (UTR).",
            "If you are GST-registered, **upload your GST invoice** for each payout: raise it to Eduwit for the taxable value and GST shown, then upload the PDF or photo. Payment waits for it. If Eduwit can't accept it, you'll see why and can upload again.",
            "Download a **monthly statement** PDF for any month: opening balance, every line and closing balance.",
            "Payouts need a verified KYC. If anything is held, Eduwit's Finance team will tell you why.",
          ],
        },
      ],
    },
    {
      id: "tax",
      title: "Tax on your earnings",
      blocks: [
        {
          list: [
            "Eduwit deducts TDS as the law requires, for example 2% on commission and 10% on fees once your yearly total passes the threshold. Without a verified PAN the rate is 20%, so complete your KYC.",
            "If you are GST-registered with a verified GSTIN, GST is added to your payout and you upload a tax invoice.",
            "Your TDS certificates (Form 16A) appear in [Earnings](/creator/earnings) each quarter once Eduwit has filed its return.",
          ],
        },
      ],
    },
    {
      id: "media-kit",
      title: "Your media kit",
      blocks: [
        {
          p: "[Media kit](/creator/media-kit) builds a web page and a PDF from your profile and platforms. Turn on the public page to share a link with brands, and choose whether your rates appear. Your contact details and KYC are never included.",
        },
      ],
    },
    {
      id: "agency",
      title: "Working with an agency",
      blocks: [
        {
          p: "If an agency manages you, it can ask to link with your account. You decide, in [Manager](/creator/agency), what it may do:",
        },
        {
          table: {
            head: ["Permission", "Lets the agency"],
            rows: [
              ["View", "See your profile and campaigns"],
              ["Act on deliverables", "Upload and manage content for your deals"],
              ["Negotiate and sign", "Apply to campaigns, counter-offer, and accept or decline deal terms for you"],
              ["View earnings", "See your deals and earnings"],
            ],
          },
        },
        {
          p: "Payouts always go to your own bank account. You can change or remove an agency's access at any time.",
        },
      ],
    },
    {
      id: "privacy",
      title: "Students' privacy",
      blocks: [
        {
          p: "You will see the leads you bring in, but students' phone numbers and email addresses are always hidden. Never ask students to send you their details directly; share your Eduwit link or code instead.",
        },
      ],
    },
    {
      id: "account",
      title: "Your account",
      blocks: [
        {
          p: "[Account](/creator/account) shows where you are signed in. Sign out any device you do not recognise.",
        },
      ],
    },
  ],
};

export const AGENCY: Guide = {
  slug: "agency",
  audience: "agency",
  title: "Agency guide",
  summary: "Linking with creators, what each permission allows, and acting on their behalf.",
  sections: [
    {
      id: "sign-in",
      title: "Signing in",
      blocks: [
        {
          p: "Eduwit invites your agency's owner by email. Sign in on the creator sign-in page with that email; we send a one-time 6-digit code. The owner can add colleagues under [Team](/agency/team).",
        },
      ],
    },
    {
      id: "linking",
      title: "Linking with your creators",
      blocks: [
        {
          steps: [
            "On [Your creators](/agency), request a link by the creator's handle.",
            "The creator approves it in their portal and chooses what you may do.",
            "Linked creators appear in your list with the permissions they gave you.",
          ],
        },
        {
          table: {
            head: ["Permission", "What you can do"],
            rows: [
              ["View", "See the creator's profile, platforms and media kit"],
              ["Act on deliverables", "Read and acknowledge briefs, submit content, go live and report metrics"],
              [
                "Negotiate and sign",
                "Answer invitations, apply to campaigns, counter-offer, accept or decline deal terms, negotiate and sign contracts",
              ],
              ["View earnings", "See their deals, earnings, payouts and statements (never bank details)"],
            ],
          },
        },
      ],
    },
    {
      id: "deliverables",
      title: "Briefs and deliverables",
      blocks: [
        {
          p: "With the act on deliverables permission, open a creator from [Your creators](/agency) to see their briefs and deliverables.",
        },
        {
          list: [
            "Read and acknowledge briefs, and ask Eduwit questions, for the creator.",
            "Upload concepts and drafts (large videos resume if the connection drops), reply to Eduwit's comments, submit live links and report metrics.",
            "Everything you do is shown as done by the agency.",
          ],
        },
      ],
    },
    {
      id: "leads",
      title: "Leads and links",
      blocks: [
        {
          p: "Open a creator from [Your creators](/agency) to see their leads and links. You see leads exactly as the creator does: stages, sources and earning status, with phone and email always masked.",
        },
        {
          list: [
            "With the negotiate and sign permission you can make tracking links and QR codes for the creator's deals.",
            "Leads are credited to the creator, never to the agency.",
          ],
        },
      ],
    },
    {
      id: "earnings",
      title: "A creator's earnings",
      blocks: [
        {
          p: "With the view earnings permission, open a creator from [Your creators](/agency) and choose **Open earnings**. You see what they see: totals, payouts, earnings by deal, monthly statements and TDS certificates.",
        },
        {
          list: [
            "Only the creator can upload their GST invoice; the page tells you when a payout is waiting for one.",
            "Payouts go to the creator's own bank account. If a contract names your agency as payee, Eduwit's Finance team arranges that payment separately.",
          ],
        },
      ],
    },
    {
      id: "acting",
      title: "Acting for a creator",
      blocks: [
        {
          list: [
            "Open a creator to see their campaigns (invitations and applications you can handle) and their deals.",
            "Everything you do is shown to Eduwit and the creator as done by the agency.",
            "On a deal, you can accept or decline proposed terms with the negotiate permission, and use the earnings simulator.",
            "With the negotiate and sign permission you also see the creator's contracts: comment on clauses, suggest wording on negotiable ones, send compensation counter-offers and sign. Your signature is recorded as signed by the agency for the creator, with your own name.",
            "A contract can name your agency as the payee only if the creator gave you the negotiate and sign permission; it says so in the contract.",
          ],
        },
        {
          warning:
            "You never see a creator's bank details or KYC, and payouts always go to the creator's own account. Students' phone numbers and emails stay hidden.",
        },
      ],
    },
  ],
};
