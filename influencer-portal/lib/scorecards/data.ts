import "server-only";
// Loading and running scorecards: facts from inf.scorecard_facts, scores and tier decisions from the pure modules,
// results stored with inf.scorecard_save. The monthly job runs as the service role (and applies tier changes);
// staff run on-demand cards with their own session (never changing a tier).
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import { readSetting } from "@/lib/settings/read";
import { periodRange } from "./period";
import { scorecard, SCORE_PARTS, type ScorecardFacts } from "./score";
import { decideTier, entryRules, tierBenefits, type Tier } from "./tiers";

const n = z.coerce.number().catch(0);
const nn = z.coerce.number().nullable().catch(null);
export const factsSchema = z.object({
  due: n,
  on_time: n,
  cancelled: n,
  revisions: n,
  reviewed: n,
  posts: n,
  views: n,
  engagements: n,
  baseline_views_per_post: nn,
  baseline_engagement_rate: nn,
  leads: n,
  qualified: n,
  junk: n,
  duplicates: n,
  attributions: n,
  enrolled: n,
  cost_paise: n,
  revenue_paise: n,
  disclosure_misses: n,
  claim_violations: n,
  checked: n,
  enrollments_90d: n,
  months_active: n,
  tier_id: z.uuid().nullable().catch(null),
  months_below: n,
  manual_tier_id: z.uuid().nullable().catch(null),
  manual_until: z.string().nullable().catch(null),
});
export type FactsRow = z.infer<typeof factsSchema>;

export const tierRow = z.object({
  id: z.uuid(),
  name: z.string(),
  rank: z.number(),
  rules: entryRules.catch({}),
  benefits: tierBenefits.catch({}),
  active: z.boolean().optional(),
  creators: z.number().optional(),
});
export type TierRow = z.infer<typeof tierRow>;

export async function loadTiers(db: Db): Promise<TierRow[]> {
  const { data, error } = await db.rpc("tiers_list");
  if (error) throw new Error(error.message);
  return z.array(tierRow).parse(data ?? []);
}

export interface RunOptions {
  db: Db;
  creatorId: string;
  period: string;
  kind: "monthly" | "on_demand";
  /** The last day counted (on-demand cards stop at today); defaults to the period's end. */
  to?: string;
  today: string;
}

/** Computes and stores one scorecard; returns its id. */
export async function runScorecard(o: RunOptions): Promise<string> {
  const { from, to: end } = periodRange(o.period);
  const to = o.to && o.to < end ? o.to : end;
  const [factsRes, weights, tiers] = await Promise.all([
    o.db.rpc("scorecard_facts", { p_creator: o.creatorId, p_from: from, p_to: to }),
    readSetting("scorecard.weights"),
    loadTiers(o.db),
  ]);
  if (factsRes.error) throw new Error(factsRes.error.message);
  const f = factsSchema.parse(factsRes.data);
  const facts: ScorecardFacts = f;
  const card = scorecard(facts, weights);
  const active: Tier[] = tiers.filter((t) => t.active !== false);
  const current = active.find((t) => t.id === f.tier_id) ?? null;
  const manualTier = active.find((t) => t.id === f.manual_tier_id) ?? null;
  const decision = decideTier(
    active,
    {
      current,
      months_below: f.months_below,
      manual: f.manual_until ? { tier: manualTier, until: f.manual_until } : null,
    },
    {
      score: card.composite,
      compliance: card.scores.compliance,
      enrollments_90d: f.enrollments_90d,
      months_active: f.months_active,
    },
    o.today,
  );
  const scoreFacts = Object.fromEntries(
    Object.entries(f).filter(([k]) => !["tier_id", "manual_tier_id", "manual_until"].includes(k)),
  );
  const { data, error } = await o.db.rpc("scorecard_save", {
    p: {
      creator_id: o.creatorId,
      kind: o.kind,
      period: o.period,
      period_from: from,
      period_to: to,
      facts: scoreFacts,
      scores: Object.fromEntries(SCORE_PARTS.map((p) => [p, card.scores[p]])),
      figures: card.figures,
      composite: card.composite,
      weights,
      tier_after: decision.tier?.id ?? "",
      change: decision.change === "manual" ? "none" : decision.change,
      months_below: decision.months_below,
    },
  });
  if (error) throw new Error(error.message);
  return z.uuid().parse(data);
}
