import { describe, expect, it } from "vitest";
import { recommend, rulesRecommender, type Recommender } from "./recommend";
import { scorecard, type ScorecardFacts } from "./score";

const W = { delivery: 0.25, content: 0.2, lead_quality: 0.25, economics: 0.2, compliance: 0.1 };
const facts: ScorecardFacts = {
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
  junk: 2,
  duplicates: 1,
  attributions: 41,
  enrolled: 4,
  cost_paise: 100000,
  revenue_paise: 150000,
  disclosure_misses: 0,
  claim_violations: 0,
  checked: 4,
};
const codes = (xs: { code: string }[]) => xs.map((x) => x.code);

describe("renewal recommendations", () => {
  it("high conversion suggests hybrid with a higher commission", () => {
    const r = recommend({
      latest: scorecard({ ...facts, enrolled: 4 }, W),
      leads: 40,
      deliverables_due: 4,
      tier: null,
    });
    expect(codes(r)).toContain("hybrid_higher_commission");
    expect(r[0]?.because).toEqual({ enrollment_rate: "10%", leads: 40 });
  });

  it("low conversion with strong reach suggests fixed only for awareness", () => {
    const s = scorecard({ ...facts, enrolled: 0, views: 100000, engagements: 5000 }, W);
    expect(codes(recommend({ latest: s, leads: 40, deliverables_due: 4, tier: null }))).toContain(
      "fixed_awareness_only",
    );
  });

  it("repeated delays require concept approval; low compliance and many revisions add safeguards", () => {
    const s = scorecard({ ...facts, on_time: 2, revisions: 12, disclosure_misses: 2 }, W);
    const r = codes(recommend({ latest: s, leads: 40, deliverables_due: 4, tier: null }));
    expect(r).toEqual(expect.arrayContaining(["require_concept_approval", "compliance_preapproval", "clearer_briefs"]));
  });

  it("strong economics suggests a longer renewal; tier uplift is mentioned", () => {
    const s = scorecard({ ...facts, revenue_paise: 300000 }, W);
    const tier = { id: "g", name: "Gold", rank: 3, rules: {}, benefits: { commission_uplift_pct: 10 } };
    const r = recommend({ latest: s, leads: 40, deliverables_due: 4, tier });
    expect(codes(r)).toEqual(expect.arrayContaining(["renew_longer_term", "tier_benefit_uplift"]));
  });

  it("small samples do not trigger lead rules", () => {
    const s = scorecard({ ...facts, leads: 10, qualified: 5, attributions: 10, enrolled: 2 }, W);
    expect(codes(recommend({ latest: s, leads: 10, deliverables_due: 1, tier: null }))).not.toContain(
      "hybrid_higher_commission",
    );
  });

  it("says when there is not enough data", () => {
    expect(codes(rulesRecommender.recommend({ latest: null, leads: 0, deliverables_due: 0, tier: null }))).toEqual([
      "not_enough_data",
    ]);
  });

  it("merges other recommenders, first one wins per code", () => {
    const ai: Recommender = {
      id: "ai",
      recommend: () => [
        { code: "renew_longer_term", kind: "suggest", because: { note: "duplicate" }, source: "ai" },
        { code: "clearer_briefs", kind: "caution", because: { note: "ai" }, source: "ai" },
      ],
    };
    const s = scorecard({ ...facts, revenue_paise: 300000 }, W);
    const r = recommend({ latest: s, leads: 40, deliverables_due: 4, tier: null }, [rulesRecommender, ai]);
    expect(r.find((x) => x.code === "renew_longer_term")?.source).toBe("rules");
    expect(r.find((x) => x.code === "clearer_briefs")?.source).toBe("ai");
  });
});
