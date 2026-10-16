# Eduwit Influencer Portal: brand palette

Source: the Eduwit logo (`eduwit-logo.jpg`, attached to the build prompt), sampled on 16 Oct 2026, and the shared Eduwit
tokens already used by the B2C CRM (`b2c-crm/docs/brand/palette.md`) and the B2B CRM. The portal reuses those tokens
so all Eduwit products look like one family.

Logo samples (dominant pixel clusters): navy `#042C58` / `#082C58` / `#04305C`; amber `#F0A400` / `#F4A404`.

## Light theme (default)

| Token | Value | Use |
| --- | --- | --- |
| `--bg` | `#F2F4F7` | Page background |
| `--surface` | `#FFFFFF` | Cards, sheets |
| `--surface-2` | `#E9EDF2` | Subtle fills, table headers |
| `--line` | `#E4E9EF` | Borders |
| `--line-strong` | `#B3C0CF` | Inputs, dividers that must be seen |
| `--ink` | `#0E2240` | Body text |
| `--muted` | `#5C6F87` | Secondary text (AA on white) |
| `--primary` | `#0B2F5E` | Eduwit navy: primary buttons, active navigation, links |
| `--primary-hover` | `#082447` | |
| `--primary-soft` | `#E6EDF6` | Selected rows, soft badges |
| `--accent` | `#F4A504` | Eduwit amber: highlights, the earnings accent, focus ring outer. **Never as text on white** |
| `--accent-hover` | `#E09700` | |
| `--on-accent` | `#0E2240` | Text on amber |
| `--accent-soft` | `#FFF3D6` | Warning and "pending" backgrounds |
| `--accent-ink` | `#8A5A00` | Amber-family text on light backgrounds (AA) |

## Dark theme

| Token | Value |
| --- | --- |
| `--bg` | `#0A1322` |
| `--surface` | `#122036` |
| `--ink` | `#E6ECF4` |
| `--muted` | `#9DB0C7` |
| `--primary` | `#C9D6E6` (on-primary `#0A1322`) |
| `--primary-soft` | `#1D3250` |
| `--accent` | `#F4A504` |
| `--accent-ink` | `#F7BC43` |

## Status families (one colour per family, reused everywhere)

| Family | Light fg / bg | Dark fg | Statuses |
| --- | --- | --- | --- |
| Neutral | `#5C6F87` / `#E9EDF2` | `#9DB0C7` | draft, not started, new, prospect |
| In progress | `#0B2F5E` / `#E6EDF6` | `#C9D6E6` | sent, submitted, in negotiation, qualifying, allocated, in counselling, accrued |
| Waiting / attention | `#8A5A00` / `#FFF3D6` | `#F7BC43` | changes requested, pending, on hold, payable, ready to sign, under review |
| Success | `#0F7A4B` / `#E4F5EC` | `#4BD08C` | approved, signed, active, live verified, enrolled, confirmed, paid |
| Problem | `#C2281D` / `#FCEBE9` | `#F8766B` | rejected, overdue, failed, lost, fraud suspected, clawed back, blocked |
| Closed | `#5C6F87` / `#F2F4F7` (outlined) | `#9DB0C7` | archived, completed, expired, void, superseded, withdrawn |

Status colours are never reused as chart series; charts use their own categorical palette (validated for contrast in
both themes in Phase 1).

## Type and shape

Geist Sans and Geist Mono (tabular numbers for money). Body 15 px on phones, 14 px on laptops. Controls 44 px tall on
phones, 40 px on laptops (touch targets). Card radius 14 px. Money in Indian format (`₹1,23,456.00`), dates `16 Oct 2026`,
times in IST with relative times.
