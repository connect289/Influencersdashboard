# Clickable design (Phase 0)

`prototype.html` is the clickable design of the three interfaces on **sample data only** (invented people; phones in the
test range 91 90000 000NN). Open it in a browser. The bar at the top switches between the **Sales app** (phone or desktop
width), the **Marketing workspace** and the **Admin console**, and between light, dark and system themes.

| What to try | Where |
| --- | --- |
| Today queue with SLA timers, the four follow-up cards, targets | Sales app → Today |
| Lead screen: brief before you call, "Already with other providers", partner-barred badge, locked contacts and "Add", cross-sell, programme fit | Today → tap a lead |
| Call → dialler (phone) or number + QR (desktop) → call log with outcome, auto stage move and required next follow-up | Lead → Call |
| Stage change with required sub-stage, comment, Lost → nurture return | Lead → tap the stage chip |
| Inbox: template-only when the 24-hour window is closed, free text when it is open | Inbox → Asha (closed) or Sneha (open) |
| Custom lead views, filters, pipeline kanban | Leads |
| Shared email templates with fork-on-edit; commission owed to Eduwit | Me |
| Nurture overview, pool, replies inbox with classification | Marketing → Nurture |
| Journey builder canvas with live counts | Marketing → Journeys → a journey |
| Admin home, Lead Allocation (rules, pools, calendar, capacity, simulation, queues, audit), Teams, Money (verify with proof), Settings, ⌘K, View as Sales | Admin console |

Source in `src/` (`data.js`, `core.js`, `sales.js`, `workspace.js`, `styles.css`); rebuild with `node build.mjs`.
Screenshots in `screens/`. This is a design artefact: Phase 1 builds the real app in Next.js from it.
