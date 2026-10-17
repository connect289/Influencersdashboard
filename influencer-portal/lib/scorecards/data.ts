import "server-only";
// Loading scorecards and tier status for the screens, and running a scorecard with the configured weights
// (run-core.ts does the work).
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import { readSetting } from "@/lib/settings/read";
import { runScorecardWith, tierRow, type RunOptions } from "./run-core";

export { factsSchema, loadTiers, tierRow, type FactsRow, type TierRow } from "./run-core";

/** Computes and stores one scorecard with the configured weights; returns its id. */
export async function runScorecard(o: Omit<RunOptions, "weights">): Promise<string> {
  return runScorecardWith({ ...o, weights: await readSetting("scorecard.weights") });
}

const scoresSchema = z.record(z.string(), z.number().nullable()).catch({});
export const cardRow = z.object({
  id: z.uuid(),
  kind: z.enum(["monthly", "on_demand"]),
  period: z.string(),
  period_from: z.string(),
  period_to: z.string(),
  scores: scoresSchema,
  figures: z.record(z.string(), z.number().nullable()).catch({}),
  composite: z.coerce.number().nullable(),
  facts: z.record(z.string(), z.unknown()).catch({}),
  created_at: z.string(),
  tier_before: z.uuid().nullable(),
  tier_after: z.uuid().nullable(),
});
export type CardRow = z.infer<typeof cardRow>;

export const creatorScorecards = z.object({
  cards: z.array(cardRow),
  history: z.array(
    z.object({
      id: z.number(),
      from_tier: z.string().nullable(),
      to_tier: z.string().nullable(),
      reason: z.enum(["eligible", "below_rules", "manual", "manual_ended"]),
      note: z.string().nullable(),
      created_at: z.string(),
      by: z.string().nullable(),
    }),
  ),
  tier_id: z.uuid().nullable(),
  state: z
    .object({
      months_below: z.number(),
      manual_tier_id: z.uuid().nullable(),
      manual_until: z.string().nullable(),
      manual_reason: z.string().nullable(),
    })
    .nullable(),
});
export type CreatorScorecards = z.infer<typeof creatorScorecards>;

export async function loadCreatorScorecards(db: Db, creatorId: string): Promise<CreatorScorecards | null> {
  const { data, error } = await db.rpc("creator_scorecards", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return data ? creatorScorecards.parse(data) : null;
}

export const tierStatus = z.object({
  tier_id: z.uuid().nullable(),
  score: z.coerce.number().nullable(),
  compliance: z.coerce.number().nullable(),
  period: z.string().nullable(),
  enrollments_90d: z.number(),
  months_active: z.number(),
  manual_until: z.string().nullable(),
  tiers: z.array(tierRow),
});
export type TierStatus = z.infer<typeof tierStatus>;

export async function loadTierStatus(db: Db, creatorId: string): Promise<TierStatus | null> {
  const { data, error } = await db.rpc("tier_status", { p_creator: creatorId });
  if (error) return null;
  return tierStatus.parse(data);
}

export const programmeRow = z.object({
  creator_id: z.uuid(),
  display_name: z.string(),
  handle: z.string().nullable(),
  tier: z.string().nullable(),
  composite: z.coerce.number().nullable(),
  scores: scoresSchema,
  period: z.string(),
  changed: z.boolean(),
});
export type ProgrammeRow = z.infer<typeof programmeRow>;

export async function loadProgrammeScorecards(db: Db, period: string): Promise<ProgrammeRow[]> {
  const { data, error } = await db.rpc("programme_scorecards", { p_period: period });
  if (error) throw new Error(error.message);
  return z.array(programmeRow).parse(data ?? []);
}

export async function loadScorecardPeriods(db: Db): Promise<string[]> {
  const { data } = await db.rpc("scorecard_periods");
  return z
    .array(z.string())
    .catch([])
    .parse(data ?? []);
}
