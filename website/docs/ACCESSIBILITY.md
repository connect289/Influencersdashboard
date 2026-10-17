# Accessibility audit (Phase 12)

**Target:** WCAG 2.1 AA (spec 10.4, 14). **Date:** 17 Oct 2026. **Build:** the Phase 12 hardened build.

## How it was checked

1. **Automated (axe-core, WCAG 2.0/2.1 A and AA rules), in both themes, on laptop (1366×820) and phone (Pixel 7):**
   every template and every interactive state the site has. Any violation of moderate impact or worse fails the build.
2. **Keyboard-only checks** (automated in Playwright): skip link, focus order, focus trapping and return in dialogs,
   Escape, the combobox search, forms submitted without a mouse.
3. **Code review** of names, roles and live regions for screen readers (Radix primitives for dialogs, switches and
   disclosure; explicit labels, `aria-invalid` and `aria-describedby` on every form field; polite live regions for
   streamed Witty replies and result counts).
4. **Lighthouse accessibility score:** 1.00 (median of 3) on all 13 Lighthouse CI paths.

| Area | Screens and states covered | Spec |
|---|---|---|
| Public pages | home, about, how it works, contact, legal pages, guides list, university list and page, curated view, compare, shortlist, creator link, thank-you, styleguide, 404 | `smoke.spec.ts`, `a11y.spec.ts` |
| Finder | results, filters, detail panel open | `finder.spec.ts` |
| Cookie banner | first view and "Choose" categories (no longer excluded from the sweep) | `a11y.spec.ts` |
| Forms | application form step 1 with validation errors, email-code entry, step 2; enquiry form | `a11y.spec.ts`, `leads.spec.ts` |
| Account | sign-in, signed-in account, data privacy page | `smoke.spec.ts`, `a11y.spec.ts` |
| Witty | gate (before we chat) and a conversation with streamed replies and programme cards | `a11y.spec.ts` |
| Admin | dashboard, content lists and editors, settings, SEO toolkit | `admin.spec.ts` |

## Findings and fixes

| # | Finding | WCAG | Fix |
|---|---|---|---|
| A1 | Closing the detail panel with Escape (or the close button) left keyboard focus on the page body instead of the programme it was opened from; panels open from deep links, not a dialog trigger, so the dialog library had nothing to return to | 2.4.3 Focus order | `components/ui/Panel.tsx` remembers what had focus when the panel opened and restores it on close (or the same link if the list re-rendered). Test: "detail panel: opens from the keyboard, traps focus, Escape closes and returns focus" |
| A2 | Choosing in the cookie banner removed the focused button with the banner; the next Tab started from nowhere | 2.4.3 Focus order | `ConsentBanner.tsx` moves focus to the main content (without scrolling) when the choice was made from the banner. Test: "choosing in the cookie banner keeps keyboard focus on the page" |

No contrast, naming, role, label or landmark violations were found on any screen in either theme. (One contrast report
during the audit was a measurement taken mid-way through a theme colour transition; the audit now waits for
transitions to finish. Both hover states measure well above AA: amber `#ffb81f` on `#1a1200` text, navy `#0b3f78`
with white text.)

## What is in place (verified)

- Skip link is the first focus stop on every page and moves focus to `<main id="main">`.
- Visible focus rings designed into both themes; no `outline: none` without a replacement.
- Dialogs and sheets (detail panel, gate, application form): focus trapped while open, Escape closes, focus returns,
  background inert for screen readers, title and description announced.
- Search combobox: arrow keys, Enter, Escape; options announced; free text resolves to filters.
- Forms: every field has a visible label; errors are shown in text, linked to the field (`aria-describedby`) and mark
  it `aria-invalid`; the first invalid field gets focus; the 6-digit code input accepts paste and works with one-time
  code autofill.
- Witty: the conversation is a `log` region; streamed replies are announced once complete through a polite live region
  (not token by token); Send is a labelled button; feedback buttons have names.
- Reduced motion: every animation (aurora, orb, count-ups, panel slides) has a static equivalent under
  `prefers-reduced-motion`; WebGL never runs when reduced motion is requested or on low-capability devices.
- Primary controls are 40–48 px high (buttons `h-10`–`h-12`, chips and links `min-h-11`); axe's target-size rule is
  not part of WCAG 2.1 AA and was not enforced. Text-resize (200%) was not separately tested.
- Language: `lang="en-IN"` on the document.

## Not covered by automation (recommended before or soon after launch)

- A manual pass with a real screen reader (NVDA + Chrome on Windows, VoiceOver on iOS Safari) through the gate, the
  finder, the detail panel, the application form and a Witty conversation. The automated checks verify names, roles
  and live regions, but not how natural the announcements sound.
- Content written in the admin later (guides, intros, FAQs) is checked only when it is published: the on-page checker
  flags heading order and missing image alt text (SEO toolkit → On-page checks).
