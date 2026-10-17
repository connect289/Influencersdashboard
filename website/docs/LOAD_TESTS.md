# Load tests (Phase 12)

**Targets (spec 3A):** 10,000+ offerings, 1,000 concurrent visitors during ad spikes, 200 concurrent Witty
conversations. Search p95 < 150 ms at 10,000 offerings (spec 6.4). Witty time to first token < 1.5 s (spec 7.3).

**Date:** 17 Oct 2026. **Where:** this build environment, one 4-vCPU / 15 GB container running everything at once:
Postgres + PostgREST (local Supabase in Docker), one `next start` process, and the load generator. Production is
Vercel (edge cache, functions that scale out, region bom1) in front of the shared Supabase project, so these numbers are
a **conservative floor** for the website's own code, not a forecast of production capacity. A repeat against a Vercel
preview and a Supabase branch is on the go-live checklist (S-55).

## How to run

```bash
cd website/web
npm run db:bench                       # search at 10k offerings, database only (rolled back)
npm run load:seed                      # COMMIT a 10k synthetic catalogue to the LOCAL database (db:reset undoes it)
npm run build && WEB_ADVISOR_PROVIDER=mock WEB_ADVISOR_MOCK_TTFT_MS=800 npx next start -p 3100
node ../scripts/load/edge-cache.mjs --port 3200 --origin http://localhost:3100   # stand-in for Vercel's edge cache
npm run load:visitors -- --vus 1000 --duration 120 --finder 0.05 --base http://localhost:3200
npm run load:sessions > sessions.txt   # 200 verified test students with sessions (local only)
WEB_SESSION_SECRET=… npm run load:witty -- --sessions sessions.txt
npm run db:reset                       # back to the real local catalogue
```

Scripts: `scripts/load/{seed-10k.sql,sessions.sql,run.mjs,edge-cache.mjs,search.pgbench}`. The visitor mix: page views
(home, curated views, university pages, about), hard loads of finder result URLs (`--finder` share), API searches
with varied filters, free text and typos, and suggestions; 1–4 s think time; one client IP per visitor.

## 1. 10,000+ offerings (search)

Synthetic catalogue: real rows ×14 across 129 universities → **10,010 offerings (9,912 visible)**.

| Query (database time, single run) | ms |
|---|---|
| All programmes, grouped (default view) | 145 |
| Free text "mba in marketing" | 30 |
| Programme + specialisation + NAAC + fee cap + eligibility | 61–65 |
| Flat list sorted by fee | 130 |
| Typo "data sciense" | 29–30 |
| Guided (goal + qualification, page 3) | 115–143 |
| Suggestions "mba mar" | 23–33 |
| Zero results ("zzzz") | 255–287 (known slow edge: recomputes the query-less count) |

Sustained uncached searches with random filters (pgbench, 45 s): **56 per second at 4 clients (71 ms average)** and
53 per second at 16 clients: CPU-bound at 4 vCPUs.

**Verdict:** filtered and text searches meet p95 < 150 ms at 10k; the unfiltered default (145 ms) is at the limit and is
served from the edge and the server cache in practice; zero-result searches exceed it (rare, and cached).

## 2. 1,000 concurrent visitors

| Run | Requests | Throughput | p50 | p95 | p99 | Errors |
|---|---|---|---|---|---|---|
| A. Origin only, no edge cache, pessimistic mix (15% finder hard loads) | 14,587 | 105/s | 870 ms | 30 s | 30 s | 26% timeouts |
| B. Origin only, 300 visitors | 9,547 | 102/s | 86 ms | 1.7 s | 4.0 s | 0 |
| C. Edge stand-in, ad mix (5% finder hard loads), before fixes | 41,513 | 335/s | 1 ms | 1.9 s | 10.8 s | 0.01% (pool timeouts) |
| **D. Edge stand-in, ad mix, after fixes** | **44,441** | **359/s** | **1 ms** | **1.5 s** | **4.2 s** | **0.74% fast 503 (search misses)** |
| E. Edge stand-in, pessimistic mix, after fixes | 31,006 | 234/s | 1 ms | 6.1 s | 30 s | 2.6% (finder page timeouts) |

Per request type in run D: page views p95 **10 ms** (0 errors), suggestions p95 11 ms, API searches p50 1 ms / p95
3.3 s (cache misses wait for the database), finder result pages p50 500 ms / p95 5.6 s. Edge hit rate ≈ 88%.

**What limits this box:** one Node process rendering finder result pages (≈ 140% CPU; a warm render is 25–40 ms but
produces 230–260 KB of HTML) and Postgres at ≈ 110% CPU, both on the same 4 vCPUs as the load generator. On Vercel,
pages and API responses come from the edge and functions scale out, so the remaining shared limit is the database.

**Found and fixed (D-080):**
1. **The shared connection pool ran out** (run C: "Timed out acquiring connection from connection pool", 55 times).
   In production that pool also serves Witty and the CRMs. Fixes: a per-instance cap on concurrent database calls
   (`WEB_DB_MAX_CONCURRENCY`, default 16; waits up to 3 s, then a fast 503 instead of holding the pool); the search
   log is written in batches (one call per 25 searches or 5 s per instance) instead of one call per search. After the
   fixes: **0 pool timeouts**; under overload the website sheds its own requests instead of starving other products.
2. **Per-instance caches on serverless:** search, suggestions and offering details now use `use cache: remote` (the
   platform's shared cache across instances); unchanged locally (in-memory fallback).
3. **Optional read replica:** with `SUPABASE_READ_REPLICA_URL` set, catalogue reads (search, suggestions, details,
   university lists) go to a Supabase read replica; leads, sessions and content stay on the primary (S-54).

**Verdict:** for traffic shaped like an ad spike (landing on static curated views and filtering through the cached
API) the site held 1,000 concurrent visitors on this one box with page views unaffected (p95 10 ms) and 0.74% of
search cache misses shed with a fast retryable error. Hard loads of many different finder URLs saturate a single
origin process here; in production they spread across function instances and hit the remote cache, so the real
limit is database capacity. **Not yet verified on production-like infrastructure** — see S-55.

## 3. 200 concurrent Witty conversations

200 signed-in test students, 4 turns each (800 turns), all starting within 2 s, 2–5 s between turns; scripted model
with an 800 ms time to first token (`WEB_ADVISOR_MOCK_TTFT_MS`) so streams stay open as with a real model.

| Metric | p50 | p95 | p99 |
|---|---|---|---|
| Time to first token (includes the 800 ms simulated model delay) | 1.31 s | 2.53 s | 3.00 s |
| Full reply | 2.00 s | 3.07 s | 3.39 s |

**800/800 turns succeeded, 0 errors, 0 fallbacks; all 1,600 messages stored.** Website overhead per turn (search,
engine, verifier, storage, lead update) ≈ 0.5 s p50 and 1.7 s p95 at this concurrency on this box.

**Verdict:** 200 concurrent conversations are handled. The < 1.5 s time-to-first-token target is met at p50 with an
800 ms model; with the real extractor and counsellor models (S-14) it must be re-measured — the extractor call happens
before the first token, so a slow extractor would push p95 past the target (mitigations if needed: a faster extractor
model, prompt caching, streaming an acknowledgement while the extractor runs).

## Before ad campaigns (owner)

- S-54: decide on a Supabase read replica for the website (recommended before paid traffic; isolates catalogue reads
  from Witty and the CRMs), or size up the shared project's compute.
- S-55: repeat runs D and §3 against a Vercel preview + Supabase branch with production-like compute and the real
  model key; record results here.
