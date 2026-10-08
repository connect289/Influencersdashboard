import { z } from "zod";

/** Staged scoring (Addendum 3, PART 4): segment stages A/B/C, the engine's parameters, the per-segment statistics the
 *  Routing screen's Segments tab shows, and the effort / SLA settings forms. Shared by the Segments tab, the decision
 *  view, the engine form and the tests.
 *
 *  Pins, share caps, per-segment exploration, partner weights and the kill switch were retired by Addendum 3 (D24): the
 *  Admin's only override tool is a routing rule. The rulebook numbers live in engine.a3_fixed and are read-only here. */

export type Stage = "A" | "B" | "C";

/** scoring_mode as stored on decisions: commission_first (Stage A), performance (Stage B or C); kill_switch only on legacy rows. */
export type ScoringMode = "commission_first" | "performance" | "kill_switch";

export const SCORING_LABEL: Record<ScoringMode, string> = {
  commission_first: "Commission first",
  performance: "Performance",
  kill_switch: "Kill switch (fixed split, retired)",
};

export const SCORING_HINT: Record<ScoringMode, string> = {
  commission_first: "Stage A: the highest commission per enrolment wins; the exploration lane sends 20% of leads to an under-tested partner while it has fewer than 30 leads.",
  performance: "Stage B or C: commission × sales-effort factor × SLA factor, and from Stage C commission per lead (× P(enrol) × (1 − refunds)). Highest score wins.",
  kill_switch: "Retired by Addendum 3. Older decisions split leads between partners in fixed shares, with no scoring.",
};

/** Stage formulas, for summaries ("Stage B: commission × effort × SLA"). */
export const STAGE_FORMULA: Record<Stage, string> = {
  A: "commission",
  B: "commission × effort × SLA",
  C: "commission per lead",
};

export type EffortMetricKey = "first_call" | "attempts_72h" | "connect_rate" | "followup" | "acts_per_open" | "stale_share";
export const EFFORT_METRICS: readonly EffortMetricKey[] = ["first_call", "attempts_72h", "connect_rate", "followup", "acts_per_open", "stale_share"];
export const EFFORT_METRIC_LABEL: Record<EffortMetricKey, string> = {
  first_call: "Minutes to the first call",
  attempts_72h: "Calls within 72 h",
  connect_rate: "Connected ÷ calls",
  followup: "Follow-up dates worked",
  acts_per_open: "Activities per open lead per week",
  stale_share: "Open leads quiet for 7 days",
};
/** Lower is better for these two (the engine inverts them). */
export const EFFORT_LOWER_IS_BETTER: readonly EffortMetricKey[] = ["first_call", "stale_share"];
export type EffortWeights = Record<EffortMetricKey, number>;

export type SlaKey = "first_attempt" | "status_update" | "enrollment_proof";
export const SLA_KEYS: readonly SlaKey[] = ["first_attempt", "status_update", "enrollment_proof"];
export const SLA_LABEL: Record<SlaKey, string> = { first_attempt: "First attempt", status_update: "Status update", enrollment_proof: "Enrolment proof" };
export type SlaWeights = Record<SlaKey, number>;

/** The rulebook ranges the Admin's bounds, step and weights must stay inside (engine.a3_fixed; owner's correction 1). */
export const EFFORT_RANGE = [0.85, 1.15] as const;
export const SLA_RANGE = [0.8, 1] as const;
export const SLA_STEP_RANGE = [0.01, 0.2] as const;
export const WEIGHT_RANGE = [0, 5] as const;

/** The fixed stage gates (engine.a3_fixed; D24, D26). */
export const STAGE_GATES = { stage_b_min_leads: 20, stage_b_min_age_days: 7, stage_c_min_matured: 30, stage_c_min_partners: 2, matured_days: 60, learn_leads: 30, exploration_share: 0.2 } as const;

/** One effort metric as b2b.effort_detail_rows logs it (values can be JSON null: a metric unknown for this partner). */
export type EffortMetricDetail = { v: number | null; median: number | null; n: number; r: number | null; w: number; basis: "segment" | "partner" | "thin" | "no_activity" };
export type EffortDetail = {
  metrics: Partial<Record<EffortMetricKey, EffortMetricDetail>>;
  basis: "segment" | "partner" | "mixed" | "none";
  has_activity: boolean;
  capped_no_activity: boolean;
  min_sample: number;
  since: string;
};

/** b2b.engine_params(p_base): the parameters in force (Admin values with p_base true; AI overlay applied with false). */
export type EngineParams = {
  matured_days: number; maturity_days: number; half_life_days: number; prior_weight: number; default_p_enroll: number; min_matured_leads: number;
  leading_weight: number; leading_min_days: number; speed_on: boolean; reliability_on: boolean;
  effort: { enabled: boolean; lo: number; hi: number; weights: EffortWeights; min_sample: number; window_days: number; source: "admin" | "ai" };
  sla: { enabled: boolean; floor: number; ceiling: number; step: number; weights: SlaWeights; window_days: number; source: "admin" | "ai" };
  stages: { stage_b_min_leads: number; stage_b_min_age_days: number; stage_c_min_matured: number; stage_c_min_partners: number; matured_days: number;
            learn_leads: number; exploration_share: number; exact_segment_min_leads: number; tier_projected_min_matured: number };
  variant: "base" | "ai";
  ai_stats_wanted?: boolean;
};

/** engine_policy: only holdout_share is editable (engine_policy_save); ai holds the optimiser's levers. */
export type EnginePolicy = {
  holdout_share?: number; leading_min_days?: number;
  ai?: { half_life_days?: number; prior_weight?: number; effort_weights?: Partial<EffortWeights>; effort_bounds?: [number, number]; sla_floor?: number } & Record<string, unknown>;
};

/** segment_mode / routing_segments.mode: the stage non-holdout leads get now, the stored auto_stage and the statistics variant. */
export type SegmentModeInfo = { stage: Stage; auto_stage: Stage | null; variant: "base" | "ai" };

/** Progress toward Stage B: received leads out of 20 and the oldest lead's age out of 7 days, each 0–1. */
export type StageBProgress = { leads: number; age: number };

export type SegmentRow = {
  segment: string;
  /** The 3-part roll-up key (course|level|mode); equals segment for a 3-part key. */
  rollup: string;
  /** A 4-part university key (course|level|mode|u<id>). */
  exact: boolean;
  leads: number; matured: number; prior: number; partners: number; partners_matured: number; best_partner_matured: number;
  mode: SegmentModeInfo; progress_b: StageBProgress; progress_c: number;
  /** Active partners offering the segment's programme. */
  competing: number;
  /** Active routing rules whose conditions cover this segment (the Admin's override tool). */
  rules_active: number;
  leads_30d: number; last_routed_at: string | null;
};

export type StageRate = { stage: "applied" | "interested" | "contacted" | "accepted" | "none"; n: number; enrolled: number; rate: number };

export type RoutingSegments = {
  /** The Admin's parameters (engine_params(true)). */
  params: EngineParams;
  /** What non-holdout leads actually get: the AI overlay applied (engine_params(false)). */
  steered_params: EngineParams;
  policy: EnginePolicy; policy_version: number; stats_at: string | null; stage_rates: StageRate[]; segments: SegmentRow[];
};

type Posterior = { leads: number; matured: number; enrolled: number; p_hat: number; alpha: number; beta: number; interval: { low: number; high: number } };

export type PSource = "model" | "p_hat" | "prior";
export const P_SOURCE_LABEL: Record<PSource, string> = { model: "model", p_hat: "segment P̂", prior: "prior" };

/** How a candidate's CPE was built (stage_score). */
export type CpeBasis = {
  tier_basis: "middle" | "projected";
  fee_source: string | null;
  fee_basis: string | null;
  offers_with_rate: number;
  /** The programme whose offer is the median. */
  programme_id: number | null;
};

/** One partner in routing_segment (m31l): the engine's own numbers for the key (stage_score with the lane off). Non-competing
 *  partners (paused, onboarding) carry the offer data and statistics but no score or tie_rank. */
export type SegmentPartner = {
  partner_id: number; name: string; status: string; competing: boolean;
  score: number | null; tie_rank: number | null;
  cpe: number | null; cpe_basis: CpeBasis | null; has_rate: boolean;
  p_used: number | null; p_source: PSource | null; p_hat: number | null;
  effort_factor: number | null; effort_raw: number | null; effort_detail: EffortDetail | null; has_activity: boolean;
  sla_adherence: number | null; sla_factor: number | null; sla_raw: number | null;
  n_received: number; first_lead_at: string | null; n_matured_c: number; under_tested: boolean | null;
  progress_b: StageBProgress; progress_c: number;
  /** The holdout's (Admin-only) numbers, present only when they differ from the steered ones. */
  holdout: { score: number | null; p_used: number | null; effort_factor: number | null; sla_factor: number | null } | null;
  exact: (Posterior & { n_received: number; n_matured_c: number }) | null;
  rollup: Posterior | null;
  refund_rate: number; offers: number; programmes: number[];
  daily_cap: number | null; monthly_cap: number | null; leads_today: number; leads_month: number; leads_week: number; leads_30d: number;
};

export type SegmentStats = {
  segment: string; variant: string; n_leads: number; n_matured: number; prior: number; partners: number; partners_matured: number;
  auto_stage: Stage | null; auto_mode: string | null; refreshed_at: string;
} & Record<string, unknown>;

export type SegmentDetail = {
  segment: string; rollup: string; exact: boolean;
  mode: SegmentModeInfo; stage: Stage; variant: "base" | "ai";
  params: EngineParams; steered_params: EngineParams;
  /** The segment the scores were evaluated in (the exact key once every competing partner has 30 leads there, else the roll-up). */
  eval_segment: string | null;
  holdout_share: number;
  progress_b: StageBProgress; progress_c: number; stats_at: string | null;
  stats: SegmentStats | null;
  partners: SegmentPartner[];
  not_offering: { partner_id: number; name: string; status: string; n_received: number; n_matured_c: number }[];
  flow_30d: { mode: string; stage: Stage | null; holdout: boolean; n: number }[];
  /** Partner allocations per IST week over the last 12 weeks (C62). */
  flow_weekly: { week: string; partner_id: number; n: number }[];
  decisions: { id: number; lead_id: number; at: string; mode: string; scoring_mode: ScoringMode | null; stage: Stage | null; holdout: boolean; partner_id: number | null;
               partner_name: string | null; selection_probability: number | null; is_test: boolean }[];
};

/** Funnel stages of routing_segments.stage_rates (was STAGE_LABEL; STAGE_LABEL in lib/routing.ts is the A/B/C scoring stage). */
export const STAGE_RATE_LABEL: Record<StageRate["stage"], string> = {
  applied: "Applied", interested: "Counselled or further", contacted: "Contacted", accepted: "Accepted by the partner", none: "Any lead",
};

/** A segment key is course|level|mode (the roll-up is course|*|*); a university segment adds |u<university_id> (D25). */
export const SEGMENT_RE = /^[^|]{1,60}\|[^|]{1,20}\|[^|]{1,20}(\|u\d{1,12})?$/;
export const isSegment = (s: unknown): s is string => typeof s === "string" && SEGMENT_RE.test(s);
/** "mba|PG|Online|u12" → "mba|PG|Online"; a 3-part key is returned as it is. */
export const segmentRollup = (s: string): string => s.split("|").slice(0, 3).join("|");
/** The university id of a 4-part key, else null. */
export const segmentUniversity = (s: string | null | undefined): number | null => {
  const m = /\|u(\d{1,12})$/.exec(s ?? "");
  return m ? Number(m[1]) : null;
};

export const pct = (v: number | null | undefined, digits = 1) =>
  v == null || !Number.isFinite(v) ? "—" : `${(v * 100).toFixed(digits).replace(/\.0+$/, "")}%`;

/** A factor such as 1.0325 → "×1.03". */
export const factorText = (v: number | null | undefined) => (v == null || !Number.isFinite(v) ? "—" : `×${v.toFixed(2)}`);

export type StageProgressInput = { n_received: number; first_lead_at: string | null; n_matured_c: number; competing?: boolean };
export type StageProgress = {
  b: { ready: boolean; leads: number; age: number; share: number; text: string };
  c: { ready: boolean; share: number; text: string };
};

/** Progress toward the stage gates (D26), over the competing partners (every partner when `competing` is not given):
 *  Stage B needs every partner to have 20 received leads with the first at least 7 days old; Stage C needs 2 partners with
 *  30 matured leads each. Shares are 0–1; the texts are the Segments tab's hints. */
export function stageProgress(partners: StageProgressInput[], gates = STAGE_GATES, now = new Date()): StageProgress {
  const comp = partners.filter((p) => p.competing !== false);
  const minLeads = gates.stage_b_min_leads, minDays = gates.stage_b_min_age_days, minMatured = gates.stage_c_min_matured, minPartners = gates.stage_c_min_partners;
  if (comp.length === 0) {
    return { b: { ready: false, leads: 0, age: 0, share: 0, text: "No competing partner yet" }, c: { ready: false, share: 0, text: `Stage C needs ${minPartners} partners with ${minMatured} matured leads each` } };
  }
  const ageDays = (p: StageProgressInput) => (p.first_lead_at ? Math.max(0, (now.getTime() - new Date(p.first_lead_at).getTime()) / 86_400_000) : 0);
  const fewest = Math.min(...comp.map((p) => p.n_received));
  const youngest = Math.min(...comp.map(ageDays));
  const leads = Math.min(1, fewest / Math.max(minLeads, 1));
  const age = Math.min(1, youngest / Math.max(minDays, 1));
  const bReady = leads >= 1 && age >= 1;
  const bText = bReady ? `Stage B: every partner has ${minLeads} leads at least ${minDays} days old`
    : leads < 1 ? `Stage B needs ${minLeads} leads per partner (fewest: ${fewest})`
    : `Stage B needs the first lead to be ${minDays} days old (youngest partner: ${Math.floor(youngest)} d)`;
  const top = comp.map((p) => p.n_matured_c).sort((a, b) => b - a).slice(0, minPartners);
  while (top.length < minPartners) top.push(0);
  const cReady = top.filter((m) => m >= minMatured).length >= minPartners;
  const cShare = Math.min(1, top.reduce((s, m) => s + Math.min(m, minMatured), 0) / (minPartners * Math.max(minMatured, 1)));
  const cText = cReady ? `Stage C: ${minPartners} partners have ${minMatured} matured leads`
    : `Stage C needs ${minPartners} partners with ${minMatured} matured leads each (best: ${top[0]}, next: ${top[1] ?? 0})`;
  return { b: { ready: bReady, leads, age, share: Math.min(leads, age), text: bText }, c: { ready: cReady, share: cShare, text: cText } };
}

/** Per-week partner shares from routing_segment.flow_weekly (C62): each week's shares sum to 1. Weeks ascending. */
export function weeklyShares(rows: { week: string; partner_id: number; n: number }[]): { week: string; total: number; shares: { partner_id: number; n: number; share: number }[] }[] {
  const byWeek = new Map<string, { partner_id: number; n: number }[]>();
  for (const r of rows) {
    const list = byWeek.get(r.week) ?? [];
    list.push({ partner_id: r.partner_id, n: r.n });
    byWeek.set(r.week, list);
  }
  return [...byWeek.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([week, list]) => {
    const total = list.reduce((s, x) => s + x.n, 0);
    return { week, total, shares: list.sort((a, b) => b.n - a.n || a.partner_id - b.partner_id).map((x) => ({ ...x, share: total > 0 ? x.n / total : 0 })) };
  });
}

/** When something ends (a lost grace, a consent request), in words; null for "no end". */
export function untilText(until: string | null | undefined, now = new Date()): string | null {
  if (!until) return null;
  const ms = new Date(until).getTime() - now.getTime();
  if (!Number.isFinite(ms)) return null;
  if (ms <= 0) return "expired";
  const days = Math.round(ms / 86_400_000);
  return days >= 1 ? `ends in ${days} day${days === 1 ? "" : "s"}` : `ends in ${Math.max(1, Math.round(ms / 3_600_000))} h`;
}

/** Plain-language summary of a decision's scoring, from stored fields only (C112, C123, C128): the same text for the live
 *  preview and the stored decision. A3 decisions (a stage) read "Stage B: commission × effort × SLA"; legacy decisions keep
 *  the M24 wording, with the draw sentence keyed on scoring_mode 'performance' alone. */
export function scoringSummary(d: { stage?: Stage | null; mode: string; scoring_mode?: ScoringMode | null; holdout?: boolean | null; holdout_share?: number | null;
                                    selection_probability: number | null; model_version?: string | null; draw?: number | null }): string | null {
  const parts: string[] = [];
  if (d.stage) {
    parts.push(`Stage ${d.stage}: ${STAGE_FORMULA[d.stage]}`);
    if (d.mode === "exploration") parts.push(`exploration lane: the under-tested partner won the ${pct(d.selection_probability, 0)} draw${d.draw != null ? ` (draw ${d.draw.toFixed(3)})` : ""}`);
    else if (d.mode === "rule") parts.push("narrowed by a routing rule");
    else if (d.mode === "minimum") parts.push("a contractual minimum behind schedule was served first");
    else if (d.mode === "manual") parts.push("sent to partners by hand");
    else if (d.draw != null) parts.push(`exploration lane drawn ${d.draw.toFixed(3)}: the highest score kept the lead`);
    if (d.holdout) parts.push(`holdout lead${d.holdout_share != null ? ` (${pct(d.holdout_share, 0)})` : ""}: the Admin's settings only, no AI changes`);
    if (d.model_version) parts.push(`model ${d.model_version}`);
    return parts.join(" · ");
  }
  if (!d.scoring_mode) return null;
  parts.push(SCORING_LABEL[d.scoring_mode]);
  if (d.holdout) parts.push("holdout lead: the Admin's settings only, no AI changes");
  if (d.scoring_mode === "performance") parts.push(`chosen in ${pct(d.selection_probability, 0)} of the seeded draws`);
  return parts.join(" · ");
}

// ---------- forms ----------

/** A required number: a blank field is an error, never 0 (z.coerce.number turns "" into 0; C63). */
export const reqNum = (msg: string) => z.string().trim().min(1, msg).pipe(z.coerce.number({ error: msg }));
/** A checkbox: "on" when ticked, absent otherwise. */
export const checkbox = () => z.string().optional().transform((v) => v === "on");

const bounded = (lo: number, hi: number, msg: string) => reqNum(msg).pipe(z.number().min(lo, msg).max(hi, msg));
const boundedInt = (lo: number, hi: number, msg: string) => reqNum(msg).pipe(z.number().int(msg).min(lo, msg).max(hi, msg));
const weight = (msg = "A weight from 0 to 5") => bounded(WEIGHT_RANGE[0], WEIGHT_RANGE[1], msg);

export const PolicySchema = z.object({
  holdout_share: reqNum("0 to 50%").pipe(z.number().min(0, "0 to 50%").max(50, "0 to 50%")).transform((v) => Math.round(v * 10) / 1000),
  reason: z.string().trim().min(3, "Say why").max(300),
});

/** The sales-effort and SLA-adherence factors as flat form fields (owner's correction 1: bounds and weights are versioned Admin
 *  settings inside the rulebook ranges). Field names: effort_enabled, effort_lo, effort_hi, effort_w_<metric>, effort_min_sample,
 *  sla_enabled, sla_floor, sla_ceiling, sla_step, sla_w_<sla>. Every number goes through reqNum: a blank field is an error. */
export const performanceFields = {
  effort_enabled: checkbox(),
  effort_lo: bounded(EFFORT_RANGE[0], 1, "Lower bound 0.85 to 1.00"),
  effort_hi: bounded(1, EFFORT_RANGE[1], "Upper bound 1.00 to 1.15"),
  effort_w_first_call: weight(),
  effort_w_attempts_72h: weight(),
  effort_w_connect_rate: weight(),
  effort_w_followup: weight(),
  effort_w_acts_per_open: weight(),
  effort_w_stale_share: weight(),
  effort_min_sample: boundedInt(3, 100, "3 to 100 observations"),
  sla_enabled: checkbox(),
  sla_floor: bounded(SLA_RANGE[0], SLA_RANGE[1], "Floor 0.80 to 1.00"),
  sla_ceiling: bounded(SLA_RANGE[0], SLA_RANGE[1], "Ceiling 0.80 to 1.00"),
  sla_step: bounded(SLA_STEP_RANGE[0], SLA_STEP_RANGE[1], "Step 0.01 to 0.20 per 10 points"),
  sla_w_first_attempt: weight(),
  sla_w_status_update: weight(),
  sla_w_enrollment_proof: weight(),
};

export type PerformanceFields = z.infer<z.ZodObject<typeof performanceFields>>;

/** Cross-field checks shared by PerformanceSchema and EngineSchema: a positive weight sum for each factor, floor ≤ ceiling. */
export function performanceRefine(d: PerformanceFields, ctx: z.RefinementCtx): void {
  const effortSum = EFFORT_METRICS.reduce((s, k) => s + d[`effort_w_${k}`], 0);
  if (effortSum <= 0) ctx.addIssue({ code: "custom", path: ["effort_weights"], message: "Give at least one effort metric a weight above 0" });
  const slaSum = SLA_KEYS.reduce((s, k) => s + d[`sla_w_${k}`], 0);
  if (slaSum <= 0) ctx.addIssue({ code: "custom", path: ["sla_weights"], message: "Give at least one SLA a weight above 0" });
  if (d.sla_ceiling < d.sla_floor) ctx.addIssue({ code: "custom", path: ["sla_ceiling"], message: "At or above the floor" });
}

/** Effort and SLA settings (Addendum 3): bounds, weights, minimum sample, floor, ceiling and step. */
export const PerformanceSchema = z.object(performanceFields).superRefine(performanceRefine);

/** The flat fields → engine_settings_save's effort_factor and sla_factor (stored shapes: bounds [lo, hi], weights by name). */
export function performancePayload(d: PerformanceFields) {
  return {
    effort_factor: {
      enabled: d.effort_enabled,
      bounds: [d.effort_lo, d.effort_hi] as [number, number],
      weights: Object.fromEntries(EFFORT_METRICS.map((k) => [k, d[`effort_w_${k}`]])) as EffortWeights,
      min_sample: d.effort_min_sample,
    },
    sla_factor: {
      enabled: d.sla_enabled,
      floor: d.sla_floor,
      ceiling: d.sla_ceiling,
      step: d.sla_step,
      weights: Object.fromEntries(SLA_KEYS.map((k) => [k, d[`sla_w_${k}`]])) as SlaWeights,
    },
  };
}

/** The stored engine.effort_factor / sla_factor → the form's default values (strings, as the inputs show them). */
export function performanceDefaults(v: {
  effort_factor?: { enabled?: boolean; bounds?: number[] | { lo?: number; hi?: number }; weights?: Partial<EffortWeights>; min_sample?: number } | null;
  sla_factor?: { enabled?: boolean; floor?: number; ceiling?: number; step?: number; weights?: Partial<SlaWeights> } | null;
}): Record<keyof typeof performanceFields, string> {
  const e = v.effort_factor ?? {}, s = v.sla_factor ?? {};
  const b = e.bounds;
  const lo = Array.isArray(b) ? b[0] : b?.lo, hi = Array.isArray(b) ? b[1] : b?.hi;
  const num = (x: number | undefined, dflt: number) => String(x ?? dflt);
  const out: Record<string, string> = {
    effort_enabled: e.enabled === false ? "" : "on",
    effort_lo: num(lo, EFFORT_RANGE[0]), effort_hi: num(hi, EFFORT_RANGE[1]), effort_min_sample: num(e.min_sample, 10),
    sla_enabled: s.enabled === false ? "" : "on",
    sla_floor: num(s.floor, SLA_RANGE[0]), sla_ceiling: num(s.ceiling, SLA_RANGE[1]), sla_step: num(s.step, 0.05),
  };
  for (const k of EFFORT_METRICS) out[`effort_w_${k}`] = num(e.weights?.[k], 1);
  for (const k of SLA_KEYS) out[`sla_w_${k}`] = num(s.weights?.[k], 1);
  return out as Record<keyof typeof performanceFields, string>;
}

/** "12: 60, 14: 40" from a stored map (legacy fixed split; kept for old rows). */
export const splitText = (s: Record<string, number> | null | undefined) => Object.entries(s ?? {}).map(([k, v]) => `${k}: ${v}`).join(", ");
