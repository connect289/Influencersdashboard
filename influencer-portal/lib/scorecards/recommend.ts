// Recommendations at deal renewal (spec 15): rules over the creator's latest scorecards suggest how to shape the next
// deal. They are suggestions for staff, never applied automatically. Each recommender implements one interface, so an
// AI recommender can be added beside the rules later without changing the screens. Pure.
import type { Scorecard } from "./score";
import type { Tier } from "./tiers";

export type RecommendationCode =
  | "hybrid_higher_commission"
  | "fixed_awareness_only"
  | "require_concept_approval"
  | "compliance_preapproval"
  | "clearer_briefs"
  | "renew_longer_term"
  | "tier_benefit_uplift"
  | "not_enough_data";

export interface Recommendation {
  code: RecommendationCode;
  /** "suggest" changes the deal shape; "caution" adds a safeguard; "info" is context. */
  kind: "suggest" | "caution" | "info";
  /** The facts that triggered it, for the explanation shown with it. */
  because: Record<string, number | string>;
  /** Which recommender produced it ("rules" today). */
  source: string;
}

export interface RecommendationInput {
  latest: Scorecard | null;
  /** Lead counts behind the latest scorecard (rules need enough of them). */
  leads: number;
  deliverables_due: number;
  tier: Tier | null;
}

export interface Recommender {
  readonly id: string;
  recommend(input: RecommendationInput): Recommendation[];
}

export const RECOMMENDATION_RULES = {
  minLeads: 20,
  highEnrollmentRate: 0.08,
  lowEnrollmentRate: 0.01,
  highReachContent: 70,
  minDeliverables: 3,
  lowOnTimeRate: 0.7,
  lowCompliance: 60,
  manyRevisions: 2,
  strongEconomics: 75,
} as const;

const pct = (n: number) => `${Math.round(n * 1000) / 10}%`;

export const rulesRecommender: Recommender = {
  id: "rules",
  recommend({ latest, leads, deliverables_due, tier }) {
    const R = RECOMMENDATION_RULES;
    const out: Recommendation[] = [];
    const add = (code: RecommendationCode, kind: Recommendation["kind"], because: Recommendation["because"]) =>
      out.push({ code, kind, because, source: "rules" });
    if (!latest || latest.composite === null) {
      add("not_enough_data", "info", {});
      return out;
    }
    const f = latest.figures;
    const s = latest.scores;
    if (leads >= R.minLeads && f.enrollment_rate !== null && f.enrollment_rate >= R.highEnrollmentRate)
      add("hybrid_higher_commission", "suggest", { enrollment_rate: pct(f.enrollment_rate), leads });
    if (
      leads >= R.minLeads &&
      f.enrollment_rate !== null &&
      f.enrollment_rate < R.lowEnrollmentRate &&
      (s.content ?? 0) >= R.highReachContent
    )
      add("fixed_awareness_only", "suggest", { enrollment_rate: pct(f.enrollment_rate), content: s.content ?? 0 });
    if (deliverables_due >= R.minDeliverables && f.on_time_rate !== null && f.on_time_rate < R.lowOnTimeRate)
      add("require_concept_approval", "caution", { on_time_rate: pct(f.on_time_rate), due: deliverables_due });
    if (s.compliance !== null && s.compliance < R.lowCompliance)
      add("compliance_preapproval", "caution", { compliance: s.compliance });
    if (f.avg_revisions !== null && f.avg_revisions > R.manyRevisions)
      add("clearer_briefs", "caution", { avg_revisions: f.avg_revisions });
    if (s.economics !== null && s.economics >= R.strongEconomics)
      add("renew_longer_term", "suggest", { economics: s.economics });
    if (tier?.benefits.commission_uplift_pct)
      add("tier_benefit_uplift", "info", { tier: tier.name, uplift_pct: tier.benefits.commission_uplift_pct });
    return out;
  },
};

/** Runs every recommender and merges the results (one per code, the first recommender wins). */
export function recommend(input: RecommendationInput, recommenders: readonly Recommender[] = [rulesRecommender]) {
  const seen = new Set<RecommendationCode>();
  return recommenders
    .flatMap((r) => r.recommend(input))
    .filter((x) => (seen.has(x.code) ? false : (seen.add(x.code), true)));
}
