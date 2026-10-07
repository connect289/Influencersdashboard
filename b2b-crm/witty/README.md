# Witty release W1 (Addendum 3)

Changes to Witty, Eduwit's live WhatsApp bot, required by `docs/B2B_CRM_ADDENDUM_3.md` (PART 7, PART 8 and Amendment 1).
Vikas, 7 Oct 2026: "Make required changes to Witty", "Push changes to Witty and take it to live production".

## What changes for students

- **Hand-off reply** (PART 8.1): "Thank you{name}. An academic counsellor will contact you shortly about {course}." (was "...one of our Academic Counselors..."). Hinglish to match.
- **Hand-off offer**: "Would you like an academic counsellor to help you with the next steps?" (was "one of our academic counselors").
- **Consent line** on the first reply (PART 7.1, 8.2): now names "our admission partners (edtech companies)". Witty records
  `consent_partner_share_at` and `consent_text_version = witty-notice-2026-10-v2`, which reach `student_leads` through
  `lead_intake`. **The wording needs the lawyer's sign-off** (PART 7.1).
- **Witty keeps talking** to leads that are only queued or in a partner's hold window, and to B2C leads without a counsellor
  (PART 8.3). It goes quiet once a partner has accepted the lead or a B2C counsellor is assigned.
- **Witty's own follow-up messages stop** once the B2B CRM has routed the lead (partner or B2C), because the B2C CRM sends
  the welcome message and its journeys (Amendment 1). Witty still answers every message the student sends.
- **Interest signal** (PART 8.4): a message with an interest intent on a B2C-held lead is logged as touchpoint `lead.interest`.
- **Escalation signals** the B2B CRM reads are reliable: `lead.escalated` wins over `lead.qualified` when both happen in one
  turn, and `lead_stage` stays `ESCALATION` while Witty is paused after a hand-off.

## Files

- `../supabase/migrations/20261007094058_w1_witty_addendum3.sql`: `w2_crm_owned`, `w2_nurture_due`, `w2_crm_payload`, `w2_commit_turn`, and the
  extractor prompt example. The previous definitions are saved on production in `b2b.witty_backup_20261007` (rollback: run
  each saved `def`, and restore the `extractor:v4` body with a version bump).
- `patch_nodes.py`: exact, counted find-and-replace on the live workflow export (aborts if any snippet is missing or found a
  different number of times). Nodes and checksums of their `jsCode`:

| Node | Id | Before (md5) | After (md5) | Lines changed |
| --- | --- | --- | --- | --- |
| Plan Reply | `5b306283-52cf-4ae3-90f2-c76e5ab31097` | `692341e33cc9e903fb81b1e01ce160be` | `2ef213c12a9f7e061340992b4baa2838` | 17 |
| Verify Reply | `165f5f05-ef34-43b7-a2c2-e2191e75a720` | `7491b0c272ce416dd3b18273b0855793` | `27a78b7c286b62e2dfbab59322507ae6` | 10 |
| Verify Rewrite | `39c94132-298d-4ff3-bec7-ad03fb2d6f6e` | `82e6f641e1f5dffb29826af13f2d3c31` | `9c8c4197425e1841568a0c9a6acdf4bf` | 10 |
| Finalize Counselor | `a90ce11c-f1dc-4a9f-9229-3bc30d0bd99f` | `9826f83140f491cf5a83c5289a71835c` | `77dfdba0dc487d89e352e8be5b339f8e` | 10 |
| Assemble Commit | `967df84b-eda9-4938-8735-30dbfa74d472` | `a23ccd036fad8fe89c28b3bc89c27976` | `e421a9b3a60b05f3fdf68019ed86ab2f` | 4 |
| Validate + Decide | `f9e167ab-4b3f-4ecd-80f4-9603f6123f30` | `d413d9373d348e41011d0f329963b97f` | `a7f3ab6e050eda0c3197162b070070e3` | 7 |

## Status (7 Oct 2026)

- **Database half: live on production** (migration `20261007094058`). A line diff against `b2b.witty_backup_20261007` shows only
  the intended lines; 15 rolled-back checks on 910000… test numbers passed (ownership for six cases, consent keys reaching
  `student_leads`, the `lead.interest` touchpoint only for B2C-held leads with an interest intent, the nurture filter, the
  extractor prompt v5). It works with the current workflow: the consent keys stay empty until the workflow sets them.
- **Workflow half: not applied.** Patching the live nodes was refused by Claude Code's permission check. Apply the six node
  changes below in the n8n editor (or allow the action), then run the harness and publish.

## Release steps

1. Re-check `get_workflow_history` for "Eduwit Witty" `PKPs7tXg9bej8AgX` (one editor at a time; the live version on 7 Oct is
   `1f79392c`, 5 Oct, "Locbizz Solution").
2. Apply the SQL migration on production `xlseqwgyjuqhktrguhyc`; diff each function against `b2b.witty_backup_20261007`.
3. Patch the six nodes' `jsCode` in the draft; read them back and compare the md5 above.
4. Run the Witty harness (`1BGAINw5XDkSHb2q`): activate, `POST https://n8n.eduwit.in/webhook/witty2-test-harness-dev` with the five
   scenarios in CLAUDE.md, read `w2_test_runs`, deactivate. Baseline 20/20. Clean up the 910000… test leads.
5. Publish the workflow. If anything fails: restore version `1f79392c` and the saved SQL.
6. Copy the four functions into the Eduwit CRM's `crm/sql/001_lead_intake.sql` (re-running 001 would revert them) and update
   its CLAUDE.md line on `w2_crm_owned`. Do not run n8n's "Setup Request" webhook: its SQL predates the CRM.

## Making the workflow edits by hand (n8n editor)

Open "Eduwit Witty", edit each Code node's JavaScript, and use find-and-replace (match case) for each pair. Every "find" text must exist before you replace it. Save (this updates the draft), run the harness, then publish.

**Plan Reply, Verify Reply, Verify Rewrite, Finalize Counselor**

Find:
```
Thank you for sharing your details{name}. Based on your interest in {course}, I've arranged for one of our Academic Counselors to contact you on this number. They'll help you with the next steps.
```
Replace with:
```
Thank you{name}. An academic counsellor will contact you shortly about {course}.
```

Find:
```
Details share karne ke liye thank you{name}. {course} mein aapki interest ke hisaab se maine hamare ek Academic Counselor ko aapse isi number par contact karne ke liye bol diya hai. Woh aapko next steps mein madad karenge.
```
Replace with:
```
Thank you{name}. Ek academic counsellor jald hi aapse {course} ke baare mein contact karenge.
```

**Plan Reply, Verify Reply, Verify Rewrite, Finalize Counselor, Assemble Commit (Hinglish text appears twice: keys hinglish and hindi)**

Find:
```
Your details are used only to help with your admission and may be shared with our partner universities. Reply STOP anytime to opt out.
```
Replace with:
```
Your details are used only to help with your admission and may be shared with our partner universities and our admission partners (edtech companies). Reply STOP anytime to opt out.
```

Find:
```
Aapki details sirf admission help ke liye use hongi aur partner universities ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain.
```
Replace with:
```
Aapki details sirf admission help ke liye use hongi aur hamari partner universities aur admission partners (edtech companies) ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain.
```

**Plan Reply, Validate + Decide**

Find:
```
Would you like one of our academic counselors to help you with the next steps?
```
Replace with:
```
Would you like an academic counsellor to help you with the next steps?
```

Find:
```
Kya aap chahenge ki hamare ek academic counselor next steps mein aapki madad karein?
```
Replace with:
```
Kya aap chahenge ki ek academic counsellor next steps mein aapki madad karein?
```

Find:
```
const type = !s.crm_fingerprint ? 'lead.qualified' : escalate ? 'lead.escalated' : clsChanged ? 'classification_changed' : 'lead.updated';
```
Replace with:
```
const type = escalate ? 'lead.escalated' : !s.crm_fingerprint ? 'lead.qualified' : clsChanged ? 'classification_changed' : 'lead.updated';
```

Find:
```
s.phase = 'ESCALATION'; s.bot_paused = true; }
else if (mode === 'SUPPORT') s.phase = 'SUPPORT';
```
Replace with:
```
s.phase = 'ESCALATION'; s.bot_paused = true; }
else if (s.escalated_at && s.bot_paused) s.phase = 'ESCALATION';
else if (mode === 'SUPPORT') s.phase = 'SUPPORT';
```

**Assemble Commit**

Find:
```
s.consent_at = new Date().toISOString(); }
```
Replace with:
```
s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v2'; }
```


## Not in this release

- The one-tap YES/NO consent request from Witty's number (PART 7.2) is not built in Witty: every new Witty lead now gets the
  partner consent line on its first reply, and production holds no Witty leads from before (data wiped 5 Oct). Leads without
  partner consent get the request from the B2C number (B2B and B2C CRM side).
- The Chatwoot hand-off brief and the `witty-handoff` label still run on escalation, also for leads that will go to a partner.
