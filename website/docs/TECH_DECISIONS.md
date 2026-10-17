# Technical decisions

Choices within the stack in spec Section 3, with the reason and the alternative kept open. Decisions that change the
spec's intent are also logged in `DECISIONS.md`.

| Area | Choice | Why | Alternative kept open |
|---|---|---|---|
| Framework | **Next.js 16.4**, App Router, RSC, Server Actions, **Cache Components** (`"use cache"`, `cacheLife`, `cacheTag`, `revalidateTag`) | Same major as both CRMs; Cache Components is Next 16's static-first model with on-demand revalidation (= ISR). | — |
| Runtime / region | Node runtime, Vercel functions pinned to **`bom1`** (`vercel.json` `regions`), static assets on the global edge | Supabase is in Mumbai (ap-south-1): DB round trips of a few ms. | — |
| Language | TypeScript **5.9** strict + `noUncheckedIndexedAccess` | Matches the CRMs. | TS 7 later |
| Styling | **Tailwind CSS 4** (CSS-first `@theme` tokens) + CSS custom properties for both themes | Tokens as CSS variables let both themes and both design concepts switch at runtime with zero JS. | — |
| Components | **shadcn/ui pattern on Radix** (`radix-ui` 1.8 unified package), `cmdk` (command palette), `vaul` (mobile bottom sheets), `sonner` (toasts), Lucide icons | Accessible primitives; components are owned in-repo (`components/ui`) and restyled to the futuristic system. | — |
| Motion | **Motion 14** (`motion/react`, the successor of Framer Motion) with `LazyMotion` + `domAnimation` features loaded on demand; CSS scroll-driven animations where supported; View Transitions API for card→panel | Keeps the motion runtime off the critical path; CSS does the cheap parts. | — |
| WebGL | **Hand-written fragment shaders** on a tiny in-house WebGL helper (no OGL/Three.js) | Spec budget: hero shader + Witty orb < 30 KB gzipped combined. A minimal helper is ~2 KB. | OGL (≈ 8 KB) if shaders grow |
| Fonts | `next/font/google`, self-hosted at build: display **Bricolage Grotesque** (variable, `opsz` 12–96, `wght` 200–800) or **Space Grotesk** per concept; body **Inter** (variable, `opsz`); numerals with `tnum` | Variable display face with optical sizing (spec 10.2); Inter is highly legible on low-dpi Android and has tabular figures. Final pairing chosen in Phase 1. | Geist (CRM font) |
| Data access | `@supabase/supabase-js` with the **service-role key on the server only**, calling website-owned `web_*` SECURITY DEFINER functions; no browser Supabase client for students | The browser never holds a privileged key; every read is a typed function with a stable contract. | PostgREST anon reads (not used) |
| Validation | **zod 4** schemas shared by client and server (`lib/schemas/`) | Spec rule 6. | — |
| Search | **Postgres-native**: materialised view `web_offering_search` with weighted `tsvector`, `pg_trgm` (typo tolerance), `unaccent`, synonyms table, facets computed in the same function call; behind a `SearchAdapter` interface | Spec 3/3A; one round trip for results + facets; Typesense/Meilisearch can replace the adapter later. | Typesense / Meilisearch adapter |
| Natural-language parsing | Deterministic parser in TypeScript (`lib/search/parse.ts`): budgets ("under 2 lakh"), levels, programme/specialisation synonyms, Hinglish fillers, mode, duration | No LLM on the search path (spec 6.4). | — |
| Key-value store | **Upstash Redis** (`@upstash/redis`, `@upstash/ratelimit`) behind a `KvStore` interface; in-memory implementation for dev/test | Vercel KV is now Upstash under the hood; HTTP-based, works in serverless. | Postgres-backed limiter (`web_rate_events`) as a fallback if Redis is down |
| Student identity | Website-owned email codes + signed httpOnly session cookie (`jose` JWT, revocable via `web_student_sessions`) | See D-005 (shared Auth trigger and project-wide OTP settings). | `SupabaseAuthOtpVerifier` adapter (disabled) |
| Staff auth (admin) | Supabase Auth (Google / email) + email-code second factor, trusted device 30 days — same pattern as Spark (`b2c-crm`) | Spec 11 ("matches the CRM"). | — |
| Email | `EmailSender` interface: SMTP (nodemailer) and Resend implementations; Mailpit locally; console in tests | CRMs already use SMTP (Google Workspace relay) and Resend/Brevo. | Brevo |
| Bot protection | Cloudflare **Turnstile** (server-verified), honeypot, rate limits per IP/device/email, disposable-email blocklist, block list, junk-risk score | Spec 7.2. | — |
| AI | **Claude API** (`@anthropic-ai/sdk`) with streaming, prompt caching, per-session token budget, per-turn timeout, circuit breaker; agent core read from the shared versioned prompt store (see `AGENT_ARCHITECTURE.md`) | Spec 7.3. Model configurable via `web_settings` (default `claude-sonnet-5-5`; `claude-haiku-5-5` for cheap classification steps). | — |
| Outbox | `web_outbox` written in the same transaction as the lead record; processed by `pg_cron` → `pg_net` call to `/api/internal/outbox` (and a Vercel cron fallback) with retries, exponential backoff, dead-letter | Spec 3A "never lose a lead". | Queue service later |
| Analytics | Consent manager (first-party, no third-party CMP) gating GA4, Meta Pixel, Clarity; Meta **Conversions API** server-side through the outbox with event-ID dedup | Spec 13.3. | — |
| Observability | `@sentry/nextjs` (lazy, DSN-gated), structured JSON logs with request IDs (`x-request-id` propagated), `/api/health`, `/api/metrics` | Spec 15. | — |
| Testing | Vitest (unit), SQL tests in `begin…rollback` (RLS + functions), Playwright (e2e, laptop + Pixel 7) with `@axe-core/playwright`, Lighthouse CI (`@lhci/cli`) with budgets | Spec 16. | — |
| Lint/format | ESLint 10 flat config (`eslint-config-next`), Prettier + `prettier-plugin-tailwindcss` | Spec 3 "Quality". | — |
| Content | `web_*` tables edited in the admin; rich text stored as a constrained block JSON (headings, paragraphs, lists, callouts, links, images, FAQ) rendered server-side | Editors use the admin, no deploy needed; blocks avoid raw HTML/XSS. MDX not chosen because non-developers edit content. | MDX for long-form if needed |
| Local DB | Supabase CLI stack + `prod-replica` container | See D-008. | Supabase branch |
