import type { Guide } from "../types";

export const CREATOR: Guide = {
  slug: "creator",
  audience: "creator",
  title: "Creator guide",
  summary: "Getting set up, finding campaigns, agreeing your deal terms, and working with an agency.",
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
          tip: "The simulator is an estimate for planning. Your earnings statements (coming soon) show what you actually earn.",
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
            "TDS certificates (Form 16A) will be available to download from your earnings pages.",
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
        { p: "Payouts always go to your own bank account. You can change or remove an agency's access at any time." },
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
        { p: "[Account](/creator/account) shows where you are signed in. Sign out any device you do not recognise." },
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
              ["Act on deliverables", "Handle content for their deals (from Phase 5)"],
              [
                "Negotiate and sign",
                "Answer invitations, apply to campaigns, counter-offer, accept or decline deal terms",
              ],
              ["View earnings", "See their deals and earnings"],
            ],
          },
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
