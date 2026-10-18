// Inputs for the tier editor, manual tiers and on-demand scorecards (Settings → Tiers, creator 360).
import { z } from "zod";
import { entryRules, tierBenefits } from "./tiers";

export const tierInput = z.object({
  id: z.uuid().optional(),
  name: z.string().trim().min(2).max(40),
  rank: z.number().int().min(1).max(20),
  rules: entryRules,
  benefits: tierBenefits,
  active: z.boolean().default(true),
});
export type TierInput = z.input<typeof tierInput>;

export const manualTierInput = z.object({
  creatorId: z.uuid(),
  tierId: z.uuid().nullable(),
  until: z.iso.date(),
  reason: z.string().trim().min(3).max(500),
});
export type ManualTierInput = z.infer<typeof manualTierInput>;

export const INSIGHT_DB_ERRORS: readonly (readonly [RegExp, string])[] = [
  [/another active tier has this rank/, "rankTaken"],
  [/invalid tier/, "invalidTier"],
  [/choose an end date in the future/, "pastDate"],
  [/say why/, "reason"],
];
