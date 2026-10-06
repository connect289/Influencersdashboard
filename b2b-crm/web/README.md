# Eduwit Partner CRM: web app

Next.js 16 (App Router, Turbopack), React 19, Tailwind CSS 4, Supabase Auth. Design: `../../docs/b2b-design.md`.

## What it does today (app shell)

- Sign-in for the single Admin (`connect@eduwit.in`): Google, or email + password; then a 6-digit authenticator code
  (TOTP). Password reset by email. Any other account is refused, signed out and logged.
- Five failed password or code attempts lock sign-in for 15 minutes. Sessions end after 12 hours idle.
- The shell: sidebar, ⌘K command palette, `g` + letter shortcuts, light/dark/system theme, Command Center, Security page
  (sessions, sign out other devices, sign-in history). Planned screens describe what is coming.
- Leads (`/leads`): search (name, phone, email, ID), status/stage/source/routing filters with counts, keyset paging,
  a drawer with the lead's details, Witty chat and activity, bulk soft delete with a reason, the recycle bin with
  restore, and CSV export (full or masked; every export is logged). State lives in the URL, so every view is a link.
- Partners (`/partners`): cards with status, live state, today's and this month's leads and go-live progress; add and
  edit (identity and student-facing brand, CRM type, duplicate handling and hold window, caps, working hours and
  holidays, SLAs, lead criteria, notification switch); mark active, pause, resume, close (with reasons); the live
  switch, which stays locked until the go-live checklist is complete.
- Programme Repository (`/programmes`): per partner, upload the partner's Excel or CSV file (kept as uploaded in a
  private bucket), map its columns once (the template is saved), and every row is normalised (amounts like "1.5 L",
  modes, levels, dates, commission) and matched to the catalogue. Review the rows that need it, preview what changes
  against the live offers (removals that leave a programme with no partner are flagged), publish, and roll back to any
  earlier version. Catalogue coverage by course across partners.

## How access is enforced

| Layer | Check |
| --- | --- |
| `proxy.ts` | Refreshes the session, signs out after 12 h idle, redirects signed-out visitors, sets a nonce CSP |
| `app/(app)/layout.tsx` → `requireAdmin()` | On every request: `b2b.me()` must say allowlisted and `is_admin` (TOTP-verified) |
| Server actions → `assertAdmin()` | Same check; throws |
| Database | RLS `(select b2b.is_admin())` on every `b2b` table; Admin functions re-check `b2b.is_admin()` |

The service-role key is used only for the signed-out steps: logging attempts, the lockout check and the reset-link
allowlist check (`lib/auth.ts`).

## Run locally

```bash
cp .env.example .env.local   # fill in the four values
npm install
npm run dev                  # http://localhost:3000
npm test && npm run typecheck && npm run build
```

## Deploy on Vercel (one time)

1. Vercel → Add New → Project → import `connect289/Influencersdashboard`. **Root Directory: `b2b-crm/web`.**
   `vercel.json` pins the Mumbai region (`bom1`).
2. Environment variables (Production and Preview):
   - `NEXT_PUBLIC_SUPABASE_URL` = `https://xlseqwgyjuqhktrguhyc.supabase.co`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` = Supabase → Project Settings → API Keys → publishable key
   - `SUPABASE_SERVICE_ROLE_KEY` = same page → secret key (mark it Sensitive)
   - `NEXT_PUBLIC_SITE_URL` = the app's URL, e.g. `https://eduwit-b2b-crm.vercel.app` (no trailing slash)
3. Supabase (production project):
   - Project Settings → Data API → **Exposed schemas: add `b2b`** (the app shows a setup notice until this is done).
   - Authentication → URL Configuration → Redirect URLs: add `https://<your app URL>/auth/callback`.
     Keep the old CRM's URLs; do not change the Site URL.
   - Authentication → Providers → Email: turn on **leaked password protection**.
   - Authentication → Multi-Factor: TOTP **enabled** (the default).
4. Deploy. Every push then builds automatically; merging to `main` updates production.
