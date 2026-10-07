# B2B CRM — Addendum 3: final lead routing rules

Version 7 October 2026 (rev. 3: unqualified leads enter the B2B CRM; staged partner scoring with sales effort and SLA adherence) · Owner: Vikas Jha · Applies to `docs/B2B_CRM_PROMPT.md`, Addendum 1 and Addendum 2

> **For Claude Code:** save as `docs/B2B_CRM_ADDENDUM_3.md`. This is the **complete, authoritative routing rulebook**. Where the main prompt, Addendum 1 or Addendum 2 differ, this addendum wins.

## Guiding principle

**Edtech partners have the larger sales workforce, so they get the bulk of the leads, including paid Meta and Google leads.** Eduwit's in-house (B2C) sales team is the **fallback**, mainly for leads that partners report as duplicates or mark lost.

**Permanent partner bar.** Once a lead reaches B2C because partners reported it as a **duplicate** (the duplicate cascade), or because a partner marked it **lost**, it is **never routed to any partner again**:

- not automatically, in any later enquiry cycle;
- not by the Admin manually.

The B2B CRM enforces this with a flag on the lead (`partner_barred_at`, `partner_bar_reason` = `duplicate` or `lost`), which no rule, AI change or manual action can override.

---

## PART 1 — Which leads enter the B2B CRM

Every lead from every source enters the B2B CRM, **qualified or unqualified**. It is saved in `student_leads` (the master database) and shown in the Master Lead Table:

1. Witty (WhatsApp AI agent)
2. Website AI agent (only after the student's phone is OTP-verified)
3. Meta Lead Ads
4. Google Ads lead forms
5. Website and landing-page forms
6. Excel / CSV imports
7. Leads added manually by the B2B Admin
8. Leads created inside the B2C CRM (manual entry, or a new number messaging the B2C WhatsApp). These are recorded only and go straight to B2C (R6).

**What happens next:**

- **Qualified leads** go to partner routing (R9).
- **Unqualified leads** are pushed to the B2B CRM too, like every other lead, and handed to B2C qualification nurture (R7). The moment they qualify, the B2B CRM routes them to partners.
- **Junk and programme-mismatch leads** are recorded but not passed to any CRM (R5).
- **Test leads** (`is_test`, or phones 910000xxxxxx) are recorded but never routed, messaged or counted.

## PART 2 — When the routing decision is made

- **Witty and website-agent leads:** at the hand-off point, whichever comes first:
  - Witty escalates (HOT hand-off);
  - the student confirms a final programme;
  - the chat has been idle for 30 minutes.
- **All other sources:** at intake.
- **Excel / CSV imports:** as chosen per import (route now, hold for review, or send to B2C).
- **Re-decisions:** a lead in B2C's **qualification nurture** (R7) is decided again every time it changes. The moment it becomes qualified, it goes through these rules again.

## PART 3 — Routing order (check in this order; first match wins)

| Rule | If the lead is… | Then |
| --- | --- | --- |
| **R1** | A test lead | Do nothing |
| **R2** | **Partner-barred** (`partner_barred_at` set: earlier duplicate cascade, or lost by a partner) | **B2C only, forever.** If B2C holds it, any new enquiry (a new Meta or Google form, Witty again) is sent to B2C as "re-enquired". Never to a partner, not even manually |
| **R3** | **With a partner** (open allocation: pushed, accepted, or lost but inside the 7-day grace) | It stays with that partner. Any new enquiry, including a new Meta or Google form, is recorded on the lead and shown to the Admin, not re-routed |
| **R4** | **Held by B2C for selling**: other fallbacks (no partner offers the programme, no capacity, partners unreachable, the student said NO to sharing, import choice, Admin re-route), or B2C-created | It stays with B2C. A new event is sent as "re-enquired". It reaches a partner only if the Admin manually routes it there (allowed for these, because they are not partner-barred). **Leads in B2C's qualification nurture (R7) are NOT held this way**: they return to routing once qualified |
| **R5** | **Junk or programme mismatch**: Witty classification JUNK or PROGRAM_MISMATCH; a blocklisted, invalid or spam number; or a course not in Eduwit's catalogue | Not passed to any CRM. Shown in the "Not passed" view with a manual **Pass to CRM** option |
| **R6** | Created in the B2C CRM | B2C sales lane |
| **R7** | **Not qualified**. Witty: UNQUALIFIED (name, email or course missing). Other sources: no course, or no valid contact | B2C **qualification nurture** (lane `nurture`, reason `not_qualified`). B2C's job is only to get the missing details. As soon as the lead is qualified, it comes back through these rules, so it normally reaches a partner |
| **R8** | Qualified but **no partner-sharing consent** recorded | Ask for consent (PART 7). Yes → R9. No (the student explicitly wants only Eduwit) → B2C sales lane. No answer in 48 hours → B2C qualification nurture, where the request repeats |
| **R9** | **Qualified**, from **any source, including paid Meta and Google leads** (Witty HOT, WARM or COLD; other sources: course plus valid contact) | **Partner routing (PART 4)** |

**Definitions.**

- **"Qualified" = sales-ready.** There is no score gate, and the university does not need to be chosen. COLD ("just exploring") leads are qualified and go to partners.
- **Paid leads** are only **Meta and Google** leads: Meta Lead Ads, Google Ads lead forms, and leads arriving with a Meta or Google ad click ID (`fbclid` from a paid placement, `gclid`, `gbraid`, `wbraid`) or from a Meta click-to-WhatsApp ad.
  - **"Paid" no longer changes routing.** Paid leads are routed to partners like every other qualified lead. The label is kept for attribution, analytics (cost per enrollment, return on ad spend) and CAPI.
  - Influencer or referral markers always mean **not paid**.
- **Click-to-WhatsApp leads** are decided at Witty's hand-off point, never on the first message.

## PART 4 — Which partner gets a qualified lead

**Step 1. Candidate partners.** Partners that meet all of these:

- live and not paused;
- their **published Programme Repository** file (Excel or Google Sheet) includes a programme matching the student's **primary interest**:
  - course + specialization;
  - plus level, mode and university when the student has given them;
- not previously reported this student as a duplicate;
- the lead meets the partner's agreed criteria (geography, qualification and so on);
- under its daily and monthly caps;
- (contractual minimums are served first while a partner is behind schedule).

**Several interests.** If the student is interested in more than one programme, use the primary interest first. If no partner offers it, try the student's secondary interests in order before falling back. The partner receives all the stated interests in the push note.

**No candidates:**

- B2C sales lane, reason `no_partner_offers_programme` (no partner sells any of the student's interests);
- or `no_capacity` (partners exist but are all full or paused).

**Step 2. Admin routing rules.** Apply in priority order. A rule may fix a partner, narrow the candidates, exclude partners, or send the lead to B2C.

**Step 3. Choosing the partner.** Partner choice moves through three stages per programme segment. A segment is university × course × level × mode; it rolls up to course × level × mode when data is thin.

**Stage A — Programme match, then highest commission** (from the first lead).

- **Only one partner offers the programme:** it gets the lead.
- **More than one partner offers it:** the lead goes to the partner paying the **highest commission per enrollment (CPE)**, net of GST.
  - **Percent rates** are applied to the partner's own fee from its programme file, otherwise the catalogue fee.
  - **Fixed rates** are used as is.
  - **Tiered rates** (a lower % at higher conversion): at cold start, use the **middle tier** for every partner (for example 20.42% in 22.42 / 20.42 / 18.42), so no partner looks better on an assumption. After a partner has 30 matured leads in the segment, use its projected tier.
  - **No university chosen:** use the median CPE across the partner's matching programmes.

**Stage B — Commission adjusted by sales effort and SLA adherence.** Applies once each competing partner has received at least **20 leads** in the segment, the oldest at least 7 days old. Effort and SLA data mature within days, long before enrollment data does.

`Score = CPE × Sales-effort factor × SLA-adherence factor`

**Stage C — Full performance: commission per lead.** Applies once at least 2 competing partners each have **30+ matured leads** (sent more than 60 days ago) in the segment.

`Score = Commission per lead × Sales-effort factor × SLA-adherence factor`

where **commission per lead** = **net commission per enrollment × lead-to-enrollment ratio** (net of GST, after refunds) = `CPE × P(enroll) × (1 − refund rate)`.

- **P(enroll)** is the partner's lead-to-enrollment ratio for this kind of lead: real conversion in the segment, weighted toward recent months, and later the ML model's prediction for this student once its activation gate passes.
- **Highest score wins.**
- **Sales-effort factor** (0.85–1.15; 1.0 = segment median). Compares the partner with the segment median over the last 30 days, from synced partner activity:
  - time from push to first call attempt;
  - call attempts in the first 72 hours;
  - connect rate;
  - follow-ups done on the scheduled date;
  - activities per open lead per week;
  - share of open leads with no update in 7 days (lower is better).

  **No activity synced:** a partner whose CRM sends no call or activity data gets at most 1.0. It can never be boosted on effort it does not show.
- **SLA-adherence factor** (0.80–1.00). The share of SLAs met in the last 30 days:
  - first call attempt within 2 working hours;
  - status update at least every 7 days while open;
  - enrollment proof within 7 days.

  100% adherence = 1.0; every 10 points below 100% subtracts 0.05, down to 0.80. Separately, 5 consecutive first-contact breaches auto-pause the partner (PART 6).
- **Bounds and weights** are Admin settings, versioned. The Claude optimiser may tune them only inside these ranges.

Every decision stores the stage used, the CPE, P(enroll), both factors and the final score, so "Why this partner" is always explainable.

**Exploration lane** (all stages). While any competing partner has fewer than 30 leads in the segment, **20%** of the segment's leads go to the under-tested partner with the highest CPE. This is how the engine learns every partner's effort and conversion. These leads still go to partners.

**Ties:** higher CPE, then better SLA adherence, then fewer leads this week.

**Step 4. Push.** The lead is created in the winning partner's CRM through its API.

## PART 5 — After the push

1. **Hold window:** 0 minutes for partners whose CRM rejects duplicates instantly, 30 minutes for the others. A duplicate or rejection inside the window still moves the lead.
2. **Accepted:** the hold window passes with no duplicate or rejection. The lead is the partner's, and the student gets a WhatsApp and an email naming the partner. They are never sent for a partner that claimed a duplicate or rejected the lead.
3. **Duplicate at partner** (with proof): exclude that partner and route to the next-best partner. That is a partner too, because partners get the bulk.
4. **Second duplicate,** or no other eligible partner after a duplicate: **B2C sales lane**, reason `duplicate_cascade`. The B2C CRM assigns it at once to an in-house counsellor by **round robin**. The lead is **partner-barred for ever** (`partner_bar_reason = duplicate`).
   - The lead carries an **"Already with other providers"** badge listing the partners and the dates they first had the student.
   - The B2C counsellor's first contact uses a neutral-adviser script: "Eduwit can help you compare options."
   - Eduwit's in-house commission comes from the university directly, so it does not compete with the partners' claims.
5. **Rejected for another reason:** contract alert; exclude that partner; route to the next. This counts as an attempt.
6. **Technical failure:** retry over about 1 hour, then route to the next partner. This does not count as an attempt.
7. **Limits:** at most 2 duplicate or rejection attempts, and at most 3 partners in total. After that: B2C sales lane.
8. **Duplicate claimed after acceptance** (within 24 hours): no re-routing. It is logged as a commission dispute for the Admin to decide.

## PART 6 — Later movements

1. **Partner marks the lead lost:**
   - **Grace period (7 days):** the lead stays with the partner as "lost, in grace". B2C sends nothing and assigns no counsellor. If the partner reports new activity in that time, the lead is simply back with the partner, with no dispute.
   - **After 7 days:** the lead moves to **B2C nurture**, reason `partner_lost`, unassigned, and is **partner-barred for ever** (`partner_bar_reason = lost`). The lost reason sets when the first nurture message goes out (3–90 days).
   - **Reactivation:** a B2C counsellor is assigned, by **round robin**, only when the student shows explicit interest again (Witty, a positive reply) or high engagement (score rising to 60+). Until then the lead stays unassigned in the nurture funnel.
   - **Late partner activity:** activity reported after the grace period is logged as a commission dispute.
2. **Admin manual re-route** (partner → B2C or another partner): only before the partner's first contact attempt, or after an SLA breach. A reason is required. A re-route to B2C does **not** bar the lead from partners; only duplicate and lost do.
3. **Manual route-to-partners** (B2C → partners): the only way a B2C-held (R4) lead reaches a partner. It needs partner-sharing consent and a reason. If no partner accepts, the lead returns to its B2C counsellor.
   - **Blocked for partner-barred leads** (R2). The button is hidden, the API refuses, and bulk actions skip them with a count.
   - **When a manual route ends in a duplicate or lost,** the lead becomes partner-barred too.
4. **SLA auto-pause:** a partner is paused after 5 first-contact SLA breaches in a row, or after 30 minutes of sync failure. Paused partners receive no new leads.

## PART 7 — Partner-sharing consent (prerequisite)

No lead in the database carries partner-sharing consent today. Without it, R8 would send almost every qualified lead away from partners. So:

1. **Before go-live,** every consent line must cover sharing with "our admission partners (edtech companies)", not only universities. That means Witty's consent message, the website agent's sign-up, every website and landing-page form, and the Meta and Google lead-form disclaimers. The wording should be checked by Eduwit's lawyer. Record `consent_partner_share_at` and `consent_text_version`.
2. **Leads without it** (including everyone captured before go-live) get a one-tap request at the hand-off point. It goes from Witty's WhatsApp number if the lead came through Witty, otherwise from the B2C number:

   > "To connect you with the best admission counsellor for {{programme}}, may we share your details with our admission partner? Reply YES or NO."

   Then:
   - **YES:** record consent, then R9.
   - **NO:** B2C sales lane, reason `no_partner_consent`.
   - **No answer in 48 hours:** B2C qualification nurture; the request repeats in its journeys.

## PART 8 — Witty changes required (for the Witty developer)

1. **Neutral hand-off wording.** On escalation Witty must not say "our" counsellors. Use: "Thank you, {{name}}. An academic counsellor will contact you shortly about {{programme}}." The B2B notification then names the partner.
2. **Consent line.** Update Witty's consent message to include admission partners (PART 7.1).
3. **Keep talking to nurture leads.** Witty stops selling only when a partner has accepted the lead, or a B2C counsellor is assigned. For **qualification-nurture** leads, Witty's job is to finish qualifying them. When they qualify, the B2B CRM routes them to partners (R7 → R9).
4. **Interest signal** to the B2C CRM, as in Addendum 1 §4b.

## Changes from earlier addenda (summary)

| Earlier rule | Now |
| --- | --- |
| All paid-campaign leads go to B2C | **Paid (Meta and Google) leads go to partners** like any qualified lead; "paid" is only an attribution label |
| Any lead once handed to B2C stays in B2C forever | **Duplicate-cascade and partner-lost leads are partner-barred for ever** (not even manual). Other B2C selling leads stay unless the Admin routes them manually. **Qualification-nurture leads return to partner routing once qualified** |
| Re-engaged `not_qualified` leads were assigned to a B2C counsellor to sell | They go through the rules again. Qualified → partners. A B2C counsellor may help qualify by phone if the student re-engages but stays unqualified for 48 hours, and the lead then goes to partner routing |
| No partner consent → B2C sales | Ask for consent first. Only an explicit "No" sends the lead to B2C sales |
| Partner-lost → B2C nurture at once | 7-day grace with the partner, then B2C nurture |
| Paid enquiry from a partner-held student | Stays with the partner |
| Projected tier at cold start | Middle tier for all partners until each has data |
| Commission-first, then commission per lead | Three stages: **A** programme match + highest commission; **B** commission × sales effort × SLA adherence (after 20 leads each); **C** commission per lead (net commission × lead-to-enrollment ratio) × sales effort × SLA adherence (after 30 matured leads each). Effort and SLA factors are **on by default** |
| Unqualified leads | Pushed to the B2B CRM like every lead, handed to B2C qualification nurture, and routed to partners once qualified |
| Primary interest only | Primary, then secondary interests, before falling back to B2C |
| Paid detection by `utm_medium` | Paid means Meta or Google only, and is an attribution label, not a routing rule |

## Tests to add

1. An unqualified Witty lead goes to B2C qualification nurture, qualifies with Witty 2 days later, and is **routed to a partner**.
2. A qualified lead without consent: YES → partner; NO → B2C sales; no answer in 48 hours → B2C nurture, and a later YES → partner.
3. A lead with two duplicate claims goes to B2C sales with the "Already with other providers" badge.
4. A partner marks a lead lost and revives it on day 3: it stays with the partner. A lead still lost on day 8 goes to B2C nurture.
5. A student wants MBA (offered by no partner) and PGDM (offered by Partner Y): the lead goes to Partner Y.
6. A qualified Meta Lead Ads lead and a qualified Google lead-form lead are routed to **partners**.
7. Tiered partners at cold start are compared on the middle tier.
8. A paid lead whose student already has an open partner allocation stays with the partner.
9. A duplicate-cascade lead and a partner-lost lead (after grace) are partner-barred. A new Meta form from the same student months later goes to B2C as "re-enquired", never to a partner. The Admin's manual route-to-partners is refused for both.
10. A lead sent to B2C because no partner offered the programme can still be manually routed to partners later.
11. **Stage A:** two partners offer the programme; the one with the higher CPE gets the lead (outside the exploration lane).
12. **Stage B:** after 20 leads each, a partner with a 10% lower CPE but much faster first contact and full SLA adherence wins over a slow, SLA-breaching partner, when its effort and SLA factors outweigh the CPE gap.
13. **Stage C:** with 30 matured leads each, the partner with the higher net commission × lead-to-enrollment ratio (adjusted by effort and SLA) wins.
14. A partner that syncs no activity data never gets a sales-effort factor above 1.0.
15. An unqualified Witty lead appears in the B2B CRM, goes to B2C nurture, and is routed to a partner when it qualifies.

## Amendment 1 (Vikas, 7 October 2026)

1. **Unqualified Witty leads are pushed only after 18 hours of inactivity.** A Witty lead that is still unqualified is decided (R7, B2C qualification nurture) only once the student has been inactive for **18 hours continuously** after their last chat session with Witty. Every new message restarts the 18 hours. If the student qualifies in the meantime, the qualified hand-off points of PART 2 apply (HOT escalation, final programme confirmed, or 30 minutes idle) and the lead goes to partner routing (R9). The 18 hours is an Admin setting.
2. **Welcome message from the B2C CRM.** As soon as such a lead is pushed to B2C qualification nurture, the B2C CRM automatically sends the student a WhatsApp message prompting them to explore suitable programmes to enhance their career. The B2B CRM asks for it in the hand-off event; it does not send the message itself.
   - Note for the B2C developer: WhatsApp allows free-form messages only within 24 hours of the student's last message, and only from the number they wrote to. A message from the B2C number therefore needs a Meta-approved template.
