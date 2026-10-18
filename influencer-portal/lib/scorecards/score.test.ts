import { describe, expect, it } from "vitest";
import {
  complianceScore,
  composite,
  contentScore,
  deliveryScore,
  economicsScore,
  leadQualityScore,
  scorecard,
  type ScorecardFacts,
  type Weights,
} from "./score";

const W: Weights = { delivery: 0.25, content: 0.2, lead_quality: 0.25, economics: 0.2, compliance: 0.1 };
const base: ScorecardFacts = {
  due: 4,
  on_time: 4,
  cancelled: 0,
  revisions: 4,
  reviewed: 4,
  posts: 4,
  views: 40000,
  engagements: 2000,
  baseline_views_per_post: 10000,
  baseline_engagement_rate: 0.05,
  leads: 40,
  qualified: 20,
  junk: 4,
  duplicates: 2,
  attributions: 42,
  enrolled: 2,
  cost_paise: 100000,
  revenue_paise: 200000,
  disclosure_misses: 0,
  claim_violations: 0,
  checked: 4,
};

describe("scorecard parts", () => {
  it("delivery: on time, revisions above one round and cancellations", () => {
    expect(deliveryScore(base)).toBe(100);
    expect(deliveryScore({ ...base, on_time: 3 })).toBe(75);
    expect(deliveryScore({ ...base, revisions: 12 })).toBe(80); // 3 rounds on average: 2 above one × 10
    expect(deliveryScore({ ...base, revisions: 40 })).toBe(70); // capped at 30
    expect(deliveryScore({ ...base, due: 3, on_time: 3, cancelled: 1 })).toBe(87.5);
    expect(deliveryScore({ ...base, due: 0, on_time: 0, cancelled: 0 })).toBeNull();
    expect(deliveryScore({ ...base, due: 1, on_time: 0, revisions: 40, reviewed: 1 })).toBe(0);
  });

  it("content against the creator's own baseline", () => {
    expect(contentScore(base)).toBe(50); // views equal to baseline, engagement equal to baseline
    // Double the views and double the engagement rate.
    expect(contentScore({ ...base, views: 80000, engagements: 8000 })).toBe(100);
    expect(contentScore({ ...base, views: 120000, engagements: 18000 })).toBe(100); // clamped
    // Double the views at the usual engagement rate: views 2×, rate 1× → 1.5× → 75.
    expect(contentScore({ ...base, views: 80000, engagements: 4000 })).toBe(75);
    // Half the views at the usual engagement rate: 0.5× and 1× → 37.5.
    expect(contentScore({ ...base, views: 20000, engagements: 1000 })).toBe(37.5);
    expect(contentScore({ ...base, baseline_engagement_rate: null })).toBe(50);
    expect(contentScore({ ...base, baseline_views_per_post: null, baseline_engagement_rate: null })).toBeNull();
    expect(contentScore({ ...base, posts: 0 })).toBeNull();
  });

  it("lead quality needs enough leads", () => {
    // 0.4×0.5 + 0.2×0.9 + 0.1×(1−2/42) + 0.3×min(1, 0.05/0.05)
    expect(leadQualityScore(base)).toBe(77.5);
    expect(leadQualityScore({ ...base, leads: 4 })).toBeNull();
    expect(leadQualityScore({ ...base, enrolled: 1 })).toBe(62.5);
  });

  it("economics from net ROI", () => {
    expect(economicsScore(base)).toBe(75); // ROI 1.0
    expect(economicsScore({ ...base, revenue_paise: 100000 })).toBe(50);
    expect(economicsScore({ ...base, revenue_paise: 0 })).toBe(25);
    expect(economicsScore({ ...base, revenue_paise: 500000 })).toBe(100);
    expect(economicsScore({ ...base, cost_paise: 0 })).toBe(100);
    expect(economicsScore({ ...base, cost_paise: 0, revenue_paise: 0 })).toBeNull();
  });

  it("compliance loses 25 points a miss", () => {
    expect(complianceScore(base)).toBe(100);
    expect(complianceScore({ ...base, disclosure_misses: 1, claim_violations: 1 })).toBe(50);
    expect(complianceScore({ ...base, disclosure_misses: 5 })).toBe(0);
    expect(complianceScore({ ...base, checked: 0 })).toBeNull();
    expect(complianceScore({ ...base, checked: 0, claim_violations: 1 })).toBe(75);
  });
});

describe("composite", () => {
  it("is the weighted mean of the parts that exist", () => {
    expect(composite({ delivery: 100, content: 50, lead_quality: 77.5, economics: 75, compliance: 100 }, W)).toBe(79.4);
    // No content and no economics: the other weights are renormalised.
    expect(composite({ delivery: 100, content: null, lead_quality: 60, economics: null, compliance: 100 }, W)).toBe(
      83.3,
    );
    expect(
      composite({ delivery: null, content: null, lead_quality: null, economics: null, compliance: null }, W),
    ).toBeNull();
    expect(
      composite(
        { delivery: 80, content: 20, lead_quality: null, economics: null, compliance: null },
        { ...W, content: 0 },
      ),
    ).toBe(80);
  });

  it("returns the figures shown beside the scores", () => {
    const s = scorecard(base, W);
    expect(s.composite).toBe(79.4);
    expect(s.figures).toMatchObject({
      on_time_rate: 1,
      avg_revisions: 1,
      views_vs_baseline: 1,
      qualification_rate: 0.5,
      enrollment_rate: 0.05,
      cost_per_enrollment_paise: 50000,
      net_roi: 1,
    });
    expect(scorecard({ ...base, enrolled: 0, cost_paise: 0, revenue_paise: 0 }, W).figures).toMatchObject({
      cost_per_enrollment_paise: null,
      net_roi: null,
    });
  });
});
