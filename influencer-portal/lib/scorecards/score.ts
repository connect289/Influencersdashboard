// Creator scorecards (spec 15): five sub-scores from 0 to 100 for a period, and a weighted composite. A sub-score is
// null when the period has too little data to judge it (no deliverables due, too few leads, no spend), and the
// composite uses the remaining weights, normalised, so a creator is never marked down for something that did not
// happen. Every formula and threshold is here and in docs/DECISIONS.md (D-172). Pure.
import { leadQuality, perUnit, ratio } from "@/lib/analytics/compute";

export const SCORE_PARTS = ["delivery", "content", "lead_quality", "economics", "compliance"] as const;
export type ScorePart = (typeof SCORE_PARTS)[number];
export type Weights = Record<ScorePart, number>;

export interface ScorecardFacts {
  /** Deliverables whose live date fell in the period, those live by that date, and cancellations. */
  due: number;
  on_time: number;
  cancelled: number;
  /** Change requests across the deliverables reviewed in the period, and how many were reviewed. */
  revisions: number;
  reviewed: number;
  /** Verified posts in the period with their reported views and engagements (likes, comments, shares, saves). */
  posts: number;
  views: number;
  engagements: number;
  /** The creator's own baseline: average views per post and engagement rate over the 180 days before the period. */
  baseline_views_per_post: number | null;
  baseline_engagement_rate: number | null;
  /** Credited leads and their outcomes in the period (stages are cumulative, METRICS.md). */
  leads: number;
  qualified: number;
  junk: number;
  duplicates: number;
  attributions: number;
  enrolled: number;
  /** Spend accrued and Eduwit revenue in the period (D-149, D-150). */
  cost_paise: number;
  revenue_paise: number;
  /** Disclosure checks failed and banned-claim matches upheld in the period, out of the deliverables checked. */
  disclosure_misses: number;
  claim_violations: number;
  checked: number;
}

export const SCORE_RULES = {
  /** Each average revision round above one costs this many points, up to the cap. */
  revisionPenalty: 10,
  revisionPenaltyCap: 30,
  /** Share of cancelled deliverables costs up to this many points. */
  cancellationPenalty: 50,
  /** Matching the creator's own baseline scores 50; double the baseline scores 100. */
  baselineScore: 50,
  /** Fewer credited leads than this and lead quality is not scored. */
  minLeads: 5,
  /** An enrolment rate at or above this gets full marks for that component. */
  targetEnrollmentRate: 0.05,
  /** Net ROI of 0 scores 50; each 1.0 of ROI adds or removes 25 points. */
  roiPoints: 25,
  /** Each compliance miss costs this many points. */
  compliancePenalty: 25,
} as const;

export type SubScores = Record<ScorePart, number | null>;

const clamp = (n: number) => Math.max(0, Math.min(100, n));
const round1 = (n: number) => Math.round(n * 10) / 10;

export function deliveryScore(f: ScorecardFacts): number | null {
  if (f.due + f.cancelled === 0) return null;
  const onTime = f.due > 0 ? f.on_time / f.due : 1;
  const avgRevisions = f.reviewed > 0 ? f.revisions / f.reviewed : 0;
  const revisionCost = Math.min(
    SCORE_RULES.revisionPenaltyCap,
    Math.max(0, avgRevisions - 1) * SCORE_RULES.revisionPenalty,
  );
  const cancelShare = f.cancelled / (f.due + f.cancelled);
  return round1(clamp(100 * onTime - revisionCost - SCORE_RULES.cancellationPenalty * cancelShare));
}

export function contentScore(f: ScorecardFacts): number | null {
  if (f.posts === 0) return null;
  const parts: number[] = [];
  if (f.baseline_views_per_post && f.baseline_views_per_post > 0)
    parts.push(f.views / f.posts / f.baseline_views_per_post);
  if (f.baseline_engagement_rate && f.baseline_engagement_rate > 0 && f.views > 0)
    parts.push(f.engagements / f.views / f.baseline_engagement_rate);
  if (parts.length === 0) return null;
  const avg = parts.reduce((a, b) => a + b, 0) / parts.length;
  return round1(clamp(SCORE_RULES.baselineScore * avg));
}

export function leadQualityScore(f: ScorecardFacts): number | null {
  if (f.leads < SCORE_RULES.minLeads) return null;
  const q = leadQuality(f);
  const enrolment = Math.min(1, (q.enrollment_rate ?? 0) / SCORE_RULES.targetEnrollmentRate);
  return round1(
    clamp(
      100 *
        (0.4 * (q.qualification_rate ?? 0) +
          0.2 * (1 - (q.junk_rate ?? 0)) +
          0.1 * (1 - (q.duplicate_rate ?? 0)) +
          0.3 * enrolment),
    ),
  );
}

export function economicsScore(f: ScorecardFacts): number | null {
  if (f.cost_paise <= 0) return f.revenue_paise > 0 ? 100 : null;
  const roi = (f.revenue_paise - f.cost_paise) / f.cost_paise;
  return round1(clamp(50 + SCORE_RULES.roiPoints * roi));
}

export function complianceScore(f: ScorecardFacts): number | null {
  const misses = f.disclosure_misses + f.claim_violations;
  if (f.checked === 0 && misses === 0) return null;
  return clamp(100 - SCORE_RULES.compliancePenalty * misses);
}

export function subScores(f: ScorecardFacts): SubScores {
  return {
    delivery: deliveryScore(f),
    content: contentScore(f),
    lead_quality: leadQualityScore(f),
    economics: economicsScore(f),
    compliance: complianceScore(f),
  };
}

/** Weighted mean of the sub-scores that exist, weights normalised over them; null when none exists. */
export function composite(s: SubScores, w: Weights): number | null {
  let sum = 0;
  let weight = 0;
  for (const p of SCORE_PARTS) {
    const v = s[p];
    if (v === null || w[p] <= 0) continue;
    sum += v * w[p];
    weight += w[p];
  }
  return weight > 0 ? round1(sum / weight) : null;
}

export interface Scorecard {
  scores: SubScores;
  composite: number | null;
  /** Figures shown beside the scores (rates as fractions). */
  figures: {
    on_time_rate: number | null;
    avg_revisions: number | null;
    views_vs_baseline: number | null;
    qualification_rate: number | null;
    junk_rate: number | null;
    duplicate_rate: number | null;
    enrollment_rate: number | null;
    cost_per_enrollment_paise: number | null;
    net_roi: number | null;
  };
}

export function scorecard(f: ScorecardFacts, w: Weights): Scorecard {
  const scores = subScores(f);
  const q = leadQuality(f);
  return {
    scores,
    composite: composite(scores, w),
    figures: {
      on_time_rate: ratio(f.on_time, f.due),
      avg_revisions: f.reviewed > 0 ? Math.round((f.revisions / f.reviewed) * 100) / 100 : null,
      views_vs_baseline:
        f.posts > 0 && f.baseline_views_per_post ? ratio(f.views / f.posts, f.baseline_views_per_post) : null,
      qualification_rate: q.qualification_rate,
      junk_rate: q.junk_rate,
      duplicate_rate: q.duplicate_rate,
      enrollment_rate: q.enrollment_rate,
      cost_per_enrollment_paise: perUnit(f.cost_paise, f.enrolled),
      net_roi: f.cost_paise > 0 ? ratio(f.revenue_paise - f.cost_paise, f.cost_paise) : null,
    },
  };
}
