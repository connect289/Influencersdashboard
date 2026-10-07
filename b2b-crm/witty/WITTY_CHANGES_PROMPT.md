# Prompt: Witty changes for the new lead routing rules

Copy everything below the line into Claude Code, started in your **Eduwit CRM folder** (the OneDrive folder with `CLAUDE.md`,
`crm/` and `witty2/`), with the n8n and Supabase connectors connected. It is self-contained. Reviewed on 7 Oct 2026 by three
independent checks: every edit was re-applied to that day's export of the live workflow and the checksums below matched.

---

You are making the Witty changes required by Eduwit's new lead routing rules. Witty is the **live** WhatsApp bot, so work slowly
and verify every step. Read `CLAUDE.md` first and follow it: patch live nodes by exact snippet, never paste
`witty2/project/dist` over live nodes, check the version history first, one editor at a time, publish only after the Witty
harness passes, no `$$` or `$'` in SQL sent through n8n, test phones `910000…`, the bulk-delete guard.

## 0. Before you start

1. Ask Vikas to confirm that **nobody else** (including the "Locbizz Solution" MCP agent) edits the "Eduwit Witty" workflow
   until you report back.
2. The **n8n MCP** must be connected (you need `get_workflow_history`, `get_workflow_details`, `update_workflow`,
   `publish_workflow`, `restore_workflow_version`, `search_executions`). If it is not, stop and ask Vikas to connect it.
3. **Secrets.** The n8n API key is in `crm/web/.env.local`. Never Read, `cat`, echo, log or write that file or any value in it.
   To find the variable name, run a small Node script that prints only the text before `=` on each non-comment line, and use
   the name containing `N8N` and `KEY`. Scripts read the value themselves. The API base is `https://n8n.eduwit.in/api/v1`
   (not the Cloud Run webhook address).
4. Write every script in **Node.js** (built-in `fetch`, `crypto.createHash('md5').update(code, 'utf8')`). Read and write files as
   UTF-8 without BOM. Never round-trip the workflow through PowerShell `Invoke-RestMethod` / `ConvertTo-Json`.

## 1. Why: the new rules, as they touch Witty

The B2B Partner CRM (repo `connect289/Influencersdashboard`, branch `claude/friendly-darwin-w7cuye`, rulebook
`docs/B2B_CRM_ADDENDUM_3.md`) is now the gateway for every lead. Witty keeps writing every chat turn into `student_leads` through
`lead_intake()`. The B2B CRM decides where each lead goes: an edtech **partner** (the bulk, including paid Meta and Google
leads), or Eduwit's **B2C CRM** (sales lane, or qualification nurture). What involves Witty:

- **Hand-off point** (PART 2): a qualified Witty lead is decided when Witty escalates (HOT hand-off), when the student confirms a
  final programme, or after 30 minutes idle. **Amendment 1:** a Witty lead that is still **unqualified** is decided only after
  **18 hours** with no student message (every message restarts the clock). It then goes to B2C qualification nurture, and the
  **B2C CRM** sends the student a WhatsApp prompting them to explore suitable programmes. The B2B CRM reads the clock from Witty's
  tables (read-only); Witty itself needs no change for it.
- **Qualified** = HOT, WARM or COLD. **Unqualified** = name, email or course missing. Junk and programme mismatch are not passed.
- **PART 7, partner-sharing consent:** every consent line must cover sharing with "our admission partners (edtech companies)";
  record `consent_partner_share_at` and `consent_text_version`. The wording needs Eduwit's lawyer's sign-off. Leads without it
  get a one-tap YES/NO request (PART 7.2).
- **PART 8, Witty changes:** (1) neutral hand-off wording, exactly: "Thank you, {{name}}. An academic counsellor will contact you
  shortly about {{programme}}." (never "our counsellors"; the B2B CRM's notification names the partner); (2) the consent line
  includes admission partners; (3) **keep talking to nurture leads**: Witty goes quiet only when a partner has **accepted** the
  lead or a B2C counsellor is **assigned**; (4) an explicit **interest signal** for leads the B2C CRM holds.

## 2. Already live on production: verify, do not redo

The database half was applied on 7 Oct 2026, 09:40 UTC, as migration `20261007094058` (`w1_witty_addendum3`) on Supabase
`xlseqwgyjuqhktrguhyc`. The previous definitions are in `b2b.witty_backup_20261007` (columns kind, name, def).

| Object | Change |
| --- | --- |
| `w2_crm_owned(text)` | true only if a B2C counsellor is assigned (`owner_user_id` set and the lead is not with a partner), or the lead's B2B allocation (`student_leads.allocation_id` → `b2b.allocations`) is a partner allocation with `status = 'accepted'`. Legacy Eduwit CRM partner allocations keep the old rule. `w2_try_claim` step 1b uses it unchanged. So Witty talks during a partner's hold window and to B2C leads without a counsellor. **Exception:** a lead Witty paused itself at escalation (`bot_paused` plus the `witty-handoff` label) stays silent (see section 8). |
| `w2_nurture_due(int)` | Witty's proactive follow-ups skip leads the B2B CRM has routed (`destination_type` set): the B2C CRM owns outbound nurture from there. Witty still answers inbound messages. |
| `w2_crm_payload(...)` | sends `consent_partner_share_at` and `consent_text_version` from `w2_conversations.state` (keys of the same names). |
| `w2_commit_turn(jsonb)` | a student message with intent `asks_fees`, `asks_eligibility`, `asks_human`, `wants_to_apply`, `pay_after_placement` or `accepted_offer`, on a lead with `destination_type = 'in_house'`, writes event `lead.interest` (key `<phone>:interest:<run_id>`) when Witty's own CRM event does not fire on that turn. |
| `w2_prompts` extractor | v5: the few-shot example quotes "Would you like an academic counsellor to help you with the next steps?" |

Verify, read-only, and stop if anything fails (the database half is then suspect; tell Vikas):
1. The migration row exists in `supabase_migrations.schema_migrations`. `pg_get_functiondef` of `w2_crm_owned` contains
   `a.status = 'accepted'`, `w2_crm_payload` contains `consent_text_version`, `w2_commit_turn` contains `lead.interest`,
   `w2_nurture_due` contains `destination_type is not null`; the extractor prompt is version 5.
2. `b2b.witty_backup_20261007` has a `function` row for each of the four functions and a `prompt` row `extractor:v4`.
3. Health since the change: `search_executions` for Witty since 2026-10-07 09:40 UTC shows no errors in Try Claim, Commit Turn or
   Claim Due; `select count(*) from w2_outbox where created_at > '2026-10-07 09:40+00' and last_error is not null` is 0.

## 3. Release W1: the workflow edits

Workflow **"Eduwit Witty"** `PKPs7tXg9bej8AgX`. Ten exact find-and-replace edits across six Code nodes' `jsCode`. The spec is
machine-readable. `count_per_node` is how many times `find` must occur in **each** listed node before replacing. Edits with
`consent_edit: true` (3, 4, 9) are the consent wording and recording; step 3.3 decides whether they ship. The md5 values are
of each node's `jsCode` (UTF-8 bytes) and are authoritative; `codepoints_*` are Unicode code points (`[...s].length` in JS),
`utf16_*` are JavaScript `.length`.

```json
{
 "workflow_id": "PKPs7tXg9bej8AgX",
 "expected_published_version": "1f79392c-ec02-4daf-a090-1d9d9dbb0a60",
 "nodes": {
  "Plan Reply": {
   "id": "5b306283-52cf-4ae3-90f2-c76e5ab31097",
   "md5_before": "692341e33cc9e903fb81b1e01ce160be",
   "md5_after_full": "0ea87b9b0700c5649a37d5d96e2e24ad",
   "codepoints_before": 60470,
   "utf16_before": 60483,
   "codepoints_after_full": 60475,
   "utf16_after_full": 60488,
   "md5_after_without_consent": "d59634275ad919903f0a4e0ef0640be6",
   "codepoints_after_without_consent": 60331
  },
  "Verify Reply": {
   "id": "165f5f05-ef34-43b7-a2c2-e2191e75a720",
   "md5_before": "7491b0c272ce416dd3b18273b0855793",
   "md5_after_full": "27a78b7c286b62e2dfbab59322507ae6",
   "codepoints_before": 18785,
   "utf16_before": 18789,
   "codepoints_after_full": 18685,
   "utf16_after_full": 18689,
   "md5_after_without_consent": "c50ff11fa867fc4d36184799215babcd",
   "codepoints_after_without_consent": 18541
  },
  "Verify Rewrite": {
   "id": "39c94132-298d-4ff3-bec7-ad03fb2d6f6e",
   "md5_before": "82e6f641e1f5dffb29826af13f2d3c31",
   "md5_after_full": "9c8c4197425e1841568a0c9a6acdf4bf",
   "codepoints_before": 17970,
   "utf16_before": 17974,
   "codepoints_after_full": 17870,
   "utf16_after_full": 17874,
   "md5_after_without_consent": "4c5dc10ba82d9971893df0aef45e32b1",
   "codepoints_after_without_consent": 17726
  },
  "Finalize Counselor": {
   "id": "a90ce11c-f1dc-4a9f-9229-3bc30d0bd99f",
   "md5_before": "9826f83140f491cf5a83c5289a71835c",
   "md5_after_full": "77dfdba0dc487d89e352e8be5b339f8e",
   "codepoints_before": 18714,
   "utf16_before": 18718,
   "codepoints_after_full": 18614,
   "utf16_after_full": 18618,
   "md5_after_without_consent": "5a24d5763c60122145148864dc1c3dbb",
   "codepoints_after_without_consent": 18470
  },
  "Assemble Commit": {
   "id": "967df84b-eda9-4938-8735-30dbfa74d472",
   "md5_before": "a23ccd036fad8fe89c28b3bc89c27976",
   "md5_after_full": "e421a9b3a60b05f3fdf68019ed86ab2f",
   "codepoints_before": 6040,
   "utf16_before": 6044,
   "codepoints_after_full": 6279,
   "utf16_after_full": 6283,
   "md5_after_without_consent": "a23ccd036fad8fe89c28b3bc89c27976",
   "codepoints_after_without_consent": 6040
  },
  "Validate + Decide": {
   "id": "f9e167ab-4b3f-4ecd-80f4-9603f6123f30",
   "md5_before": "d413d9373d348e41011d0f329963b97f",
   "md5_after_full": "a7f3ab6e050eda0c3197162b070070e3",
   "codepoints_before": 55674,
   "utf16_before": 55685,
   "codepoints_after_full": 55725,
   "utf16_after_full": 55736,
   "md5_after_without_consent": "a7f3ab6e050eda0c3197162b070070e3",
   "codepoints_after_without_consent": 55725
  }
 },
 "edits": [
  {
   "edit": 1,
   "consent_edit": false,
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
   "edit": 2,
   "consent_edit": false,
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
   "edit": 3,
   "consent_edit": true,
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
   "edit": 4,
   "consent_edit": true,
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
   "edit": 5,
   "consent_edit": false,
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
   "edit": 6,
   "consent_edit": false,
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
   "edit": 7,
   "consent_edit": false,
   "nodes": [
    "Plan Reply",
    "Validate + Decide"
   ],
   "find": "const type = !s.crm_fingerprint ? 'lead.qualified' : escalate ? 'lead.escalated' : clsChanged ? 'classification_changed' : 'lead.updated';",
   "replace": "const type = escalate ? 'lead.escalated' : !s.crm_fingerprint ? 'lead.qualified' : clsChanged ? 'classification_changed' : 'lead.updated';",
   "count_per_node": 1,
   "why": "B2B hand-off trigger: 'lead.escalated' wins when a lead qualifies and escalates in the same turn"
  },
  {
   "edit": 8,
   "consent_edit": false,
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
   "edit": 9,
   "consent_edit": true,
   "nodes": [
    "Assemble Commit"
   ],
   "find": "s.consent_at = new Date().toISOString(); }",
   "replace": "s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v2'; }",
   "count_per_node": 1,
   "why": "PART 7.1 record partner-sharing consent and the wording version when the new consent line is shown"
  },
  {
   "edit": 10,
   "consent_edit": false,
   "nodes": [
    "Plan Reply"
   ],
   "find": "course: course || 'your program' });",
   "replace": "course: course || (plan.language === 'english' ? 'your programme' : 'aapke programme') });",
   "count_per_node": 1,
   "why": "Hand-off reply fallback when no course is known: 'your programme' / 'aapke programme'"
  }
 ]
}
```

What the edits do: the hand-off reply and the hand-off offer become neutral (edits 1, 2, 5, 6, 10); the consent line on Witty's
first live reply names admission partners (3, 4), and when it is shown Witty sets `state.consent_partner_share_at` (= `consent_at`)
and `state.consent_text_version = 'witty-notice-2026-10-v2'` (9), which reach `student_leads` through the live `w2_crm_payload`;
the two signals the B2B CRM uses to detect a hand-off become reliable (7, 8). `Verify Reply`, `Verify Rewrite` and
`Finalize Counselor` hold copies of the reply texts that are not normally sent: patch them too so every copy matches.
`Validate + Decide` and `Plan Reply` hold byte-identical ENGINE copies: keep them identical. The disabled node "Seed Prompts"
still holds the old offer text in a stale seed: leave it alone (disabled, older than `w2_prompts`, never to be run).

### 3.1 Version and backup
`get_workflow_history`: the newest version and the published one must both be `1f79392c-ec02-4daf-a090-1d9d9dbb0a60` (5 Oct,
"Locbizz Solution"). If anything is newer, stop and ask Vikas. Then one `GET /api/v1/workflows/PKPs7tXg9bej8AgX`: save that exact
response as the backup (e.g. `n8n/backups/Eduwit-Witty-1f79392c.json`) and patch from the same response.

### 3.2 Baseline harness run (before any edit)
Run the harness once on the current version, run_tag `w1a3-before` (procedure in 4.1). This tests the database half on its own
and records the old wording. If it is not 20/20, stop: something other than this release is wrong.

### 3.3 Ask Vikas about the consent wording (once)
Quote the new English and Hinglish consent lines (edits 3 and 4) and the version `witty-notice-2026-10-v2`. Ask: "Has the lawyer
approved this wording, and does continuing the chat after this notice count as consent to share with admission partners? Or do
you want it live pending sign-off?" If he says go (approved, or live pending sign-off): release **full** (all ten edits). If he
says hold: release **without consent** (skip edits 3, 4 and 9: the old notice stays and nothing is stamped; expect the
`md5_after_without_consent` values; `Assemble Commit` then stays unchanged). Record his answer for the report.

### 3.4 Build the patched code (Node script, nothing saved yet)
For each node: its `jsCode` md5 must equal `md5_before`. **If any differs, stop and change nothing**: the code changed since this
spec was made; report the node names and current md5 values to Vikas. Apply the chosen edits with the count check (abort on any
mismatch), confirm no applied `find` text remains, and check the md5 equals the chosen `md5_after_*`. Write each patched node to a
file and run `node --check` on it wrapped as `(async function(){ <code> });`.

### 3.5 Offline tests of the patched code (Node, no network)
The harness cannot see the consent line (harness phones are never "live"), and no harness scenario exercises edits 7 and 8, so
test them here:
1. **Assemble Commit** (full release only): run the patched code as
   `new (Object.getPrototypeOf(async function(){}).constructor)('$input', code)($input)` with `$input.first().json` =
   `{ phone: '910000000001', state: {}, plan: { language: L, answer_mode: 'ANSWER' }, reply: 'Hi', live: true, turn: { route: 'full', message: 'hi', intents: [] } }`
   (add whatever else the code reads), once with L = 'english' and once with 'hinglish'. The reply must end with the new consent
   line for L; `state.consent_partner_share_at === state.consent_at`; `state.consent_text_version === 'witty-notice-2026-10-v2'`.
   With `live: false`, none of the three keys may be set.
2. **ENGINE**: take the text from `const ENGINE = (() => {` to its closing `})();` in the patched Plan Reply (it must be
   byte-identical in the patched Validate + Decide), append `module.exports = ENGINE;`, and call `ENGINE.planReply` on a state
   whose profile has student_name, email_id, interested_course 'MBA' and program_level 'PG' confirmed, plus highest_qualification
   'BCom', academic_score '70%', enrollment_timeline 'now', classification 'UNQUALIFIED', no crm_fingerprint; turn
   `{ route: 'full', intents: [] }`; catalog `{ rows: [{ id: 1, level: 'PG', min_qualification: 'UG', min_pct_general: 50, fee_yearly: 100000 }], total_for_course: 1, specializations: [] }`
   (adjust to what the function needs). Expect `outbox.event_type = 'lead.escalated'` (old code gives 'lead.qualified') and
   `state.phase = 'ESCALATION'`. Call again with the returned state and route 'skip': phase must still be 'ESCALATION' (old code:
   'ENRICH_IT').

### 3.6 Save as a draft (never straight to the published version)
1. **Find out what a PUT does here.** Immediately before, GET again and abort unless `versionId` is still the one from 3.1 and
   equals the published version. PUT the workflow back **unchanged** (`name`, `nodes`, `connections`, `settings` exactly as
   fetched). Read it with `get_workflow_details`. If there is a new `versionId` and the published version is still `1f79392c…`,
   PUT saves a draft: continue with step 2. If the published version moved to the new `versionId`, PUT publishes (harmless now,
   the content is identical): do **not** PUT the edits; save them as a draft with MCP `update_workflow` (`updateNodeParameters` on
   each node's `jsCode`, from your files), or ask Vikas to apply the find/replace pairs in the editor (match case) and Save.
2. Save the edits as a draft (PUT with the patched `nodes`, or as decided above). Send `settings` exactly as fetched. If the API
   answers `request/body/settings must NOT have additional properties`, nothing was saved: drop only the rejected key(s), PUT again,
   and restore them in the editor (Workflow settings) or with MCP `update_workflow` `setWorkflowSettings` before testing.
3. **Read back** and compare with the backup: the six nodes' md5 equal the chosen `md5_after_*`; node count (148), `connections`,
   and every other node's parameters, `disabled`, `credentials` and `typeVersion` unchanged; `settings` equal to the backup
   (including `availableInMCP: true` and `binaryMode: 'separate'`); the "Setup Request" webhook still `disabled: true`; the
   published version still `1f79392c…`. If the published version is no longer `1f79392c…`, live Witty is running untested code:
   publish `1f79392c-ec02-4daf-a090-1d9d9dbb0a60` at once (`publish_workflow` with that `versionId`), then stop and report.
   Record the new draft version id.

**Abort rule:** whenever you stop after saving a draft without publishing it, `restore_workflow_version` to
`1f79392c-ec02-4daf-a090-1d9d9dbb0a60`, confirm the six md5 values are back to `md5_before`, do not publish (the published
version is already `1f79392c`), and report the draft id you discarded.

## 4. Test, then publish

### 4.1 Harness on the draft
Activate `1BGAINw5XDkSHb2q`, `POST https://n8n.eduwit.in/webhook/witty2-test-harness-dev` with
`{ "run_tag": "w1a3-draft-1", "only": ["happy_path_mba","hinglish_parent","general_questions","fee_check_jamia_hamdard","alternatives_and_complaints"] }`,
read `w2_test_runs`, then **always** deactivate the harness (also after a failure). Use a new run_tag for every run. The webhook
answers only after all 20 turns, so if the POST times out do not resend it: poll
`select summary from w2_test_runs where run_tag = '<tag>'`.
- **Proof that the draft ran:** `alternatives_and_complaints` turn 8 (answer_mode HANDOFF, a fixed reply) contains "academic
  counsellor" and not "Academic Counselor". If it shows the old text, the harness ran the published version: the result does not
  count. Do not publish; apply the abort rule; ask Vikas how he wants the draft tested (for example, publish in a quiet hour, run
  the harness at once, and publish `1f79392c` again on any failure).
- **Pass:** 20/20. No harness expectation contains the old wording, so every failed check is real: do not edit the harness. A
  check that fails on latency only may be re-run once; the same turn failing twice is a failure. On failure: abort rule.
- **Extra checks** (read-only SQL, this run's test phones): that hand-off reply reads "Thank you… An academic counsellor will contact
  you shortly about …" (Hinglish: "Ek academic counsellor jald hi …"); that lead has `lead_stage = 'ESCALATION'` and a
  `touchpoints` row `lead.escalated`.

### 4.2 Publish
Right before publishing, `get_workflow_history`: the newest version must be the draft id you recorded. Publish with
`publish_workflow { workflowId: 'PKPs7tXg9bej8AgX', versionId: '<that draft id>' }` and confirm the published version equals it.
Note the time T.

### 4.3 Watch for 30 minutes
About every 10 minutes: `search_executions` for Witty with status error since T is empty;
`select count(*) from w2_outbox where created_at > T and last_error is not null` is 0; outgoing `w2_messages` to real (not
`910000…` / `9190000000NN`) phones since T have `sent = true`. On any execution error in a changed node, or any new outbox error,
roll back (section 6). For the first real conversation after T that got the consent line
(`select phone, state->>'consent_partner_share_at', state->>'consent_text_version' from w2_conversations where consent_at > T`)
confirm both keys and that its `student_leads` row has `consent_partner_share_at` set (`consent_text_version` is write-once, so
it may hold an earlier source's version). If no real conversation arrives in the window, put these queries in the report.
Also report, read-only: `select count(*) from w2_conversations where consent_at is not null and not w2_is_test(phone) and
state->>'consent_text_version' is null` (chats that saw the old notice: they keep it and have no partner consent; **never back-fill**
them; until the PART 7.2 request exists the B2B CRM sends them to B2C).

### 4.4 Clean up (published or rolled back)
Only this release's test phones: the ones in `w2_test_runs.results` for your run_tags (5 per run). Per phone, in one transaction:
delete its rows from every public `w2_*` table with a `phone` column except `w2_test_runs`
(`select table_name from information_schema.columns where table_schema = 'public' and table_name like 'w2\_%' and column_name = 'phone'`),
then `delete from student_leads where whatsapp_number = '<phone>' and is_test` (one row, so the guard does not apply). If a foreign
key blocks it, delete that table's rows for the lead id first. Never use `crm.allow_bulk_delete` for test data. Keep `w2_test_runs`.

## 5. After a successful publish: keep the sources from reverting it

1. `crm/sql/001_lead_intake.sql`: replace `w2_crm_owned` (line ~50), `w2_crm_payload` (~187) and `w2_commit_turn` (~374) with
   production's current definitions (`pg_get_functiondef`), in the file's `$fn$` style. Add a comment above `w2_crm_owned`: it reads
   `b2b.allocations` (B2B CRM schema), so 001 now needs that schema. `w2_nurture_due` is not in 001: find it in Witty's SQL in
   `witty2/project` and update it there. Re-running an old copy would silently revert the new rules.
2. `witty2/project`: first run the unit tests on the unchanged source (`for f in *.test.js; do node --test "$f"; done`) as a
   baseline. Then apply the same changes as the published variant; for each edit report found-and-replaced, changed by hand (source
   formatting differs from the minified node), or absent. Update tests that assert the old wording, event order or phase, add the
   two ENGINE cases from 3.5 as unit tests, and require the same tests to pass as at baseline. Then `node build.js` and
   `node gen/prompts.js`. Never paste `dist` into the live workflow.
3. `crm/sql/test_lead_intake.sql`: add `w2_crm_owned` cases, in one transaction that always ends in `rollback` (never committed;
   B2B cron jobs would act on committed allocations), raising on failure like the other tests: partner allocation `queued` → false;
   `pushed` → false; `accepted` → true; B2C allocation with no owner → false; B2C with an owner → true; partner allocation `pushed`
   with an owner still set → false. Add: on a test phone with `destination_type = 'in_house'` and no owner, `w2_commit_turn` with
   message_ids, intents `['asks_fees']` and no outbox writes a `lead.interest` touchpoint; with an outbox event_type it writes that
   event instead.
4. `CLAUDE.md`: the line "Witty stops chatting once a lead has a CRM owner or partner (`w2_crm_owned`)" becomes "Witty stops chatting
   once a partner has accepted the lead (`b2b.allocations.status = 'accepted'`) or a B2C counsellor is assigned (`owner_user_id`)
   (`w2_crm_owned`, Addendum 3 PART 8.3); a lead Witty paused at escalation stays paused." Also note: Witty's own nurture stops once
   the B2B CRM routes a lead; the consent line names admission partners (lawyer sign-off: <Vikas's answer>); the B2B CRM reads
   Witty tables read-only (`w2_inbox.received_at`, `w2_messages` direction 'in') for the 18-hour rule, so do not rename, purge or
   stop writing them; `last_student_at` is not a reliable student-message clock; "Setup Request" stays disabled and its nodes
   ("Create Witty 2.0 Tables", "Lead Tracking Functions", "Intelligence Layer", "Seed Prompts") must never be run. Same rule change
   in `crm/README.md` (~line 58).

## 6. Rollback

- **Workflow:** `publish_workflow` with `versionId: '1f79392c-ec02-4daf-a090-1d9d9dbb0a60'` (or `restore_workflow_version` then
  publish). The database half works with the old workflow (that is the state before this release), so this is always safe.
- **Database, only with Vikas's OK** (e.g. the baseline in 3.2 fails, or live executions fail inside a `w2_*` function): in one
  transaction through the Supabase connector (not through n8n), run every `function` row's `def` from `b2b.witty_backup_20261007`,
  and restore the extractor prompt from the `prompt / extractor:v4` row with `version = version + 1`. Then re-run the baseline.

## 7. Decisions for Vikas (ask; do not implement without his answer)

1. **Refusals.** If the notice counts as consent, how does Witty record a later "only Eduwit" or "don't share my details"?
   `lead_intake` cannot clear `consent_partner_share_at` (write-once), so it needs a touchpoint such as `consent.partner_declined`
   or a column the B2B CRM reads (the B2B CRM then sends the lead to B2C sales, R8).
2. **Chatwoot hand-off.** At escalation Witty posts the "Counselor Brief", adds the `witty-handoff` label and pauses itself, though
   most qualified leads now go to a partner (the B2B CRM decides after the hand-off, so Witty cannot know the destination then).
   Options: keep it for every escalation; drop the brief and label now that the CRMs own follow-up; or post the brief only when
   `student_leads.destination_type = 'in_house'` at escalation.
3. **Witty's 3-hour follow-up** for unqualified leads still runs before the 18-hour hand-off (it can bring the student back and
   restart the clock). Keep it, or stop proactive messages before the hand-off.
4. **Chats without an access code.** Witty writes a lead only after a valid access code. Check (read-only) how a Meta
   click-to-WhatsApp student gets one; if such students can chat without one, decide whether Witty must record them (PART 1).

## 8. Release W2: Witty changes that ship with the B2B CRM's Addendum 3 release (do not do now)

These are required by the rules but depend on B2B behaviour that is not live yet. List them in your report as pending:
1. **Clearing Witty's escalation pause** (PART 8.3, Addendum 1 §4b, PART 6.1): once `w2_crm_owned` is false and the lead's current
   B2B allocation is in_house with no owner (B2C nurture, including partner-lost after the 7-day grace, and B2C sales with no
   counsellor yet), Witty must answer again. Recommended: in `w2_try_claim`, after step 1b, set `bot_paused = false` (column and
   state) for such leads and remove the Chatwoot label `witty-handoff`; `escalated_at` stays, so Witty never promises a counsellor
   twice.
2. **"Witty again" on CRM-owned leads** (R2, R3): `w2_try_claim` step 1b swallows these messages (`crm_paused`) without calling
   `lead_intake`, so they are not recorded on the lead. Recommended: in step 1b, before the return,
   `begin perform lead_intake(jsonb_build_object('source_system','witty','event_type','chat.reenquiry','idempotency_key', p_phone || ':paused:' || p_run, 'phone', p_phone, 'lead', '{}'::jsonb)); exception when others then null; end;`
   (debounce per day if noisy). Alternative: the B2B CRM reads `w2_messages` kind `crm_paused` read-only (Vikas to approve).
3. **PART 7.2 one-tap consent request** from Witty's number for Witty leads without partner consent (the chats counted in 4.3,
   and every lead if the lawyer requires an explicit YES): "To connect you with the best admission counsellor for {programme}, may
   we share your details with our admission partner? Reply YES or NO." Sent through Chatwoot (free text inside 24 h, an approved
   template outside). Parse the reply in SQL before the AI, in `w2_try_claim` **before** step 1b, strictly (no "ok" or emoji, so a
   feedback answer is never read as consent), and set `pending_question = 'NONE'` when sending so a missed reply is a normal turn.
   YES → `consent_partner_share_at` + version `witty-partner-ask-2026-10-v1`; NO → recorded for the B2B CRM (decision 7.1).
   The B2B CRM triggers the request at the hand-off and handles the 48-hour no-answer rule.
4. **Qualification-assist counsellor** (rulebook "Changes" table, row 3): if B2C assigns a counsellor to help an unqualified nurture
   lead, `owner_user_id` silences Witty, yet only Witty's classification can make a chat lead qualified. Decide: such an assignment
   does not set `owner_user_id`; or `w2_crm_owned` ignores the owner while the B2C allocation is lane nurture, reason
   `not_qualified`; or the B2B CRM accepts "qualified" from the B2C CRM.

## 9. Not Witty's job (context only)

- **B2B CRM** (being built): the 18-hour rule; re-routing nurture leads once they qualify (detect it from `lead_status`
  HOT/WARM/COLD, not only a `lead.qualified` touchpoint, because Witty now emits `lead.escalated` when both happen in one turn);
  consent handling and the 48-hour rule; the 7-day "lost, in grace" period, **planned** as allocation status `accepted` so Witty
  stays quiet (today `apply_partner_lost` still hands the lead to B2C at once; any other status must be added to `w2_crm_owned` in
  the same migration); the partner bar; forwarding Witty's interest to the B2C CRM: every touchpoint after the B2C hand-off on a
  B2C-held lead whose event is `lead.interest`, or `lead.escalated` / `classification_changed` / `lead.updated` with an interest
  intent in `lead.last_intent`.
- **B2C CRM:** send the "explore programmes" WhatsApp as soon as an unqualified Witty lead is pushed to qualification nurture
  (after 18 h); it goes from the B2C number, so it needs a **Meta-approved template**. Assign a counsellor by round robin for
  duplicate-cascade leads, and when a partner-lost nurture lead shows interest (PART 6.1 reactivation).

## 10. Report back

Vikas's answers (one-editor, consent wording); versions (before, draft, published); the variant released; the md5 values after;
harness results (baseline and draft, x/20, the turn-8 proof); offline test results; the 30-minute watch; the old-notice count;
what was cleaned up; files changed; anything pending (section 8) or any decision you hit.
