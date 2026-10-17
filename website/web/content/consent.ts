/**
 * Consent texts shown at the point of collection (drafts for legal review: docs/legal/consent-texts.md, S-44,
 * A-CONSENT-1). The accepted version is stored with every consent; Phase 7 serves them from web_consent_texts.
 */
export const CONSENT = {
  form: {
    version: "web-form-2026-10-v1",
    text: "I agree that Eduwit Learning Services may use the details I have entered to help me with my admission, and may share them with our partner universities and our admission partners (edtech companies). A counsellor may call, WhatsApp or email me about this enquiry. I can withdraw consent or ask for my data to be deleted at any time.",
  },
  gate: {
    version: "web-gate-2026-10-v1",
    text: "I agree that Eduwit Learning Services may use my name, phone number and email to help me choose a programme and with my admission, and may share them with our partner universities and our admission partners (edtech companies). My chat with Witty, Eduwit's AI admissions assistant, is stored to answer me and to improve the service. I can withdraw consent or ask for my data to be deleted at any time.",
  },
  marketing: "Send me programme updates on WhatsApp and email.",
} as const;
