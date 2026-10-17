import { describe, expect, it } from "vitest";
import {
  checkRules,
  decideTier,
  eligibleTier,
  entryRules,
  nextTierProgress,
  tierBenefits,
  type Tier,
  type TierFacts,
} from "./tiers";

const bronze: Tier = { id: "b", name: "Bronze", rank: 1, rules: {}, benefits: {} };
const silver: Tier = {
  id: "s",
  name: "Silver",
  rank: 2,
  rules: { min_score: 60, min_months_active: 3 },
  benefits: { early_access_days: 2 },
};
const gold: Tier = {
  id: "g",
  name: "Gold",
  rank: 3,
  rules: { min_score: 75, min_enrollments_90d: 10, min_compliance: 80, demote_after_months: 3 },
  benefits: { commission_uplift_pct: 10, payout_cycle: "weekly" },
};
const TIERS = [gold, bronze, silver];
const strong: TierFacts = { score: 82, compliance: 90, enrollments_90d: 12, months_active: 8 };

describe("tier rules", () => {
  it("validates rules and benefits", () => {
    expect(entryRules.safeParse({ min_score: 101 }).success).toBe(false);
    expect(entryRules.safeParse({ unknown: 1 }).success).toBe(false);
    expect(tierBenefits.safeParse({ payout_cycle: "daily" }).success).toBe(false);
    expect(tierBenefits.parse({ commission_uplift_pct: 5 })).toEqual({ commission_uplift_pct: 5 });
  });

  it("checks each rule that is set", () => {
    expect(checkRules(gold.rules, { ...strong, enrollments_90d: 4 })).toEqual([
      { rule: "min_score", required: 75, actual: 82, met: true },
      { rule: "min_enrollments_90d", required: 10, actual: 4, met: false },
      { rule: "min_compliance", required: 80, actual: 90, met: true },
    ]);
    // No compliance data yet counts as met; no score does not.
    expect(checkRules(gold.rules, { ...strong, compliance: null }).every((c) => c.met)).toBe(true);
    expect(checkRules(silver.rules, { ...strong, score: null })[0]?.met).toBe(false);
  });

  it("picks the highest tier met", () => {
    expect(eligibleTier(TIERS, strong)?.name).toBe("Gold");
    expect(eligibleTier(TIERS, { ...strong, enrollments_90d: 2 })?.name).toBe("Silver");
    expect(eligibleTier(TIERS, { ...strong, months_active: 1, enrollments_90d: 0 })?.name).toBe("Bronze");
    expect(
      eligibleTier([silver, gold], { score: 10, compliance: null, enrollments_90d: 0, months_active: 0 }),
    ).toBeNull();
  });
});

describe("tier decisions", () => {
  const today = "2026-11-01";
  it("moves up at once", () => {
    expect(decideTier(TIERS, { current: silver, months_below: 0 }, strong, today)).toEqual({
      tier: gold,
      months_below: 0,
      change: "up",
      reason: "eligible",
    });
  });

  it("holds for a month below the rules, then moves down", () => {
    const weak: TierFacts = { score: 65, compliance: 90, enrollments_90d: 3, months_active: 9 };
    const first = decideTier(TIERS, { current: gold, months_below: 0 }, weak, today);
    expect(first).toMatchObject({ tier: gold, months_below: 1, change: "none", reason: "held" });
    const second = decideTier(TIERS, { current: gold, months_below: 1 }, weak, today);
    expect(second.change).toBe("none"); // gold waits 3 months
    const third = decideTier(TIERS, { current: gold, months_below: 2 }, weak, today);
    expect(third).toMatchObject({ tier: silver, change: "down", reason: "below_rules" });
    // Silver demotes after the default 2 months.
    const low: TierFacts = { score: 40, compliance: 90, enrollments_90d: 0, months_active: 9 };
    expect(decideTier(TIERS, { current: silver, months_below: 1 }, low, today)).toMatchObject({
      tier: bronze,
      change: "down",
    });
  });

  it("a month meeting the rules again resets the count", () => {
    expect(decideTier(TIERS, { current: gold, months_below: 2 }, strong, today)).toMatchObject({
      tier: gold,
      months_below: 0,
      change: "none",
    });
  });

  it("a manual tier holds until its end date", () => {
    const manual = { tier: silver, until: "2026-12-31" };
    expect(decideTier(TIERS, { current: silver, months_below: 0, manual }, strong, today)).toMatchObject({
      tier: silver,
      change: "manual",
    });
    expect(decideTier(TIERS, { current: silver, months_below: 0, manual }, strong, "2027-01-01").tier).toBe(gold);
  });

  it("shows what the next tier needs", () => {
    const p = nextTierProgress(TIERS, silver, { ...strong, enrollments_90d: 4 });
    expect(p?.tier.name).toBe("Gold");
    expect(p?.checks.find((c) => !c.met)?.rule).toBe("min_enrollments_90d");
    expect(nextTierProgress(TIERS, gold, strong)).toBeNull();
    expect(nextTierProgress(TIERS, null, strong)?.tier.name).toBe("Bronze");
  });
});
