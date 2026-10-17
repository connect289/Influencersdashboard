# Phase 0 discovery: how Witty is built today, and how `web_advisor` can share its core

Date: 2026-10-17. Author: Phase 0 discovery (read-only). Spec references: `WEBSITE_SPEC.md` §3A (Witty path), §7, §18 Q3–Q4.

Verbatim prompt bodies: [`witty-prompts.md`](./witty-prompts.md). Related: [`crm-conventions.md`](./crm-conventions.md) (lead
sources, consent texts, `lead_intake` contract seen from the CRM side).

---

## 0. Key findings (read this first)

1. **Witty is not a free-form "agent with tools".** It is a deterministic n8n pipeline (workflow "Eduwit Witty",
   `PKPs7tXg9bej8AgX`, 148 nodes) with **two narrow LLM calls**: an **extractor** (facts + intents as JSON, with
   character-exact evidence) and a **counselor** (writes one reply in a given `answer_mode`, with `{{P1.fee}}`-style
   placeholders that code fills). Everything in between (what to ask next, eligibility, classification HOT/WARM/COLD,
   phase, hand-off, catalogue search, consent) is **JavaScript in n8n Code nodes** (an object called `ENGINE`, duplicated
   byte-for-byte in "Plan Reply" and "Validate + Decide") plus **Postgres functions** (`w2_*`). A verifier then checks every
   reply (unsourced claims, unverified numbers, length) and either rewrites it once or falls back to a fixed text.
2. **LLM: Google Gemini, model `gemini-3.6-flash`, for both calls**, with Gemini explicit context caching of the two system
   prompts (`w2_gemini_caches`, refreshed by a 15-minute branch). No Anthropic/OpenAI model is used.
3. **Prompts live in `public.w2_prompts`** (PK `name`, one row per name, integer `version`, no history in-table):
   `counselor` v6 (2026-10-05) and `extractor` v6 (2026-10-16). `w2_build_prompt(name)` appends a generated catalogue index
   (extractor only) and any approved "lessons" from `w2_learnings`. Old versions are kept in `b2b.witty_backup_<date>`.
4. **The decision logic is not in the database.** The ask order, the HOT/WARM/COLD rule, readiness, the hand-off trigger and
   the reply texts (ASK_TEXT, consent line, hand-off line) are in the n8n `ENGINE` code. **The n8n workflow could not be
   read** (n8n MCP down; no export in this repo). Its source is `witty2/project` (build.js, gen/prompts.js, `*.test.js`)
   on the owner's machine, also not in this repo. Section 4.4 gives the classification rule **as observed in data**, not
   as written in code. Getting the export (or `witty2/project`) is the top open item.
5. **"Witty 2.0" is already live.** The `w2_*` schema *is* Witty 2.0 (harness "Witty 2.0 · Test Harness", webhook
   `witty2-test-harness-dev`, source folder `witty2/`). It replaced Witty 1 (an n8n chat agent with
   `n8n_chat_histories` memory, 1,338 legacy rows) around 1–5 Oct 2026 (data wiped 5 Oct). It has had releases W1 (7 Oct),
   W2 (14 Oct, B2C CRM) and W3 "soft gate" (16 Oct). W2/W3 SQL is on production but **not in this repo**. No evidence was
   found of a further multi-agent rebuild beyond this extractor → engine → counselor → verifier pipeline.
6. **Hazards for naive sharing (all verified on production):**
   - `w2_conversations` is keyed by **phone** (PK). A website chat for a phone that also chats on WhatsApp would share one
     row: one lock, one `pending_question`, one `bot_paused`, one state. The web channel cannot use it as is.
   - `w2_messages` has **no channel column**, and four CRM functions compute the **WhatsApp 24-hour service window** and
     "student last inbound" from `w2_messages where phone = … and direction = 'in'` (`crm_whatsapp_window__impl`,
     `b2b.student_last_inbound`, `b2b.reenquiry_scan`, `b2c.may_market`, `b2c.witty_busy`, `crm_marketing_allowed`).
     Writing web messages there under the student's phone would make the CRMs believe a WhatsApp window is open and could
     cause free-form WhatsApp sends outside Meta's 24-hour window. **Do not write web turns into `w2_messages` until a
     `channel` column exists and those readers filter on it.**
   - `w2_commit_turn` → `w2_crm_payload` hard-codes `source_system = 'witty'`, `channel = 'whatsapp'`,
     `first_agent_channel = 'whatsapp'`, and `lead_intake` stamps `phone_verified_at = now()`,
     `phone_verification_method = 'whatsapp_inbound'` on new leads when `source_system = 'witty'`. Using it for the web
     would falsely mark an unverified website phone as verified.
7. **Good news: the approved lead path for the web already exists.** `lead_intake()` already treats
   `source_system = 'web_agent'` as a trusted agent source (same overwrite rules as Witty) and accepts `web_session_id`.
   The website can write the same lead keys `w2_crm_payload` builds, with `source_system = 'web_agent'`, **with zero changes**.

---

## 1. Sources used, and what could not be seen

| Source | Used for | Status |
| --- | --- | --- |
| `b2b-crm/witty/README.md`, `WITTY_CHANGES_PROMPT.md`, `patch_nodes.py` | Node names, ids and md5s; exact live snippets (hand-off, consent, event-type and phase lines); ENGINE test fixtures | Read |
| `b2c-crm/docs/WITTY_CHANGES_B2C.md` | Release W2 (pause clearing, re-enquiry, marketing consent v3, `w2_messages` read contract) | Read |
| `docs/B2B_CRM_PROMPT.md`, `ADDENDUM_1..4`, `b2b-design.md`, `phase0-audit.md`, `b2c-contract.md`, `go-live-setup.md`, `HANDOVER.md` | How the CRMs read Witty's signals (`lead_status`, `lead_stage`, touchpoints) | Grepped / read in part |
| `b2b-crm/supabase/migrations/20261007094058_w1_witty_addendum3.sql`, `00000000000000_baseline.sql` | `w2_*` DDL, W1 function bodies | Read |
| Production Supabase `xlseqwgyjuqhktrguhyc` (read-only `SELECT`, `pg_get_functiondef`, `pg_catalog`) | Prompts, all 57 `w2_*` functions, table shapes, enum values, distinct keys, model names, test runs, migration list | Read |
| n8n workflow "Eduwit Witty" `PKPs7tXg9bej8AgX` | Node graph, ENGINE code, per-turn input JSON | **Not accessible** (n8n MCP failed to connect; no export in repo) |
| `witty2/project` (source of the n8n Code nodes, unit tests) | ENGINE rules, ASK_TEXT, classification | **Not in this repo** (on the owner's machine) |
| Migrations `w2_witty_b2c` (14 Oct) and `w3_witty_*` (16 Oct) | W2/W3 changes | Seen only on production (`supabase_migrations.schema_migrations`), **not in repo** |

No personal data was copied into these files. Counts below are aggregates; message contents were not exported.

---

## 2. Architecture

### 2.1 Components

```
Student (WhatsApp, +91 96439 77407)
  │  Meta Cloud API
  ▼
Chatwoot (chat.eduwit.in, inbox 4)  ── webhook ──►  n8n "Eduwit Witty" (n8n.eduwit.in, GCP VM n8n-vm, India region)
                                                       │
         ┌─────────────────────────────────────────────┤ Postgres credential "Postgres account" (privileged role)
         ▼                                             ▼
  w2_inbox_add(p)                              w2_try_claim(phone, run, 45s)   ← lease + all gates in SQL
  (w2_inbox + w2_messages 'in')                      │ returns conversation, messages, access, prompts (cache names)
                                                     ▼
                         [Code] route: blocked / crm_paused / agent_paused / feedback / gate / greeting / skip / full
                                                     ▼
                         Gemini gemini-3.6-flash  ← cached system prompt "extractor"   (facts, enquirer, intents)
                                                     ▼
                         [Code] Validate + Decide (ENGINE): accept/reject facts, update profile,
                                eligibility, readiness, classification, phase, next ask, answer_mode, escalate?
                                                     │  w2_search_programs_cached(q)  (catalogue)
                                                     │  w2_kb_search(p)               (knowledge base, embeddings + FTS)
                                                     ▼
                         [Code] Plan Reply (ENGINE copy): task JSON for the counselor, P-rows, facts
                                                     ▼
                         Gemini gemini-3.6-flash  ← cached system prompt "counselor"   ({"reply": "..."})
                                                     ▼
                         [Code] Verify Reply → (Verify Rewrite, one retry) → Finalize Counselor / fixed / fallback
                                fill {{Pn.*}} placeholders from catalogue rows, append consent line on first live reply
                                                     ▼
                         [Code] Assemble Commit → Chatwoot send → w2_commit_turn(p)   (one transaction)
                                                     │   on send failure: w2_send_failed(phone, run, error)
                                                     ▼
                         lead_intake(w2_crm_payload(...))  → student_leads + touchpoints   (failure → w2_outbox, retried)
```

Side workflows / branches seen through their functions: prompt-cache refresh every 15 min (`w2_cache_plan`,
`w2_cache_saved`, `w2_turn_prompts`); outbox retry every minute (`w2_outbox_retry`, `w2_outbox_claim`, `w2_outbox_result`);
nurture follow-ups (`w2_nurture_due`, `w2_nurture_done`, `w2_nurture_offset`; first at +3 h, 09:00–20:00 IST only,
UNQUALIFIED/PROGRAM_MISMATCH only); Chatwoot human take-over (`w2_agent_pause`: 4-hour silence); bot/abuse defence
(`w2_bot_check`, `w2_blocks`, `w2_meta.bot_rules`); Google Drive → knowledge base sync (`w2_drive_*`, `w2_kb_*`); weekly
learning review (`w2_learning_digest`, `w2_learning_save`, trigger `w2_learning_apply`); alerts (`w2_health_digest`,
`w2_health_alerts`, W3); access-code issuing for links/QR (`w2_issue_code`, `w2_register_lead`, `w2_redeem_code`,
`w2_clicks`, `w2_sources`); test harness (`w2_test_*`, workflow `1BGAINw5XDkSHb2q`). The disabled "Setup Request" webhook
holds stale seed SQL and must never run.

### 2.2 Known n8n Code nodes (from `patch_nodes.py` and W1 docs)

| Node | Id | What it holds |
| --- | --- | --- |
| Plan Reply | `5b306283-52cf-4ae3-90f2-c76e5ab31097` | `ENGINE` (copy 1, ~60 KB): `planReply`, `ASK_TEXT` (incl. `OFFER_HANDOFF`), hand-off reply, consent line, outbox event-type rule, phase rule |
| Validate + Decide | `f9e167ab-4b3f-4ecd-80f4-9603f6123f30` | `ENGINE` (copy 2, byte-identical to Plan Reply's) |
| Verify Reply | `165f5f05-ef34-43b7-a2c2-e2191e75a720` | Checks the counselor reply; copies of fixed texts |
| Verify Rewrite | `39c94132-298d-4ff3-bec7-ad03fb2d6f6e` | One rewrite attempt; copies of fixed texts |
| Finalize Counselor | `a90ce11c-f1dc-4a9f-9229-3bc30d0bd99f` | Fills placeholders, final text; copies of fixed texts |
| Assemble Commit | `967df84b-eda9-4938-8735-30dbfa74d472` | Builds the `w2_commit_turn` payload; sets consent stamps and `consent_text_version` |
| Seed Prompts (disabled) | – | Stale prompt seed, older than `w2_prompts`; never run |

### 2.3 LLM provider and models

- Provider: **Google Gemini** (Vertex/Gemini API; one historic error reads "Lightning dunning decision is deny for project:
  projects/N", i.e. a GCP billing block, 12 occurrences before 4 Oct).
- Model: **`gemini-3.6-flash`** for extractor and counselor (`w2_gemini_caches.model`; `w2_messages.model` =
  `"gemini-3.6-flash + gemini-3.6-flash"` on full turns, `"gemini-3.6-flash"` when only the extractor ran).
  `w2_learning_reports.model` is also `gemini-3.6-flash`. Harness summaries say `counselor_model: "default"`.
- Embeddings: `w2_kb_chunks.embedding vector(768)` (model not recorded in the DB; 768-d suggests a Google text-embedding model).
- Prompt caching: explicit Gemini caches. Extractor cache ≈ 6,163 tokens, counselor ≈ 4,678 tokens. Refresh window 40 min
  before expiry; `w2_turn_prompts()` hands the cache names to each turn and falls back to the plain text.
- Latency (harness, 20 turns): p50 ≈ 6.0–6.2 s, p90 ≈ 6.7–7.0 s per turn (not streaming; WhatsApp).

### 2.4 Where conversation state lives

| Table | Key | Content |
| --- | --- | --- |
| `w2_conversations` | **`phone`** (PK) | Columns: `state jsonb`, `classification` (default `UNQUALIFIED`), `readiness` (default `EXPLORING`), `eligibility` (default `INSUFFICIENT_DATA`), `pending_question` (default `NONE`), `bot_paused`, `opted_out`, `consent_at`, `escalated_at`, `lead_source`, `access_code`, `access_at`, `attribution`, `last_student_at`, `nurture_step`, `nurture_next_at`, `crm_record_id`, `version`, `lock_id`, `lock_until`, Chatwoot `conversation_id`/`account_id` |
| `w2_conversations.state` keys (observed) | – | `profile`, `phase`, `classification`, `readiness`, `eligibility`, `pending_question`, `pending_value`, `asks` (count per ask), `flags` (`shown_ids`, `exclude_specs`, `specialization_asked`, `programs_shown_key`, `complaints`, `shown_rows`, `consent_set_run`), `language`, `enquirer` {name, relation}, `recent_turns` [{role, text}], `turn_count`, `revisits`, `fallback_streak`, `last_ask_text`, `crm_fingerprint`, `bot_paused`, `opted_out`, `consent_at`, `consent_partner_share_at`, `consent_marketing_at`, `consent_text_version`, `escalated_at`, `lead_source`, `activation_code`, `access` {code, via, at}, `attribution`, `feedback_asked_at`, `feedback_asked_mode`, `gate_count`, `paused_by`/`paused_at`/`paused_agent` (W3) |
| `state.profile.<field>` | – | `{value, status: confirmed / unconfirmed / declined, turn, scale?}`; `final_program` = `{status, id, university, program_name, at}` |
| `w2_inbox` | `message_id` | Raw inbound (Chatwoot), `received_at`, `claimed_by`, `processed_at`, `referral` (click-to-WhatsApp, W3) |
| `w2_messages` | `id` | Transcript, both directions (section 7) |
| `w2_fact_log` | `id` | Every extracted fact, accepted or rejected, with evidence, op, subject, reason, model |
| `w2_events` | `id` | `turn` (diagnostics per turn), `handoff` (brief + team), `agent_takeover`, `send_failed` |
| `w2_outbox` | `idempotency_key` unique | CRM events sent / pending retry |

---

## 3. One turn, step by step (as far as visible)

1. Chatwoot webhook → `w2_inbox_add`: stores the message in `w2_inbox` and a `w2_messages` row (`direction='in'`, `kind='chat'`).
2. `w2_try_claim(phone, run_id, 45)`: takes a 45 s lease on the conversation, claims all unprocessed inbox rows (so bursts of
   messages are answered together), then in order:
   1. **Bots/abuse:** blocked number → no reply (`kind='blocked'`).
   2. **CRM owns the lead** (`w2_crm_owned`: partner accepted, or a B2C counsellor assigned) → silent, `kind='crm_paused'`,
      one `chat.reenquiry` touchpoint per day via `lead_intake` (W2.2).
   3. **Pause clearing** (W2.1): escalated-and-paused chat whose lead is now with B2C and has no counsellor → `bot_paused=false`.
   4. **Human agent pause** (W3): 4 h silence after a Chatwoot agent replied (`kind='agent_paused'`).
   5. **Feedback** one-tap reply to "Was this chat helpful?" within 48 h → `w2_feedback`, `kind='feedback'`, no reply.
   6. **Access / attribution** (W3 soft gate, 16 Oct): a code in the text binds ad/creator attribution; otherwise the chat is
      bound as `DIRECT` (organic `whatsapp_direct`) or, with a click-to-WhatsApp referral, as `influencer` (`via='ctwa'`).
      **Every chat is now a lead from its first message** (before W3, a valid access code was required: route `gate`).
   7. Returns conversation, messages, access, `prompts` (cache names/text) and KB readiness.
3. Routes seen in `w2_events.payload.route`: `full` (normal), `gate`, `greeting`, `skip`.
4. Extractor call (Gemini, cached `extractor` prompt) with `{pending_question, witty_last_message, known_profile, student_message}`.
5. ENGINE (Validate + Decide): validates each fact (evidence must appear in the message; reject reasons seen:
   `"Test" is a stopword`, `confirm without a name read back`, `hesitation is not a refusal`), updates `profile`,
   computes eligibility from catalogue minimums, readiness, classification, phase, the next ask, `answer_mode`, escalation.
6. Catalogue: `w2_search_programs_cached(q)`; knowledge: `w2_kb_search` only for general questions.
7. Counselor call (Gemini, cached `counselor` prompt) with the task JSON; returns `{"reply": "..."}`.
8. Verify: observed checks (`verify_errors`): `unsourced claim "<word>"` (ugc, equivalent, validity, valid, recognized,
   approval, approved, accreditation, deb), `general question answered without a source`, `unverified number …`,
   `too long`; then `(fixed on rewrite)`, `rewrite: empty rewrite`, `(no time for a rewrite)`, `(no time for the counselor: -N ms left)`.
   `reply_source` ∈ `counselor`, `rewrite`, `fixed` (deterministic text, e.g. HANDOFF, GATE, GREETING), `fallback`.
   There is a per-turn time budget (`budget_left_ms`, `elapsed_ms`, `turn_ms` in the turn event).
9. Assemble Commit: consent line appended on the first live reply (sets `consent_at`, `consent_partner_share_at`,
   `consent_marketing_at` if W2.3 shipped, `consent_text_version`, `flags.consent_set_run`); send via Chatwoot;
   `w2_commit_turn(p)`; if the send fails, `w2_send_failed` marks the message unsent and **withdraws** the consent stamped on it.

---

## 4. Qualification contract

### 4.1 Fact keys (extractor `field` values, exact)

`student_name, last_name, email_id, interested_course, specialization, field_of_interest, program_level,
highest_qualification, current_study, academic_score, annual_budget, enrollment_timeline, primary_motivation,
study_mode_preference, current_city_country, study_destination, university_preference, work_experience_years,
current_job_role, chosen_program` (+ `enquirer` {name, relation} for parents/siblings writing on a student's behalf).

Per fact: `value`, `evidence` (exact substring, 1–8 words), `op` ∈ set / correct / confirm / negate / declined / unsure,
`subject` ∈ self / child / sibling / other, `scale` (academic_score: percent / cgpa10 / gpa4 / unknown), `confidence`
HIGH / MEDIUM / LOW. `chosen_program` (v6) is resolved by code to `profile.final_program`.

Fact keys seen in `w2_fact_log` (incl. the 1–4 Oct backup): program_level, interested_course, study_mode_preference,
highest_qualification, academic_score, student_name, specialization, email_id, university_preference, annual_budget,
current_job_role, primary_motivation, current_city_country, last_name, work_experience_years, enrollment_timeline.

### 4.2 Profile → CRM payload → `student_leads` column

| `state.profile` key | `w2_crm_payload` lead key | `student_leads` column (via `lead_intake` map) |
| --- | --- | --- |
| student_name | full_name, is_name_confirmed | student_name, name_confirmed |
| email_id | email, is_email_confirmed | email_id, email_confirmed |
| interested_course | interested_course | interested_course |
| specialization | interested_specialization | interested_specialization |
| field_of_interest | field_of_interest | field_of_interest |
| university_preference | university_preference | university_preference |
| final_program (confirmed) | interested_university, final_program_id, final_program_name, final_program_confirmed_at | interested_university (others not in `lead_intake`'s allowed list → dropped) |
| flags.shown_rows | programs_shown | (not in allowed list → dropped) |
| program_level | programme_level | program_level |
| study_mode_preference | study_mode_preference | study_mode_preference |
| highest_qualification | highest_qualification | highest_qualification |
| current_study | current_study | current_study |
| academic_score | academic_score_raw, academic_score_pct (`crm_num`) | academic_percentage_gpa, academic_score_pct |
| work_experience_years | work_experience_raw, work_experience_years_num | work_experience_years, work_experience_years_num |
| current_job_role | current_job_role | current_job_role |
| annual_budget | annual_budget_raw, annual_budget_inr | annual_budget, annual_budget_inr |
| enrollment_timeline | enrollment_timeline | enrollment_timeline |
| primary_motivation | primary_motivation | primary_motivation |
| current_city_country | location_raw | current_city_country |
| state.language | preferred_language (`english` / `hinglish` / `hindi`) | preferred_language |
| state.enquirer | enquirer_relation, guardian_name (father/mother/parent) | enquirer_relation, guardian_name |
| classification | classification, classification_ai | **lead_status**, lead_classification |
| readiness | readiness | admission_readiness |
| eligibility | eligibility | eligibility_status |
| state.phase | conversation_phase | **lead_stage** |
| turn intents | last_intent (comma list) | intent_type |
| lead_source / attribution | source, source_detail, campaign, utm_*, click_ids, landing_url, referrer_url, referred_by_code, access_code, ip, device, fingerprint | lead_source, … (first-touch only) |
| consent | consent_sales_at (= consent_at), consent_partner_share_at, consent_marketing_at, consent_text_version, consent_partner_share_declined_at | consent_* (first-touch, write-once; `…declined_at` not in allowed list → dropped) |
| – | channel = `'whatsapp'`, first_agent_channel = `'whatsapp'` (hard-coded) | channel, first_agent_channel |
| opted_out, bot_paused, conversation_id | is_opted_out, is_bot_paused, chatwoot_conversation_id | is_opted_out, is_bot_paused, chatwoot_conversation_id |
| – | last_agent_message_at (now() when a reply was logged) | last_agent_message_at |

`lead_intake` then sets `temperature` = lower(HOT/WARM/COLD), `is_sales_ready = true` on the first HOT/WARM/COLD,
`stage` new → qualifying, and writes a `touchpoints` row (`lead.created` / the event type) unless it is a plain merged
`chat.turn`. It returns `crm_owned` (= `w2_crm_owned`).

### 4.3 Conversation phases, asks, modes, enums

- **Phase** (`state.phase` → `lead_stage`): `EARN_IT` → `QUALIFY_IT` → `ENRICH_IT`, plus `ESCALATION` (HOT hand-off, stays
  while paused after a hand-off, W1 edit 8) and `SUPPORT` (already enrolled). Observed: EARN_IT while course unknown,
  QUALIFY_IT while course known but name/email/qualification missing, ENRICH_IT once classified.
- **Asks** (`pending_question`, `state.asks` counters, extractor input): `ASK_NAME, ASK_LAST_NAME, CONFIRM_NAME,
  ASK_QUALIFICATION, ASK_SCORE, ASK_QUAL_AND_SCORE, ASK_QUAL_AND_COURSE, ASK_COURSE, ASK_SPECIALIZATION, ASK_EMAIL,
  ASK_BUDGET, ASK_TIMELINE, ASK_STUDY_MODE, ASK_MOTIVATION, ASK_UNIVERSITY, CONFIRM_COURSE, OFFER_HANDOFF, NONE`.
  Frequency in 977 pre-5-Oct turns: QUAL_AND_SCORE 190, SPECIALIZATION 155, EMAIL 151, NAME 144, COURSE 125, LAST_NAME 84,
  NONE 68, TIMELINE 38, MOTIVATION 9, STUDY_MODE 4, OFFER_HANDOFF 3, BUDGET 3, SCORE 2, CONFIRM_COURSE 1.
- **Answer modes** (counselor `task.answer_mode` + fixed ones): `ACK, DIRECTIONAL, PROGRAMS, NO_MATCH, NOT_ELIGIBLE, ANSWER,
  CLOSE, SUPPORT` (LLM) and `GREETING, GATE, HANDOFF` (fixed text).
- **Intents** (extractor v6): asks_programs, asks_fees, asks_eligibility, asks_human, wants_to_apply, pay_after_placement,
  general_question, already_enrolled, wants_alternatives, complaint, not_interested, closing, stop, declines_sharing,
  erasure_request (`accepted_offer` also appears in data and in `w2_commit_turn`'s interest list; it is set by code).
- **Classification** (`w2_conversations.classification` → `lead_status`): `UNQUALIFIED` (default), `HOT`, `WARM`, `COLD`,
  `PROGRAM_MISMATCH`, `JUNK`. **Readiness:** `EXPLORING` (default), `PLANNING`, `READY_NOW`. **Eligibility:**
  `INSUFFICIENT_DATA` (default), `LIKELY_ELIGIBLE`, `ELIGIBLE`, `PROGRAM_MISMATCH` (and presumably a not-eligible value
  behind answer_mode `NOT_ELIGIBLE`; not observed).
- **Languages:** `english`, `hinglish`, `hindi` (Hinglish = Hindi in Latin script).

### 4.4 "Ask before suggesting" and HOT/WARM/COLD (what is known, and how exactly)

**Ask-before-suggest** is enforced in code, not by the prompt alone: the counselor may only present programmes in mode
`PROGRAMS` / `NO_MATCH` with `P`-rows the engine chose. Before that, mode `DIRECTIONAL` says only how many options match
(`facts.program_count`) "without naming any program, university or fee yet" and ends with the engine's next ask
(typically specialization, then qualification + score, so that only eligible programmes are shown: "main sirf wahi
dikhaunga jinke liye aap eligible hain"). The ask order and limits per ask live in `ENGINE` (not visible). The
counselor's last line is always the engine's `task.ask_text`, one question only.

**HOT/WARM/COLD — exact code rule not visible.** What is certain:

- Classification happens only once the **tier-1 profile** is complete (`b2b-design.md` §4.2); a lead is **unqualified**
  while name, email or course is missing (Addendum 3). `lead_intake` treats any HOT/WARM/COLD as sales-ready.
- `PROGRAM_MISMATCH` = the student wants a course the catalogue does not have (eligibility also `PROGRAM_MISMATCH`).
- W1's ENGINE test fixture: profile with `student_name`, `email_id`, `interested_course` MBA, `program_level` PG confirmed,
  `highest_qualification` BCom, `academic_score` 70%, `enrollment_timeline` "now", catalogue row PG min 50% → the turn
  escalates (`lead.escalated`, phase `ESCALATION`), i.e. **HOT**.

Observed in all 393 conversations (production + 1–4 Oct backup), every classified row fits this pattern:

| classification | readiness | eligibility | name + email + course | escalated |
| --- | --- | --- | --- | --- |
| HOT (8) | READY_NOW | ELIGIBLE | all confirmed | always |
| WARM (34) | PLANNING | ELIGIBLE | name + email confirmed (course confirmed in 32) | never |
| COLD (0 observed) | (presumably EXPLORING) | – | – | – |
| UNQUALIFIED | any | any | at least one of name / email / course missing | never |

Working hypothesis (to confirm from `ENGINE`): tier-1 complete + eligible → HOT if readiness READY_NOW (timeline "now"/this
month, or `wants_to_apply`), WARM if PLANNING, COLD if EXPLORING; HOT triggers the hand-off. **The website must not
re-implement this from the table above; it must use Witty's own code (section 9).**

### 4.5 Hand-off / escalation

- Trigger: HOT classification (or `asks_human` after the engine's `OFFER_HANDOFF` question "Would you like an academic
  counsellor to help you with the next steps?").
- Effects: `answer_mode = HANDOFF` (fixed text) "Thank you{name}. An academic counsellor will contact you shortly about
  {course}." (Hinglish: "Thank you{name}. Ek academic counsellor jald hi aapse {course} ke baare mein contact karenge.";
  fallback course "your programme" / "aapke programme"); `escalated_at` set; `bot_paused = true`; phase `ESCALATION`;
  Chatwoot label `witty-handoff`; `w2_events` type `handoff` with a brief; CRM event `lead.escalated` (wins over
  `lead.qualified` in the same turn). W2 decision D1: stop posting the Chatwoot "Counselor Brief" (status of that node
  edit unknown). `task.may_promise_callback` is true only after a real assignment.
- CRM event types from `Validate + Decide`: `lead.escalated` > `lead.qualified` (first time, no `crm_fingerprint`) >
  `classification_changed` > `lead.updated`; otherwise `chat.turn`; `lead.interest` for B2C-held leads with an interest intent.
- Silence rules: `w2_crm_owned` (partner accepted / B2C counsellor assigned), `bot_paused`, agent take-over (4 h), opted out.

### 4.6 Consent

- Line appended to Witty's **first live reply** (from n8n code, not `w2_prompts`). Live since W1's workflow half shipped
  (a 16 Oct chat carries `witty-notice-2026-10-v2`):
  "Your details are used only to help with your admission and may be shared with our partner universities and our
  admission partners (edtech companies). Reply STOP anytime to opt out." — version **`witty-notice-2026-10-v2`**.
- W2.3 (approved 14 Oct, pending lawyer sign-off; its DB half is live: `w2_crm_payload` already passes
  `consent_marketing_at`) changes it to v3: "…, may be shared with our partner universities and our admission partners
  (edtech companies), and Eduwit may send you programme updates on WhatsApp and email. Reply STOP anytime to opt out."
  — **`witty-notice-2026-10-v3`**. Whether v3 is live could not be confirmed (no v3 row in production data yet).
- Stamps: `consent_sales_at` (= `consent_at`), `consent_partner_share_at`, `consent_marketing_at` (v3),
  `consent_text_version`; write-once in `lead_intake`; withdrawn by `w2_send_failed` if the reply carrying them was not sent.
  `declines_sharing` → `consent_partner_share_declined_at` in state (W3; `lead_intake` currently drops it).
- Consent texts are registered in the B2B CRM (`b2b.consent_texts`; channels include `witty` and `website_agent`), see
  `crm-conventions.md`.

### 4.7 Guardrails (prompt + code)

- No fee, cutoff, university or programme name typed by the model: placeholders only, filled by code from catalogue rows;
  only numbers from the student, `facts.program_count`, `facts.knowledge`, small counts.
- General questions (validity, UGC, approvals, placements, rankings, dates, documents, EMI) answered only from
  `facts.knowledge` (`w2_kb_search`); otherwise "a counselor can confirm". Verifier rejects unsourced claim words.
- No promises of callback, admission, seat, scholarship, placement, job; no "let me check later".
- One question per reply; plain WhatsApp formatting (bullets "•", one *bold*, no headings, links only `{{Pn.brochure}}`).
- Identity/scam question: "Witty, Eduwit's AI admissions assistant"; human on request; STOP to opt out.
- Parent/sibling writers addressed as such; first name at most once.
- Extractor: exact-evidence rule, `unsure` over guessing; code rejects bad facts (`w2_fact_log.reject_reason`).
- Abuse: `w2_bot_check` (rate/burst/repeat/links/fast-typing thresholds in `w2_meta.bot_rules`), blocks 24 h then 168 h,
  `w2_security_log` (bad codes), test numbers `910000xxxxxx` / `w2_trusted.is_test`.
- Fee data sanity: `w2_fee_sanity(level, dual, yearly, semester, total)` drops contradictory fee fields (`w2_fee_review` view).

---

## 5. JSON contracts

**Extractor output** (prompt v6): `{"facts":[{field, value, evidence, op, subject, scale?, confidence}], "enquirer":
{"name", "relation"}, "intents": [...]}`.

**Counselor input**: `{"task":{"answer_mode","ask_text","may_promise_callback","language","max_words"}, "profile":{...},
"programs":[{"ref":"P1","has":[fields],"eligible":"yes|likely (score not known)"}], "facts":{program_count,
specialization_examples, requested_specialization_found, requested_mode_found, requested_university_found,
some_options_above_budget, alternatives_to, knowledge:[{ref,doc,text}], writer:{relation,name}}, "conversation":[{role,
text}], "student_message"}`. **Output:** `{"reply":"..."}` with placeholders `{{Pn.program|university|mode|specialization|
fee|fee_yearly|fee_semester|fee_total|fee_exam|fee_registration|min_pct|brochure}}`. `max_words` 80 (120 for PROGRAMS).

**`w2_commit_turn(p jsonb)` input** (from its body): `phone`, `run_id`, `model`, `conversation_id`, `account_id`,
`state` (full new state; columns derived from it), `message_ids` [inbox ids answered], `nurture` (`keep`/`start`/`stop`),
`facts` [{field, value, evidence, op, subject, accepted, reason}], `event` {type, payload} (turn diagnostics:
route, answer_mode, ask, intents, classification, readiness, eligibility, escalate, reply_source, verify_errors, tokens
{extractor, counselor}, rows, catalog_rows_seen, latency…), `log` {content, kind, answer_mode, reply_source,
prompt_tokens, cached_tokens, output_tokens, latency_ms, verify_errors, sent, meta}, `outbox` {event_type,
idempotency_key}. Returns `{version, outbox_id, crm, crm_error}`.

**`w2_crm_payload` output** = `lead_intake` input: `{source_system:'witty', event_type, idempotency_key, phone, lead:{…
section 4.2 …}, attribution, occurred_at, is_test}`.

---

## 6. Tools / catalogue access (grounding)

| Function | Role | Notes |
| --- | --- | --- |
| `w2_search_programs(q jsonb)` | The catalogue "tool" | `q` = {course, specialization, level, mode, field, university}. Course resolved via `catalog_synonyms.alias → course_key`; specialization abbreviations (ai, ml, hr, it, ba, ds, ib, fin, mkt…) expanded and fuzzy-matched (`similarity > 0.35`); mode and university filters (university matching ignores dots/spaces). Returns `{rows (≤30; field search ≤15), total_for_course, course_key, specializations (top 8), modes, spec_matched, mode_matched, universities}`; each row: id, university, university_short, level, course, specialization, program_name, mode, fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, min_qualification, min_pct_general, min_pct_reserved, brochure_url, dual, fee_emi, pay_after_placement, loan_available, match, uni_match. Reads `public.catalog_programs` (active) + `catalog_universities` directly, not the B2B `catalog.*` views |
| `w2_search_programs_cached(q)` | Same, cached | `w2_search_cache` keyed by md5(lower(q)) + `w2_meta.catalog_version` (6 today; bump invalidates) |
| `w2_kb_search(p)` | Knowledge for general questions | {text, embedding(768), limit≤6}; hybrid vector + FTS with reciprocal-rank fusion; returns [{ref K1.., doc, text, score, similarity}]. **KB is nearly empty: 1 doc, 1 chunk** ("FAQ: validity of online and ODL degrees") |
| `w2_catalog_index()` | Spelling aid appended to the extractor prompt | ≤80 course lines with top specializations, modes, levels |
| `w2_fee_sanity(...)`, view `w2_fee_review` | Fee data hygiene | – |

So Witty "tool use" is **code-driven retrieval** (the engine decides the query; the LLM never calls tools). Facts about
programmes reach the student only through placeholder substitution from these rows.

---

## 7. How Witty writes messages and leads

**`w2_messages`** columns: `id, phone, direction ('in'|'out'), kind, message_id, run_id, content, answer_mode,
reply_source, model, prompt_tokens, cached_tokens, output_tokens, latency_ms, verify_errors jsonb, sent, meta jsonb,
created_at`. **There is no `channel` column**; the conversation key is the phone (E.164 digits without '+').

- Inbound rows by `w2_inbox_add` (`kind='chat'`, `meta` {conversation_id, content_type, has_attachment, referral}); later
  re-tagged `blocked`, `crm_paused`, `agent_paused`, `feedback` by `w2_try_claim`.
- Outbound rows by `w2_commit_turn` (`kind` `reply` | `gate` | `nurture`, `meta` {prompt_source, knowledge,
  catalog_cached, …}); `sent=false` + `meta.send_error` via `w2_send_failed`.
- Published read contract (W2.5): `phone, direction, kind, content, created_at, sent, meta` are read by the B2C CRM
  (`b2c.witty_transcript`, `b2c.witty_messages`) and must not be renamed. They are also read by the WhatsApp-window and
  re-enquiry functions listed in finding 6.
- RLS is enabled on `w2_*` tables; the `w2_*` functions are `SECURITY INVOKER`; n8n connects with a privileged role.

**Leads:** the only approved path is `lead_intake(p jsonb)` (`SECURITY DEFINER`, executable by `service_role` only). Witty
calls it inside `w2_commit_turn` (savepoint; failure → `w2_outbox`, retried every minute) on every turn of a bound
chat (`access_code is not null`, i.e. every chat since W3). `lead_intake` trusted systems: `witty`, `web_agent`, `crm`
(trusted = later values overwrite non-first-touch fields). Only `witty` gets `phone_verified_at` / `whatsapp_inbound`.
`lead_intake` accepts `web_session_id` but **not** `email_verified_at` (column exists on `student_leads`).

---

## 8. Witty 2.0 status

- **Live.** Witty 2.0 = the `w2_*` design (extractor/engine/counselor/verifier, Gemini caching, SQL gates, outbox).
  Harness runs since 1 Oct; production data since 5 Oct (earlier test-period data in `*_backup_20261004/5`); a
  `cutover-…` harness run on 12 Oct and `bridge-before/after` runs the same day (purpose not documented in the repo).
- Releases: W1 DB 7 Oct (`20261007094058`), W1 workflow half applied by 16 Oct (v2 consent stamps in data); W2
  `w2_witty_b2c` 14 Oct (pause clearing, re-enquiry touchpoint, marketing-consent payload line); W3 16 Oct (soft gate: every
  chat a lead, click-to-WhatsApp = influencer, agent pause, extractor v6 with `chosen_program` / `declines_sharing` /
  `erasure_request`, health digest, send-failed consent withdrawal, EMI/PAP/loan fields in search, contextual nurture).
- Harness: 5 standard scenarios × 20 turns (`happy_path_mba`, `hinglish_parent`, `general_questions`,
  `fee_check_jamia_hamdard`, `alternatives_and_complaints`), baseline 20/20 (last run 14 Oct); 22 scenario names in
  history (validity_en/hinglish/ugc, handoff_check, career_and_off_topic, injection_trusted_no_block,
  bot_blocking_untrusted, no_access_code, scholarship_influencer, unsure_discovery, real-chat replays, …).
  Results in `w2_test_runs`; checks include `answer_mode`, `contains_any`, `not_contains`, `no_fallback_reply`, `handoff`.
- No sign of a different "multi-agent" Witty in the database. If a further rebuild is planned, it is not visible here.

---

## 9. Recommendation: how `web_advisor` shares the core without forking

### 9.1 What "the core" is

| Layer | Where it lives today | Shareable as is? |
| --- | --- | --- |
| Prompts (extractor, counselor) | `w2_prompts` + `w2_build_prompt` + `w2_learnings` | **Yes**: read at runtime by name and version |
| Catalogue and knowledge tools | `w2_search_programs[_cached]`, `w2_kb_search`, `w2_catalog_index` | **Yes**: call the same functions |
| Lead write | `lead_intake` with the `w2_crm_payload` key set | **Yes**, with `source_system='web_agent'` (do not call `w2_commit_turn`) |
| Decision engine (ask order, eligibility, classification, phase, hand-off, ASK_TEXT, fixed texts, verifier) | **JavaScript inside n8n Code nodes** (`ENGINE`), source `witty2/project` | **No**: not readable, not importable |
| State, transcript | `w2_conversations` (PK phone), `w2_messages` (no channel) | **No**: collides with the WhatsApp chat of the same phone; corrupts WhatsApp-window logic |

### 9.2 Recommended architecture

1. **Agent core package, extracted from Witty's own source, not re-written.** Ask the owner for `witty2/project` (or the
   workflow export). Publish its `ENGINE` (planReply / validate+decide / ASK_TEXT / verifier / placeholder filling) as a
   versioned, channel-agnostic module (e.g. `@eduwit/witty-core`, plain JS/TS, no n8n globals, unit tests from
   `witty2/project/*.test.js`). The website imports a pinned version; Witty's n8n build (`node build.js`) bundles the same
   module into its Code nodes. Until the owner adopts it, the website pins the module to the exact md5 of the live
   `ENGINE` (W1 "after" md5 of Plan Reply / Validate + Decide) and the harness must pass against it. This keeps the
   reasoning, questions and HOT/WARM/COLD rules identical by construction (spec §7.3).
2. **Prompts by reference.** At cold start, `web_advisor` reads `w2_build_prompt('extractor')` and
   `w2_build_prompt('counselor')` (or `w2_prompts` + the same assembly), records `name:version:md5` in
   `web_advisor_sessions.agent_core_version`, caches in memory, re-checks `w2_prompts.updated_at` every few minutes.
   Use **the same model** (`gemini-3.6-flash`) and the same JSON contracts, or the behaviour is not "the same brain".
3. **Channel overlay as data, not a fork.** The counselor prompt hard-codes WhatsApp formatting (rule 5, "on WhatsApp").
   Add one versioned row, e.g. `w2_prompts(name='channel_web', version=1, body='CHANNEL: web chat … you may use markdown
   lists; programme rows are rendered as cards by the page, so keep the {{Pn.*}} bullets …')`, appended after the base
   prompt for the web only. `w2_cache_plan` loops only over `'extractor','counselor'`, so an extra row is invisible to
   Witty. Placeholders stay, so web cards render from the same `P`-rows. (Data change in a shared table: needs approval.
   Zero-approval fallback: keep the overlay in the website's own `web_settings`, still versioned.)
4. **Tools = the same SQL.** `search_programmes` → `w2_search_programs_cached`; `get_offering_details` /
   `compare_offerings` / `get_university_details` → website read model (`web_offering_search`) keyed by the same
   `catalog_programs.id`; `check_eligibility` → the ENGINE's eligibility function (from the core package) over those rows;
   knowledge → `w2_kb_search`. Keep the engine deciding when to search (as Witty does) rather than letting the LLM call tools
   freely; the spec's tool names can be the engine's internal calls. Ensure the website read model and
   `w2_search_programs` agree (same `active` filter, same `catalog_version`).
5. **Web-owned state and transcript (until approvals land).** `web_advisor_sessions` (session id, lead id, phone, email,
   agent-core version, Witty-shaped `state` jsonb, classification/readiness/eligibility/phase, tokens, cost) and
   `web_advisor_messages` with **exactly the `w2_messages` columns plus `channel = 'web'` and `session_id`**, so it can be
   merged later without transformation. Optionally offer a read-only union view for the CRMs' transcript screen.
6. **Lead writes through `lead_intake` directly**, `source_system = 'web_agent'`, the `w2_crm_payload` key set built from
   the web state (same keys), plus `channel` / `first_agent_channel` / `source` per the contract in `crm-conventions.md`,
   `web_session_id`, consent stamps with the website's own `consent_text_version`, event types identical to Witty's
   (`lead.qualified`, `lead.escalated`, `classification_changed`, `lead.updated`, `chat.turn`, `lead.interest`), idempotency
   key `<phone>:web:<session>:<turn>`. Never call `w2_commit_turn`.

### 9.3 Works with zero changes to shared objects

- Reading `w2_prompts`, `w2_build_prompt`, `w2_catalog_index`, `w2_learnings` (approved lessons).
- Calling `w2_search_programs`, `w2_search_programs_cached` (note: it writes to `w2_search_cache`, a cache table; if even
  that is unwanted, call `w2_search_programs`, which is `STABLE`), `w2_kb_search`.
- `lead_intake(source_system='web_agent', …, web_session_id)` for create/merge, classification, phase, consent, UTMs.
- Web-owned `web_advisor_sessions`, `web_advisor_messages`, `web_gate_attempts`, overlay in `web_settings`.
- Same Gemini model and caching approach on the website side (its own caches; do not write `w2_gemini_caches`).

### 9.4 Shared-object changes that need owner approval (for `APPROVALS_NEEDED.md`)

| # | Change | Why | Risk / note |
| --- | --- | --- | --- |
| A1 | Provide the n8n export of "Eduwit Witty" and/or `witty2/project` source; agree to extract `ENGINE` into a shared versioned package that Witty's build also consumes | Only way to share ask order, eligibility, HOT/WARM/COLD, hand-off and verifier without re-inventing them | Witty-side build change; harness must stay 20/20 |
| A2 | Add `w2_messages.channel text not null default 'whatsapp'` and `session_id text` (dev first) | Spec §7.5 wants one shared transcript with `channel = 'web'` | **Must ship together with A3**, otherwise WhatsApp-window logic breaks |
| A3 | Make every reader of `w2_messages` that means "WhatsApp" filter `channel = 'whatsapp'`: `crm_whatsapp_window__impl`, `b2b.student_last_inbound`, `b2b.reenquiry_scan`, `b2c.may_market`, `b2c.witty_busy`, `crm_marketing_allowed`, `w2_health_digest`; show channel in `b2c.witty_transcript` / `b2c.witty_messages`, `b2b.lead_detail`, `crm_timeline__impl`, `crm_score_lead__impl`, `crm_journey_tick` | Prevents free-form WhatsApp sends outside Meta's 24 h window and false "student replied" signals | Touches B2B and B2C CRM functions (their owners) |
| A4 | Insert `w2_prompts` row `channel_web` (overlay), versioned like the others | Web formatting without forking the counselor prompt | Data-only; invisible to Witty (`w2_cache_plan` ignores other names) |
| A5 | Optional: a `w2_prompts` history (e.g. `w2_prompt_versions`) or a convention that every change writes the old body to `b2b.witty_backup_<date>` | Lets the web pin and replay an exact prompt version | Today only the latest body is in-table |
| A6 | `lead_intake`: accept `email_verified_at` (and set `email_verified_at` only for `web_agent`), keep `phone_verified_at` null for `web_agent` (already the case) | Spec §7.2 email-verified flag | Change to the shared lead writer |
| A7 | Optional: allow `final_program_id` / `final_program_name` / `programs_shown` / `consent_partner_share_declined_at` in `lead_intake` (Witty already sends them; they are silently dropped) | Data parity for both channels | Shared lead writer |
| A8 | If the owner prefers one conversation per person across channels: a channel-aware conversation key (`w2_conversations` keyed by `(phone, channel)` or a separate web row) and a channel-aware `w2_commit_turn` / `w2_crm_payload` (`source_system`, `channel`, `first_agent_channel` from input; no `whatsapp_inbound` verification for web) | Would let the web reuse `w2_commit_turn` | Large change to Witty's hot path; not recommended for launch |
| A9 | Register the website consent text version (e.g. `web-witty-notice-2026-10-v1`) in `b2b.consent_texts` (channel `website_agent`) | Partner-share and marketing consent must count in both CRMs | B2B admin action |

### 9.5 Launch plan if approvals are slow

Ship `web_advisor` behind `web_advisor_enabled = false`. If A1 is not granted before launch, do **not** approximate the
engine: launch with the guided finder and the application form (spec allows launch before Witty 2.0 is "ready"), or, if
the owner explicitly accepts it in `DECISIONS.md`, run a web adapter that reads the shared prompts and tools and marks
leads with `lead_stage`/`lead_status` only via a ported copy of `ENGINE` pinned to the live md5 and re-tested with the
harness scenarios. Everything web-specific stays in web-owned tables until A2–A3 land.

---

## 10. Open questions for the owner

1. Export of workflow `PKPs7tXg9bej8AgX` (and `witty2/project`): needed for the exact ask order, HOT/WARM/COLD and
   readiness rules, fixed texts (GREETING, GATE, HANDOFF, OFFER_HANDOFF), verifier rules and the counselor input builder.
2. Is W2.3 (consent v3 with marketing) live, or still waiting for the lawyer?
3. Is Witty 2.0 being rebuilt again as a multi-agent system, or is "Witty 2.0" the live `w2_*` system?
4. Should a person who chats on both WhatsApp and the website have one shared conversation state, or one per channel
   (recommended for launch: one per channel, one lead)?
5. Approval for A2+A3 (channel column and channel-aware readers) vs. a web-owned transcript table with a union view.
6. Same Gemini model and GCP project for the website, or a separate key/project for cost tracking?
