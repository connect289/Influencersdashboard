# Performance budgets (spec 13.2)

Measured with Lighthouse CI on the mobile profile (applied throttling: slow 4G, 4× CPU), median of 3 runs, against
`next start` with the local stack. Enforced in CI by `web/lighthouserc.cjs` (fails the build on regressions).

| Budget | Limit | Where it applies |
|---|---|---|
| Performance score | ≥ 0.90 | every path |
| LCP | ≤ 2.5 s | every path |
| CLS | ≤ 0.1 | every path |
| TBT (lab proxy for INP < 200 ms) | ≤ 300 ms | every path |
| JavaScript (transfer size, all scripts) | ≤ 250 KB | every path |
| Accessibility | ≥ 0.95 (all at 100) | every path |
| SEO | ≥ 0.95 | indexable paths (not admin, account, creator, thank-you, filtered finder URLs) |

## JavaScript per route (17 Oct 2026, transfer size)
| Route | JS | Notes |
|---|---|---|
| `/` | 192 KB | hero is server HTML; Witty orb shader starts when idle; chat code loads only on `/witty` |
| `/programmes`, curated views | 213 KB | panels, guided finder, filter sheet, slider and toaster load on demand (D-039); desktop-only rail (D-043) |
| `/universities/[slug]` | 228 KB | application form loads when opened |
| `/witty` | 228 KB | full chat |
| content pages | 181–203 KB | |

About 110 KB of every route is the React + Next.js runtime; its hydration is most of the remaining TBT
(≈ 200–290 ms on the throttled profile). Things already done to stay inside the budget: server-rendered consent banner
(D-037), zod kept out of client code, lazy panels and forms, first finder page of 12 groups, idle-time shaders, no
client-side data fetching on first paint.

## Load targets (spec 3A)
Verified by the Phase 12 load tests: 10,000+ offerings (search p95 measured at 145 ms on 10k rows, `npm run db:bench`),
1,000 concurrent visitors, 200 concurrent Witty conversations.
