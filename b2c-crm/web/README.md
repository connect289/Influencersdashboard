# Eduwit B2C CRM: web app (Phase 1 "Sell", Phase 2 "Nurture")

Next.js 16 (App Router, Turbopack), React 19, `@supabase/ssr`, zod, sonner, lucide, Geist. The styles are the approved
design's stylesheet (`app/globals.css`, from `../design`), not Tailwind. The database is the `b2c` schema
(`../supabase/migrations`, b1–b18); every action calls a `b2c.*` function that checks the person's permission itself.

```
npm install
cp .env.example .env.local   # fill in
npm run dev                  # http://localhost:3000
npm run typecheck && npm test && npm run build
```

## What is in it

| Area | Routes |
| --- | --- |
| Sign-in | `/login` (Google limited to eduwit.in, or email and password), `/verify` (6-digit code to the company inbox; trust the device for 30 days), `/pending` |
| Sales app (counsellors, sales head, Admin) | `/s` Today, `/s/leads`, `/s/leads/[id]`, `/s/pipeline`, `/s/followups`, `/s/inbox`, `/s/programmes`, `/s/me` |
| Workspace (Admin; Marketing reads) | `/w` Home, `/w/leads` (bulk tools, Recycle bin), `/w/leads/[id]`, `/w/pipeline`, `/w/allocation` (rules, pools, hours and leave, simulation, queues, decisions), `/w/teams`, `/w/enrollments`, `/w/connectors`, `/w/settings`, `/w/guide` |
| Marketing (Admin and Marketing) | `/w/nurture` (Overview, Pool, Journeys, Campaigns, Segments, Replies, Scoring and rules, suppressions), `/w/nurture/journeys/[id]` (steps, trigger, draft and publish, versions, test on a test lead), `/w/templates` (sales and marketing WhatsApp, counsellor and marketing email; submit to Meta). On the lead screen: nurture history, journey, one-off message, consent, hand to a counsellor |
| Public (signed links in marketing email) | `/u/[token]` unsubscribe per channel, `POST /e/u/[token]` one-click (List-Unsubscribe), `/e/o/[token]` open pixel, `/e/c/[token]` tracked click and "I'm interested", `/thanks` |
| From the B2B CRM | `POST /v1/handoffs`: signed webhooks (HMAC over the raw body, 5-minute window), stored and applied once per envelope id |
| From Meta | `GET/POST /v1/webhooks/whatsapp`: signed with the app secret; messages to `b2c.wa_inbound`, statuses to `b2c.wa_status` |
| Jobs (pg_cron → here, `x-internal-key`) | `POST /api/internal/sync?mode=urgent` (every minute, also sends phone alerts and classifies replies with Claude), `?mode=batch` (every 15 minutes), `POST /api/internal/reconcile` (every 5 minutes, also reads the marketing mailbox's replies and bounces and, hourly, Meta template status and quality), `POST /api/internal/directory` (daily, 02:10 IST) |
| Export (Admin) | `GET /w/leads/export?v=<view>&q=<search>`: the view or search as CSV, up to 10,000 rows, logged in the audit log |

**Sync with the B2B CRM** (decisions K2 and K14): the B2B CRM sends hand-offs and lead changes in real time. The B2C CRM
sends its activity back in one batch every 15 minutes (merged to one update per lead), except what must go at once:
consent request sent, consent answer, opt-out, erasure, route-to-partners, new students (Intake API) and **every
counsellor assignment and its end**, so the B2B CRM records each hand-off to the internal sales team like a hand-off to a
partner (Addendum 4 §4a). A lead reaches a partner only through the B2B engine.

**Messages**: WhatsApp from the Eduwit B2C number (template first outside the 24-hour window) and counsellors' email from
their own mailbox. Nothing is sent unless `LIVE_MODE=on` **and** Settings → live mode is on; test leads (phones `910000…`,
`9190000000…`) never get a real message. In test mode a message is recorded as "test mode, not sent".

## Setup (Vikas), staging first

1. **Supabase → Project Settings → Data API → Exposed schemas: add `b2c`** and save. Until then sign-in says the app
   cannot reach its data.
2. **Vercel**: new project from this repo, root directory `b2c-crm/web`, region Mumbai (`bom1`, in `vercel.json`). Set
   the variables in `.env.example`. Generate `B2C_INTERNAL_KEY` with `openssl rand -hex 32`.
3. **Supabase → Authentication**: enable Google (OAuth client from Google Cloud, authorised redirect
   `https://mplbspysxmtohnlwpbti.supabase.co/auth/v1/callback`); under URL Configuration add the site URL and
   `https://<site>/auth/callback`. Turn off public sign-ups: the Admin adds people under Teams.
4. **First Admin**: sign in once with Google as connect@eduwit.in (you land on "Waiting for access"), then in the SQL
   editor: `insert into b2c.users (user_id, email, full_name, role, is_active) select id, email, 'Vikas Jha', 'admin', true from auth.users where email = 'connect@eduwit.in';`
   After that, add everyone else from Teams.
5. **Timers**: in the SQL editor, `select vault.create_secret('<B2C_INTERNAL_KEY>', 'b2c_internal_key');` and
   `update b2c.settings set value = '{"base_url": "https://<site>"}', updated_at = now() where key = 'app';`
   The four `b2c-*` cron jobs then start calling the app (until both exist they do nothing).
6. **B2B CRM → System health → Webhooks and API keys**: register `https://<site>/v1/handoffs`, subscribe to `b2c.*` and
   `b2b.*`, issue the signing secret (`B2B_SIGNING_SECRET`) and an API key with scopes `b2c`, `events`, `intake`
   (`B2B_API_KEY`). Send the test ping; then switch the endpoint on. Run `npm run mock-b2b` against the deployment to
   play the signature checks (test leads only; delete them afterwards).
7. **Email codes**: SMTP settings (Google Workspace SMTP relay, or a mailbox with an app password).
8. **Phone alerts**: `npx web-push generate-vapid-keys`; set `NEXT_PUBLIC_VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`.
   Each person turns alerts on per device under Me → Availability and alerts.
9. **Teams sync**: add the scope `https://www.googleapis.com/auth/admin.directory.user.readonly` to the service account's
   domain-wide delegation and set `GOOGLE_ADMIN_EMAIL` (a Workspace admin it acts as).
9a. **Nurture (Phase 2)**: set `LINK_SECRET` (`openssl rand -hex 32`), `ANTHROPIC_API_KEY` (reply classification; the
   model is Settings → nurture → `classify_model`, `claude-haiku-4-5` by default) and `WHATSAPP_WABA_ID`; add
   `https://www.googleapis.com/auth/gmail.readonly` to the delegation and set Settings → `marketing_email` to the
   marketing mailbox. Then in `/w/templates` submit the marketing templates to Meta, and in `/w/nurture` read each
   starter journey (they start paused) before you **Run** it.
10. **Later, for live channels**: WhatsApp Cloud API number and templates (audit §9), Gmail delegation (audit §8). Keep
   `LIVE_MODE=off` until the end-to-end test with test leads passes.

## Checks

- `npm test`: signing (contract reference code), batch and answer mapping, Intake API body, WhatsApp body and webhook
  parsing, Meta signatures, Gmail JWT and header injection, IST dates, the internal key, email and share text (HTML
  escaping, placeholders), CSV (formula injection), the guides' Markdown, directory mapping; Phase 2: signed email
  links, marketing email (tracked links, footer, List-Unsubscribe), the marketing inbox reader, Meta template mapping.
  57 tests.
- `../supabase/tests/test_phase1.sql` (99) and `test_phase2.sql` (45): rolled-back database checks (run in the SQL editor).
- `npm run mock-b2b`: the B2B webhook checks against a running deployment.

Not yet verified end to end: sign-in with real accounts, the B2B link (needs Addendum 4 deployed and the keys), live
WhatsApp and Gmail, Meta template approval, Claude classification with a real key. Those are the staging steps above.
