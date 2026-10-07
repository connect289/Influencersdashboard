import { z } from "zod";

/** AI Optimiser screen: types, labels and form parsing (B14.3). Pure; shared by the page, actions and tests. */

export type RecStatus = "open" | "applied" | "rejected" | "expired" | "rolled_back" | "superseded";
export type Change = {
  lever: string; segment?: string; partner_id?: number; value?: unknown; until?: string; reason?: string;
  rule?: { name: string; action: string; partner_ids: number[]; conditions: Record<string, unknown>; priority?: number };
};
export type Simulation = {
  simulated: boolean; why?: string; decisions?: number; ncpl_now?: number; ncpl_new?: number; difference?: number;
  ci95?: [number, number]; gain_pct?: number | null; ess?: number; enough?: boolean;
};
export type Recommendation = {
  id: number; run_id: number; run_kind?: string; kind: "setting_change" | "rule_draft" | "pause_draft" | "insight"; status: RecStatus;
  title: string; rationale: string; evidence: { tool?: string; metric?: string; value?: unknown }[]; change: Change | null;
  simulation: Simulation | null; risk: string | null; expires_at: string; decided_by: string | null; decided_at: string | null;
  decision_note: string | null; applied: { version?: number; from?: unknown; to?: unknown; edited?: boolean; rule_id?: string } | null;
  check_due_at: string | null; created_at: string;
  check_result?: { verdict?: "waiting" | "kept" | "worse" | "inconclusive"; z?: number | null; auto_rolled_back?: boolean;
                   steered?: { leads: number; expected_ncpl: number | null }; holdout?: { leads: number; expected_ncpl: number | null } } | null;
};
export type AiRun = {
  id: number; trigger: string; kind: string; model: string; status: string; created_at: string; finished_at: string | null; tools: number;
  tokens_in: number; tokens_out: number; cost_usd: number; error: string | null; summary: string | null; recommendations: number[] | null;
};
export type Uplift = {
  maturity_days: number; steered: { leads: number; ncpl: number }; holdout: { leads: number; ncpl: number }; uplift_pct: number | null; z: number;
  by_month: { month: string; steered: number | null; holdout: number | null; steered_n: number; holdout_n: number }[];
};
export type AiSettings = {
  enabled: boolean; mode: "advisory" | "autopilot"; autopilot?: { min_gain_pct: number; max_per_day: number; min_decisions?: number }; models: { regular: string; deep: string; quick: string }; daily_budget_usd: number;
  schedules: { light: boolean; hourly: boolean; nightly: boolean; weekly: boolean }; worker_url: string | null; max_turns?: number;
};
export type AiOverview = {
  settings: AiSettings; settings_version: number;
  worker: { seen_at?: string; has_anthropic_key?: boolean; updated_at?: string } | null; worker_key: boolean;
  spend: { today_usd: number; month_usd: number }; uplift: Uplift; holdout_share: number | null;
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
  trained_on: { rows?: number; enrolled?: number; train?: number; valid?: number; partners?: number; from?: string; to?: string };
  gate: { outcomes?: number; min_outcomes?: number; outcomes_ok?: boolean; partners?: number; partners_ok?: boolean; beats_baseline?: boolean; policy_value_ok?: boolean; passed?: boolean };
  metrics: {
    holdout?: { n: number; log_loss: number; ece: number; mean_p: number; mean_y: number; deciles: { bin: number; pred: number; actual: number; n: number }[] };
    baseline?: { log_loss: number; ece: number };
    policy?: { decisions: number; agree: number; logged_value: number; model_value: number; ess: number };
    top_weights?: { feature: string; w: number }[];
    monitor?: { at: string; matured?: { n: number; ece: number }; mean_p_30d?: number };
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
export const TRIGGER_LABEL: Record<string, string> = {
  light: "new alerts", hourly: "hourly", nightly: "nightly", weekly: "weekly", event: "an event", manual: "by hand", ask: "a question",
};
export const REC_STATUS_LABEL: Record<RecStatus, string> = {
  open: "Open", applied: "Applied", rejected: "Rejected", expired: "Expired", rolled_back: "Rolled back", superseded: "Superseded",
};
export const MODEL_STATUS_LABEL: Record<MlModel["status"], string> = {
  training: "Training", shadow: "Shadow", challenger: "Challenger", champion: "Champion", retired: "Retired", failed: "Failed",
};

const pct = (v: unknown) => (typeof v === "number" ? `${Math.round(v * 1000) / 10}%` : String(v));

/** A change in plain words. names: partner id → name. */
export function describeChange(c: Change | null, names: Record<string, string> = {}): string {
  if (!c) return "No change: an observation";
  const seg = c.segment ? ` for ${c.segment.split("|").map((x, i) => (x === "*" ? "any" : i === 0 ? x.toUpperCase() : x)).join(" · ")}` : "";
  const partner = c.partner_id != null ? names[String(c.partner_id)] ?? `partner #${c.partner_id}` : "";
  const until = c.until ? ` until ${new Date(c.until).toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "Asia/Kolkata" })}` : "";
  switch (c.lever) {
    case "exploration_share": return `Exploration share ${pct(c.value)}${seg}`;
    case "segment_pin": return `Pin${seg} to ${c.value === "performance" ? "performance" : "commission first"}${until}`;
    case "partner_weight": return `Weight ${partner} at ${pct(c.value)}${until}`;
    case "share_cap": return c.value == null ? `Remove the share cap${seg}` : `Share cap ${pct(c.value)}${seg}`;
    case "maturity_days": return `Maturity ${c.value} days`;
    case "half_life_days": return `Recency half-life ${c.value} days`;
    case "prior_weight": return `Prior strength ${c.value} leads`;
    case "speed_factor": return `Speed factor ${c.value ? "on" : "off"}`;
    case "reliability_factor": return `Reliability factor ${c.value ? "on" : "off"}`;
    case "rule_draft": return `Draft rule “${c.rule?.name ?? ""}” (created inactive)`;
    case "pause_draft": return `Pause ${partner}`;
    default: return c.lever;
  }
}

export const rupees = (n: number | null | undefined) => (n == null || !Number.isFinite(n) ? "—" : `₹${Math.round(n).toLocaleString("en-IN")}`);
const signedRupees = (n: number) => `${n < 0 ? "−" : "+"}${rupees(Math.abs(n))}`;

/** The simulated impact in words, or why there is none. */
export function simulationText(s: Simulation | null): string {
  if (!s) return "Not simulated";
  if (!s.simulated) return s.why ?? "Cannot be simulated";
  if (!s.decisions) return "No matured decisions to replay yet";
  const ci = s.ci95 ? ` (95%: ${signedRupees(s.ci95[0])} to ${signedRupees(s.ci95[1])})` : "";
  return `NCPL ${rupees(s.ncpl_now)} → ${rupees(s.ncpl_new)}${s.gain_pct != null ? `, ${s.gain_pct >= 0 ? "+" : "−"}${Math.abs(s.gain_pct)}%` : ""}${ci} on ${s.decisions} decisions${s.enough ? "" : ": too few to rely on"}`;
}

/** "expires in 6 days" / "expires in 5 h" / "expired". */
export function expiresText(at: string, now = new Date()): string {
  const ms = new Date(at).getTime() - now.getTime();
  if (!Number.isFinite(ms) || ms <= 0) return "expired";
  const d = Math.floor(ms / 86_400_000);
  return d >= 1 ? `expires in ${d} day${d === 1 ? "" : "s"}` : `expires in ${Math.max(1, Math.round(ms / 3_600_000))} h`;
}

/** Whether the change could be edited in the inbox: numeric levers only. */
export const editable = (c: Change | null) => !!c && ["exploration_share", "partner_weight", "share_cap", "maturity_days", "half_life_days", "prior_weight"].includes(c.lever);

/** The inbox's edit field (what the Admin types) → the change's value. */
export function editedChange(c: Change, typed: string): Change | string {
  const n = Number(typed.trim().replace("%", ""));
  if (!typed.trim() || !Number.isFinite(n)) return "Enter a number";
  const asFraction = ["exploration_share", "partner_weight", "share_cap"].includes(c.lever);
  return { ...c, value: asFraction ? Math.round(n * 10) / 1000 : n };
}

export const AiSettingsSchema = z.object({
  enabled: z.string().optional().transform((v) => v === "on"),
  mode: z.enum(["advisory", "autopilot"]).default("advisory"),
  min_gain_pct: z.coerce.number().min(1, "1 to 50%").max(50, "1 to 50%").default(3),
  max_per_day: z.coerce.number().int().min(1, "1 to 10").max(10, "1 to 10").default(3),
  daily_budget_usd: z.coerce.number().min(0, "$0 to $200").max(200, "$0 to $200"),
  worker_url: z.string().trim().max(300).refine((v) => v === "" || /^https:\/\/[^\s/]+(\/\S*)?$/.test(v), "Starts with https://"),
  model_regular: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  model_deep: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  model_quick: z.string().trim().regex(/^claude-[a-z0-9.-]{3,60}$/, "A claude-… model name"),
  light: z.string().optional().transform((v) => v === "on"),
  hourly: z.string().optional().transform((v) => v === "on"),
  nightly: z.string().optional().transform((v) => v === "on"),
  weekly: z.string().optional().transform((v) => v === "on"),
  reason: z.string().trim().min(3, "Say why").max(300),
});

export function aiSettingsPayload(d: z.infer<typeof AiSettingsSchema>) {
  return {
    enabled: d.enabled, mode: d.mode, daily_budget_usd: d.daily_budget_usd, worker_url: d.worker_url,
    autopilot: { min_gain_pct: d.min_gain_pct, max_per_day: d.max_per_day },
    models: { regular: d.model_regular, deep: d.model_deep, quick: d.model_quick },
    schedules: { light: d.light, hourly: d.hourly, nightly: d.nightly, weekly: d.weekly },
  };
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
    case "worse": return `7-day review: did worse than the holdout${c.auto_rolled_back ? ", rolled back automatically" : "; consider rolling it back"}${nums}`;
  }
}
