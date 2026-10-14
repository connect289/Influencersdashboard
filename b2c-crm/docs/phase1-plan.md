# Eduwit B2C CRM: Phase 1 plan ("Sell")

Version 14 October 2026 · Approved by Vikas ("everything is approved, proceed with Phase 1") · Spec B19.2 row 1

## Rules for the whole phase

- Database work only on the **staging project** `mplbspysxmtohnlwpbti`. Production is not touched in Phase 1.
- Never run `student_leads_v2_rename.sql`; never change `w2_*`, `lead_intake()`, the n8n workflows or the B2B CRM.
- B2C never reads or writes `student_leads` or `b2b.*` (decision K1). Lead records arrive from the B2B CRM; writes go back
  through its API: one batch every 15 minutes, six kinds at once (K2).
- Test leads only. `LIVE_MODE` per channel (WhatsApp, email) is off; with it off nothing is sent to a real number or address.
- Every business rule is a SQL function in schema `b2c`; the app calls them. Each migration has a rolled-back SQL test.

## Deviation from the spec, on purpose

- **Users live in `b2c.users`, not `crm_users`.** The old CRM still reads `crm_users` on production by name; changing it
  now would break the old CRM before cut-over (K9). `b2c.users` carries every column B14 lists for `crm_users`. At
  cut-over the 4 rows move and `crm_users` retires.
- **Hosting on Vercel** (K5); timers in `pg_cron` + `pg_net` calling the app's `/api/internal/*` routes.

## Database (schema `b2c`), in migration order

| File | Contents |
| --- | --- |
| `b1_access` | `users`, `settings` (+ versions), `events`, `audit_log`, `sign_in_log`, `session_checks`, `email_codes`, `trusted_devices`; `me()`, `can()`, `require()`, `mfa_issue()` (server), `mfa_verify()`, `device_trust_check()` |
| `b2_records` | `lead_records` (read-only cache of the B2B record, by version), `leads_state` (B2C lifecycle), `lead_contacts`, `field_history`, `stages`, `sub_stages` (seeded B5.1); `leads_v` |
| `b3_plumbing` | `inbox` (every B2B envelope, idempotent), `outbox` (writes and events to B2B; one merged update per lead per batch), `sync_state`; `handoff_receive()`, `apply_envelope()`, `apply_record()`, `queue_update()`, `queue_activity()`, `queue_event()`, `outbox_take()`, `outbox_done()` |
| `b4_allocation` | `work_patterns`, `shift_overrides`, `holidays`, `leaves`, `pools`, `pool_members`, `allocation_rules`, `allocation_decisions`, `assignments`; `working_now()`, `next_working_at()`, `add_working_minutes()`, `rule_matches()`, `pick()`, `allocate()`, `reassign()`, `hand_back()`, `allocation_tick()`, `simulate()` |
| `b5_work` | `tasks`, `activities`, `calls`, `sla_clocks`, `saved_views`, `notifications`; `set_stage()`, `call_tap()`, `call_log()`, `task_*()`, `add_contact()`, `set_primary()`, `correct_lead()`, `lead_list()`, `lead_detail()`, `today()`, `followups()`, `sla_tick()`, `reminder_tick()` |
| `b6_messaging` | `wa_templates`, `wa_conversations`, `wa_messages`, `consent_requests`, `emails`, `sales_email_templates`, `send_queue`; `wa_compose()`, `wa_queue_template()`, `wa_queue_text()`, `wa_inbound()`, `wa_status()`, `send_take()`, `send_done()`, `email_template_save()` (fork-on-edit) |
| `b7_apps_admin` | `applications`, `documents`, `enrollments`; `application_save()`, `enrollment_record()`, `enrollment_verify()`, `route_to_partners()`, `lead_delete()`, `lead_restore()`, `programmes_v` (over the catalogue until B2B publishes `catalog.*`), `programme_search()` |
| `b8_jobs` | `pg_cron` jobs: allocation and SLA tick (1 min), reminders (1 min), outbox urgent (1 min) and batch (15 min), reconciliation (5 min), send queue (1 min) |

## App (`b2c-crm/web`, Next.js 16, same stack as the B2B CRM)

| Area | Routes |
| --- | --- |
| Sign-in | `/login` (Google restricted to `eduwit.in`, or email + password), `/verify` (6-digit code to the company inbox, trust device 30 days), `/pending` |
| Sales app | `/s` Today, `/s/leads`, `/s/pipeline`, `/s/followups`, `/s/inbox`, `/s/leads/[id]`, `/s/programmes`, `/s/me` |
| Workspace (Admin; Marketing read-only in Phase 1) | `/w` home, `/w/leads`, `/w/pipeline`, `/w/allocation`, `/w/teams`, `/w/enrollments`, `/w/connectors`, `/w/settings`, `/w/guide` |
| Contract | `POST /v1/handoffs` (signed B2B webhooks), `POST /v1/webhooks/whatsapp`, `GET /v1/events` (B2C's own feed) |
| Jobs | `/api/internal/sync` (outbox: urgent and 15-minute batch), `/api/internal/reconcile`, `/api/internal/send`, `/api/internal/tick` |
| Adapters | `lib/b2b` (HMAC, client, schema cache), `lib/whatsapp` (Cloud API, dry-run unless `LIVE_MODE`), `lib/gmail` (send as the user, domain-wide delegation), `lib/directory` (Workspace sync) |

## Exit test (spec B19.2, row 1), how it is checked

Rolled-back SQL tests on staging for every function; Vitest for adapters, signing, batching and permissions; a mock B2B
sender (`mock-b2b/`) that plays the contract's checks against `/v1/handoffs`.

## Setup steps that need Vikas (listed in `web/README.md`)

1. Supabase (staging) → API settings → exposed schemas: add `b2c`.
2. Vercel project for `b2c-crm/web` with the environment variables in `web/.env.example`.
3. B2B Admin → System health: register the B2C webhook URL, issue the key (scopes `b2c`, `events`, `intake`).
4. Google Cloud (audit §8) and the WhatsApp number (audit §9) for the live channels.
