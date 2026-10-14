# Eduwit B2C CRM: Phase 2 plan ("Nurture")

Version 14 October 2026 · Spec B6, B9, B19.2 row 2 · Builds on Phase 1 (b1–b13 on staging)

## Rules for the whole phase

The same as Phase 1:

- Staging only (`mplbspysxmtohnlwpbti`).
- Test leads only.
- Nothing is sent unless `LIVE_MODE` is on and Settings → live mode is on. Test leads are never sent anything.
- Never touch `w2_*`, `lead_intake()`, the n8n workflows, the B2B CRM or `student_leads`.

Every business rule is a `b2c.*` function with rolled-back checks in `tests/test_phase2.sql`.

Witty signals arrive only as B2B events (`b2c.lead_interest`, `b2c.lead_reenquired`, `lead.escalated`). The CRM never parses `w2_messages` text (B6.3).

## Database, in migration order

| File | Contents |
| --- | --- |
| `b14_marketing_templates` | `message_templates`: marketing WhatsApp and email. Columns: versions, language variants, buttons, Meta category and status, tags, usage. Sales WhatsApp templates stay in `wa_templates`, Admin only. Functions: `template_save()` (Marketing and Admin; a sales template stays Admin only), `template_render()` (merge fields from `leads_v`, preview with a test lead), and the unsubscribe token (secret in Vault, B9.6). |
| `b15_consent` | `consents`: per channel, text version, source and time. `suppressions`: global. Functions: `opt_out()` and `opt_in()` per channel; STOP is already handled in `wa_inbound()`. Each one emits `b2ccrm.opted_out` / `b2ccrm.marketing_consent` (urgent). `may_market(lead, channel)` is the single guardrail check: consent, opt-out, suppression, quiet hours 09:00–20:00 IST, frequency caps (1 WhatsApp a day, 6 per 30 days, 2 emails a day), one journey at a time, no marketing within 30 minutes of a Witty message, partner holds, and no automated marketing during active sales unless the journey allows it. It returns the reason when blocked, so the Nurture page can count suppressions. |
| `b16_segments_campaigns` | `segments`: dynamic, using the same filter language as views (`filter_sql`); static lists from a CSV or a snapshot. `segment_count()` for the live count and `segment_overlap()`. `campaigns` and `campaign_sends`: one-off or recurring, send window, throttle, A/B on subject or template with a sample and the winner. `campaign_tick()` paces sends through `send_queue` (email within the daily Gmail allowance). |
| `b17_journeys` | `journeys`, `journey_versions` (draft → publish; running leads stay on their version or migrate), `journey_runs`, `journey_steps_log`. Triggers: pool entry with a reason, segment entry, field or tag change, N days without activity, a date, email open or click, WhatsApp reply. Steps: send, wait, branch (condition, reply class, A/B), update a field or score, tag, Admin task, assign (re-engage), exit. `journey_tick()` runs every minute in small batches. Test mode runs on test leads only. Seeds the 8 starter journeys from B9.4 plus *partner-lost by reason*, *qualification nurture*, *consent repeat* and *fix and reapply*. These come from the 6 production journeys reviewed in audit §4.6, re-keyed to the B6.4 lost sub-stages and delays. |
| `b18_scoring` | `score_rules` (fit and engagement points, editable) and `score_events` (every change, with its rule). `score_apply()` handles engagement events: WhatsApp read or reply, email open, click or reply, brochure click, Witty resumed, form filled. `score_decay_tick()` halves engagement points after 14 days without activity, in batches of 500 off-peak. A **rise** to 60 or more after pool entry, with at least one engagement event since, calls `reengage(lead, 'score')`; fit points alone never do. The score and temperature go to B2B only on a band change or when it crosses 60 (B9.5). |
| `b19_replies` | `replies`: each reply's class, method, confidence and the Admin's correction. `reply_rules`: keywords in English, Hindi and Hinglish. `reply_classify_take()` / `reply_classify_done()` for the Claude step. Reply class wiring: positive → `reengage(lead, 'whatsapp_reply' / 'email_reply')`; negative → long-gap journey or lost; question → Replies inbox; opt-out → `opt_out()`. Below 0.8 confidence the reply goes to the inbox. Also: dormancy after 12 months without a response (B6.5), the pool-health roll-ups, and the cron jobs `b2c-journeys` (1 min), `b2c-campaigns` (1 min), `b2c-decay` (nightly) and `b2c-classify` (1 min, app). |

Everything that would need a DELETE is a soft flag (`archived_at`, `removed_at`), as in Phase 1. The connector still cannot apply DELETE.

## App

| Area | Routes |
| --- | --- |
| Marketing workspace (Admin and Marketing) | `/w/nurture`: Overview, Pool (B6.2), Journeys, Campaigns, Segments, Replies, Scoring, Guardrails. `/w/templates`: one page for all four template kinds with the B9.2a rights. |
| Journey builder | `/w/nurture/journeys/[id]`: steps as a vertical flow with live counts per step, draft/publish, versions, test mode, clone |
| Lead level | On the lead: nurture history, pause or resume, move to another journey, one-off message, hand to a counsellor |
| Unsubscribe | `/u/[token]`: public, signed token, one-click opt-out per channel (List-Unsubscribe header on every marketing email) |
| Email events | Open pixel and click redirect (`/e/o/[id]`, `/e/c/[id]`), signed. Gmail reply threading through the reconcile job. |
| Classification | `/api/internal/classify`: keyword misses go to Claude Haiku (`claude-haiku-4-5-20251001`, configurable). Only the reply text and the course interest are sent: no name, phone or email (B6.6, A3). |
| Marketing guide | The marketing articles in `user_guides`, completed for these screens |

## Tests (`tests/test_phase2.sql`, plus unit tests)

The phase's exit test, on test leads:

1. A partner-lost lead enters the pool and gets its journey after the sub-stage's delay.
2. It is allocated within 60 s of each trigger type: Witty interest, new paid enquiry, positive WhatsApp button, positive email reply, score rising to 60.
3. A lead that enters the pool already scoring 60 from fit alone is **not** allocated.
4. Opt-out stops everything at once.
5. Every guardrail holds:
   - quiet hours;
   - both frequency caps;
   - no message within 30 minutes of a Witty chat;
   - no automated marketing during active sales unless the journey allows it;
   - one journey at a time.

## What I need from you (none blocks the build; all block going live)

1. **Meta-approved templates on the B2C number** for each starter journey, plus the quick-reply buttons ("Yes, call me", "I'm interested", "Share details").
2. **An Anthropic API key** (`ANTHROPIC_API_KEY`) for reply classification. Without it, keyword rules decide and everything else goes to the Replies inbox.
3. **Email volume (audit §8, B21 #8).** Marketing email from one Gmail mailbox is capped at about 2,000 a day. Campaigns will pace within that until a bulk provider is chosen.
4. **The lawyer's sign-off** on the marketing consent wording (also W2.3 for Witty).
