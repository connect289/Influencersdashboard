import { describe, expect, it } from "vitest";
import {
  isSegment, maturityProgress, PartnerWeightSchema, PerformanceSchema, PolicySchema, pct, scoringSummary, SegmentPolicySchema,
  segmentPolicyPayload, splitText, untilText,
} from "./segments";

const base = { segment: "mba|PG|Online", pin: "auto", pin_until: "", exploration_share: "", share_cap: "", reason: "test" };

describe("segments", () => {
  it("recognises segment keys", () => {
    expect(isSegment("mba|PG|Online")).toBe(true);
    expect(isSegment("mba|*|*")).toBe(true);
    expect(isSegment("mba|PG")).toBe(false);
    expect(isSegment("a|b|c|d")).toBe(false);
    expect(isSegment(undefined)).toBe(false);
  });

  it("formats percentages", () => {
    expect(pct(0.1447)).toBe("14.5%");
    expect(pct(0.2, 0)).toBe("20%");
    expect(pct(null)).toBe("—");
  });

  it("measures progress toward performance mode", () => {
    expect(maturityProgress([{ matured: 30 }, { matured: 31 }], 30)).toMatchObject({ ready: 2, share: 1 });
    expect(maturityProgress([{ matured: 30 }], 30)).toMatchObject({ ready: 1, share: 0.5 });
    expect(maturityProgress([{ matured: 15 }, { matured: 0 }, { matured: 3 }], 30).text).toContain("best: 15, next: 3");
  });

  it("describes when a pin ends", () => {
    const now = new Date("2026-10-07T10:00:00Z");
    expect(untilText(null, now)).toBeNull();
    expect(untilText("2026-10-10T10:00:00Z", now)).toBe("ends in 3 days");
    expect(untilText("2026-10-07T13:00:00Z", now)).toBe("ends in 3 h");
    expect(untilText("2026-10-01T00:00:00Z", now)).toBe("expired");
  });

  it("summarises a decision's scoring", () => {
    expect(scoringSummary({ scoring_mode: null, mode: "commission_first", selection_probability: 1 })).toBeNull();
    expect(scoringSummary({ scoring_mode: "performance", mode: "performance", selection_probability: 0.62, mc_draws: 200, holdout: true }))
      .toBe("Performance · holdout lead: the Admin's settings only, no AI changes · chosen in 62% of 201 seeded draws");
    expect(scoringSummary({ scoring_mode: "commission_first", mode: "commission_first", selection_probability: 1, pinned: true }))
      .toBe("Commission first · pinned by the Admin");
  });

  it("parses the segment policy form", () => {
    const auto = SegmentPolicySchema.parse(base);
    expect(segmentPolicyPayload(auto)).toEqual({ pin: null, exploration_share: null, share_cap: null, killed: false });
    const soon = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
    const pinned = SegmentPolicySchema.parse({ ...base, pin: "performance", pin_until: soon, exploration_share: "10", share_cap: "70", killed: "on" });
    expect(segmentPolicyPayload(pinned)).toEqual({ pin: { mode: "performance", until: `${soon}T23:59:59+05:30` }, exploration_share: 0.1, share_cap: 0.7, killed: true });
    expect(SegmentPolicySchema.safeParse({ ...base, pin: "performance", pin_until: "2099-01-31" }).success).toBe(false);
    expect(SegmentPolicySchema.safeParse({ ...base, share_cap: "40" }).success).toBe(false);
    expect(SegmentPolicySchema.safeParse({ ...base, exploration_share: "60" }).success).toBe(false);
    expect(SegmentPolicySchema.safeParse({ ...base, pin: "performance", pin_until: "2020-01-01" }).success).toBe(false);
    expect(SegmentPolicySchema.safeParse({ ...base, segment: "nope" }).success).toBe(false);
    expect(SegmentPolicySchema.safeParse({ ...base, pin_until: undefined }).success).toBe(true);
  });

  it("parses partner weights", () => {
    expect(PartnerWeightSchema.parse({ partner_id: "4", weight: "105", days: "7", reason: "new team" })).toEqual({ partner_id: 4, weight: 1.05, days: 7, reason: "new team" });
    expect(PartnerWeightSchema.parse({ partner_id: "4", weight: "", days: "7", reason: "remove" }).weight).toBeNull();
    expect(PartnerWeightSchema.safeParse({ partner_id: "4", weight: "120", days: "7", reason: "x y" }).success).toBe(false);
    expect(PartnerWeightSchema.safeParse({ partner_id: "4", weight: "100", days: "20", reason: "x y" }).success).toBe(false);
  });

  it("parses the policy and performance settings", () => {
    expect(PolicySchema.parse({ holdout_share: "10", mc_draws: "200", leading_weight: "50", leading_min_days: "3", reason: "new policy" }))
      .toEqual({ holdout_share: 0.1, mc_draws: 200, leading_weight: 0.5, leading_min_days: 3, reason: "new policy" });
    expect(PolicySchema.safeParse({ holdout_share: "60", mc_draws: "200", leading_weight: "50", leading_min_days: "3", reason: "new policy" }).success).toBe(false);
    const perf = PerformanceSchema.parse({ maturity_days: "60", half_life_days: "30", prior_weight: "20", default_p_enroll: "5", min_matured_leads: "30",
      speed_factor: "on", reliability_factor: undefined, kill_switch: undefined, fixed_split: "12: 60, 14: 40" });
    expect(perf).toMatchObject({ default_p_enroll: 0.05, speed_factor: true, reliability_factor: false, kill_switch: false, fixed_split: { "12": 60, "14": 40 } });
    expect(PerformanceSchema.safeParse({ maturity_days: "5", half_life_days: "30", prior_weight: "20", default_p_enroll: "5", min_matured_leads: "30", fixed_split: "" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ maturity_days: "60", half_life_days: "30", prior_weight: "20", default_p_enroll: "5", min_matured_leads: "30", fixed_split: "twelve: 60" }).success).toBe(false);
    expect(splitText({ "12": 60, "14": 40 })).toBe("12: 60, 14: 40");
    expect(splitText(undefined)).toBe("");
  });
});
