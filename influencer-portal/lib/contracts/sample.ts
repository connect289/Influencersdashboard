// Sample deals for the template editor's preview, so staff can see how a template adapts to each deal type before
// any real contract uses it. Illustrative values only; they never reach a contract.
import { compConfig, dealModel, type CompConfig } from "@/lib/compensation/schema";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import type { TemplateContext } from "./template";
import { buildContext } from "./variables";

export const SAMPLE_KINDS = ["hybrid", "commission_only", "fixed_only", "full"] as const;
export type SampleKind = (typeof SAMPLE_KINDS)[number];

/** Fixed + commission with every optional part: bonus, penalty, exclusivity fee. Exercises every conditional. */
const FULL: CompConfig = compConfig.parse({
  ...SYSTEM_PRESETS.fixed_plus_commission.config,
  bonuses: [
    {
      id: "ten",
      label: "10 enrolments",
      conditions: { op: "and", items: [{ metric: "enrollments", comparator: "gte", value: 10 }] },
      window: { type: "deal" },
      amount: { type: "fixed", amount_paise: 5_000_00 },
    },
  ],
  penalties: [{ id: "disc", type: "disclosure", label: "Missing #ad disclosure", amount_paise: 2_000_00 }],
  fees: [
    {
      id: "excl",
      kind: "exclusivity",
      label: "Exclusivity (other edtechs)",
      amount_paise: 10_000_00,
      duration_days: 90,
    },
  ],
});

const CONFIGS: Record<SampleKind, CompConfig> = {
  hybrid: SYSTEM_PRESETS.fixed_plus_commission.config,
  commission_only: SYSTEM_PRESETS.commission_only.config,
  fixed_only: SYSTEM_PRESETS.fixed_only.config,
  full: FULL,
};

export function sampleContext(kind: SampleKind, today: string): TemplateContext {
  const config = CONFIGS[kind];
  return buildContext({
    creator: {
      legal_name: "Sample Creator",
      display_name: "Sample",
      handle: "sample.creator",
      city: "Pune",
      state: "Maharashtra",
      email: "creator@example.test",
      pan_masked: "XXXXXX123F",
      gstin: null,
    },
    payee: { name: "Sample Creator", is_agency: false },
    deal: {
      code: "DL-SAMPLE",
      title: "Sample deal",
      starts_on: today,
      ends_on: null,
      model: dealModel(config),
      config,
    },
    deliverables: [
      { platform: "instagram", format: "reel", count: 2 },
      { platform: "youtube", format: "youtube_video", count: 1 },
    ],
    campaign: { name: "Sample campaign" },
    eduwit: {
      legal_name: "Eduwit",
      address: "Registered office address",
      gstin: "GSTIN",
      pan: "PAN",
      support_email: "creators@example.test",
    },
    signatory: { name: "Authorised Signatory", designation: "Director" },
    contract: { number: "CT-SAMPLE", date: today, parent_number: null },
  });
}
