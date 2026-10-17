// The seed clause library and default template (spec 8.1). Professionally structured DRAFT wording: every clause
// starts with the draft marker and stays "unreviewed" until a Super Admin marks it legally reviewed; the legal-review
// gate (setting contracts.signing.legal_review_gate) blocks sending contracts that contain unreviewed clauses.
// Inserted once by a generated migration (never overwriting edits); staff edit them as new versions.

export const DRAFT_MARKER = "DRAFT — requires legal review before use.";

export const CLAUSE_CATEGORIES = [
  "parties",
  "scope",
  "timelines",
  "compensation",
  "taxes",
  "content_approval",
  "disclosure",
  "claims",
  "usage_rights",
  "exclusivity",
  "confidentiality",
  "data_protection",
  "conduct",
  "penalties",
  "termination",
  "force_majeure",
  "indemnity",
  "disputes",
  "notices",
  "entire_agreement",
] as const;
export type ClauseCategory = (typeof CLAUSE_CATEGORIES)[number];

export interface SeedClause {
  key: string;
  category: ClauseCategory;
  title: string;
  /** Plain text: blank lines separate paragraphs, "- " starts a bullet, {{…}} are variables and conditionals. */
  body: string;
  required: boolean;
  negotiable: boolean;
  locked: boolean;
  /** Deal types the clause applies to (empty = all). */
  deal_types: string[];
}

export const SEED_CLAUSES: readonly SeedClause[] = [
  {
    key: "parties",
    category: "parties",
    title: "Parties and definitions",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

This agreement is made between {{eduwit.legal_name}}, {{eduwit.address}} ("Eduwit"), and {{creator.legal_name}} ({{creator.handle}}), {{creator.address}} ("the Creator").

{{#if payee.is_agency}}Payments under this agreement are made to {{payee.name}}, acting for the Creator, who confirms its authority to receive them.{{/if}}

In this agreement:
- "Deal" means deal {{deal.code}} ({{deal.title}}) recorded on the Eduwit creator portal, including every accepted version of its terms.
- "Deliverables" means the content listed in the Scope clause.
- "Portal" means the Eduwit creator portal through which briefs, approvals, leads and payments are managed.
- "Lead" means a prospective student attributed to the Creator under the portal's attribution rules.`,
  },
  {
    key: "scope",
    category: "scope",
    title: "Scope and deliverables",
    required: true,
    negotiable: false,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

The Creator will create and publish the following content{{#if campaign.name}} for the campaign "{{campaign.name}}"{{/if}}:

{{deliverables_table}}

Each deliverable follows the brief issued through the Portal. Specifications, formats and posting windows in the brief form part of this agreement.`,
  },
  {
    key: "timelines",
    category: "timelines",
    title: "Term and timelines",
    required: true,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

This agreement starts on {{deal.start_date}}{{#if deal.end_date}} and ends on {{deal.end_date}}{{else}} and continues until terminated under this agreement{{/if}}.

Due dates for concepts, drafts and publication are set in the brief. The Creator will tell Eduwit through the Portal as soon as a due date is at risk.`,
  },
  {
    key: "compensation",
    category: "compensation",
    title: "Compensation and payment terms",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

The Creator's compensation is exactly as recorded in the accepted terms of the Deal and set out below. The amounts are generated from the Deal and are not typed by hand.

{{#if deal.has_fixed}}
Fixed fees{{#if deal.fixed_fee_total}} (total {{deal.fixed_fee_total}}){{/if}}:
{{deal.milestone_table}}
{{/if}}
{{#if deal.has_commission}}
Commission:
{{deal.commission_table}}
Commission is earned on leads and enrolments attributed to the Creator under the Portal's attribution rules. Commission clawed back under these rules (for example on a cancelled or refunded enrolment within the stated window) is deducted from later payments.
{{/if}}
{{#if deal.has_recoupment}}
{{deal.recoupment_text}}
{{/if}}
{{#if deal.has_bonuses}}
Bonuses:
{{deal.bonus_table}}
{{/if}}
{{#if deal.has_fees}}
Additional fees:
{{deal.fee_table}}
{{/if}}

Amounts become payable on the due dates shown and are paid in the Portal's payout cycle to the bank account verified in the Creator's KYC{{#if payee.is_agency}} or to the payee named above{{/if}}. Statements for every payment are available in the Portal.`,
  },
  {
    key: "taxes",
    category: "taxes",
    title: "Taxes (TDS and GST)",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

Eduwit deducts tax at source (TDS) as required by the Income-tax Act, 1961, at the rates applicable to each kind of payment, and issues TDS certificates through the Portal. Where the Creator has not provided a valid PAN, the higher rate prescribed by law applies.

{{#if creator.gst_registered}}The Creator is registered for GST ({{creator.gstin}}). GST is payable in addition to the fees on receipt of a valid tax invoice from the Creator.{{else}}The Creator confirms that it is not required to be registered for GST. The Creator will tell Eduwit promptly if this changes.{{/if}}

Each party bears its own other taxes.`,
  },
  {
    key: "content_approval",
    category: "content_approval",
    title: "Content approval and revisions",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

The Creator submits concepts, scripts and drafts through the Portal before publication. Eduwit reviews them within a reasonable time and may request revisions up to the limit set in the brief.

Content may be published only after Eduwit's approval in the Portal. Approved content may not be changed materially without a new approval.`,
  },
  {
    key: "disclosure",
    category: "disclosure",
    title: "ASCI disclosure and advertising standards",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

Every piece of content made under this agreement is advertising. The Creator will clearly disclose the paid partnership as required by the Advertising Standards Council of India (ASCI) guidelines for influencer advertising and the Consumer Protection Act, 2019, using the disclosure labels required for each platform, placed so that they are prominent and not hidden among other text.

The Creator will comply with the ASCI Code and the platforms' branded-content rules.`,
  },
  {
    key: "claims",
    category: "claims",
    title: "Claims and accuracy",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

The Creator will make only the claims about programmes, universities, fees, placements and outcomes that Eduwit has approved in the brief. The Creator will not promise admission, scholarships, jobs, salaries or results, and will not compare programmes or institutions in a misleading way.

If Eduwit tells the Creator that a published claim is inaccurate, the Creator will correct or remove it within 24 hours.`,
  },
  {
    key: "usage_rights",
    category: "usage_rights",
    title: "Usage rights and intellectual property",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

The Creator owns the content it creates. The Creator grants Eduwit a non-exclusive licence to share, embed and refer to the published content on Eduwit's own channels for the term of this agreement.

{{#if deal.has_fees}}Any wider rights (paid amplification, whitelisting, use in Eduwit's advertising or for a longer period) are granted only as listed in the additional fees of the Compensation clause, for the platforms and duration stated there.{{/if}}

Eduwit's names, logos and materials remain Eduwit's property and may be used only for the deliverables.`,
  },
  {
    key: "exclusivity",
    category: "exclusivity",
    title: "Exclusivity and non-compete",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

For the period and category stated in the exclusivity fee of the Compensation clause, the Creator will not promote competing education services or platforms, including other edtech or admission-counselling businesses, on the platforms stated.

Content already published before this agreement is not affected.`,
  },
  {
    key: "confidentiality",
    category: "confidentiality",
    title: "Confidentiality",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

Each party keeps confidential the other's non-public information received under this agreement, including commercial terms, briefs before publication and Portal data, and uses it only for this agreement. This obligation survives for two years after the agreement ends, except where disclosure is required by law.`,
  },
  {
    key: "data_protection",
    category: "data_protection",
    title: "Data protection",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

Each party will comply with the Digital Personal Data Protection Act, 2023 and related rules. The Creator will not collect students' personal data directly (for example phone numbers or email addresses in messages or comments) and will direct prospective students to Eduwit's links, codes and channels.

Lead information shown in the Portal is provided only to measure the Creator's performance; contact details are masked and must not be sought, copied or shared.

Eduwit processes the Creator's personal data (including KYC details) as described in its privacy notice for creators.`,
  },
  {
    key: "conduct",
    category: "conduct",
    title: "Conduct and reputation",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

During the term, the Creator will not publish content that is unlawful, defamatory, hateful, obscene or likely to bring Eduwit or its partner institutions into disrepute. If the Creator becomes involved in a public controversy that may affect Eduwit, the parties will discuss in good faith, and Eduwit may pause or end the deal under the Termination clause.`,
  },
  {
    key: "penalties",
    category: "penalties",
    title: "Penalties and clawback",
    required: false,
    negotiable: false,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

The following deductions may apply:

{{deal.penalty_table}}

Every deduction is proposed by the Portal and applied only after an Eduwit manager approves it; the Creator is told the reason. Total deductions under this agreement are capped as set in Eduwit's compensation settings at the time the deduction is approved.`,
  },
  {
    key: "termination",
    category: "termination",
    title: "Termination",
    required: true,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

Either party may end this agreement by giving 15 days' written notice through the Portal. Either party may end it immediately if the other materially breaches it and does not remedy the breach within 7 days of notice.

On termination, amounts earned up to the termination date remain payable, subject to the Penalties clause, and commission on leads attributed before termination is paid as it is confirmed. The Disclosure, Claims, Confidentiality and Data protection clauses survive termination.`,
  },
  {
    key: "force_majeure",
    category: "force_majeure",
    title: "Force majeure",
    required: false,
    negotiable: false,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

Neither party is liable for delay or failure caused by events beyond its reasonable control, including natural disasters, epidemics, government action or platform outages, provided it informs the other promptly and resumes performance as soon as reasonably possible. Due dates move by the length of the delay.`,
  },
  {
    key: "indemnity",
    category: "indemnity",
    title: "Indemnity and limitation of liability",
    required: false,
    negotiable: true,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

Each party will indemnify the other against third-party claims arising from its breach of this agreement or its violation of law. Except for breaches of the Confidentiality and Data protection clauses and amounts payable under the Compensation clause, neither party is liable for indirect or consequential loss, and each party's total liability is limited to the fees paid or payable under this agreement in the preceding twelve months.`,
  },
  {
    key: "disputes",
    category: "disputes",
    title: "Dispute resolution and jurisdiction",
    required: true,
    negotiable: false,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

The parties will first try to resolve any dispute through good-faith discussion for 30 days. Unresolved disputes are referred to arbitration by a sole arbitrator under the Arbitration and Conciliation Act, 1996, seated in Ghaziabad, Uttar Pradesh, in English. This agreement is governed by the laws of India, and subject to arbitration the courts at Ghaziabad have exclusive jurisdiction.`,
  },
  {
    key: "notices",
    category: "notices",
    title: "Notices",
    required: false,
    negotiable: false,
    locked: false,
    deal_types: [],
    body: `${DRAFT_MARKER}

Notices under this agreement are given through the Portal or by email: to Eduwit at {{eduwit.support_email}}, and to the Creator at {{creator.email}}. A notice is received when it is shown in the Portal or one business day after the email is sent.`,
  },
  {
    key: "entire_agreement",
    category: "entire_agreement",
    title: "Entire agreement and signatures",
    required: true,
    negotiable: false,
    locked: true,
    deal_types: [],
    body: `${DRAFT_MARKER}

This agreement, the accepted terms of the Deal and the briefs issued under it form the entire agreement between the parties on its subject. {{#if contract.is_amendment}}This agreement amends contract {{contract.parent_number}}; the rest of that contract continues to apply.{{/if}} Changes are valid only as a new version of this agreement signed through the Portal.

The parties agree to sign electronically. Each signature is verified with a one-time code and recorded with the document's SHA-256 hash, which is printed on the signature certificate.`,
  },
];

export const DEFAULT_TEMPLATE = {
  key: "standard_creator_agreement",
  name: "Standard creator agreement",
  description: "Adapts to every deal type through conditional clauses. All clauses are drafts until legally reviewed.",
  title: "Creator Agreement {{contract.number}}",
  header: `${DRAFT_MARKER}

Contract {{contract.number}} dated {{contract.date}}, for deal {{deal.code}}.`,
  footer: `Signed electronically for {{eduwit.legal_name}} by {{eduwit.signatory_name}}, {{eduwit.signatory_designation}}, and by {{creator.legal_name}}. The signature certificate follows.`,
  clauses: [
    { key: "parties", condition: null },
    { key: "scope", condition: null },
    { key: "timelines", condition: null },
    { key: "compensation", condition: null },
    { key: "taxes", condition: null },
    { key: "content_approval", condition: null },
    { key: "disclosure", condition: null },
    { key: "claims", condition: null },
    { key: "usage_rights", condition: null },
    { key: "exclusivity", condition: "deal.has_exclusivity" },
    { key: "confidentiality", condition: null },
    { key: "data_protection", condition: null },
    { key: "conduct", condition: null },
    { key: "penalties", condition: "deal.has_penalties" },
    { key: "termination", condition: null },
    { key: "force_majeure", condition: null },
    { key: "indemnity", condition: null },
    { key: "disputes", condition: null },
    { key: "notices", condition: null },
    { key: "entire_agreement", condition: null },
  ],
} as const;
