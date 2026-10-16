# Eduwit Spark: brand palette and design system

Status: **settled 16 October 2026** (Vikas: "fresh look, same logo; use the best design as per best logic"). Replaces the
14 October palette, which kept the same two logo colours but drew every box with a hairline.

## Source

Sampled in code from `eduwit-logo.jpg` (1264 × 1264, JPEG). Two clusters make up the logo:

| Logo colour | Sampled | Share of logo pixels |
| --- | --- | --- |
| Navy (left half of bulb, book, "Edu", tagline) | `#072E5A` | 54% |
| Amber (right half of bulb, book, "wit") | `#F4A504` | 46% |

Every token below is a tint or shade of these two, plus one red and one green that are used for status only (the spec
needs "breached" and "success" states, and the logo has neither).

## The idea

- **Paper and cards.** The page is a cool, pale canvas (`bg`); content sits on white cards with a 14 px radius and a
  barely-there shadow. No hairline boxes, no cards inside cards: the canvas tone separates things.
- **Navy works, amber signals.** Navy is every word, button, link and selected state. Amber appears only where
  something needs the eye: the one Call button on a screen, "hot", the unread count, the live marker. Amber is never
  text on white; amber words use `amber-ink`.
- **One scale, a size larger on a phone.** Body 15 px on a phone, 14 px on a laptop; headings 24/26, 17, 15; small 13.
  Controls are 44 px tall on a phone and 40 px on a laptop. Geist Sans for words, Geist Mono with tabular numbers for
  numbers, phones and times.
- **One thing at a time.** Long screens become tabs (the lead screen: Overview, Profile, Applications, with the activity
  rail beside them on a laptop and as a tab on a phone). Rarely used blocks fold away (`details`).
- **Search anywhere.** ⌘K / Ctrl+K or "/" opens a search for students and screens from any page.

## Tokens (`web/app/globals.css`)

### Light

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#F2F4F7` | The canvas |
| `surface` | `#FFFFFF` | Cards, inputs, the sidebar's selected item |
| `surface-2` | `#E9EDF2` | Quiet buttons, tab bars, tracks, hover |
| `surface-3` | `#DCE3EB` | Hover on quiet buttons |
| `line` | `#E4E9EF` | Table rows and the few remaining dividers |
| `line-strong` | `#B3C0CF` | Input borders |
| `ink` | `#0E2240` | Words (16.1 on white) |
| `muted` | `#5C6F87` | Secondary words and labels (5.6 on white) |
| `faint` | `#8A9BB0` | Group labels, sources |
| `primary` / `primary-hover` | `#0B2F5E` / `#082447` | Buttons, links, the chosen pill |
| `primary-soft` | `#E6EDF6` | Soft navy: avatars, selected rows, active phone-nav icon |
| `amber` / `amber-hover` | `#F4A504` / `#E09700` | The Call button, "hot", counts |
| `on-amber` | `#0E2240` | Words on amber (7.8) |
| `amber-soft` / `amber-ink` | `#FFF3D6` / `#8A5A00` | "At risk", warnings; amber words (6.1 on white) |
| `red` / `red-soft` | `#C2281D` / `#FCEBE9` | Breached, errors, overdue |
| `green` / `green-soft` | `#0F7A4B` / `#E4F5EC` | Working, verified, success |

### Dark (chosen by the person; the system setting is respected)

| Token | Hex |
| --- | --- |
| `bg` / `surface` / `surface-2` / `surface-3` | `#0A1322` / `#122036` / `#1B2C45` / `#263A56` |
| `line` / `line-strong` | `#233650` / `#4C6283` |
| `ink` / `muted` / `faint` | `#EEF2F7` / `#A5B3C5` / `#7B8CA3` |
| `primary` / `primary-hover` / `on-primary` / `primary-soft` | `#C9D6E6` / `#DCE5F0` / `#0A1322` / `#1D3250` |
| `amber` / `amber-soft` / `amber-ink` | `#F4A504` / `#3A2E12` / `#F7BC43` |
| `red` / `red-soft` / `green` / `green-soft` | `#F8766B` / `#3A1A1B` / `#4BD08C` / `#10301F` |

Charts keep the separately validated categorical order (`--c1…--c8`) and one-hue ramps; see the `dataviz` notes in
`globals.css`. Status colours are never reused for a chart series.

## Components, in one line each

- **Button** (`.btn`): quiet grey by default; `.primary` navy; `.call` amber; `.quiet` text-only; `.sm` for row actions.
- **Pill** (`.pill`): a choice in a row (views, filters, options); the chosen one is navy.
- **Chip** (`.chip`): a small tinted label with an icon or a word, never colour alone: hot, warm, risk, breach, ok, line.
- **Tabs** (`.tabs`, `.tabbar`): a soft segmented control; the active segment is a white card.
- **Panel** (`.panel`): a white card with a title row; `details.panel` folds.
- **Stat / KPI** (`.stat`, `.kpi`): a label, a big tabular number, a one-line delta.
- **Sheet** (`.sheet`): a bottom sheet on a phone, a centred dialog on a laptop.
- **Queue card** (`.qcard`): avatar, name and why, the Call button, the SLA chip; a red ring when the SLA is breached.
