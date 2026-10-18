// Creator tiers (spec 15): entry rules and benefits are configured per tier (Settings → Tiers and scorecard). After
// each monthly scorecard a creator moves up at once to the highest tier whose rules they meet, and moves down only after
// failing their tier's rules for `demote_after_months` months in a row, so one quiet month never costs a tier. A manual
// tier set by staff (with a reason) holds until its end date. Pure.
import { z } from "zod";

export const entryRules = z.strictObject({
  /** Composite score of the latest scorecard. */
  min_score: z.number().min(0).max(100).optional(),
  /** Enrolments credited in the last 90 days. */
  min_enrollments_90d: z.number().int().min(0).max(100000).optional(),
  /** Months since the creator was approved. */
  min_months_active: z.number().int().min(0).max(120).optional(),
  /** Compliance sub-score of the latest scorecard (no data counts as met). */
  min_compliance: z.number().min(0).max(100).optional(),
  /** Months in a row below this tier's rules before moving down (default 2). */
  demote_after_months: z.number().int().min(1).max(12).optional(),
});
export type EntryRules = z.infer<typeof entryRules>;

export const PAYOUT_CYCLES = ["weekly", "fortnightly", "monthly"] as const;

export const tierBenefits = z.strictObject({
  /** Suggested in the deal builder for new deals: commission rates and amounts raised by this percentage. */
  commission_uplift_pct: z.number().min(0).max(100).optional(),
  /** Days before everyone else that this tier sees new open campaigns. */
  early_access_days: z.number().int().min(0).max(60).optional(),
  /** Payout cycle Finance offers this tier (shown when preparing a batch). */
  payout_cycle: z.enum(PAYOUT_CYCLES).optional(),
  /** Anything else, shown to the creator. */
  note: z.string().trim().max(300).optional(),
});
export type TierBenefits = z.infer<typeof tierBenefits>;

export interface Tier {
  id: string;
  name: string;
  /** Higher rank = higher tier. */
  rank: number;
  rules: EntryRules;
  benefits: TierBenefits;
}

export interface TierFacts {
  score: number | null;
  compliance: number | null;
  enrollments_90d: number;
  months_active: number;
}

export interface RuleCheck {
  rule: keyof Omit<EntryRules, "demote_after_months">;
  required: number;
  actual: number | null;
  met: boolean;
}

/** Each rule of a tier against the facts (rules that are not set are not listed). */
export function checkRules(rules: EntryRules, f: TierFacts): RuleCheck[] {
  const out: RuleCheck[] = [];
  if (rules.min_score !== undefined)
    out.push({
      rule: "min_score",
      required: rules.min_score,
      actual: f.score,
      met: (f.score ?? -1) >= rules.min_score,
    });
  if (rules.min_enrollments_90d !== undefined)
    out.push({
      rule: "min_enrollments_90d",
      required: rules.min_enrollments_90d,
      actual: f.enrollments_90d,
      met: f.enrollments_90d >= rules.min_enrollments_90d,
    });
  if (rules.min_months_active !== undefined)
    out.push({
      rule: "min_months_active",
      required: rules.min_months_active,
      actual: f.months_active,
      met: f.months_active >= rules.min_months_active,
    });
  if (rules.min_compliance !== undefined)
    out.push({
      rule: "min_compliance",
      required: rules.min_compliance,
      actual: f.compliance,
      met: f.compliance === null || f.compliance >= rules.min_compliance,
    });
  return out;
}

export const meetsRules = (rules: EntryRules, f: TierFacts) => checkRules(rules, f).every((c) => c.met);

/** The highest tier whose rules the facts meet (a tier with no rules is met by everyone), or null. */
export function eligibleTier(tiers: readonly Tier[], f: TierFacts): Tier | null {
  return [...tiers].sort((a, b) => b.rank - a.rank).find((t) => meetsRules(t.rules, f)) ?? null;
}

export interface TierState {
  current: Tier | null;
  /** Consecutive months the creator has not met the current tier's rules (before this evaluation). */
  months_below: number;
  /** A tier staff set by hand, holding until `until` (ISO date), if any. */
  manual?: { tier: Tier | null; until: string } | null;
}

export interface TierDecision {
  tier: Tier | null;
  months_below: number;
  change: "up" | "down" | "none" | "manual";
  reason: "eligible" | "below_rules" | "held" | "manual" | "unchanged";
}

/** Next month's tier from the current state and this month's facts. `today` is an ISO date (IST). */
export function decideTier(tiers: readonly Tier[], state: TierState, f: TierFacts, today: string): TierDecision {
  if (state.manual && state.manual.until >= today)
    return { tier: state.manual.tier, months_below: 0, change: "manual", reason: "manual" };
  const eligible = eligibleTier(tiers, f);
  const cur = state.current;
  const rank = (t: Tier | null) => (t ? t.rank : Number.NEGATIVE_INFINITY);
  if (rank(eligible) > rank(cur)) return { tier: eligible, months_below: 0, change: "up", reason: "eligible" };
  if (!cur || meetsRules(cur.rules, f)) return { tier: cur, months_below: 0, change: "none", reason: "unchanged" };
  const below = state.months_below + 1;
  if (below >= (cur.rules.demote_after_months ?? 2))
    return { tier: eligible, months_below: 0, change: "down", reason: "below_rules" };
  return { tier: cur, months_below: below, change: "none", reason: "held" };
}

/** What the creator still needs for the next tier up, for their home page. */
export function nextTierProgress(
  tiers: readonly Tier[],
  current: Tier | null,
  f: TierFacts,
): { tier: Tier; checks: RuleCheck[] } | null {
  const next = [...tiers]
    .filter((t) => t.rank > (current?.rank ?? Number.NEGATIVE_INFINITY))
    .sort((a, b) => a.rank - b.rank)[0];
  return next ? { tier: next, checks: checkRules(next.rules, f) } : null;
}
