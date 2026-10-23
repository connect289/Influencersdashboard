# Eduwit One — changes

Append-only, newest first. One entry per deploy or per phase step; production database changes name the dump they
followed.

## 23 Oct 2026 — phase 0, preflight

- Added `eduwit-one/` with `config/defaults.json` (non-secret hosts and ids) and `config/setup-items.json` (the Setup
  checklist, 31 items).
- Added `scripts/preflight.ts`, a re-runnable access preflight. It made real reads against GitHub, Vercel, Chatwoot,
  n8n, Lightsail, UptimeRobot, Resend, the B2B API, WhatsApp, the model APIs and the app health endpoints. Optionally it
  runs a read-only survey of production through `psql`.
- First run: 13 verified, 12 not provided, 1 refused (Lightsail), 5 unfilled. Results are in `docs/PREFLIGHT.md`, and
  the seed for `one.settings.setup` is in `supabase/seed/setup.json`.
- Logo saved as `web/public/brand/eduwit-logo-source.jpg`; palette navy `#072E59`, amber `#F2A505`.
- No database, Vault, Vercel or n8n object was created or changed. All reads were read-only.
