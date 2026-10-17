// The lead pipeline's URL filters, shared by the filter bar, saved views and the loader. Pure.
export const LEAD_FILTER_KEYS = [
  "stage",
  "campaign",
  "deal",
  "deliverable",
  "link",
  "programme",
  "temperature",
  "city",
  "from",
  "to",
  "q",
] as const;
export type LeadFilterKey = (typeof LEAD_FILTER_KEYS)[number];
