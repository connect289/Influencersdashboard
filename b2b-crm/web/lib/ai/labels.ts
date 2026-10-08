import { z } from "zod";
import { EFFORT_METRIC_LABEL, EFFORT_METRICS, EFFORT_RANGE, reqNum, SLA_RANGE, WEIGHT_RANGE, type EffortMetricKey, type EffortWeights } from "../segments";

/**
 * AI Optimiser screen: types, labels and form parsing (B14.3, Addendum 3). Pure; shared by the page, the actions, the
 * what-if simulator and the tests. Shapes mirror m31m: ai_validate_change (levers and ranges), ai_change_path, ai_simulate
 * (support, window), ai_uplift (diff_ci95), ai_review_tick (check_result.realised), ai_apply_setting (applied.change / edited).
 */

export { EFFORT_METRIC_LABEL, EFFORT_METRICS };
export type { EffortMetricKey, EffortWeights };

export type RecStatus = "open" | "applied" | "rejected" | "expired" | "rolled_back" | "superseded";

/** The five setting levers the AI may tune, each stored at engine_policy.ai.<lever> (m31m ai_change_path). */
export const SETTING_LEVERS = ["effort_weights", "effort_bounds", "sla_floor", "half_life_days", "prior_weight"] as const;
export type SettingLever = (typeof SETTING_LEVERS)[number];
/** Drafts: a rule is created inactive, a pause happens only on approval. */
export const DRAFT_LEVERS = ["rule_draft", "pause_draft"] as const;
export type Lever = SettingLever | (typeof DRAFT_LEVERS)[number];
export const LEVER_LABEL: Record<Lever, string> = {
  effort_weights: "Sales-effort weights",
  effort_bounds: "Sales-effort factor bounds",
  sla_floor: "SLA-adherence factor floor",
  half_life_days: "Recency half-life of P(enrol)",
  prior_weight: "Prior strength of P(enrol)",
  rule_draft: "Routing rule (draft)",
  pause_draft: "Partner pause (draft)",
};

export type Change = {
  lever: Lever; partner_id?: number; value?: unknown; reason?: string;
  rule?: { name: string; action: string; partner_ids: number[]; conditions: Record<string, unknown>; priority?: number };
  /** Rows decided before Addendum 3 may still carry these; the levers that used them (pins, caps, weights) are retired. */
  segment?: string; until?: string;
};

/** b2b.ai_simulate (m31m 8): a doubly robust replay of matured decisions against the current policy. */
export type Simulation = {
  simulated: boolean; why?: string; days?: number;
  /** The decisions replayed: routed inside this window, so their outcomes are known (matured 60 days). */
  window?: { from: string; to: string } | null;
  decisions?: number; affected?: number; ncpl_now?: number; ncpl_new?: number; difference?: number;
  ci95?: [number, number]; gain_pct?: number | null; ess?: number;
  /** Share of replayed decisions whose new policy puts all its mass on partners the log could have chosen. */
  support?: number;
  /** Autopilot's bar for support (ai.autopilot.min_support, 0.5). */
  min_support?: number;
  /** At least 30 decisions and support at or above min_support. */
  enough?: boolean;
};
/** One group of the realised check: leads and net commission per lead. */
export type RealisedGroup = { leads: number; ncpl: number | null };
/** ai_review_tick's realised effect (C42): 14 days before and after an applied change, AI-steered and holdout. */
export type Realised = {
  before: RealisedGroup; after: RealisedGroup; holdout_before: RealisedGroup; holdout_after: RealisedGroup;
  /** (after − before) − (holdout_after − holdout_before), ₹ per lead; null when a group is empty. */
  did: number | null; window_days?: number; from?: string; to?: string; at?: string;
};
export type Recommendation = {
  id: number; run_id: number; run_kind?: string; kind: "setting_change" | "rule_draft" | "pause_draft" | "insight"; status: RecStatus;
  title: string; rationale: string; evidence: { tool?: string; metric?: string; value?: unknown }[]; change: Change | null;
  simulation: Simulation | null; risk: string | null; expires_at: string; decided_by: string | null; decided_at: string | null;
  decision_note: string | null;
  /** ai_apply_setting: what went live. `change` is the value applied (edited by the Admin when `edited`); from/to are the slot's values. */
  applied: { key?: string; version?: number; path?: string[]; from?: unknown; to?: unknown; change?: Change; edited?: boolean; rule_id?: string } | null;
  check_due_at: string | null; created_at: string;
  check_result?: { verdict?: "waiting" | "kept" | "worse" | "inconclusive"; z?: number | null; auto_rolled_back?: boolean;
                   steered?: { leads: number; expected_ncpl: number | null }; holdout?: { leads: number; expected_ncpl: number | null };
                   not_rolled_back?: string; superseded_by?: number; superseded_at?: string; realised?: Realised | null } | null;
};
export type AiRun = {
  id: number; trigger: string; kind: string; model: string; status: string; created_at: string; finished_at: string | null; tools: number;
  tokens_in: number; tokens_out: number; cost_usd: number; error: string | null; summary: string | null; recommendations: number[] | null;
};
export type Uplift = {
  maturity_days: number; days?: number; steered: { leads: number; ncpl: number }; holdout: { leads: number; ncpl: number }; uplift_pct: number | null; z: number;
  /** 95% interval of steered − holdout NCPL per lead (C42); null when either group is empty. */
  diff_ci95?: [number, number] | null;
  by_month: { month: string; steered: number | null; holdout: number | null; steered_n: number; holdout_n: number }[];
};
export type AiSettings = {
  enabled: boolean; mode: "advisory" | "autopilot";
  /** min_support (0.5) is seeded by m31m and shown read-only: Autopilot applies a change only when its simulation's support reaches it. */
  autopilot?: { min_gain_pct: number; max_per_day: number; min_decisions?: number; min_support?: number };
  models: { regular: string; deep: string; quick: string }; daily_budget_usd: number;
  schedules: { light: boolean; hourly: boolean; nightly: boolean; weekly: boolean }; worker_url: string | null; max_turns?: number;
  /** US$ per million tokens, by model name (every model in use needs one). */
  prices_per_mtok?: Record<string, { in: number; out: number; cache_read?: number; cache_write?: number }>;
};
export type AiOverview = {
  settings: AiSettings; settings_version: number;
  worker: { seen_at?: string; has_anthropic_key?: boolean; updated_at?: string } | null; worker_key: boolean;
  spend: { today_usd: number; month_usd: number }; uplift: Uplift; holdout_share: number | null;
  /** When Autopilot may be switched on (absent on databases before the gate). */
  autopilot_gate?: { open: boolean; steered: { leads: number; ncpl: number; weeks: number }; holdout: { leads: number; ncpl: number; weeks: number } };
  open: Recommendation[]; decided: Recommendation[]; runs: AiRun[];
};
export type AiRunDetail = AiRun & {
  context: Record<string, unknown>; tool_calls: { call_no: number; name: string; ms: number }[]; output: { summary?: string; findings?: { title: string; detail: string }[] } | null;
  narrative: string | null; validation: { ok?: boolean; unverified?: string[]; checked?: number; rejected_changes?: { title: string; why: string }[] } | null;
  prompt_version: string | null; input_hash: string | null; cache_read: number; cache_write: number; started_at: string | null;
  tool_outputs: { call_no: number; name: string; input: unknown; output: unknown }[]; recommendations_rows: Recommendation[];
};

export type MlModel = {
  id: number; version: string; kind: string; status: "training" | "shadow" | "challenger" | "champion" | "retired" | "failed"; created_at: string;
  trained_at: string | null; status_at: string; status_reason: string | null; requested_by: string | null; error: string | null;
  trained_on: { rows?: number; enrolled?: number; train?: number; valid?: number; partners?: number; from?: string; to?: string; maturity_days?: number };
  gate: { outcomes?: number; min_outcomes?: number; outcomes_ok?: boolean; partners?: number; partners_ok?: boolean; beats_baseline?: boolean; policy_value_ok?: boolean; passed?: boolean };
  metrics: {
    holdout?: { n: number; log_loss: number; ece: number; mean_p: number; mean_y: number; deciles: { bin: number; pred: number; actual: number; n: number }[] };
    baseline?: { log_loss: number; ece: number };
    /** The doubly robust policy value over Stage C decisions (m31m ml_train). */
    policy?: { decisions: number; agree: number; logged_value: number; model_value: number; ess: number; support?: number; estimator?: string; matured_days?: number };
    top_weights?: { feature: string; w: number }[];
    monitor?: {
      at: string; matured?: { n: number; ece: number }; mean_p_30d?: number | null;
      mean_p_training?: number | null; mean_p_reference?: number | null; drift?: boolean;
      feature_psi?: { n_live: number; n_training: number; max: number; top: { feature: string; training: number; recent: number; psi: number }[];
                      score_training: number | null; score_30d: number | null } | null;
    };
  };
  features: number; was_champion: boolean;
  champion_check: { model_leads: number; other_leads: number; model_ncpl: number; other_ncpl: number; z: number; ready: boolean } | null;
};
export type MlOverview = {
  settings: { min_outcomes: number; challenger_share: number; ece_fallback: number; train_hour_ist: number; auto_train: boolean };
  settings_version: number;
  data: { matured: number; matured_enrolled: number; partners: number; young: number }; maturity_days: number;
  decided_30d: Record<string, number>; models: MlModel[];
};

export const RUN_KIND_LABEL: Record<string, string> = {
  light_check: "Light check", optimise: "Optimisation", deep_review: "Nightly deep review", weekly_report: "Weekly report", ask: "Ask the CRM",
};
/** The kinds of run the Admin can queue by hand ('ask' runs come only from Ask the CRM). */
export const RUN_NOW_KINDS = ["light_check", "optimise", "deep_review", "weekly_report"] as const;
export type RunNowKind = (typeof RUN_NOW_KINDS)[number];
export const TRIGGER_LABEL: Record<string, string> = {
  light: "new alerts", hourly: "hourly", nightly: "nightly", weekly: "weekly", event: "an event", manual: "by hand", ask: "a question",
};
export const REC_STATUS_LABEL: Record<RecStatus, string> = {
  open: "Open", applied: "Applied", rejected: "Rejected", expired: "Expired", rolled_back: "Rolled back", superseded: "Superseded",
};
export const MODEL_STATUS_LABEL: Record<MlModel["status"], string> = {
  training: "Training", shadow: "Shadow", challenger: "Challenger", champion: "Champion", retired: "Retired", failed: "Failed",
};

// ---------- lever ranges (C113) ----------

export type LeverRanges = {
  half_life_days: readonly [number, number]; prior_weight: readonly [number, number];
  /** The low bound of the effort factor (lo ≤ 1) and the high bound (hi ≥ 1). */
  effort_lo: readonly [number, number]; effort_hi: readonly [number, number];
  /** As a fraction (0.8 = 80%). */
  sla_floor: readonly [number, number];
  /** Each effort weight; the sum must be positive. */
  weight: readonly [number, number];
};
/** What the Admin may save (m31l engine_settings_save, CONTRACT 1.4) and what the what-if simulator accepts (m31m simulate_change). */
export const ADMIN_LEVER_RANGES: LeverRanges = {
  half_life_days: [7, 120], prior_weight: [1, 100],
  effort_lo: [EFFORT_RANGE[0], 1], effort_hi: [1, EFFORT_RANGE[1]], sla_floor: [SLA_RANGE[0], SLA_RANGE[1]], weight: [WEIGHT_RANGE[0], WEIGHT_RANGE[1]],
};
/**
 * What the AI may propose (m31m ai_validate_change). The half-life and the prior are narrower than the Admin's; the factor
 * bounds and the SLA floor are further limited to the Admin's current setting at run time (Admin lo…1, 1…Admin hi,
 * Admin floor…ceiling), so these are their widest.
 */
export const AI_LEVER_RANGES: LeverRanges = {
  half_life_days: [14, 60], prior_weight: [5, 50],
  effort_lo: [EFFORT_RANGE[0], 1], effort_hi: [1, EFFORT_RANGE[1]], sla_floor: [SLA_RANGE[0], SLA_RANGE[1]], weight: [WEIGHT_RANGE[0], WEIGHT_RANGE[1]],
};

const pct = (v: unknown) => (typeof v === "number" ? `${Math.round(v * 1000) / 10}%` : String(v));
const num2 = (v: unknown) => (typeof v === "number" ? v.toFixed(2) : String(v));

/** A lever's range in words, for the ranges table (AI against Admin). */
export function leverRangeText(lever: SettingLever, r: LeverRanges): string {
  switch (lever) {
    case "effort_weights": return `${r.weight[0]} to ${r.weight[1]} each, not all 0`;
    case "effort_bounds": return `low ${num2(r.effort_lo[0])}–${num2(r.effort_lo[1])}, high ${num2(r.effort_hi[0])}–${num2(r.effort_hi[1])}`;
    case "sla_floor": return `${pct(r.sla_floor[0])} to ${pct(r.sla_floor[1])}`;
    case "half_life_days": return `${r.half_life_days[0]} to ${r.half_life_days[1]} days`;
    case "prior_weight": return `${r.prior_weight[0]} to ${r.prior_weight[1]} leads`;
  }
}

// ---------- values in words ----------

/** Effort weights by metric name, in the engine's metric order; unknown keys as they are. */
function weightsText(v: unknown): string {
  if (!v || typeof v !== "object" || Array.isArray(v)) return String(v);
  const w = v as Record<string, unknown>;
  const known = EFFORT_METRICS.filter((k) => k in w).map((k) => `${EFFORT_METRIC_LABEL[k]} ${w[k]}`);
  const other = Object.keys(w).filter((k) => !(EFFORT_METRICS as readonly string[]).includes(k)).map((k) => `${k} ${w[k]}`);
  return [...known, ...other].join(", ") || "none";
}

/** A lever's value in the Admin's units (85%, 0.90–1.10, 30 days, 20 leads, weights by name); null or undefined reads 'default'. */
export function leverValueText(lever: Lever | string, v: unknown): string {
  if (v == null) return "default";
  switch (lever) {
    case "sla_floor": return pct(v);
    case "effort_bounds": return Array.isArray(v) && v.length === 2 ? `${num2(v[0])}–${num2(v[1])}` : String(v);
    case "effort_weights": return weightsText(v);
    case "half_life_days": return `${v} days`;
    case "prior_weight": return `${v} leads`;
    default: return typeof v === "object" ? JSON.stringify(v) : String(v);
  }
}

const segmentText = (s: string) => s.split("|").map((x, i) => (x === "*" ? "any" : i === 0 ? x.toUpperCase() : x)).join(" · ");

/** A change in plain words. names: partner id → name. */
export function describeChange(c: Change | null, names: Record<string, string> = {}): string {
  if (!c) return "No change: an observation";
  const partner = c.partner_id != null ? names[String(c.partner_id)] ?? `partner #${c.partner_id}` : "";
  switch (c.lever) {
    case "effort_weights": return `Effort weights: ${weightsText(c.value)}`;
    case "effort_bounds": return `Effort factor ${leverValueText("effort_bounds", c.value)}`;
    case "sla_floor": return `SLA factor floor ${pct(c.value)}`;
    case "half_life_days": return `Recency half-life ${leverValueText("half_life_days", c.value)}`;
    case "prior_weight": return `Prior strength ${leverValueText("prior_weight", c.value)}`;
    case "rule_draft": return `Draft rule “${c.rule?.name ?? ""}” (created inactive)`;
    case "pause_draft": return `Pause ${partner}`;
    default: {
      // a lever retired by Addendum 3 (pins, share caps, partner weights, exploration, speed/reliability, maturity): change-log rows only
      const seg = c.segment ? ` for ${segmentText(c.segment)}` : "";
      return `${String(c.lever).replace(/_/g, " ")} (retired lever)${seg}`;
    }
  }
}

/** The line of a recommendation card: the value that went live, with the proposal when the Admin edited it (C42). */
export function changeLine(r: Pick<Recommendation, "change" | "applied">, names: Record<string, string> = {}): string {
  const live = r.applied?.change ?? r.change;
  const text = describeChange(live, names);
  return r.applied?.edited && r.change ? `${text} (proposed: ${describeChange(r.change, names)})` : text;
}

/** "80% → 85%": the slot's value before and after an applied setting change (null reads 'default'), or null for a draft. */
export function fromToText(r: Pick<Recommendation, "change" | "applied">): string | null {
  const a = r.applied;
  if (!a || (!("from" in a) && !("to" in a))) return null;
  const lever = (a.change ?? r.change)?.lever ?? a.path?.[1] ?? "";
  return `${leverValueText(lever, a.from)} → ${leverValueText(lever, a.to)}`;
}

/** Where an evidence chip leads: the run, at the first output of the tool it cites (C42). */
export function evidenceHref(r: Pick<Recommendation, "run_id">, e: { tool?: string }): string {
  return `/ai/runs/${r.run_id}${e.tool ? `#tool-${encodeURIComponent(e.tool)}` : ""}`;
}

export const rupees = (n: number | null | undefined) => (n == null || !Number.isFinite(n) ? "—" : `₹${Math.round(n).toLocaleString("en-IN")}`);
export const signedRupees = (n: number) => `${n < 0 ? "−" : "+"}${rupees(Math.abs(n))}`;

/** The simulated impact in words, or why there is none. */
export function simulationText(s: Simulation | null): string {
  if (!s) return "Not simulated";
  if (!s.simulated) return s.why ?? "Cannot be simulated";
  if (!s.decisions) return "No matured decisions to replay yet";
  const ci = s.ci95 ? ` (95%: ${signedRupees(s.ci95[0])} to ${signedRupees(s.ci95[1])})` : "";
  // not enough: under 30 decisions, or the log cannot speak for the new policy (support below Autopilot's bar)
  const weak = s.enough !== false ? ""
    : s.decisions >= 30 && s.support != null && s.min_support != null && s.support < s.min_support
      ? `: support ${pct(s.support)} is below the ${pct(s.min_support)} Autopilot needs`
      : ": too few to rely on";
  return `NCPL ${rupees(s.ncpl_now)} → ${rupees(s.ncpl_new)}${s.gain_pct != null ? `, ${s.gain_pct >= 0 ? "+" : "−"}${Math.abs(s.gain_pct)}%` : ""}${ci} on ${s.decisions} decisions${weak}`;
}

/** The support of a simulation in words (the share of replayed decisions the log can speak for), or null. */
export function supportText(s: Simulation | null): string | null {
  if (!s?.simulated || s.support == null) return null;
  const need = s.min_support != null ? ` (Autopilot needs ${pct(s.min_support)})` : "";
  const ess = s.ess != null ? `, effective sample ${Math.round(s.ess)}` : "";
  return `Support ${pct(s.support)} of ${s.decisions ?? 0} decisions${need}${ess}`;
}

/** The realised effect of an applied change (C42): 'Realised: ₹X → ₹Y per lead (holdout ₹A → ₹B; net effect ±₹D) on n leads', or null. */
export function realisedText(r: Pick<Recommendation, "check_result">): string | null {
  const x = r.check_result?.realised;
  if (!x) return null;
  const n = (x.before?.leads ?? 0) + (x.after?.leads ?? 0);
  const did = x.did == null ? "not measurable" : signedRupees(x.did);
  return `Realised: ${rupees(x.before?.ncpl)} → ${rupees(x.after?.ncpl)} per lead (holdout ${rupees(x.holdout_before?.ncpl)} → ${rupees(x.holdout_after?.ncpl)}; net effect ${did}) on ${n} leads`;
}

/** "expires in 6 days" / "expires in 5 h" / "expired". */
export function expiresText(at: string, now = new Date()): string {
  const ms = new Date(at).getTime() - now.getTime();
  if (!Number.isFinite(ms) || ms <= 0) return "expired";
  const d = Math.floor(ms / 86_400_000);
  return d >= 1 ? `expires in ${d} day${d === 1 ? "" : "s"}` : `expires in ${Math.max(1, Math.round(ms / 3_600_000))} h`;
}

// ---------- editing and parsing (C23, C100) ----------

/**
 * A number typed by the Admin: trimmed, one trailing % stripped; '' or anything non-numeric is the error 'Enter a number.'.
 * unit 'pct' divides by 100 (85 → 0.85), 'num' returns the number as typed.
 */
export function parseLeverValue(raw: string, unit: "pct" | "num"): number | string {
  const t = raw.trim().replace(/%$/, "");
  if (t === "") return "Enter a number.";
  const n = Number(t);
  if (!Number.isFinite(n)) return "Enter a number.";
  return unit === "pct" ? n / 100 : n;
}

/** The levers with one number the Admin can edit in the inbox; weights and bounds are approved or rejected as proposed. */
export const EDITABLE_LEVERS: readonly Lever[] = ["sla_floor", "half_life_days", "prior_weight"];
export const editable = (c: Change | null) => !!c && (EDITABLE_LEVERS as readonly string[]).includes(c.lever);

/**
 * The inbox's edit field (what the Admin types) → the change's value. The SLA floor accepts a fraction (0.8–1) or a percent
 * (80–100) and is stored as a fraction with 3 decimals, the units ai_validate_change reports in; days and leads as typed.
 */
export function editedChange(c: Change, typed: string): Change | string {
  if (!editable(c)) return "This change cannot be edited here: approve or reject it as proposed.";
  const n = parseLeverValue(typed, "num");
  if (typeof n === "string") return n;
  if (c.lever === "sla_floor") {
    const v = n <= 1 ? n : n / 100;
    if (v < SLA_RANGE[0] || v > SLA_RANGE[1]) return "Enter 80 to 100 (%), e.g. 85";
    return { ...c, value: Math.round(v * 1000) / 1000 };
  }
  // the database takes whole days for the half-life (its range message would not explain a fraction)
  if (c.lever === "half_life_days" && !Number.isInteger(n)) return "Enter whole days, e.g. 30";
  return { ...c, value: n };
}

/** Autopilot's rule in one sentence, with the support requirement (D23): for the Settings tab. */
export function autopilotRuleText(a: AiSettings["autopilot"] | undefined): string {
  const gain = a?.min_gain_pct ?? 3, perDay = a?.max_per_day ?? 3, decisions = a?.min_decisions ?? 30, support = a?.min_support ?? 0.5;
  return `Autopilot applies a setting change on its own only when its simulation shows at least ${gain}% more net commission per lead `
    + `on ${decisions} or more matured decisions, with the 95% interval above zero and support of at least ${pct(support)} `
    + `(the share of replayed decisions the log can speak for); at most ${perDay} a day. Drafts always wait for an Admin.`;
}

// ---------- settings forms ----------

/** The three model roles of the AI settings, and the parts of a model's price (US$ per million tokens). */
export const AI_MODEL_ROLES = ["regular", "deep", "quick"] as const;
export type AiModelRole = (typeof AI_MODEL_ROLES)[number];
export const PRICE_PARTS = ["in", "out", "cache_read", "cache_write"] as const;
type PricePart = (typeof PRICE_PARTS)[number];
type PriceKey = `price_${AiModelRole}_${PricePart}`;
/** The form fields of the prices, price_<role>_<part>. */
export const AI_PRICE_KEYS = AI_MODEL_ROLES.flatMap((r) => PRICE_PARTS.map((p) => `price_${r}_${p}` as PriceKey));
type ModelPrice = NonNullable<AiSettings["prices_per_mtok"]>[string];

/** An optional price field: empty is "not given", otherwise 0 to 1000. */
const price = z.preprocess((v) => (v == null || (typeof v === "string" && v.trim() === "") ? undefined : v),
  z.coerce.number({ error: "0 to 1000" }).min(0, "0 to 1000").max(1000, "0 to 1000").optional());

/** One role's price from the parsed form, or null unless both in and out are given. */
function rolePrice(d: Partial<Record<PriceKey, number>>, role: AiModelRole): ModelPrice | null {
  const v = (part: PricePart) => d[`price_${role}_${part}`];
  const pin = v("in"), pout = v("out"), cr = v("cache_read"), cw = v("cache_write");
  if (pin === undefined || pout === undefined) return null;
  return { in: pin, out: pout, ...(cr !== undefined ? { cache_read: cr } : {}), ...(cw !== undefined ? { cache_write: cw } : {}) };
}

/* Every number goes through reqNum (C63): a blank field is an error, never 0. min_gain_pct and max_per_day keep their default
   for a form that does not carry them (the default applies only when the field is absent, not when it is blank). */
export const AiSettingsSchema = z.object({
  enabled: z.string().optional().transform((v) => v === "on"),
  mode: z.enum(["advisory", "autopilot"]).default("advisory"),
  min_gain_pct: reqNum("1 to 50%").pipe(z.number().min(1, "1 to 50%").max(50, "1 to 50%")).default(3),
  max_per_day: reqNum("1 to 10").pipe(z.number().int("1 to 10").min(1, "1 to 10").max(10, "1 to 10")).default(3),
  daily_budget_usd: reqNum("$0 to $200").pipe(z.number().min(0, "$0 to $200").max(200, "$0 to $200")),
  worker_url: z.string().trim().max(300).refine((v) => v === "" || /^https:\/\/[^\s/]+(\/\S*)?$/.test(v), "Starts with https://"),
  model_regular: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  model_deep: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  model_quick: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  light: z.string().optional().transform((v) => v === "on"),
  hourly: z.string().optional().transform((v) => v === "on"),
  nightly: z.string().optional().transform((v) => v === "on"),
  weekly: z.string().optional().transform((v) => v === "on"),
  price_regular_in: price, price_regular_out: price, price_regular_cache_read: price, price_regular_cache_write: price,
  price_deep_in: price, price_deep_out: price, price_deep_cache_read: price, price_deep_cache_write: price,
  price_quick_in: price, price_quick_out: price, price_quick_cache_read: price, price_quick_cache_write: price,
  reason: z.string().trim().min(3, "Say why").max(300),
}).superRefine((d, ctx) => {
  // a price is in and out (cache optional); two roles on the same model must agree on its price
  const seen = new Map<string, (number | undefined)[]>();
  for (const role of AI_MODEL_ROLES) {
    const parts = PRICE_PARTS.map((part) => d[`price_${role}_${part}`]);
    if (parts.every((x) => x === undefined)) continue;
    for (const part of ["in", "out"] as const) {
      if (d[`price_${role}_${part}`] === undefined) ctx.addIssue({ code: "custom", path: [`price_${role}_${part}`], message: "Give the in and out prices" });
    }
    const model = d[`model_${role}`], prev = seen.get(model);
    const differs = prev ? PRICE_PARTS.findIndex((_, i) => prev[i] !== parts[i]) : -1;
    if (differs >= 0) ctx.addIssue({ code: "custom", path: [`price_${role}_${PRICE_PARTS[differs]}`], message: "Same model as above: give it the same prices" });
    if (!prev) seen.set(model, parts);
  }
});

/** ai_settings_save's payload. autopilot carries only min_gain_pct and max_per_day: the database keeps min_support (and min_decisions). */
export function aiSettingsPayload(d: z.infer<typeof AiSettingsSchema>) {
  // prices keyed by the chosen model names; a role left blank adds none (the database keeps the stored price)
  const prices: Record<string, ModelPrice> = {};
  for (const role of AI_MODEL_ROLES) {
    const pr = rolePrice(d, role);
    if (pr && !prices[d[`model_${role}`]]) prices[d[`model_${role}`]] = pr;
  }
  return {
    enabled: d.enabled, mode: d.mode, daily_budget_usd: d.daily_budget_usd, worker_url: d.worker_url,
    autopilot: { min_gain_pct: d.min_gain_pct, max_per_day: d.max_per_day },
    models: { regular: d.model_regular, deep: d.model_deep, quick: d.model_quick },
    schedules: { light: d.light, hourly: d.hourly, nightly: d.nightly, weekly: d.weekly },
    ...(Object.keys(prices).length ? { prices_per_mtok: prices } : {}),
  };
}

export const MlSettingsSchema = z.object({
  min_outcomes: z.coerce.number().int().min(100, "100 to 100000").max(100000, "100 to 100000"),
  challenger_pct: z.coerce.number().min(1, "1 to 50%").max(50, "1 to 50%"),
  ece_fallback: z.coerce.number().min(0.01, "0.01 to 0.30").max(0.3, "0.01 to 0.30"),
  train_hour_ist: z.coerce.number().int().min(0, "0 to 23").max(23, "0 to 23"),
  auto_train: z.string().optional().transform((v) => v === "on"),
  reason: z.string().trim().min(3, "Say why (3 characters or more)").max(500),
});
export function mlSettingsPayload(d: z.infer<typeof MlSettingsSchema>) {
  return { min_outcomes: d.min_outcomes, challenger_share: Math.round(d.challenger_pct * 10) / 1000, ece_fallback: d.ece_fallback, train_hour_ist: d.train_hour_ist, auto_train: d.auto_train };
}

/** What still stands between the Admin and a working optimiser. */
export function setupSteps(o: Pick<AiOverview, "settings" | "worker" | "worker_key">): { label: string; done: boolean }[] {
  return [
    { label: "An API key with the AI optimiser worker scope (System → API keys), set as AI_WORKER_KEY on the server", done: o.worker_key && !!o.worker?.seen_at },
    { label: "ANTHROPIC_API_KEY set on the server (Vercel project settings)", done: !!o.worker?.has_anthropic_key },
    { label: "The worker address (the CRM's https:// address) in AI settings", done: !!o.settings.worker_url },
    { label: "The optimiser switched on", done: o.settings.enabled },
  ];
}

export type AskHistoryItem = { id: number; at: string; status: string; question: string; answer: string | null; sources: { metric: string; dims?: string[]; period?: string }[] | null;
                               cost_usd: number; unverified: string[] | null; error: string | null };

/** The 7-day review in words. */
export function reviewText(c: Recommendation["check_result"]): string | null {
  if (!c?.verdict) return null;
  const inr = (v: number | null | undefined) => `₹${Math.round(v ?? 0).toLocaleString("en-IN")}`;
  const nums = c.steered && c.holdout ? ` (AI-steered ${inr(c.steered.expected_ncpl)} on ${c.steered.leads} leads, holdout ${inr(c.holdout.expected_ncpl)} on ${c.holdout.leads})` : "";
  switch (c.verdict) {
    case "waiting": return `7-day review: too few leads yet, checked again next week${nums}`;
    case "kept": return `7-day review: kept${nums}`;
    case "inconclusive": return `7-day review: inconclusive after three weeks, kept${nums}`;
    case "worse": return `7-day review: did worse than the holdout${c.auto_rolled_back ? ", rolled back automatically" : c.not_rolled_back ? ` (not rolled back: ${c.not_rolled_back})` : "; consider rolling it back"}${nums}`;
  }
}
