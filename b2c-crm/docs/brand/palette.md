# Eduwit B2C CRM: brand palette

Status: **settled 14 October** (Vikas: "use the best palette as per your judgement; no black except in dark mode").
Chosen: the sampled navy and amber, plus option B (a red and a green for status only).

## Source

Sampled in code from `eduwit-logo.jpg` (1264 × 1264, JPEG). Pixels were clustered after removing the white background; the
two clusters that make up the logo:

| Logo colour | Sampled | Share of logo pixels | B2B CRM uses |
| --- | --- | --- | --- |
| Navy (left half of bulb, book, "Edu", tagline) | `#072E5A` | 54% | `#0B2F5E` |
| Amber (right half of bulb, book, "wit") | `#F4A504` | 46% | `#F5A800` |
| White (background, pen nib) | `#FFFFFF` | — | — |

The B2B CRM's values sit within JPEG noise of these, so both products read as one family. I propose the sampled values
for B2C. Every other token below is a **mix of these three colours only** (navy and amber tinted towards white or shaded
towards black), so nothing comes from outside the logo.

## Tokens

Contrast ratios are WCAG 2.1, computed in code. AA needs 4.5 for body text, 3.0 for large text and UI boundaries.

### Light mode

| Token | Hex | Use | Contrast |
| --- | --- | --- | --- |
| `bg` | `#FFFFFF` | Page | — |
| `surface` | `#F8F9FA` | Cards, sidebar | — |
| `surface-2` | `#EEF0F3` | Table headers, hover rows | — |
| `border` | `#D7DEE5` | Hairline dividers (decorative) | — |
| `border-strong` | `#778CA4` | Inputs, checkboxes, focusable outlines | 3.46 on bg ✓ (UI) |
| `text` | `#052244` | Body text | 15.9 on bg ✓ |
| `text-muted` | `#516D8C` | Secondary text, labels | 5.36 on bg, 5.09 on surface ✓ |
| `primary` | `#072E5A` | Primary buttons, links, active nav | 13.6 on bg ✓ |
| `primary-hover` | `#052244` | Hover / pressed | — |
| `on-primary` | `#FFFFFF` | Text on primary | 13.6 ✓ |
| `primary-soft` | `#E6EAEE` | Selected row, soft chips | text 13.2 ✓ |
| `accent` | `#F4A504` | Highlights: "hot", unread dot, progress, active tab underline, CTA on dark areas | **2.05 on white: never text on white** |
| `on-accent` | `#052244` | Text on amber fills | 7.76 ✓ |
| `accent-soft` | `#FDF1D7` | "At risk", "Already with providers" badge background | — |
| `accent-text` | `#7F5602` | Amber-family text on white or `accent-soft` | 6.49 / 5.79 ✓ |
| `focus` | `#072E5A` | 2 px focus ring, offset 2 px | 13.6 ✓ |

### Dark mode

| Token | Hex | Use | Contrast |
| --- | --- | --- | --- |
| `bg` | `#020D19` | Page (navy shaded) | — |
| `surface` | `#031224` | Cards, sidebar | — |
| `surface-2` | `#041932` | Table headers, hover rows | — |
| `border` | `#345478` | Hairline dividers | — |
| `border-strong` | `#6A829C` | Inputs, focusable outlines | 4.92 on bg, 4.74 on surface ✓ |
| `text` | `#F0F2F5` | Body text | 17.4 on bg ✓ |
| `text-muted` | `#A1B0C0` | Secondary text | 8.83 on bg, 7.97 on surface-2 ✓ |
| `primary` | `#B5C0CE` | Primary buttons, links (navy tinted) | 10.6 on bg ✓ |
| `primary-hover` | `#C8D1DB` | Hover | — |
| `on-primary` | `#020D19` | Text on primary | 10.6 ✓ |
| `primary-soft` | `#052244` | Selected row | text 14.2 ✓ |
| `accent` | `#F4A504` | Highlights, as in light; usable as text on dark | 9.52 on bg ✓ |
| `on-accent` | `#020D19` | Text on amber fills | 9.52 ✓ |
| `accent-soft` | `#2E2C1E` | "At risk" badge background | — |
| `accent-text` | `#F7BC43` | Amber text | 11.4 on bg, 8.18 on accent-soft ✓ |
| `focus` | `#F4A504` | Focus ring | 9.52 ✓ |

## How the two colours are used

- **Navy is the working colour:** navigation, primary actions, links, selected states, headings.
- **Amber is the signal colour, used sparingly:** hot leads, unread, SLA "at risk", the active tab marker, progress
  towards target, the one call-to-action per screen in the Sales app (Call), badges such as "Already with other
  providers". Amber is never text on white; amber text uses `accent-text`.
- Charts: navy and amber as the two primary series, then navy tints at 70%, 45% and 25% for more series.

## Decision needed: status colours

The logo has no red and no green. The spec needs both: "a breach turns the lead red in queues" (B8.7), plus success and
error messages. Two options:

| | Option A: logo colours only | Option B (recommended): two functional colours, for status only |
| --- | --- | --- |
| SLA breached, errors, destructive actions | Navy chip with a ⚠ icon and the word "Breached" | Red: light `#B42318` (6.57 on white; white text on it 6.57), soft `#FEF3F2`; dark `#F97066` (7.02 on bg) |
| Success, enrolled, verified | Navy-soft chip with ✓ | Green: light `#067647` (5.69 on white), soft `#ECFDF3`; dark `#47CD89` (9.65 on bg) |
| At risk, warning | Amber family (both options) | Amber family |

Under option B, red and green appear only on status chips, timers, toasts and destructive buttons, never in branding,
so the product still looks navy and amber. Every status also carries an icon and a word, so it never depends on colour
alone (WCAG 1.4.1).

**Chosen: option B.** The spec needs a red SLA breach, and red and green on status chips only keep the product navy and amber.

## No black in light mode

Light mode uses no black and no grey made from black: the darkest colour is the navy text `#052244`, borders and
muted text are navy tints, and shadows (where used at all) are navy at low opacity. Only dark mode, which a user turns
on, uses the navy-black ground `#020D19`.
