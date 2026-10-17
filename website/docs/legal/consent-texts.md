# Consent texts (drafts for lawyer review — S-44, A-CONSENT-1)

Status: **draft**. The spec asks to reuse the current site's contact-form consent text, updated to mention AI chat
storage and partner sharing. The current text could not be crawled yet (D-006); these drafts follow the wording style of
Witty's live, B2B-registered consent line `witty-notice-2026-10-v2` ("…may be shared with our partner universities and
our admission partners (edtech companies)…"), which the B2B CRM requires for partner-share consent
(`docs/go-live-setup.md` §4). After the crawl, the current site's text will be merged in and both versions compared
for the lawyer.

Each version is stored in `web_consent_texts` and the accepted version + timestamp are stored with every consent.

## `web-gate-2026-10-v1` — Witty gate (channel `website_agent`)
> I agree that Eduwit Learning Services may use my name, phone number and email to help me choose a programme and with my
> admission, and may share them with our partner universities and our admission partners (edtech companies). My chat with
> Witty, Eduwit's AI admissions assistant, is stored to answer me and to improve the service. I can withdraw consent or ask
> for my data to be deleted at any time ([Data privacy & opt-out](/legal/data-privacy-opt-out)). See the
> [Privacy Policy](/legal/privacy-policy).

Purposes: `sales`, `partner_share`, `ai_chat_storage`. Optional separate box (unticked by default):
> Send me programme updates on WhatsApp and email. (purpose `marketing`)

## `web-form-2026-10-v1` — application and enquiry forms (channel `web_form`)
> I agree that Eduwit Learning Services may use the details I have entered to help me with my admission, and may share them
> with our partner universities and our admission partners (edtech companies). A counsellor may call, WhatsApp or email me
> about this enquiry. I can withdraw consent or ask for my data to be deleted at any time
> ([Data privacy & opt-out](/legal/data-privacy-opt-out)). See the [Privacy Policy](/legal/privacy-policy).

Purposes: `sales`, `partner_share`. Optional marketing box as above.

## Notes for the lawyer
- DPDP Act 2023: purpose statement, itemised notice, withdrawal as easy as giving consent, grievance contact — the notice
  links to the Privacy Policy and the opt-out page; the grievance officer details must be in the Privacy Policy.
- Phone numbers are **not** verified by OTP at launch; emails are verified by a 6-digit code.
- Proposed Privacy Policy additions (AI chat storage, email verification, application form data, analytics with consent)
  are in `docs/legal/privacy-policy-proposed-additions.md` (Phase 6), as a separate reviewable diff on top of the verbatim
  migrated policy.
