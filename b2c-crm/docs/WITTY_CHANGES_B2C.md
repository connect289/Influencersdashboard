# Prompt: Witty changes for the B2C CRM (release W2)

Version 14 October 2026 · Owner: Vikas Jha · Approved by Vikas on 14 Oct ("everything is approved")

> **For Claude Code, in a session on Vikas's machine with n8n access.** This is the second Witty release. It follows
> release W1 (`b2b-crm/witty/README.md`, `b2b-crm/witty/WITTY_CHANGES_PROMPT.md`), whose rules, checks, harness,
> publishing and rollback steps apply here unchanged: one editor at a time, patch live nodes by exact snippet, save as a
> draft, run the harness (baseline 20/20), publish, watch 30 minutes, keep a rollback. Read both W1 files first.
>
> **Never** change `lead_intake()`, rename or drop a `student_leads` column, or edit `w2_*` tables. Function changes
> (`w2_try_claim`, `w2_commit_turn`, `w2_crm_payload`) go in one tracked migration, applied to the staging project
> `mplbspysxmtohnlwpbti` first, with the previous definitions saved in `b2b.witty_backup_<date>` exactly as W1 did.

## Why

The B2C CRM (`b2c-crm/docs/B2C_CRM_PROMPT.md`, final 14 Oct) now holds every lead the partners cannot take, plus every
unqualified and partner-lost lead in its **Nurture Pool**. Witty matters to it in four ways:

1. **Re-engagement.** A pooled lead that writes to Witty again with real interest must reach a counsellor within 60
   seconds (B6.3). Witty signals it; the B2B CRM forwards it to the B2C CRM (already built: B2B `m31k_a3_redecide`
   forwards `lead.interest` for every holder and `lead.escalated` for B2C holders).
2. **Keep talking to pooled leads**, and go quiet once a B2C counsellor is assigned.
3. **Marketing consent.** B2C nurture (WhatsApp and email journeys) may only message a lead with `consent_marketing_at`
   (B6.1, B9.6). Witty is where most leads start, and it records no marketing consent today.
4. **Transcripts.** Counsellors see the Witty chat on the lead screen, read-only, from `w2_messages`.

## 0. Prerequisite: finish release W1

On 7 Oct W1's database half went live (migration `20261007094058`) but its **workflow half was not applied** (six node
edits: neutral hand-off wording, the consent line naming admission partners, escalation signals). Check the live
workflow first:

- If the six nodes already carry W1's "after" md5 values (`b2b-crm/witty/README.md`), go on.
- If not, run W1 now (`WITTY_CHANGES_PROMPT.md` sections 3–6), then come back. W2 builds on W1's consent line and its
  `lead.interest` signal; without W1, B2C nurture has no consented Witty leads and no interest signal.

## 1. Changes in this release

### W2.1 Clear Witty's escalation pause for B2C leads without a counsellor (database)

*Was W1 §8 item 1.* At escalation Witty pauses itself (`bot_paused`, Chatwoot label `witty-handoff`). When that lead then
lands in B2C with **no counsellor** (qualification nurture, partner-lost after the 7-day grace, a sales lead waiting for
assignment), Witty must answer again, otherwise a pooled student who writes back is never heard and never re-engages.

In `w2_try_claim`, after step 1b (`w2_crm_owned`), when **all** hold:
- `w2_crm_owned(phone)` is false;
- the lead's current B2B allocation (`student_leads.allocation_id` → `b2b.allocations`) has `destination_type = 'in_house'`
  and `status = 'handed_off'`;
- `student_leads.owner_user_id` is null;
- `w2_conversations.bot_paused` is true,

then set `bot_paused = false` (column and `state.bot_paused`) and queue removal of the Chatwoot label `witty-handoff`.
Keep `escalated_at` so Witty never promises a counsellor twice. Do it once per lead (it is idempotent: the next turn finds
`bot_paused` false).

Test (staging, test phone `910000…`): escalate a test chat; hand it to B2C nurture with the B2B Admin's **Test hand-off**
or by setting the test allocation; send a new message → Witty answers; `escalated_at` unchanged; label removed.

### W2.2 Record messages Witty does not answer (database)

*Was W1 §8 item 2.* When `w2_crm_owned` is true (a B2C counsellor is assigned, or a partner accepted the lead),
`w2_try_claim` step 1b returns `crm_paused` and the message is never recorded on the lead. The B2C CRM must know: the
counsellor gets a "new message on Witty" alert, and a partner-barred lead's re-enquiry must be logged (Addendum 3, R2).

In step 1b, before the return, record it through `lead_intake` (no change to `lead_intake` itself):

```sql
begin
  perform lead_intake(jsonb_build_object(
    'source_system', 'witty', 'event_type', 'chat.reenquiry',
    'idempotency_key', p_phone || ':paused:' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'),
    'phone', p_phone, 'lead', '{}'::jsonb));
exception when others then null;  -- never block Witty
end;
```

One touchpoint per lead per day (the date in the key debounces). The B2B CRM forwards it to the B2C CRM as
`b2c.lead_reenquired`.

Test: assign a B2C counsellor on a test lead (`owner_user_id` set), send two messages the same day → exactly one
`touchpoints` row `chat.reenquiry`; Witty sends nothing.

### W2.3 Marketing consent in Witty's consent line (workflow + database)

Today Witty's consent line covers admission help and sharing with partners, and Witty records `consent_sales_at` and
`consent_partner_share_at`, never `consent_marketing_at`. Without it B2C nurture cannot message any Witty lead.

**Wording (needs the lawyer's sign-off before publishing; ask Vikas once, as in W1 §3.3):**

- English: "Your details are used only to help with your admission, may be shared with our partner universities and our
  admission partners (edtech companies), and Eduwit may send you programme updates on WhatsApp and email. Reply STOP
  anytime to opt out."
- Hinglish: "Aapki details sirf admission help ke liye use hongi, hamari partner universities aur admission partners
  (edtech companies) ke saath share ho sakti hain, aur Eduwit aapko WhatsApp aur email par programme updates bhej sakta
  hai. Kabhi bhi STOP likh kar band kar sakte hain."

**Workflow:** in the same five nodes W1 changed for the consent line (Plan Reply, Verify Reply, Verify Rewrite,
Finalize Counselor, Assemble Commit; the Hinglish text appears under keys `hinglish` and `hindi`), replace W1's consent
sentence with the new one. In **Assemble Commit**, where W1 set the consent keys, also set the marketing key and bump the
version:

Find (W1's "after"):
```
s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v2'; }
```
Replace with:
```
s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_marketing_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v3'; }
```

**Database:** `w2_crm_payload` must pass `consent_marketing_at` from `w2_conversations.state` (key of the same name), next
to `consent_partner_share_at` and `consent_text_version` (W1 added those). `lead_intake` already accepts
`consent_marketing_at` and treats consent stamps as first-touch, so nothing else changes.

**Register the text** `witty-notice-2026-10-v3` with the B2B CRM's consent texts (B2B Admin → Consent texts) as naming
admission partners **and** marketing on WhatsApp and email, so both CRMs count it.

Note: consent stamps are write-once in `lead_intake`. Leads that already got the v2 notice keep v2 and no marketing
consent; the B2C CRM asks them for marketing consent itself (a WhatsApp opt-in button), and reports it to the B2B CRM.

Test: a new test chat's first reply carries the v3 line; after the turn, `student_leads.consent_marketing_at` and
`consent_partner_share_at` are set and `consent_text_version = 'witty-notice-2026-10-v3'`.

### W2.4 Interest signal: also on escalation (database, small)

W1 writes `lead.interest` for a B2C-held lead (`destination_type = 'in_house'`) when the student's message has intent
`asks_fees`, `asks_eligibility`, `asks_human`, `wants_to_apply`, `pay_after_placement` or `accepted_offer`, **unless
Witty's own CRM event fires on that turn**. When that own event is `lead.escalated`, the B2B CRM already forwards it for
B2C holders, so nothing is lost. **Keep W1's intent list** (do not add `asks_programs` or `wants_alternatives`: browsing is
not interest, and a false trigger costs a counsellor's time).

Only check, do not change: on a B2C-held test lead, (a) "what is the fee?" writes `lead.interest`; (b) a turn that
escalates writes `lead.escalated` and no duplicate `lead.interest`; (c) "show me other programmes" writes neither.

### W2.5 Things to verify, no change expected

| Item | Expected today | Why B2C needs it |
| --- | --- | --- |
| STOP on Witty's number | `w2_crm_payload` sends `is_opted_out` from `w2_conversations.opted_out`; `student_leads.is_opted_out` becomes true on that turn | The B2C CRM stops every journey and campaign at once (A3) |
| Language | `preferred_language` is sent from `state.language` | B2C picks English or Hindi templates from it. Report the exact values Witty writes (e.g. `english`, `hinglish`, `hindi`) so B2C maps them |
| Proactive follow-ups | `w2_nurture_due` skips leads with `destination_type` set (W1) | Once B2B routes a lead, B2C owns outbound nurture; two senders would double-message |
| `w2_messages` columns | `phone`, `direction`, `kind`, `content`, `created_at`, `sent`, `meta` | The B2C CRM reads these (read-only, through its own function) for the transcript. **Treat them as a published read contract:** tell the B2C CRM before renaming or dropping any of them |

## 2. Decisions (Vikas answered "everything approved" on 14 Oct; these are the choices applied)

| # | Question (W1 §7, §8) | Decision |
| --- | --- | --- |
| D1 | Chatwoot "Counselor Brief" and `witty-handoff` at escalation | **Keep the pause and the label** (they are how Witty goes quiet); **stop posting the Counselor Brief** to Chatwoot: partners get the lead from the B2B CRM and B2C counsellors work in the B2C CRM, which shows the transcript and a "Brief before you call". W2.1 clears the pause for B2C leads without a counsellor |
| D2 | Witty's 3-hour follow-up before the 18-hour unqualified hand-off | **Keep it.** It can bring the student back and finish qualifying, which sends the lead to a partner; the B2C welcome message goes out only after the 18 hours |
| D3 | Qualification help by a B2C counsellor (W1 §8 item 4) | **No Witty change.** The B2C CRM never sets `owner_user_id` for a counsellor who only collects missing details; the details go to the B2B CRM, which re-routes the lead. Witty keeps talking meanwhile |
| D4 | One-tap partner-consent request from Witty's number (W1 §8 item 3) | **Not in W2.** Every new Witty lead gets the consent line (W1/W2.3); leads without partner consent are asked from the B2C number |
| D5 | A later "don't share my details" (W1 §7 item 1) | **Not in W2**; stays open for the B2B side. The B2C CRM treats such a lead as `no_partner_consent` when the B2B CRM says so |
| D6 | Witty speaking after a counsellor is assigned | Witty goes quiet once `owner_user_id` reaches `student_leads`. The B2C CRM writes its activity back every 15 minutes, so for up to 15 minutes after an assignment Witty can still answer. The B2C CRM's assignment message waits until the chat has been idle 10 minutes (B7.6), so the student does not get two voices at once. No Witty change |

## 3. Order of work

1. Version and backup, as W1 §3.1 (workflow version, `pg_get_functiondef` of `w2_try_claim`, `w2_commit_turn`,
   `w2_crm_payload` into `b2b.witty_backup_<date>`).
2. Baseline harness run (W1 §3.2).
3. Ask Vikas for the lawyer's sign-off on the W2.3 wording (once). Without it, ship W2.1, W2.2 and the checks, and hold W2.3.
4. Database migration `w2_witty_b2c` on **staging**: W2.1, W2.2, the `w2_crm_payload` line of W2.3. Run the tests above
   inside `begin … rollback` on test phones. Then production, diffing each function against the backup.
5. Workflow: the W2.3 node edits as a draft; harness on the draft (20/20, plus a turn that shows the v3 line); publish;
   watch 30 minutes (W1 §4.3); clean up test leads.
6. Copy the changed functions into `eduwit-crm/crm/sql/001_lead_intake.sql` so a re-run of 001 cannot revert them (W1 §5).

## 4. Rollback

Restore the saved function definitions from `b2b.witty_backup_<date>` and the previous workflow version. W2.1 and W2.2 are
additive in behaviour (a pause cleared, a touchpoint recorded); W2.3 only changes text and adds a stamp.

## 5. Report back

Versions (before, draft, published); md5 of the changed nodes; harness results (baseline, draft); the staging and
production test results for W2.1–W2.5; the language values Witty writes; whether W1's workflow half had to be applied
first; anything held back (W2.3 without sign-off).
