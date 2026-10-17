# Design system

Living style guide: **`/styleguide`** (noindex) — tokens, contrast table, type scale, space/radius/elevation,
every component with its states, the motion gallery with reduced-motion previews, and the capability tiers.

## Files
| Area | Where |
|---|---|
| Tokens (colour both themes, type, space, radius, blur, motion, z-layers; concept B overrides) | `web/app/tokens.css` |
| Tailwind mapping, surfaces (glass, luminous hairline, grain), motion keyframes, reduced motion | `web/app/globals.css` |
| Fonts (self-hosted Latin subsets, OFL) | `web/app/fonts/`, `web/lib/fonts.ts` |
| Contrast pairs + test (CI) | `web/lib/design/contrast.ts`, `contrast.test.ts` |
| Components | `web/components/ui/*` (Button, Badge, Chip, Card, Field, Input/Textarea/NativeSelect, Checkbox, CodeInput, RangeSlider, Segmented, Panel, BottomSheet, Accordion, Disclosure, Tabs, Tooltip, Popover, Odometer, FeeBar, GradeMeter, ProgressTrack, Skeleton, EmptyState) |
| Brand | `web/components/brand/Logo.tsx`, `web/public/brand/*.svg` |
| Atmosphere + Witty presence | `web/components/fx/Atmosphere.tsx`, `web/components/witty/WittyOrb.tsx`, `web/lib/client/gl.ts`, `web/lib/client/shaders/*`, `web/lib/client/witty-presence.ts` |
| Theme + tiers boot script | `web/lib/client/boot-script.ts` (inline, CSP-hashed), `web/components/theme/ThemeToggle.tsx`, `web/lib/client/use-tier.ts` |

## Rules
- Colour: semantic tokens only in components (`bg-surface`, `text-muted`, …). Amber is never body text on light
  surfaces (use `text-amber-text`). Every pair is AA (tested).
- Surfaces: glass is solid on the low tier, without backdrop-filter, and in high-contrast mode.
- Type: inputs never below 16 px; fees/counts use tabular figures; headlines balanced.
- Motion: every animation has a reduced-motion equivalent; nothing scroll-jacks; no autoplay sound; counters only count
  to real numbers.
- WebGL: never the LCP element; loads after first paint; ≤ 0.75× resolution; fps cap; pauses off-screen/hidden tab;
  budget 30 KB gz (currently 7 KB).
- Theme scoping: use the `only-dark` / `only-light` utilities for theme-specific assets (they follow the nearest
  `[data-theme]`, including nested previews); the Tailwind `dark:` variant follows the nearest themed ancestor only when
  the theme is set on `<html>`.
