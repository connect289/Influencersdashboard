# B2B CRM — Addendum 2: every lead is passed to a CRM, except junk and programme mismatch

Version 6 October 2026 · Owner: Vikas Jha · Applies to `docs/B2B_CRM_PROMPT.md` and Addendum 1

> **For Claude Code:** save as `docs/B2B_CRM_ADDENDUM_2.md`. **Where it differs from the main prompt or Addendum 1, this addendum wins.**

## The rule

**Every lead is passed to a CRM, qualified or not, except junk and programme-mismatch leads.**

- **Qualified leads** go to partner routing (main prompt B7), or to B2C under Addendum 1's rules (paid campaign, B2C-held, no consent, fallbacks).
- **Unqualified leads** go to the B2C CRM's Nurture Pool (lane `nurture`, reason `not_qualified`).
- **Junk and programme-mismatch leads** are **not passed** to any CRM. They stay in `student_leads`, the master database, but no CRM works them.

## Definitions

| Class | How it is decided |
| --- | --- |
| **Junk** | Witty or the website agent classifies the lead `JUNK` (`student_leads.lead_status`). For every source: blocklisted numbers, invalid phones and spam patterns (main prompt B4). Test leads (`is_test`) stay excluded as before |
| **Programme mismatch** | Witty or the website agent classifies the lead `PROGRAM_MISMATCH` (the student wants something Eduwit's catalogue does not offer). For forms, imports and ad leads: the stated course matches nothing in `catalog_programs` or `catalog_synonyms` after normalisation and fuzzy matching |
| **Qualified** | As in main prompt B4: Witty's qualification complete (HOT, WARM or COLD) and, for other sources, the course plus valid contact known |
| **Unqualified** | Everything else that is not junk or mismatch (for example Witty's `UNQUALIFIED`: name, email or course still missing) |

**Programme mismatch is not the same as "no partner offers the programme".** If the programme exists in Eduwit's catalogue but no partner sells it, the lead is still passed, to B2C (reason `no_partner_offers_programme`, main prompt B7.6).

## When the decision is made

- **Witty and website-agent leads:** at the hand-off point. That is when Witty escalates, the student confirms a final programme, or the chat has been idle for **30 minutes** (configurable).
  - The classification at that moment decides the outcome: qualified → routing; unqualified → B2C nurture; junk or mismatch → not passed.
  - This **replaces Addendum 1's 24-hour window** for unqualified leads, so they reach B2C nurture as quickly as qualified leads reach routing.
- **Every other source:** at intake.
- **Order of checks:** exclusion is checked **first**, before every routing rule in Addendum 1, including the paid-campaign rule. A paid lead that is junk, or a paid click-to-WhatsApp chat that Witty classifies `PROGRAM_MISMATCH`, is not passed.

## When the classification changes later

| Change | What happens |
| --- | --- |
| A **not-passed** lead becomes qualified or unqualified (for example, the student later picks a programme Eduwit offers) | It is passed at the next hand-off point, following the normal rules |
| A **passed** lead is later classified junk or mismatch by Witty | **Not pulled back automatically.** The B2B CRM flags it on the lead and in an Admin review queue. For a B2C-held lead, it emits `b2c.lead_flagged` so the B2C CRM can close it if the Admin agrees. A partner-held lead stays with the partner |

## In the B2B CRM

- **Master Lead Table:** a view **"Not passed (junk / mismatch)"** with the reason, Witty's classification, the course the student asked for, and the date. Default views hide these leads.
- **Rescue:**
  - **Pass to CRM** sends a not-passed lead through the normal rules. Use it when Witty misclassified it.
  - **Bulk pass** lets the Admin pass a whole group, for example when Eduwit adds a programme that many mismatch leads had asked for.

  Both are logged with a reason.
- **Analytics:** count not-passed leads by reason, source and requested course. The mismatch list shows which programmes students ask for that Eduwit doesn't offer, which is useful demand data.
- **CAPI:** not-passed leads produce no conversion events beyond the original lead event. An optional setting, off by default, sends a "disqualified" signal to Meta and Google for junk.

## Nothing changes on Witty's side

Witty already writes every gated chat into `student_leads` through `lead_intake()` and keeps `lead_status` current (HOT, WARM, COLD, UNQUALIFIED, PROGRAM_MISMATCH, JUNK). The B2B CRM reads that column; no Witty change is needed for this rule.

## Tests to add (Phase 1 exit)

1. A Witty chat classified `UNQUALIFIED` that has been idle for 30 minutes goes to B2C, lane `nurture`, reason `not_qualified`.
2. A Witty chat classified `JUNK` or `PROGRAM_MISMATCH` is not passed. It appears in "Not passed" and nowhere else.
3. A paid lead classified junk is not passed. A paid lead that is qualified goes to B2C, lane `sales`.
4. A mismatch lead that later chooses a catalogue programme is passed at the next hand-off point.
5. A passed lead later re-classified junk is flagged for review, not moved.
6. **Pass to CRM** on a not-passed lead routes it normally.
