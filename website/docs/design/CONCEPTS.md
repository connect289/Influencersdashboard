# Design concepts (Phase 1) and the choice

Both concepts are real pages over real catalogue data (subset of the 17 Oct 2026 export) and share one design system,
one component library and both themes. They differ in composition, display typography, atmosphere and how central Witty
is. Preview: `/concepts` (noindex). Recordings: `docs/design/recordings/concept-{a,b}-{phone,desktop}.webm`.

## Concept A — Luminous (dark-led) ✅ chosen
- **Hero = Witty.** A breathing light-orb and Witty's greeting sit at the centre of a living aurora (WebGL, reacts to
  pointer, scroll and Witty's activity). The chat composer *is* the banner; starter chips below. Trust line counts up
  from live catalogue numbers.
- Display face **Bricolage Grotesque** (variable, optical sizing) with kinetic word reveals and weight shift on hover.
- Finder: left facet rail (bottom sheet on phones), grouped results as floating glass cards with luminous hairlines,
  odometer counts, histogram fee slider, card → detail panel with view transitions.
- Chat: Witty's turns render as generative components (cards assemble, fee bars fill, checks tick, comparison grid builds
  column by column).

## Concept B — Prism (light-led) — preserved
- **Editorial split hero:** "Choose your education wisely." (the brand tagline) with search on the left; Witty as a
  floating companion card on the right; daylight-through-a-prism light beams.
- Display face **Inter** at its display optical size (one font file for the whole concept).
- Finder: horizontal filter pills with popovers, crisper cards and smaller radii.
- Chat: bubble-style turns, same generative components.

## Scores (production build, mobile)
Lighthouse 13.5, Moto-G-class emulation. **Applied throttling** (DevTools: slow 4G + 4× CPU) is the realistic measure;
**simulated** (Lantern) adds the framework JS requested before LCP as if it blocked it.

| Page | Applied: Perf / LCP / CLS / TBT | Simulated: Perf / LCP | A11y | Best practices |
|---|---|---|---|---|
| A home | 98 / 1.7 s / 0 / 130 ms | 91 / 3.5 s | 96 | 100 |
| B home | 98 / 1.7 s / 0 / 120 ms | 91 / 3.5 s | 96 | 100 |
| A finder | — | 89 / 3.3 s | 98 | 100 |
| B finder | — | 90 / 3.2 s | 98 | 100 |
| A chat | — | 95 / 2.8 s | 100 | 100 |
| B chat | — | 95 / 3.0 s | 100 | 100 |
| Style guide | — | 95 / 3.0 s | 97 | 100 |

SEO 60–63 on these pages only because they are deliberately `noindex`. Observed (unthrottled) LCP = FCP ≈ 0.2 s: the
LCP element is server HTML text. JavaScript: the framework (React DOM + Next runtime) is ~165 KB gz; the home page adds
~17 KB of its own; **hero shader + Witty orb = 7 KB gz** (budget 30 KB). Full JSON: `docs/design/lighthouse/`.

Fixes made during Phase 1 measurement: Roboto Flex (190 KB) removed; fonts self-hosted as Latin-only subsets (₹ falls
back to the system font instead of a 130 KB latin-ext file); `font-display: optional` (no swap, no CLS); odometers reserve
their final width; FAQs use zero-JS `<details>`; concept pages split per route so each ships only its own islands.

## Why A
Scored against spec 10.1 principles, 10.4 guardrails and the numbers above:
1. **AI-native, not AI-decorated** — A makes Witty the hero (spec §8 item 1); in B Witty is a side card that falls below
   the fold on phones, where most traffic comes from.
2. **Spatial and luminous / "looks like the future"** — A's aurora, orb and glass depth deliver the owner's direction
   most strongly; B is calmer and more conventional.
3. **Calm power, data as delight** — equal (shared components).
4. **Futuristic but credible** — B is marginally more "traditional-trustworthy"; A carries the same trust layer
   (verified badges, last-verified dates, real contact details, no hype) so the gap is small.
5. **Performance and accessibility** — tied (98 vs 98 applied; AA contrast enforced by tests in both themes).
6. **Witty switched off at launch (D-012)** — A's central surface hosts the guided finder + "Get free counselling"
   instead of the chat, keeping the composition.

## How to switch to B
- Site-wide: set `web_settings.design_concept = "b"` in the admin (Phase 10) — the root layout writes
  `data-concept="b"` on `<html>`; tokens, display face and the B layouts (hero, finder bar, chat bubbles) switch with no
  redeploy. Default theme follows `web_settings.default_theme`.
- The B pages are also kept at `/concepts/b/*` and on the local git branch `concept-b` (D-023).
