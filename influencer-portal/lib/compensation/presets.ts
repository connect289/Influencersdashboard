// The three system presets (spec 6.2). Each is only a pre-filled component set: the deal builder copies it and every
// value stays editable. Amounts are starting points for the Influencer Manager, not commitments.
import { compConfig, type CompConfig, type CompConfigInput } from "./schema";

const commissionRule: CompConfigInput["commission"] = [
  {
    id: "commission",
    label: "Commission per enrolment",
    scope: { type: "all" },
    basis: { type: "pct_of_eduwit_commission", pct: 10, base: "net_of_gst" },
    confirmation: { type: "on_eduwit_commission_received" },
  },
];

const fixedFee: CompConfigInput["fixed"] = [
  {
    id: "fee",
    label: "Content fee",
    amount_paise: 15_000_00,
    basis: "lump_sum",
    milestones: [
      {
        id: "signing",
        label: "On signing",
        share: { type: "pct", pct: 50 },
        trigger: { type: "on_contract_signed" },
        payment_terms_days: 7,
      },
      {
        id: "live",
        label: "When the content is live",
        share: { type: "pct", pct: 50 },
        trigger: { type: "on_deliverable_live" },
        payment_terms_days: 7,
      },
    ],
  },
];

const RAW: Record<PresetKey, { name: string; description: string; config: CompConfigInput }> = {
  commission_only: {
    name: "Commission only",
    description: "No fixed fee. The creator earns a share of Eduwit's commission on every confirmed enrolment.",
    config: { schema_version: 1, commission: commissionRule },
  },
  fixed_plus_commission: {
    name: "Fixed + commission",
    description: "A content fee paid half on signing and half when the content is live, plus commission per enrolment.",
    config: { schema_version: 1, fixed: fixedFee, commission: commissionRule },
  },
  fixed_only: {
    name: "Fixed only",
    description: "A content fee paid half on signing and half when the content is live. No commission.",
    config: { schema_version: 1, fixed: fixedFee },
  },
};

export const PRESET_KEYS = ["commission_only", "fixed_plus_commission", "fixed_only"] as const;
export type PresetKey = (typeof PRESET_KEYS)[number];

export const SYSTEM_PRESETS: Record<PresetKey, { name: string; description: string; config: CompConfig }> =
  Object.fromEntries(PRESET_KEYS.map((k) => [k, { ...RAW[k], config: compConfig.parse(RAW[k].config) }])) as Record<
    PresetKey,
    { name: string; description: string; config: CompConfig }
  >;
