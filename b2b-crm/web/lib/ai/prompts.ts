/**
 * Claude optimiser prompts and tools (spec B7.8.2). Versioned: every run logs PROMPT_VERSION. Claude reads only the
 * aggregated, pseudonymised tools below and answers through submit_report (structured output). Data tools are read-only;
 * nothing Claude returns is applied until an Admin approves it (Advisory).
 */

export const PROMPT_VERSION = "opt-2026-10-07.1";

export type RunKind = "light_check" | "optimise" | "deep_review" | "weekly_report";

export const LEVERS = [
  "exploration_share", "segment_pin", "partner_weight", "share_cap", "maturity_days", "half_life_days", "prior_weight",
  "speed_factor", "reliability_factor", "rule_draft", "pause_draft",
] as const;

const BASE = `You are the allocation optimiser of Eduwit's B2B partner CRM. Eduwit sends qualified student leads (people
interested in online and distance degree programmes in India) to partner companies that sell those programmes, and earns
a commission when a student enrols. Your goal is to maximise realised net commission per lead (NCPL), honestly measured.

How routing works:
- Rules come first and are not yours to change: consent, duplicates and attempt limits, the hand-off to Eduwit's B2C CRM,
  partner capacity and contracts, commission rates and live switches.
- Each segment (course|level|mode) is in commission-first mode (the highest commission wins, with an exploration lane
  for under-sampled partners) until 2 partners each have enough matured leads; then performance mode ranks partners by
  NCPL = P̂(enrol) × commission × (1 − refund rate), sampled from each partner's uncertainty (Thompson sampling).
- A holdout of leads always uses the Admin's settings without any AI change, so your value is measured against it.

What you may propose (each is a recommendation an Admin approves, edits or rejects):
- exploration_share for a segment (0 to 0.5); segment_pin to commission_first or performance (expires within 30 days);
  partner_weight 0.9 to 1.1 for up to 14 days with a reason; share_cap for a segment (0.5 to 1, or null to remove);
  maturity_days 30 to 90; half_life_days 14 to 60; prior_weight 5 to 50; speed_factor or reliability_factor on/off;
  rule_draft (keep/narrow/exclude partners for some leads; created inactive for the Admin to review);
  pause_draft (pause a partner, with the reason).
Never propose anything else, never message students or partners, and never ask for personal data: leads appear only as
pseudonyms (L-xxxxxxxx).

Rules for your answer:
1. Every number you write must come from a tool result in this run. Do not compute new numbers yourself (no sums,
   differences or ratios that a tool did not return); quote tool numbers as they are or rounded. A validator rejects the
   whole run if a number cannot be traced to a tool.
2. Before proposing any setting change, call run_simulation with exactly that change and cite its result. If it says
   there is not enough data, say so and prefer no change.
3. Prefer no recommendation over a weak one. Small data means wide uncertainty: say so.
4. Finish by calling submit_report once. Write plainly for a busy business owner: short sentences, no jargon.`;

const BY_KIND: Record<RunKind, string> = {
  light_check: `This is a light check because new alerts arrived. Look at the alerts and partner scorecards only as needed.
Report anomalies in one or two findings (e.g. a partner's SLA or duplicate rate jumped). Recommend a pause_draft only for
a clear, current problem. Keep it short and use few tool calls.`,
  optimise: `This is the hourly optimisation pass. Review segment and partner scorecards, settings and recent decisions;
look for segments where the flow of leads should shift, exploration that is too high or too low, or settings worth
testing. Simulate before recommending. At most 3 recommendations.`,
  deep_review: `This is the nightly deep review. Review every segment, partner cohorts, model metrics, the uplift against the
holdout and recent changes. Explain what is working and what is not, then recommend at most 5 changes, each simulated.`,
  weekly_report: `This is the weekly partner-performance report for Eduwit's management. Summarise each active partner's
leads, contact and enrolment progress, SLA and duplicate behaviour, and money (from the tools), and the AI's measured
uplift. Findings carry the report; recommendations are optional.`,
};

export function systemPrompt(kind: RunKind): string {
  return `${BASE}\n\n${BY_KIND[kind]}`;
}

export function userPrompt(kind: RunKind, context: Record<string, unknown>, now = new Date()): string {
  const ctx = Object.keys(context).length ? `\nContext: ${JSON.stringify(context)}` : "";
  return `Run: ${kind}. Time: ${now.toISOString()}.${ctx}\nStart by calling the tools you need.`;
}

type JsonSchema = Record<string, unknown>;
export type ToolDef = { name: string; description: string; input_schema: JsonSchema };

const segmentDays: JsonSchema = {
  type: "object",
  properties: {
    segment: { type: "string", description: "Optional segment key course|level|mode, e.g. mba|PG|Online" },
    days: { type: "integer", minimum: 1, maximum: 365 },
  },
  additionalProperties: false,
};

const change: JsonSchema = {
  type: "object",
  properties: {
    lever: { type: "string", enum: [...LEVERS] },
    segment: { type: "string" },
    partner_id: { type: "integer" },
    value: { description: "number, boolean or mode name, depending on the lever" },
    until: { type: "string", description: "ISO time the change ends (pins within 30 days, weights within 14)" },
    rule: { type: "object", description: "rule_draft only: {name, action: fix_partner|narrow|exclude, partner_ids, conditions}" },
    reason: { type: "string", description: "pause_draft only" },
  },
  required: ["lever"],
};

export const DATA_TOOLS: ToolDef[] = [
  { name: "segment_scorecards", description: "Per segment: mode, leads, matured leads, average enrolment rate, partners with matured data, policy.", input_schema: segmentDays },
  { name: "partner_scorecards", description: "Per partner: leads, accepted, duplicates, rejections, SLA, enrolments, P̂ per segment, refund rate, speed, reliability, weight.", input_schema: segmentDays },
  { name: "conversion_cohorts", description: "By month and partner: leads and how many reached contacted, interested, applied, enrolled.", input_schema: segmentDays },
  { name: "commission_rates", description: "Median commission per partner and course (net of GST, INR).", input_schema: segmentDays },
  { name: "engine_settings", description: "Engine settings, the AI policy, effective parameters, recent change history with reasons, and the bounds.", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  { name: "model_metrics", description: "The per-lead model registry: status, holdout metrics against segment P̂, gate, monitoring.", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  { name: "recent_decisions", description: "Recent routing decisions without personal data (pseudonymous lead ids).", input_schema: { type: "object", properties: { segment: { type: "string" }, limit: { type: "integer", minimum: 1, maximum: 200 } }, additionalProperties: false } },
  { name: "alerts", description: "Alerts of the last days (SLA breaches, auto-pauses, NCPL drops, sync problems).", input_schema: segmentDays },
  { name: "uplift", description: "Realised net commission per matured lead: AI-steered against the holdout, overall and by month.", input_schema: segmentDays },
  { name: "run_simulation", description: "Replays logged, matured decisions under one proposed change (inverse propensity): NCPL now and with the change, the difference with a 95% interval, decisions used, effective sample size.",
    input_schema: { type: "object", properties: { change, days: { type: "integer", minimum: 7, maximum: 365 } }, required: ["change"], additionalProperties: false } },
];

export const SUBMIT_TOOL: ToolDef = {
  name: "submit_report",
  description: "Your final answer. Call exactly once, at the end.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "Two to four sentences." },
      findings: { type: "array", maxItems: 10, items: { type: "object", properties: {
        title: { type: "string" }, detail: { type: "string" },
        evidence: { type: "array", items: { type: "object", properties: { tool: { type: "string" }, metric: { type: "string" }, value: {} } } },
      }, required: ["title", "detail"] } },
      recommendations: { type: "array", maxItems: 5, items: { type: "object", properties: {
        title: { type: "string" }, rationale: { type: "string" }, risk: { type: "string" },
        evidence: { type: "array", items: { type: "object", properties: { tool: { type: "string" }, metric: { type: "string" }, value: {} } } },
        change,
      }, required: ["title", "rationale"] } },
    },
    required: ["summary", "findings", "recommendations"],
  },
};

export const ALL_TOOLS: ToolDef[] = [...DATA_TOOLS, SUBMIT_TOOL];
export const DATA_TOOL_NAMES = new Set(DATA_TOOLS.map((t) => t.name));

export type Report = {
  summary: string;
  findings: { title: string; detail: string; evidence?: unknown[] }[];
  recommendations: { title: string; rationale: string; risk?: string; evidence?: unknown[]; change?: Record<string, unknown> }[];
};

/** The text the validator checks: everything a person reads. */
export function reportText(r: Report): string {
  return [
    r.summary,
    ...r.findings.flatMap((f) => [f.title, f.detail]),
    ...r.recommendations.flatMap((x) => [x.title, x.rationale, x.risk ?? ""]),
  ].join("\n");
}

/** A report as Claude sent it, made safe to store (types checked, lengths capped). */
export function normaliseReport(input: unknown): Report | null {
  if (!input || typeof input !== "object") return null;
  const o = input as Record<string, unknown>;
  const s = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");
  if (!s(o.summary, 2000)) return null;
  const arr = (v: unknown) => (Array.isArray(v) ? v : []);
  return {
    summary: s(o.summary, 2000),
    findings: arr(o.findings).slice(0, 10).flatMap((f) => {
      const x = f as Record<string, unknown>;
      return s(x?.title, 200) && s(x?.detail, 3000) ? [{ title: s(x.title, 200), detail: s(x.detail, 3000), evidence: arr(x.evidence).slice(0, 10) }] : [];
    }),
    recommendations: arr(o.recommendations).slice(0, 5).flatMap((r) => {
      const x = r as Record<string, unknown>;
      if (!s(x?.title, 200) || !s(x?.rationale, 3000)) return [];
      const c = x.change && typeof x.change === "object" && !Array.isArray(x.change) ? (x.change as Record<string, unknown>) : undefined;
      return [{ title: s(x.title, 200), rationale: s(x.rationale, 3000), risk: s(x.risk, 1000) || undefined, evidence: arr(x.evidence).slice(0, 10), change: c }];
    }),
  };
}
