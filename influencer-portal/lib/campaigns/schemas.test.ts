import { describe, expect, it } from "vitest";
import { applyInput, campaignInput, offerTerms, rupeesToPaise, STATUS_MOVES } from "./schemas";

const id = "7c9e6679-7425-40de-944b-e07fc1f90ae7";

describe("campaignInput", () => {
  it("accepts a minimal draft", () => {
    expect(campaignInput.safeParse({ name: "MBA push", objective: "leads" }).success).toBe(true);
  });
  it("checks date order", () => {
    const r = campaignInput.safeParse({
      name: "MBA push",
      objective: "leads",
      startsOn: "2026-11-10",
      endsOn: "2026-11-01",
    });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.message).toBe("end_before_start");
    expect(
      campaignInput.safeParse({ name: "MBA push", objective: "leads", applyBy: "2026-12-01", endsOn: "2026-11-30" })
        .success,
    ).toBe(false);
  });
  it("validates deliverables and eligibility", () => {
    expect(
      campaignInput.safeParse({
        name: "MBA push",
        objective: "leads",
        deliverables: [{ platform: "instagram", format: "reel", count: 2 }],
        eligibility: { min_followers: 10000, platforms: ["instagram"], niches: ["mba"] },
      }).success,
    ).toBe(true);
    expect(
      campaignInput.safeParse({
        name: "MBA push",
        objective: "leads",
        deliverables: [{ platform: "tiktok", format: "reel", count: 1 }],
      }).success,
    ).toBe(false);
  });
});

describe("offerTerms", () => {
  it("needs a fee for fixed and hybrid deals", () => {
    expect(offerTerms.safeParse({ deal_type: "fixed" }).success).toBe(false);
    expect(offerTerms.safeParse({ deal_type: "hybrid", fixed_fee_paise: 0 }).success).toBe(false);
    expect(offerTerms.safeParse({ deal_type: "fixed", fixed_fee_paise: 1500000 }).success).toBe(true);
    expect(offerTerms.safeParse({ deal_type: "commission", includes_commission: true }).success).toBe(true);
    expect(offerTerms.safeParse({ deal_type: "barter" }).success).toBe(true);
  });
  it("rejects fractional paise", () => {
    expect(offerTerms.safeParse({ deal_type: "fixed", fixed_fee_paise: 10.5 }).success).toBe(false);
    expect(rupeesToPaise(12000.555)).toBe(1200056);
  });
});

describe("applyInput", () => {
  it("requires https sample links", () => {
    const base = { campaignId: id, creatorId: id, terms: { deal_type: "barter" as const } };
    expect(applyInput.safeParse({ ...base, samples: ["https://instagram.com/p/1"] }).success).toBe(true);
    expect(applyInput.safeParse({ ...base, samples: ["http://instagram.com/p/1"] }).success).toBe(false);
  });
});

describe("status moves", () => {
  it("never allows going back to draft and ends at archived", () => {
    for (const moves of Object.values(STATUS_MOVES)) expect(moves).not.toContain("draft");
    expect(STATUS_MOVES.archived).toEqual([]);
  });
});
