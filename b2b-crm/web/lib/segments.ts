import { z } from "zod";

/** Performance routing (M24): segment modes, statistics and the Admin's per-segment policy. Shared by the Routing
 *  screen's Segments tab, the decision view and the tests. */

export type ScoringMode = "commission_first" | "performance" | "kill_switch";

export const SCORING_LABEL: Record<ScoringMode, string> = {
  commission_first: "Commission first",
  performance: "Performance",
  kill_switch: "Kill switch (fixed split)",
};

export const SCORING_HINT: Record<ScoringMode, string> = {
  commission_first: "The highest commission wins, with the exploration lane while a partner is under-sampled.",
  performance: "The highest expected net commission per lead wins: P̂(enrol) × commission × (1 − refunds), sampled from each partner's uncertainty.",
  kill_switch: "Scoring is off: leads are split between partners in the fixed shares you set.",
};

type Sourced<T> = { value: T; source: "admin" | "ai"; by?: string; at?: string };
export type SegmentPin = { mode: "commission_first" | "performance"; until?: string | null; source: "admin" | "ai"; by?: string; at?: string; reason?: string };
export type SegmentPolicy = { pin?: SegmentPin; exploration_share?: Sourced<number>; share_cap?: Sourced<number> };
export type SegmentModeInfo = { auto: "commission_first" | "performance"; pin: SegmentPin | null; killed: boolean; mode: ScoringMode };
export type PartnerWeight = { weight: number; until: string; source: "admin" | "ai"; by?: string; reason?: string };

export type EngineParams = {
  maturity_days: number; half_life_days: number; prior_weight: number; default_p_enroll: number; min_matured_leads: number;
  speed_on: boolean; reliability_on: boolean; leading_weight: number; leading_min_days: number; variant: "base" | "ai";
};

export type EnginePolicy = {
  holdout_share?: number; mc_draws?: number; leading_weight?: number; leading_min_days?: number;
  segments?: Record<string, SegmentPolicy>; partner_weights?: Record<string, PartnerWeight>; kill_segments?: string[];
  ai?: Record<string, unknown>;
};

export type SegmentRow = {
  segment: string; rollup: boolean; leads: number; matured: number; prior: number; partners: number; partners_matured: number;
  best_partner_matured: number; mode: SegmentModeInfo; exploration_share: Sourced<number> | null; share_cap: Sourced<number> | null;
  leads_30d: number; last_routed_at: string | null;
};

export type StageRate = { stage: "applied" | "interested" | "contacted" | "accepted" | "none"; n: number; enrolled: number; rate: number };

export type RoutingSegments = {
  params: EngineParams; policy: EnginePolicy; policy_version: number; stats_at: string | null; stage_rates: StageRate[]; segments: SegmentRow[];
};

type Posterior = { leads: number; matured: number; enrolled: number; p_hat: number; alpha: number; beta: number; interval: { low: number; high: number } };
export type SegmentPartner = {
  partner_id: number; name: string; status: string;
  exact: (Posterior & { w_matured: number; w_enrolled: number; young: number; young_expected: number }) | null;
  rollup: Posterior | null;
  uses: "segment" | "course";
  refund_rate: number; sla_compliance: number | null; first_contact_hours: number | null; speed: number; reliability: number;
  weight: PartnerWeight | null; cpe: number | null; offers: number; ncpl: number; leads_30d: number;
};

export type SegmentDetail = {
  segment: string; rollup: string; mode: SegmentModeInfo; policy: SegmentPolicy; params: EngineParams;
  stats: { n_leads: number; n_matured: number; prior: number; partners: number; partners_matured: number; auto_mode: string; refreshed_at: string } | null;
  partners: SegmentPartner[];
  flow_30d: { mode: string; holdout: boolean; n: number }[];
  decisions: { id: number; lead_id: number; at: string; mode: string; scoring_mode: ScoringMode | null; holdout: boolean; partner_id: number | null;
               partner_name: string | null; selection_probability: number | null; is_test: boolean }[];
};

export const STAGE_LABEL: Record<StageRate["stage"], string> = {
  applied: "Applied", interested: "Counselled or further", contacted: "Contacted", accepted: "Accepted by the partner", none: "Any lead",
};

/** A segment key is course|level|mode; the course roll-up is course|*|*. */
export const SEGMENT_RE = /^[^|]{1,60}\|[^|]{1,20}\|[^|]{1,20}$/;
export const isSegment = (s: unknown): s is string => typeof s === "string" && SEGMENT_RE.test(s);

export const pct = (v: number | null | undefined, digits = 1) =>
  v == null || !Number.isFinite(v) ? "—" : `${(v * 100).toFixed(digits).replace(/\.0+$/, "")}%`;

/** Progress toward performance mode: the two best-sampled partners each need min_matured matured leads. */
export function maturityProgress(partners: { matured: number }[], minMatured: number): { ready: number; needed: number; share: number; text: string } {
  const top = [...partners].map((p) => p.matured).sort((a, b) => b - a).slice(0, 2);
  while (top.length < 2) top.push(0);
  const ready = top.filter((m) => m >= minMatured).length;
  const share = Math.min(1, (Math.min(top[0]!, minMatured) + Math.min(top[1]!, minMatured)) / (2 * Math.max(minMatured, 1)));
  const text = ready >= 2 ? "Enough matured data for performance mode"
    : `${ready} of 2 partners have ${minMatured} matured leads (best: ${top[0]}, next: ${top[1]})`;
  return { ready, needed: 2, share, text };
}

/** When a pin or weight ends, in words; null for "no end". */
export function untilText(until: string | null | undefined, now = new Date()): string | null {
  if (!until) return null;
  const ms = new Date(until).getTime() - now.getTime();
  if (!Number.isFinite(ms)) return null;
  if (ms <= 0) return "expired";
  const days = Math.round(ms / 86_400_000);
  return days >= 1 ? `ends in ${days} day${days === 1 ? "" : "s"}` : `ends in ${Math.max(1, Math.round(ms / 3_600_000))} h`;
}

/** Plain-language summary of a stored decision's scoring (decision view). */
export function scoringSummary(d: { scoring_mode?: ScoringMode | null; mode: string; holdout?: boolean | null; selection_probability: number;
                                    pinned?: boolean | null; mc_draws?: number | null }): string | null {
  if (!d.scoring_mode) return null;
  const parts = [SCORING_LABEL[d.scoring_mode]];
  if (d.pinned) parts.push("pinned by the Admin");
  if (d.holdout) parts.push("holdout lead: the Admin's settings only, no AI changes");
  if (d.scoring_mode === "performance" && d.mode === "performance") {
    parts.push(`chosen in ${pct(d.selection_probability, 0)} of ${d.mc_draws ? d.mc_draws + 1 : "the"} seeded draws`);
  }
  return parts.join(" · ");
}

// ---------- forms ----------

const optionalPct = (min: number, max: number, msg: string) =>
  z.string().trim().transform((v, ctx) => {
    if (v === "") return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < min || n > max) { ctx.addIssue({ code: "custom", message: msg }); return z.NEVER; }
    return Math.round(n * 10) / 1000;
  });

export const SegmentPolicySchema = z.object({
  segment: z.string().regex(SEGMENT_RE, "Unknown segment"),
  pin: z.enum(["auto", "commission_first", "performance"]),
  pin_until: z.string().regex(/^(\d{4}-\d{2}-\d{2})?$/, "A date").optional().default(""),
  exploration_share: optionalPct(0, 50, "0 to 50%, or empty for the engine's share"),
  share_cap: optionalPct(50, 100, "50 to 100%, or empty for no cap"),
  killed: z.string().optional().transform((v) => v === "on"),
  reason: z.string().trim().min(3, "Say why").max(300),
}).superRefine((d, ctx) => {
  if (d.pin !== "auto" && d.pin_until) {
    const t = new Date(`${d.pin_until}T23:59:59+05:30`).getTime();
    if (t <= Date.now()) ctx.addIssue({ code: "custom", path: ["pin_until"], message: "A date in the future" });
    if (t > Date.now() + 366 * 86_400_000) ctx.addIssue({ code: "custom", path: ["pin_until"], message: "Within a year" });
  }
});

/** The segment form → b2b.segment_policy_save's payload. */
export function segmentPolicyPayload(d: z.infer<typeof SegmentPolicySchema>) {
  return {
    pin: d.pin === "auto" ? null : { mode: d.pin, until: d.pin_until ? `${d.pin_until}T23:59:59+05:30` : null },
    exploration_share: d.exploration_share,
    share_cap: d.share_cap,
    killed: d.killed,
  };
}

export const PartnerWeightSchema = z.object({
  partner_id: z.string().regex(/^\d+$/, "Choose a partner").transform(Number),
  weight: z.string().trim().transform((v, ctx) => {
    if (v === "") return null;
    const n = Number(v);
    if (!Number.isFinite(n) || n < 90 || n > 110) { ctx.addIssue({ code: "custom", message: "90 to 110%" }); return z.NEVER; }
    return Math.round(n * 10) / 1000;
  }),
  days: z.coerce.number().int().min(1, "1 to 14 days").max(14, "1 to 14 days"),
  reason: z.string().trim().min(3, "Say why").max(300),
});

export const PolicySchema = z.object({
  holdout_share: z.coerce.number().min(0, "0 to 50%").max(50, "0 to 50%").transform((v) => Math.round(v * 10) / 1000),
  mc_draws: z.coerce.number().int().min(50, "50 to 1000").max(1000, "50 to 1000"),
  leading_weight: z.coerce.number().min(0, "0 to 100%").max(100, "0 to 100%").transform((v) => Math.round(v * 10) / 1000),
  leading_min_days: z.coerce.number().int().min(0, "0 to 30 days").max(30, "0 to 30 days"),
  reason: z.string().trim().min(3, "Say why").max(300),
});

/** Performance settings added to the engine form (M24). */
export const PerformanceSchema = z.object({
  maturity_days: z.coerce.number().int().min(14, "14 to 180 days").max(180, "14 to 180 days"),
  half_life_days: z.coerce.number().int().min(7, "7 to 120 days").max(120, "7 to 120 days"),
  prior_weight: z.coerce.number().min(1, "1 to 100 leads").max(100, "1 to 100 leads"),
  default_p_enroll: z.coerce.number().min(0.1, "0.1 to 50%").max(50, "0.1 to 50%").transform((v) => Math.round(v * 100) / 10000),
  min_matured_leads: z.coerce.number().int().min(5, "5 to 500").max(500, "5 to 500"),
  speed_factor: z.string().optional().transform((v) => v === "on"),
  reliability_factor: z.string().optional().transform((v) => v === "on"),
  kill_switch: z.string().optional().transform((v) => v === "on"),
  fixed_split: z.string().trim().max(500).transform((v, ctx) => {
    const out: Record<string, number> = {};
    for (const part of v.split(/[,;\n]+/).map((x) => x.trim()).filter(Boolean)) {
      const m = /^(\d{1,12})\s*[:=]\s*(\d+(?:\.\d+)?)$/.exec(part);
      if (!m || Number(m[2]) <= 0) { ctx.addIssue({ code: "custom", message: `"${part}" should look like 12: 60 (partner ID: share)` }); return z.NEVER; }
      out[m[1]!] = Number(m[2]);
    }
    return out;
  }),
});

/** "12: 60, 14: 40" for the form from the stored split. */
export const splitText = (s: Record<string, number> | null | undefined) => Object.entries(s ?? {}).map(([k, v]) => `${k}: ${v}`).join(", ");
