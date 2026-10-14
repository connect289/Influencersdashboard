# Eduwit B2C CRM

In-house sales and nurture CRM for Eduwit Learning Services. Spec: `docs/B2C_CRM_PROMPT.md` (final, 14 Oct 2026).

Status: **Phase 0** (audit and design). Nothing is built or applied to any database yet.

| File | What |
| --- | --- |
| `docs/B2C_CRM_PROMPT.md` | The product specification (Part A: how to work; Part B: the product; B21 wins) |
| `docs/phase0-audit.md` | Phase 0 audit: existing objects with verdicts, `b2c` schema plan, what the B2B CRM must expose, Google Workspace setup, open questions |
| `docs/brand/` | Logo, proposed palette (`palette.md`, `palette-preview.html`), awaiting confirmation |

Hard limits while building: staging or a Supabase branch only; never run `student_leads_v2_rename.sql`; never change
Witty's `w2_*` objects, `lead_intake()`, the n8n workflows or the B2B CRM (`../b2b-crm`); test leads only.
