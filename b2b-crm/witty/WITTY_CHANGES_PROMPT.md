# Prompt: Witty changes for the new lead routing rules

Copy everything below the line into Claude Code, started in your **Eduwit CRM folder** (the OneDrive folder with `CLAUDE.md`,
`crm/` and `witty2/`). It is self-contained.

---

You are making the Witty changes required by Eduwit's new lead routing rules. Read `CLAUDE.md` first and follow it, in particular
the rules on Witty (patch live nodes by exact snippet, never paste `witty2/project/dist` over live nodes, check the version history
first, one editor at a time, publish only after the Witty harness passes, SQL through n8n without `$$` or `$'`, test phones
`910000…`, the bulk-delete guard). Never print secrets; read them from `crm/web/.env.local` in scripts.

## 1. Why: the new rules, as they touch Witty

The B2B Partner CRM (repo `connect289/Influencersdashboard`, branch `claude/friendly-darwin-w7cuye`, rulebook
`docs/B2B_CRM_ADDENDUM_3.md`) is now the gateway for every lead. Witty keeps writing every chat turn into `student_leads` through
`lead_intake()`. The B2B CRM decides where each lead goes: an edtech **partner** (the bulk, including paid Meta and Google leads),
or Eduwit's **B2C CRM** (sales lane or qualification nurture). Rules that involve Witty:

- **Hand-off point** (PART 2): a qualified Witty lead is decided when Witty escalates (HOT hand-off), when the student confirms a
  final programme, or after 30 minutes idle. **Amendment 1:** a Witty lead that is still **unqualified** is decided only after
  **18 hours** with no student message (every message restarts the clock); it then goes to B2C qualification nurture and the
  **B2C CRM** sends the student a WhatsApp prompting them to explore suitable programmes. The B2B CRM measures this from Witty's
  tables (read-only); Witty needs no change for it.
- **Qualified** = HOT, WARM or COLD (sales-ready). **Unqualified** = name, email or course missing. Junk and programme mismatch
  are not passed to any CRM.
- **PART 7, partner-sharing consent:** every consent line must cover sharing with "our admission partners (edtech companies)".
  Record `consent_partner_share_at` and `consent_text_version`. The wording needs Eduwit's lawyer's sign-off.
- **PART 8, Witty changes:** (1) neutral hand-off wording: "Thank you, {{name}}. An academic counsellor will contact you shortly
  about {{programme}}." (never "our counsellors"; the B2B CRM's notification names the partner); (2) the consent line includes
  admission partners; (3) **keep talking to nurture leads**: Witty goes quiet only when a partner has **accepted** the lead or a
  B2C counsellor is **assigned**; (4) an explicit **interest signal** for leads the B2C CRM holds.

## 2. Already live on production (verify, do not redo)

The database half was applied on 7 Oct as migration `20261007094058` (`w1_witty_addendum3`) on Supabase `xlseqwgyjuqhktrguhyc`.
The previous definitions are saved in `b2b.witty_backup_20261007` (columns kind, name, def).

| Object | Change |
| --- | --- |
| `w2_crm_owned(text)` | true only if a B2C counsellor is assigned (`owner_user_id` set and the lead is not with a partner), or the lead's B2B allocation (`student_leads.allocation_id` → `b2b.allocations`) is a partner allocation with `status = 'accepted'`; legacy Eduwit CRM partner allocations keep the old rule. `w2_try_claim` step 1b uses it unchanged, so Witty now talks during a partner's hold window and to B2C leads without a counsellor. |
| `w2_nurture_due(int)` | Witty's proactive follow-ups skip leads the B2B CRM has routed (`destination_type` set): the B2C CRM sends the welcome and journeys. Witty still answers inbound messages. |
| `w2_crm_payload(...)` | sends `consent_partner_share_at` and `consent_text_version` from `w2_conversations.state` (keys of the same names). |
| `w2_commit_turn(jsonb)` | a student message with intent `asks_fees`, `asks_eligibility`, `asks_human`, `wants_to_apply`, `pay_after_placement` or `accepted_offer` on a lead whose `destination_type = 'in_house'` writes outbox/touchpoint event `lead.interest` (key `<phone>:interest:<run_id>`). |
| `w2_prompts` extractor | v5: the few-shot example quotes "Would you like an academic counsellor to help you with the next steps?" |

Verify with read-only SQL: the migration row exists in `supabase_migrations.schema_migrations`; `pg_get_functiondef` of
`w2_crm_owned` contains `a.status = 'accepted'`; `w2_crm_payload` contains `consent_text_version`; `w2_commit_turn` contains
`lead.interest`; `w2_nurture_due` contains `destination_type is not null`; extractor version 5. If any check fails, stop and report.

## 3. The workflow edits (the main job)

Workflow **"Eduwit Witty"** `PKPs7tXg9bej8AgX` on https://n8n.eduwit.in. Nine exact find-and-replace edits across six Code nodes'
`jsCode`. The spec below is machine-readable: `count_per_node` is how many times the `find` text must occur in **each** listed
node before replacing; the md5 values are of each node's `jsCode` string (UTF-8) before and after all edits.

```json
{
 "workflow_id": "PKPs7tXg9bej8AgX",
 "expected_live_version": "1f79392c-ec02-4daf-a090-1d9d9dbb0a60",
 "nodes": {
  "Plan Reply": {
   "id": "5b306283-52cf-4ae3-90f2-c76e5ab31097",
   "jsCode_md5_before": "692341e33cc9e903fb81b1e01ce160be",
   "jsCode_md5_after": "2ef213c12a9f7e061340992b4baa2838",
   "length_before": 60470,
   "length_after": 60421
  },
  "Verify Reply": {
   "id": "165f5f05-ef34-43b7-a2c2-e2191e75a720",
   "jsCode_md5_before": "7491b0c272ce416dd3b18273b0855793",
   "jsCode_md5_after": "27a78b7c286b62e2dfbab59322507ae6",
   "length_before": 18785,
   "length_after": 18685
  },
  "Verify Rewrite": {
   "id": "39c94132-298d-4ff3-bec7-ad03fb2d6f6e",
   "jsCode_md5_before": "82e6f641e1f5dffb29826af13f2d3c31",
   "jsCode_md5_after": "9c8c4197425e1841568a0c9a6acdf4bf",
   "length_before": 17970,
   "length_after": 17870
  },
  "Finalize Counselor": {
   "id": "a90ce11c-f1dc-4a9f-9229-3bc30d0bd99f",
   "jsCode_md5_before": "9826f83140f491cf5a83c5289a71835c",
   "jsCode_md5_after": "77dfdba0dc487d89e352e8be5b339f8e",
   "length_before": 18714,
   "length_after": 18614
  },
  "Assemble Commit": {
   "id": "967df84b-eda9-4938-8735-30dbfa74d472",
   "jsCode_md5_before": "a23ccd036fad8fe89c28b3bc89c27976",
   "jsCode_md5_after": "e421a9b3a60b05f3fdf68019ed86ab2f",
   "length_before": 6040,
   "length_after": 6279
  },
  "Validate + Decide": {
   "id": "f9e167ab-4b3f-4ecd-80f4-9603f6123f30",
   "jsCode_md5_before": "d413d9373d348e41011d0f329963b97f",
   "jsCode_md5_after": "a7f3ab6e050eda0c3197162b070070e3",
   "length_before": 55674,
   "length_after": 55725
  }
 },
 "edits": [
  {
   "nodes": [
    "Plan Reply",
    "Verify Reply",
    "Verify Rewrite",
    "Finalize Counselor"
   ],
   "find": "Thank you for sharing your details{name}. Based on your interest in {course}, I've arranged for one of our Academic Counselors to contact you on this number. They'll help you with the next steps.",
   "replace": "Thank you{name}. An academic counsellor will contact you shortly about {course}.",
   "count_per_node": 1,
   "why": "PART 8.1 neutral hand-off reply (English)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Verify Reply",
    "Verify Rewrite",
    "Finalize Counselor"
   ],
   "find": "Details share karne ke liye thank you{name}. {course} mein aapki interest ke hisaab se maine hamare ek Academic Counselor ko aapse isi number par contact karne ke liye bol diya hai. Woh aapko next steps mein madad karenge.",
   "replace": "Thank you{name}. Ek academic counsellor jald hi aapse {course} ke baare mein contact karenge.",
   "count_per_node": 1,
   "why": "PART 8.1 neutral hand-off reply (Hinglish)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Verify Reply",
    "Verify Rewrite",
    "Finalize Counselor",
    "Assemble Commit"
   ],
   "find": "Your details are used only to help with your admission and may be shared with our partner universities. Reply STOP anytime to opt out.",
   "replace": "Your details are used only to help with your admission and may be shared with our partner universities and our admission partners (edtech companies). Reply STOP anytime to opt out.",
   "count_per_node": 1,
   "why": "PART 7.1 consent line names admission partners (English)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Verify Reply",
    "Verify Rewrite",
    "Finalize Counselor",
    "Assemble Commit"
   ],
   "find": "Aapki details sirf admission help ke liye use hongi aur partner universities ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain.",
   "replace": "Aapki details sirf admission help ke liye use hongi aur hamari partner universities aur admission partners (edtech companies) ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain.",
   "count_per_node": 2,
   "why": "PART 7.1 consent line (Hinglish; appears under keys hinglish and hindi)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Validate + Decide"
   ],
   "find": "Would you like one of our academic counselors to help you with the next steps?",
   "replace": "Would you like an academic counsellor to help you with the next steps?",
   "count_per_node": 1,
   "why": "PART 8.1 hand-off offer without 'our' (English)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Validate + Decide"
   ],
   "find": "Kya aap chahenge ki hamare ek academic counselor next steps mein aapki madad karein?",
   "replace": "Kya aap chahenge ki ek academic counsellor next steps mein aapki madad karein?",
   "count_per_node": 1,
   "why": "PART 8.1 hand-off offer without 'our' (Hinglish)"
  },
  {
   "nodes": [
    "Plan Reply",
    "Validate + Decide"
   ],
   "find": "const type = !s.crm_fingerprint ? 'lead.qualified' : escalate ? 'lead.escalated' : clsChanged ? 'classification_changed' : 'lead.updated';",
   "replace": "const type = escalate ? 'lead.escalated' : !s.crm_fingerprint ? 'lead.qualified' : clsChanged ? 'classification_changed' : 'lead.updated';",
   "count_per_node": 1,
   "why": "B2B hand-off trigger: 'lead.escalated' must win when a lead qualifies and escalates in the same turn"
  },
  {
   "nodes": [
    "Plan Reply",
    "Validate + Decide"
   ],
   "find": "s.phase = 'ESCALATION'; s.bot_paused = true; }\nelse if (mode === 'SUPPORT') s.phase = 'SUPPORT';",
   "replace": "s.phase = 'ESCALATION'; s.bot_paused = true; }\nelse if (s.escalated_at && s.bot_paused) s.phase = 'ESCALATION';\nelse if (mode === 'SUPPORT') s.phase = 'SUPPORT';",
   "count_per_node": 1,
   "why": "B2B hand-off trigger: lead_stage stays ESCALATION while Witty is paused after a hand-off"
  },
  {
   "nodes": [
    "Assemble Commit"
   ],
   "find": "s.consent_at = new Date().toISOString(); }",
   "replace": "s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v2'; }",
   "count_per_node": 1,
   "why": "PART 7.1 record partner-sharing consent and the wording version when the consent line is shown"
  }
 ]
}
```

What the edits do: the hand-off reply and the hand-off offer become neutral; the consent line on Witty's first live reply names
admission partners, and when it is shown Witty sets `state.consent_partner_share_at` (= `consent_at`) and
`state.consent_text_version = 'witty-notice-2026-10-v2'`, which reach `student_leads` through the live `w2_crm_payload`; the two
signals the B2B CRM uses to detect a hand-off become reliable. Notes: `Verify Reply`, `Verify Rewrite` and `Finalize Counselor`
hold copies of the reply texts that are not normally sent; patch them too so every copy matches. `Validate + Decide` and
`Plan Reply` hold byte-identical ENGINE copies; keep them identical.

Steps:

1. `get_workflow_history` (n8n MCP) or the API: the live/published version must be `1f79392c-ec02-4daf-a090-1d9d9dbb0a60`
   (5 Oct, "Locbizz Solution") with nothing newer. If anyone edited it since, stop and ask Vikas.
2. Save a full backup of the current workflow JSON (e.g. `n8n/backups/Eduwit-Witty-1f79392c.json`).
3. Apply the edits with a small script, not by hand-copying code: fetch the workflow with the n8n public API
   (`GET /api/v1/workflows/PKPs7tXg9bej8AgX`, header `X-N8N-API-KEY` from `crm/web/.env.local`), check each node's
   `jsCode_md5_before`, apply each edit with the count check (abort on any mismatch, change nothing), check `jsCode_md5_after`,
   run `node --check` on each patched node wrapped as `(async function(){ <code> });`, then `PUT /api/v1/workflows/PKPs7tXg9bej8AgX`
   with `name`, `nodes`, `connections` and `settings` (if the API rejects unknown `settings` keys, send only the keys it accepts).
   Read the workflow back and confirm the six md5 values and that no other node's parameters changed. Confirm the published
   version is still `1f79392c` (the edit is a draft until published). If md5 values before differ, the live code changed since this
   spec was made: apply the edits only if every `find` still matches with the expected count, and report the new md5 values.
4. Bring the local source in step: apply the same `find` → `replace` pairs in `witty2/project` wherever the old text exists,
   update unit tests that assert the old wording, then run `cd witty2/project`, `for f in *.test.js; do node --test "$f"; done`
   (all must pass), `node build.js`, `node gen/prompts.js`. Do **not** paste `dist` into the live workflow.

## 4. Test, then publish

1. Run the Witty harness as in `CLAUDE.md`: activate `1BGAINw5XDkSHb2q`, `POST https://n8n.eduwit.in/webhook/witty2-test-harness-dev`
   with `{ "run_tag": "w1-addendum3", "only": ["happy_path_mba","hinglish_parent","general_questions","fee_check_jamia_hamdard","alternatives_and_complaints"] }`,
   read `w2_test_runs`, then deactivate the harness. Baseline **20/20**. The harness runs Witty's saved workflow through Execute
   Workflow; confirm from the transcript that replies use the new wording (so it tested the draft). If a check fails only because
   it expects the old wording, update that expectation in the harness and re-run; any other failure: roll back (section 6).
2. Extra checks on a harness conversation that reached its first live reply and, if any, its hand-off (test phones only, read-only
   SQL): `w2_conversations.state` has `consent_partner_share_at` and `consent_text_version = 'witty-notice-2026-10-v2'`; the test
   lead in `student_leads` has both columns set; a hand-off reply reads "An academic counsellor will contact you shortly about …";
   the escalated lead has `lead_stage = 'ESCALATION'` and a `lead.escalated` touchpoint.
3. Publish the workflow (n8n MCP `publish_workflow`, or Publish in the editor). Confirm the new published version id.
4. Watch the first live conversations: no new `w2_outbox` rows with `status = 'pending'` and an error, replies sending normally.
5. Clean up the harness's `910000…` test leads as `CLAUDE.md` describes (more than 5 rows needs `set local crm.allow_bulk_delete = 'on'`
   and a backup table in the same transaction). Never touch real leads.

## 5. Keep the sources from reverting the live changes

1. `crm/sql/001_lead_intake.sql`: replace the bodies of `w2_crm_owned` (line ~50), `w2_crm_payload` (~187) and `w2_commit_turn` (~374)
   with production's current definitions (`pg_get_functiondef`), keeping the file's `$fn$` style. `w2_nurture_due` is not in 001: find
   it in Witty's own SQL in `witty2/project` and update it there. Re-running an old copy of any of these would silently revert the
   new rules.
2. n8n's "Setup Request" webhook (`/webhook/witty2-setup-rtf2bfa2`, nodes "Create Witty 2.0 Tables" and "Intelligence Layer") holds
   very old copies of `w2_try_claim`, `w2_commit_turn` and `w2_nurture_due` (no CRM gate, no CRM sync). Running it would break Witty.
   Disable the "Setup Request" trigger node in the same draft (setNodeDisabled), unless Vikas prefers to replace the SQL there.
3. `crm/sql/test_lead_intake.sql`: add `w2_crm_owned` cases on test phones (inside a rolled-back transaction or with cleanup):
   partner allocation `queued` → false; `pushed` → false; `accepted` → true; B2C allocation with no owner → false; B2C with an
   owner → true; partner allocation `pushed` with an owner still set → false.
4. Documentation: `CLAUDE.md` line "Witty stops chatting once a lead has a CRM owner or partner" becomes "Witty stops chatting once a
   partner has accepted the lead (`b2b.allocations.status = 'accepted'`) or a B2C counsellor is assigned (`owner_user_id`)
   (`w2_crm_owned`, Addendum 3 PART 8.3)"; the same in `crm/README.md` (~line 58). Note in `CLAUDE.md` that Witty's own nurture
   stops once the B2B CRM routes a lead, and that the consent line names admission partners (lawyer sign-off pending).

## 6. Rollback

Workflow: restore version `1f79392c-ec02-4daf-a090-1d9d9dbb0a60` (n8n `restore_workflow_version`) and publish it. Database (only if
Vikas asks): for each row of `b2b.witty_backup_20261007` with kind `function`, run its `def`; restore the extractor prompt from the
row `prompt / extractor:v4` with `version = version + 1`.

## 7. Decisions for Vikas (do not implement without his answer)

1. **Explicit YES/NO consent.** If the lawyer says the first-reply notice is not enough (DPDP wants a clear affirmative action), Witty
   needs the PART 7.2 one-tap request ("To connect you with the best admission counsellor for {programme}, may we share your details
   with our admission partner? Reply YES or NO."), sent through Chatwoot from Witty's number (free text inside 24 h, an approved
   template outside), with the reply parsed in SQL before the AI (in `w2_try_claim`, before the CRM-ownership gate) so a "YES" is
   never read as an answer to another question, YES → `consent_partner_share_at` + version, NO → recorded for the B2B CRM (which
   sends the lead to B2C sales). Not built now: production holds no Witty leads from before the new consent line.
2. **Chatwoot hand-off for partner-bound leads.** At escalation Witty still posts the "Counselor Brief", adds the `witty-handoff` label
   and pauses itself, although most qualified leads now go to a partner. Options: keep it, or skip the brief for leads the B2B CRM
   will route to partners.
3. **Unpausing for B2C nurture.** A lead Witty paused at escalation stays silent even if it ends up in B2C nurture without a counsellor
   (e.g. no consent answer within 48 h). PART 8.3 wants Witty to keep talking to such leads. Option: clear the pause when the lead's
   B2B allocation is B2C nurture with no owner.
4. **Witty's 3-hour follow-up** for unqualified leads still runs before the 18-hour hand-off (it can bring the student back and restart
   the clock). Keep it, or stop all proactive messages before the hand-off.
5. **"Shortly".** The hand-off reply promises contact "shortly"; under the rules a lead with no partner consent answer waits up to
   48 hours. Keep the word or soften it.

## 8. Not Witty's job (context only)

- **B2B CRM** (being built): the 18-hour rule, re-routing nurture leads to partners once they qualify, consent handling, the 7-day
  "lost, in grace" period (kept as allocation status `accepted`, so Witty stays quiet), partner bar for duplicate and lost leads.
- **B2C CRM:** send the "explore programmes" WhatsApp as soon as a lead arrives in qualification nurture. It goes from the B2C number,
  so it needs a **Meta-approved template**. Assign a counsellor by round robin for duplicate-cascade leads.

## 9. Report back

Versions (before, draft, published), the six md5 values after, harness result (x/20), the extra checks, what was cleaned up, the
files changed, and any decision you hit.
