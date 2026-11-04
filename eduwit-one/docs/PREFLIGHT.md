# Eduwit One — access preflight

Run on 23 Oct 2026 with `npm run preflight`. The full generated table is
[`PREFLIGHT-table.md`](./PREFLIGHT-table.md): every row of the prerequisites access list, with what was run, the
result, the fix, and what the item unblocks. Rows exercised through the build session's connectors are listed with
what was run in [`preflight-connector.json`](./preflight-connector.json). No secret was printed or stored.

**Result: 13 verified, 12 not provided, 1 refused, 5 unfilled.**

## Seeded enabled from the first deploy (verified)

Supabase production read, staging, advisors and logs · Chatwoot (one inbox, WITTY2; its webhook points at
`n8n.eduwit.in`) · Vercel (team eduwit; website, influencer, Spark and B2B production deployments READY; no
`eduwit-one` project yet) · Resend (`eduwit.in` verified, last email delivered) · UptimeRobot (6 of 6 monitors up) · the
B2B referrals API · the website's and the influencer portal's `/api/health` (both 200 and ok) · the test-row agreement ·
the brand assets.

These items are written as validated into `supabase/seed/setup.json`. Migration 0007 loads that file into
`one.settings.setup`, so their real clients are wired and their checks are seeded enabled.

## Refused

| Item | What happened | Fix |
| --- | --- | --- |
| Lightsail | The key is valid, but `us-east-1` has no instances, and every other region is denied by an AWS Organizations service control policy owned by account 901486127742 | Set `ONE_AWS_REGION` to the n8n server's region and allow `lightsail:Get*` there, or create the key in the account that owns the server |

## Not provided or unfilled (stubbed, seeded disabled with `setup:<item>`)

| Item | Effect until filled |
| --- | --- |
| Production connection string (`ONE_PROD_DB_URL`) | **Blocks the phase 1 production apply** (no dump possible). Staging rehearsal continues |
| n8n API key for the app | WITTY-02, WITTY-08, WITTY-09, FIX-N8N-RETRY, FIX-CACHE-W2, n8n heartbeats, T-WITTY-QUALIFY not configured. The instance itself is healthy (connector: 10,072 runs, 0 errors since 22 Oct) |
| Spark base URL and `b2c_internal_key` | PLAT-05 fires (as it should); HB `spark` and FIX-OUTBOX-B2C not configured |
| WhatsApp token and WABA ids | B2C-06 template and quality parts, `whatsapp:*` heartbeats |
| Meta | HB `meta`, Marketing spend tiles |
| Model provider | Vault has `one_gemini_key`; the specification says Claude (D-004, Q1). The AI layer ships provider-neutral |
| P1 inbox, second contact, developer | Defaults: P1 to connect@eduwit.in by email; escalation re-sends to the same inbox; developer alerts to the P1 inbox |
| Test identities (real test phone, mailbox, preview URL, Spark test user, intake key, test partner, test creator) | All synthetic tests that need them are seeded disabled |

## Findings that need the owner (none blocks phases 2 to 7)

1. **Production dump.** Add `ONE_PROD_DB_URL` to the build environment's secrets (Supabase → Connect → session
   pooler). Without it, schema `one` is not created on production (D-010).
2. **UptimeRobot alert contact is paused.** None of the six monitors emails anyone until it is activated.
3. **The B2B key "Eduwit one" carries all five scopes.** Replace it with a referrals-only key and a separate intake key
   for tests (D-017).
4. **Spark is still unconfigured.** Run `select b2c.app_deploy_set('https://spark.eduwit.in', '<B2C_INTERNAL_KEY>');`.
5. **Three legacy influencer accounts are still active.** They grant full-row reads of referred leads through the old
   RLS policy (D-019).
6. **The website deploys from a branch, not from `main`** (D-003).
