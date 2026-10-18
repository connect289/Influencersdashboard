# Eduwit Influencer Portal

Runs Eduwit's creator programme in one place: discovery and outreach, campaigns, deals with configurable compensation,
contracts with negotiation and OTP click-sign, briefs, content approval, lead attribution with a masked live pipeline for
creators, the earnings ledger, TDS and payouts, dashboards, messaging, scorecards and compliance.

- Spec: `docs/INFLUENCER_PORTAL_SPEC.md`
- Status: **Phases 0–2 done (foundation, creators and campaigns); Phase 3 (deals and compensation) next** (`docs/PROGRESS.md`)
- Developer commands and conventions: root `CLAUDE.md`
- Phase 0 documents: `docs/PHASE0_FINDINGS.md`, `docs/ERD.md`, `docs/SHARED_CHANGES.md`,
  `docs/LEAD_FIELD_WHITELIST.md`, `docs/STAGE_MAPPING.md`, `docs/INTEGRATION_CONTRACTS.md`, `docs/DECISIONS.md`
- Brand: `docs/brand/palette.md`, `docs/brand/eduwit-logo.jpg`

The portal is a separate app with its own deployment. It shares the Supabase project `xlseqwgyjuqhktrguhyc` with Witty,
the B2B CRM and the B2C CRM, keeps its objects in schema `inf`, and reads other products' data only through approved,
read-only paths (`docs/SHARED_CHANGES.md`).
