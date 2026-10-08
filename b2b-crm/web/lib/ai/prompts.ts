/**
 * Claude optimiser prompts and tools (spec B7.8.2, Addendum 3). Versioned: every run logs PROMPT_VERSION. Claude reads only
 * the aggregated, pseudonymised tools below and answers through submit_report (structured output). Data tools are read-only;
 * nothing Claude returns is applied until an Admin approves it (Advisory) or Autopilot's gates pass. The levers, their
 * bounds and the fixed numbers mirror m31m ai_validate_change and engine.a3_fixed (m31a).
 */

export const PROMPT_VERSION = "opt-2026-10-08.1";

export type RunKind = "light_check" | "optimise" | "deep_review" | "weekly_report";

/** The Addendum 3 levers: five settings at engine_policy.ai.<lever> and two drafts. Pins, share caps, partner weights,
 *  per-segment exploration, the maturity window and the speed/reliability switches were retired (D24). */
export const LEVERS = ["effort_weights", "effort_bounds", "sla_floor", "half_life_days", "prior_weight", "rule_draft", "pause_draft"] as const;
export type Lever = (typeof LEVERS)[number];

/** The six sales-effort metrics, in the engine's order (m31c effort_detail; lib/segments EFFORT_METRICS). */
export const EFFORT_METRIC_KEYS = ["first_call", "attempts_72h", "connect_rate", "followup", "acts_per_open", "stale_share"] as const;

/** The lever bounds BASE states (C100): the validator allows them as quoted facts, in the units BASE uses. */
export const LEVER_BOUND_FACTS: number[] = [0.8, 1, 0.85, 1.15, 0, 5, 14, 60, 5, 50, 80, 100];
/**
 * Every number BASE states as a fixed fact, which Claude may quote without a tool result: the lever bounds and the Addendum 3
 * stage numbers (20 leads / 7 days for Stage B, 30 matured / 60 days / 2 partners for Stage C, the 20% lane, the SLA step of
 * 0.05 per 10 points, 72 h). The validator allows them (worker.ts).
 */
export const PROMPT_FACTS: number[] = [...LEVER_BOUND_FACTS, 20, 7, 30, 2, 0.2, 10, 0.05, 72];

const BASE = `You are the allocation optimiser of Eduwit's B2B partner CRM. Eduwit sends qualified student leads (people
interested in online and distance degree programmes in India) to partner companies that sell those programmes, and earns
a commission when a student enrols. Your goal is to maximise realised net commission per lead (NCPL), honestly measured.

How routing works (Addendum 3; these rules are fixed and not yours to change):
- Rules come first: consent, duplicates and the partner bar, attempt and partner limits, the hand-off to Eduwit's B2C CRM,
  partner capacity, contracts and criteria, commission rates, the Admin's routing rules and the live switches.
- Partner choice is deterministic: the highest score wins. Each programme segment (course|level|mode, or with the
  university when it has enough data) moves through three stages:
  - Stage A, from the first lead: the highest commission per enrolment (CPE, net of GST) wins.
  - Stage B, once every competing partner has received 20 leads in the segment and the oldest is 7 days old:
    score = CPE × sales-effort factor × SLA-adherence factor.
  - Stage C, once 2 competing partners each have 30 matured leads (routed more than 60 days ago):
    score = CPE × P(enrol) × (1 − refund rate) × sales-effort factor × SLA-adherence factor. P(enrol) is the partner's
    recency-weighted conversion in the segment (P̂, with a prior), or the per-lead model's prediction once that model
    passes its gate.
- Ties: higher CPE, then better SLA adherence, then fewer leads this week.
- The sales-effort factor (1.0 = segment median) compares six metrics over 30 days against the segment: minutes to the
  first call, calls within 72 h, connect rate, follow-ups worked on their date, activities per open lead per week, and
  open leads quiet for 7 days. A partner that syncs no activity is capped at 1.0. The SLA-adherence factor starts at 1.0
  and steps down by 0.05 for every 10 points of adherence below 100%, down to the floor.
- Exploration lane: while a competing partner has fewer than 30 leads in the segment, 20% of the segment's leads go to
  the under-tested partner with the highest CPE. The 20% is fixed.
- A holdout of leads always uses the Admin's settings without any AI change, so your value is measured against it.
- Fixed by Addendum 3 (never propose them): the stage gates, the 20% lane, the 60-day maturity, attempt and partner
  limits, hold windows, the duplicate window, the lost grace and the consent wait.

What you may propose (each is a recommendation an Admin approves, edits or rejects, or Autopilot applies when its gates
pass). The Admin owns the bounds and weights; you may tune them only inside the Admin's current settings, which lie
inside these ranges:
- effort_weights: a weight from 0 to 5 per effort metric (first_call, attempts_72h, connect_rate, followup,
  acts_per_open, stale_share), not all 0;
- effort_bounds: [low, high] of the sales-effort factor, low between the Admin's low and 1, high between 1 and the
  Admin's high (never outside 0.85 to 1.15);
- sla_floor: the SLA-adherence factor's floor, between the Admin's floor and ceiling (never outside 80% to 100%; send a
  fraction, 0.85 = 85%);
- half_life_days: the recency half-life of P̂, 14 to 60 days;
- prior_weight: the prior strength of P̂, 5 to 50 leads;
- rule_draft (keep, narrow or exclude partners for some leads; created inactive for the Admin to review);
- pause_draft (pause a partner, with the reason).
Nothing else exists: there are no segment pins, share caps, partner weights, exploration shares or speed and
reliability switches any more. Never propose anything else, never message students or partners, and never ask for
personal data: leads appear only as pseudonyms (L-xxxxxxxx).

Rules for your answer:
1. Every number you write must come from a tool result in this run. Do not compute new numbers yourself (no sums,
   differences or ratios that a tool did not return); quote tool numbers as they are or rounded. A validator rejects the
   whole run if a number cannot be traced to a tool.
2. Before proposing any setting change, call run_simulation with exactly that change and cite its result: NCPL now and
   with the change, the 95% interval and the support (the share of replayed decisions the log can speak for). If it
   says there is not enough data or support, say so and prefer no change. The half-life cannot be replayed (the holdout
   measures it): propose it only with a clear reason from the scorecards.
3. Prefer no recommendation over a weak one. Small data means wide uncertainty: say so.
4. Finish by calling submit_report once. Write plainly for a busy business owner: short sentences, no jargon.`;

const BY_KIND: Record<RunKind, string> = {
  light_check: `This is a light check because new alerts arrived. Look at the alerts and partner scorecards only as needed.
Report anomalies in one or two findings (e.g. a partner's SLA or duplicate rate jumped). Recommend a pause_draft only for
a clear, current problem. Keep it short and use few tool calls.`,
  optimise: `This is the hourly optimisation pass. Review segment and partner scorecards, sales effort, settings and recent
decisions; look for effort metrics whose weight should change, factor bounds or an SLA floor worth testing, or a P̂
half-life or prior strength that fits the data better. Simulate before recommending. At most 3 recommendations.`,
  deep_review: `This is the nightly deep review. Review every segment and its stage, partner cohorts, sales effort and SLA,
model metrics, the uplift against the holdout and recent changes. Explain what is working and what is not, then recommend
at most 5 changes, each simulated.`,
  weekly_report: `This is the weekly partner-performance report for Eduwit's management. Summarise each active partner's
leads, contact and enrolment progress, sales effort, SLA and duplicate behaviour (sales_effort tool), and money (from the
tools), and the AI's measured uplift. Findings carry the report; recommendations are optional.`,
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

/** The window of a replay or an uplift: matured decisions only, so their outcomes are known (C23). */
export const MATURED_DAYS_TEXT = "days of matured decisions (routed more than 60 days ago)";

const maturedSegmentDays: JsonSchema = {
  type: "object",
  properties: {
    segment: { type: "string", description: "Optional segment key course|level|mode, e.g. mba|PG|Online" },
    days: { type: "integer", minimum: 30, maximum: 365, description: `${MATURED_DAYS_TEXT}; default 180` },
  },
  additionalProperties: false,
};

const change: JsonSchema = {
  type: "object",
  properties: {
    lever: { type: "string", enum: [...LEVERS] },
    value: { description: "effort_weights: an object {metric: weight} over first_call, attempts_72h, connect_rate, followup, acts_per_open, stale_share (0 to 5 each); effort_bounds: [low, high]; sla_floor: a fraction (0.85 = 85%); half_life_days: whole days; prior_weight: leads" },
    partner_id: { type: "integer", description: "pause_draft only" },
    rule: { type: "object", description: "rule_draft only: {name, action: fix_partner|narrow|exclude, partner_ids, conditions}" },
    reason: { type: "string", description: "pause_draft only" },
  },
  required: ["lever"],
};

export const DATA_TOOLS: ToolDef[] = [
  { name: "segment_scorecards", description: "Per segment: stage (A, B or C) and progress to the next stage, leads, matured leads, average enrolment rate, partners with matured data.", input_schema: segmentDays },
  { name: "partner_scorecards", description: "Per partner: leads, accepted, duplicates, rejections, SLA, enrolments, P̂ per segment, refund rate; per segment the leads received, effort factor, whether activity is synced, SLA adherence and factor.", input_schema: segmentDays },
  { name: "sales_effort", description: "Per partner: the six effort metrics routing uses (value vs median, sample, effort factor, whether activity is synced) and SLA adherence with its factor; plus raw activity over accepted leads (hours to first attempt median/p90, attempts in 24 h and 72 h, connect rate, stale share, activities in 7 days).", input_schema: segmentDays },
  { name: "conversion_cohorts", description: "By month and partner: leads and how many reached contacted, interested, applied, enrolled.", input_schema: segmentDays },
  { name: "commission_rates", description: "Median commission per partner and course (net of GST, INR); with a segment, the CPE per programme with its tier basis and fee source.", input_schema: segmentDays },
  { name: "engine_settings", description: "The Admin's engine settings, your levers (the AI policy), the effective parameters, the numbers fixed by Addendum 3, recent change history with reasons, and your bounds.", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  { name: "model_metrics", description: "The per-lead model registry: status, holdout metrics against segment P̂, gate, monitoring.", input_schema: { type: "object", properties: {}, additionalProperties: false } },
  { name: "recent_decisions", description: "Recent routing decisions without personal data (pseudonymous lead ids): stage, reason code, winner, and each candidate's CPE, P(enrol), factors, score and propensity.", input_schema: { type: "object", properties: { segment: { type: "string" }, limit: { type: "integer", minimum: 1, maximum: 200 } }, additionalProperties: false } },
  { name: "alerts", description: "Alerts of the last days (SLA breaches, auto-pauses, NCPL drops, sync problems).", input_schema: segmentDays },
  { name: "uplift", description: "Realised net commission per matured lead: AI-steered against the holdout, overall and by month, with a 95% interval of the difference.", input_schema: maturedSegmentDays },
  { name: "run_simulation", description: "Replays logged, matured decisions under one proposed setting change, doubly robust against the current policy: NCPL now and with the change, the difference with a 95% interval, decisions used and affected, effective sample size, and the support (share of decisions the log can speak for). The half-life cannot be replayed.",
    input_schema: { type: "object", properties: { change, days: { type: "integer", minimum: 7, maximum: 365, description: `${MATURED_DAYS_TEXT}; default 90` } }, required: ["change"], additionalProperties: false } },
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

export type Evidence = { tool?: string; metric?: string; value?: string | number | boolean };
export type Report = {
  summary: string;
  findings: { title: string; detail: string; evidence?: Evidence[] }[];
  recommendations: { title: string; rationale: string; risk?: string; evidence?: Evidence[]; change?: Record<string, unknown> }[];
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
  // evidence items are objects {tool, metric, value} with a text tool and metric and a scalar value; anything else is dropped
  const ev = (v: unknown): Evidence[] => arr(v).slice(0, 10).flatMap((e) => {
    if (!e || typeof e !== "object" || Array.isArray(e)) return [];
    const x = e as Record<string, unknown>;
    const value = typeof x.value === "number" || typeof x.value === "string" || typeof x.value === "boolean" ? x.value : undefined;
    return [{ tool: s(x.tool, 60) || undefined, metric: s(x.metric, 120) || undefined, value }];
  });
  return {
    summary: s(o.summary, 2000),
    findings: arr(o.findings).slice(0, 10).flatMap((f) => {
      const x = f as Record<string, unknown>;
      return s(x?.title, 200) && s(x?.detail, 3000) ? [{ title: s(x.title, 200), detail: s(x.detail, 3000), evidence: ev(x.evidence) }] : [];
    }),
    recommendations: arr(o.recommendations).slice(0, 5).flatMap((r) => {
      const x = r as Record<string, unknown>;
      if (!s(x?.title, 200) || !s(x?.rationale, 3000)) return [];
      const c = x.change && typeof x.change === "object" && !Array.isArray(x.change) ? (x.change as Record<string, unknown>) : undefined;
      return [{ title: s(x.title, 200), rationale: s(x.rationale, 3000), risk: s(x.risk, 1000) || undefined, evidence: ev(x.evidence), change: c }];
    }),
  };
}
