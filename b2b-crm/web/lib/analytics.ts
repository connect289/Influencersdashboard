import { z } from "zod";
import { CONSENT_STATE_LABEL, HOLD_LABEL, REASON_LABEL } from "@/lib/routing";

/** Analytics (B13): metric results, widgets and dashboards, formatting, the formula parser and chart helpers. Pure. */

export type Unit = "count" | "pct" | "inr" | "hours" | "days" | "minutes" | "usd" | "number";
export type MetricMeta = { key: string; label: string; unit: Unit; area: string; higher_is_better: boolean; description: string | null; calculated: boolean };
export type MetricRow = { d: (string | null)[] | null; value: number | null; prev: number | null };
export type MetricResult = {
  metric: MetricMeta; dims: string[]; from: string; to: string; rows: MetricRow[]; total: { value: number | null; prev: number | null };
  labels: { partner: Record<string, string> };
  /** The period the numbers were run for (filled on the client side only, so drill links keep it). */
  period?: string;
  /** The date basis metric_run dated the rows by (Addendum 3, C70); null or absent means the metric's own date column. */
  date_basis?: DateBasis | null;
  /** The row cap metric_run applied, and whether rows were cut at it. */
  limit?: number; truncated?: boolean;
};
export type CatalogueMetric = MetricMeta & { fact: string | null; dims: string[]; formula: unknown };
export type Catalogue = { metrics: CatalogueMetric[]; facts_at: string | null };

export const WIDGET_TYPES = ["kpi", "line", "bar", "stacked", "funnel", "sankey", "heatmap", "table", "leaderboard", "map", "gauge", "sla_timers", "alerts", "text"] as const;
export type WidgetType = (typeof WIDGET_TYPES)[number];
export const PERIODS = ["today", "7d", "30d", "90d", "month", "quarter", "year"] as const;
export type Period = (typeof PERIODS)[number];
/** The date a number can be counted by (metric_run / metric_drill `date_basis`, C70): absent = the metric's own date column. */
export const DATE_BASES = ["created", "routed", "accepted", "enrolled"] as const;
export type DateBasis = (typeof DATE_BASES)[number];
export const DATE_BASIS_LABEL: Record<DateBasis, string> = { created: "Created", routed: "Routed", accepted: "Accepted", enrolled: "Enrolled" };
export const DATE_BASIS_HINT: Record<DateBasis, string> = {
  created: "Counted by the date the lead (or the allocation or enrolment) was created", routed: "Counted by the date the lead was routed to a partner or B2C",
  accepted: "Counted by the date the partner accepted the lead", enrolled: "Counted by the date the student enrolled",
};
/** The column a basis names on each fact: the same table as b2b.metric_date_col (m31o). A fact missing a basis cannot be dated by it. */
export const DATE_BASIS_COLUMN: Record<string, Partial<Record<DateBasis, string>>> = {
  fact_leads: { created: "created_at", routed: "routed_at", accepted: "accepted_at", enrolled: "enrolled_at" },
  fact_allocations: { created: "created_at", routed: "created_at", accepted: "accepted_at" },
  fact_enrollments: { created: "created_at", enrolled: "enrolled_at" },
};
export type Widget = {
  id: string; type: WidgetType; title?: string; metric?: string; metrics?: string[]; dims?: string[]; steps?: string[];
  filters?: Record<string, string[]>; period?: Period; date_basis?: DateBasis; sort?: string; target?: number; text?: string; w: number; h: number;
};
export type Dashboard = {
  id: number; slug: string; name: string; description: string | null; widgets: Widget[]; period: Period; filters: Record<string, string[]>;
  is_default: boolean; is_home?: boolean; updated_at: string;
};
export type WidgetData = { series?: MetricResult[]; rows?: Record<string, unknown>[]; from?: string; to?: string; error?: string };
export type DashboardData = { dashboard: Dashboard; data: Record<string, WidgetData>; facts_at: string | null };

export const PERIOD_LABEL: Record<Period, string> = {
  today: "Today", "7d": "Last 7 days", "30d": "Last 30 days", "90d": "Last 90 days", month: "This month", quarter: "This quarter", year: "Last 12 months",
};
export const WIDGET_LABEL: Record<WidgetType, string> = {
  kpi: "KPI tile", line: "Line chart", bar: "Bar chart", stacked: "Stacked bars", funnel: "Funnel", sankey: "Sankey (flow)", heatmap: "Heatmap / cohorts",
  table: "Table", leaderboard: "Leaderboard", map: "India map by state", gauge: "Gauge / target", sla_timers: "Live SLA timers", alerts: "Alerts", text: "Text or note",
};
/** Breakdown keys as people read them (every key of b2b.metric_dimensions(), m31o). `stage` is the stage a lead reached; the A/B/C
 *  scoring stage of Addendum 3 is `score_stage` (C90). */
export const DIM_LABEL: Record<string, string> = {
  // lead dimensions (fact_leads, and on allocations, SLAs, enrolments and money since Addendum 3)
  source: "Source", sub_source: "Sub-source", channel: "Channel", campaign: "Campaign", platform: "Ad platform", paid: "Paid", form: "Form", utm_source: "UTM source", utm_medium: "UTM medium",
  city: "City", state: "State", course: "Course", level: "Level", mode: "Mode", segment: "Segment", specialization: "Specialization", university: "University", programme: "Programme",
  lead_status: "Witty status", temperature: "Temperature", stage: "Stage", sub_stage: "Sub-stage", lost_reason: "Lost reason", language: "Language",
  destination: "Destination", b2c_lane: "B2C lane", b2c_reason: "Why sent to B2C", hold_kind: "B2C hold", partner_barred: "Partner-barred", consent_state: "Partner-sharing consent",
  not_passed_reason: "Why not passed", partner: "Partner",
  // allocation dimensions
  routing_mode: "Routing mode", attempt_no: "Attempt", status: "Status", holdout: "Holdout", scoring_mode: "Scoring mode", model_version: "Model", counsellor: "Counsellor",
  score_stage: "Scoring stage", origin: "How it was routed", from_b2c: "Sent from B2C",
  // the other facts
  product: "Product", sla: "SLA", due_hour: "Hour due", kind: "Kind", period: "Period", ageing: "Age", run_kind: "Run / recommendation type", rec_status: "Recommendation",
  day: "Day", week: "Week", month: "Month",
};
/** Breakdown values that are yes / no. */
export const BOOLEAN_DIMS = new Set(["holdout", "paid", "partner_barred", "from_b2c"]);
/** allocations.origin (CONTRACT 1.1): the request that routed the lead. */
export const ORIGIN_LABEL: Record<string, string> = {
  auto: "Automatically", pass: "Passed by the Admin (not-passed override)", to_partners: "Sent to partners by hand", requalify: "Re-qualified from B2C nurture",
  reroute: "Re-routed by the Admin", sandbox: "Test routing (sandbox)",
};
export const TIME_DIMS = new Set(["day", "week", "month"]);

/** A metric value as people read it. */
export function formatValue(v: number | null | undefined, unit: Unit, compact = false): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return "—";
  switch (unit) {
    case "pct": return `${(v * 100).toFixed(Math.abs(v) < 0.1 ? 1 : 0)}%`;
    case "inr": return compact && Math.abs(v) >= 100000 ? `₹${(v / 100000).toFixed(1)} L` : `₹${Math.round(v).toLocaleString("en-IN")}`;
    case "usd": return `$${v.toFixed(2)}`;
    case "hours": return `${v.toFixed(1)} h`;
    case "days": return `${v.toFixed(1)} d`;
    case "minutes": return `${v.toFixed(1)} min`;
    case "count": return Math.round(v).toLocaleString("en-IN");
    default: return Number.isInteger(v) ? v.toLocaleString("en-IN") : v.toFixed(2);
  }
}

/** Gauge targets are stored in the metric's own scale (a pct target as a fraction); the editor shows pct targets in percent. */
export function gaugeTargetInput(target: number | undefined, unit: Unit | undefined): string {
  if (target === undefined) return "";
  return String(unit === "pct" ? Math.round(target * 1e6) / 1e4 : target);
}
export function gaugeTargetValue(input: string, unit: Unit | undefined): number | undefined {
  if (input.trim() === "") return undefined;
  const n = Number(input);
  if (!Number.isFinite(n)) return undefined;
  return unit === "pct" ? n / 100 : n;
}

/** Change against the previous period: the arrow's direction and whether it is good. */
export function delta(value: number | null, prev: number | null, higherIsBetter: boolean, unit: Unit): { text: string; tone: "good" | "bad" | "flat" } | null {
  if (value === null || prev === null || !Number.isFinite(value) || !Number.isFinite(prev)) return null;
  const diff = value - prev;
  if (Math.abs(diff) < 1e-9) return { text: "no change", tone: "flat" };
  // a change too small to show at the display precision reads as no change, not "−0.0 pts"
  if (unit === "pct" ? Math.round(Math.abs(diff) * 1000) === 0 : prev !== 0 && Math.round(Math.abs(diff / prev) * 100) === 0) return { text: "no change", tone: "flat" };
  const sign = diff > 0 ? "+" : "−";
  const text = unit === "pct" ? `${sign}${Math.abs(diff * 100).toFixed(1)} pts`
    : prev !== 0 ? `${sign}${Math.abs((diff / Math.abs(prev)) * 100).toFixed(0)}%` : `${sign}${formatValue(Math.abs(diff), unit)}`;
  return { text, tone: (diff > 0) === higherIsBetter ? "good" : "bad" };
}

/** A breakdown value as a label (partner ids become names). */
export function dimLabel(dim: string, v: string | null | undefined, labels?: MetricResult["labels"]): string {
  if (v === null || v === undefined || v === "") return "(none)";
  if (dim === "partner") return labels?.partner?.[v] ?? `Partner #${v}`;
  if (dim === "month") return new Date(`${v}T00:00:00`).toLocaleDateString("en-IN", { month: "short", year: "2-digit" });
  if (dim === "day" || dim === "week") return new Date(`${v}T00:00:00`).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
  if (BOOLEAN_DIMS.has(dim)) return v === "true" ? "Yes" : "No";
  if (dim === "segment") return v.split("|").map((x, i) => (x === "*" ? "any" : i === 0 ? x.toUpperCase() : x)).join(" · ");
  if (dim === "course") return v.toUpperCase();
  if (dim === "score_stage") return `Stage ${v}`;
  if (dim === "b2c_reason") return REASON_LABEL[v] ?? v.replace(/_/g, " ");
  if (dim === "hold_kind") return HOLD_LABEL[v] ?? v.replace(/_/g, " ");
  if (dim === "consent_state") return CONSENT_STATE_LABEL[v] ?? v.replace(/_/g, " ");
  if (dim === "origin") return ORIGIN_LABEL[v] ?? v.replace(/_/g, " ");
  return v.replace(/_/g, " ");
}

/** The link that lists the rows behind a number; a date basis (C70) goes along so the list is dated like the widget. */
export function drillHref(metric: string, filters: Record<string, string[]>, from?: string, to?: string, period?: string, dateBasis?: DateBasis | string | null): string {
  const p = new URLSearchParams({ metric });
  if (Object.keys(filters).length) p.set("filters", JSON.stringify(filters));
  if (from) p.set("from", from);
  if (to) p.set("to", to);
  if (period) p.set("period", period);
  if (dateBasis) p.set("date_basis", dateBasis);
  return `/dashboards/drill?${p.toString()}`;
}

/** The date basis named in a URL, or undefined when none or unknown (the SQL would refuse an unknown one with 22023). */
export function dateBasisParam(v: string | string[] | undefined): DateBasis | undefined {
  return typeof v === "string" && (DATE_BASES as readonly string[]).includes(v) ? (v as DateBasis) : undefined;
}

/** Filters for one row or cell of a breakdown: its dimension values (time buckets included) added to the widget's filters.
 *  A null value filters on '(none)' (sent as "", which the SQL matches to NULL). */
export function rowFilters(base: Record<string, string[]>, dims: string[], d: (string | null)[] | null): Record<string, string[]> {
  const out = { ...base };
  dims.forEach((dim, i) => { const v = d?.[i]; if (v !== undefined) out[dim] = [v ?? ""]; });
  return out;
}

/** Dashboard filters that apply to a metric: only its own dimensions (same rule as widget_data). */
export function applicableFilters(filters: Record<string, unknown>, dims: string[]): Record<string, string[]> {
  return Object.fromEntries(Object.entries(filters).filter(([k, v]) => dims.includes(k) && Array.isArray(v) && v.every((x) => typeof x === "string"))) as Record<string, string[]>;
}

// ---------- the formula parser (calculated metrics) ----------
export type Token = { m: string } | { n: number } | { op: "+" | "-" | "*" | "/" };

/** "commission_realised / allocations * 100" → RPN tokens, or an error. Only metric keys, numbers, + - * / and brackets. */
export function parseFormula(text: string, known: Set<string>): Token[] | string {
  const src = text.trim();
  if (!src) return "Write a formula, e.g. commission_realised / allocations";
  const tokens = src.match(/[a-z][a-z0-9_]*|\d+(?:\.\d+)?|[()+\-*/]|\S/g) ?? [];
  const out: Token[] = [];
  const ops: string[] = [];
  const prec: Record<string, number> = { "+": 1, "-": 1, "*": 2, "/": 2 };
  let expectOperand = true;
  for (const t of tokens) {
    if (/^[a-z]/.test(t)) {
      if (!expectOperand) return `Missing an operator before ${t}`;
      if (!known.has(t)) return `Unknown metric: ${t}`;
      out.push({ m: t }); expectOperand = false;
    } else if (/^\d/.test(t)) {
      if (!expectOperand) return `Missing an operator before ${t}`;
      out.push({ n: Number(t) }); expectOperand = false;
    } else if (t === "(") {
      if (!expectOperand) return "Missing an operator before (";
      ops.push(t);
    } else if (t === ")") {
      if (expectOperand) return "Something is missing before )";
      while (ops.length && ops[ops.length - 1] !== "(") out.push({ op: ops.pop() as "+" });
      if (!ops.length) return "Unbalanced brackets";
      ops.pop();
    } else if (t in prec) {
      if (expectOperand) return `Something is missing before ${t}`;
      while (ops.length && ops[ops.length - 1] !== "(" && prec[ops[ops.length - 1]!]! >= prec[t]!) out.push({ op: ops.pop() as "+" });
      ops.push(t); expectOperand = true;
    } else return `Not allowed: ${t}`;
  }
  if (expectOperand) return "The formula ends with an operator";
  while (ops.length) { const o = ops.pop()!; if (o === "(") return "Unbalanced brackets"; out.push({ op: o as "+" }); }
  if (out.filter((x) => "m" in x).length === 0) return "Use at least one metric";
  return out;
}

/** RPN back to readable infix (for showing a saved formula). */
export function formulaText(tokens: Token[]): string {
  const st: { s: string; p: number }[] = [];
  const prec: Record<string, number> = { "+": 1, "-": 1, "*": 2, "/": 2 };
  for (const t of tokens) {
    if ("m" in t) st.push({ s: t.m, p: 3 });
    else if ("n" in t) st.push({ s: String(t.n), p: 3 });
    else {
      const b = st.pop(), a = st.pop();
      if (!a || !b) return "";
      const p = prec[t.op]!;
      const wa = a.p < p ? `(${a.s})` : a.s;
      const wb = b.p < p || (b.p === p && (t.op === "-" || t.op === "/")) ? `(${b.s})` : b.s;
      st.push({ s: `${wa} ${t.op} ${wb}`, p });
    }
  }
  return st.length === 1 ? st[0]!.s : "";
}

// ---------- chart helpers ----------
/** Rows of a 2-dim result as a matrix: row keys, column keys, value lookup. */
export function pivot(res: Pick<MetricResult, "rows">): { rows: string[]; cols: string[]; get: (r: string, c: string) => number | null; max: number } {
  const rows = [...new Set(res.rows.map((x) => x.d?.[0] ?? ""))];
  const cols = [...new Set(res.rows.map((x) => x.d?.[1] ?? ""))].sort();
  const m = new Map(res.rows.map((x) => [`${x.d?.[0] ?? ""}\u0000${x.d?.[1] ?? ""}`, x.value]));
  const max = Math.max(0, ...res.rows.map((x) => x.value ?? 0));
  return { rows, cols, get: (r, c) => m.get(`${r}\u0000${c}`) ?? null, max };
}

export type SankeyNode = { id: string; step: number; label: string; value: number; y: number; h: number };
export type SankeyLink = { from: string; to: string; value: number; y0: number; y1: number; h: number };

/** A simple Sankey layout for steps of pairwise flows (each series: dims [step i, step i+1]). */
export function sankeyLayout(series: MetricResult[], height: number, gap = 6): { nodes: SankeyNode[]; links: SankeyLink[]; steps: number } {
  const steps = series.length + 1;
  const totals = new Map<string, number>();
  const add = (k: string, v: number) => totals.set(k, (totals.get(k) ?? 0) + v);
  const links: { from: string; to: string; value: number }[] = [];
  series.forEach((s, i) => s.rows.forEach((r) => {
    const v = r.value ?? 0;
    if (v <= 0) return;
    const a = `${i}:${r.d?.[0] ?? ""}`, b = `${i + 1}:${r.d?.[1] ?? ""}`;
    links.push({ from: a, to: b, value: v });
    if (i === 0) add(a, v);
    add(b, v);
  }));
  // a middle node's size is the larger of what flows in and out
  series.forEach((s, i) => { if (i === 0) return; const outs = new Map<string, number>(); s.rows.forEach((r) => { const a = `${i}:${r.d?.[0] ?? ""}`; outs.set(a, (outs.get(a) ?? 0) + (r.value ?? 0)); });
    outs.forEach((v, k) => totals.set(k, Math.max(totals.get(k) ?? 0, v))); });
  const nodes: SankeyNode[] = [];
  for (let step = 0; step < steps; step++) {
    const ks = [...totals.entries()].filter(([k]) => k.startsWith(`${step}:`)).sort((a, b) => b[1] - a[1]);
    const sum = ks.reduce((a, [, v]) => a + v, 0) || 1;
    const avail = height - gap * Math.max(ks.length - 1, 0);
    let y = 0;
    for (const [k, v] of ks) { const h = Math.max(2, (v / sum) * avail); nodes.push({ id: k, step, label: k.slice(k.indexOf(":") + 1), value: v, y, h }); y += h + gap; }
  }
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const outOff = new Map<string, number>(), inOff = new Map<string, number>();
  const placed: SankeyLink[] = [];
  for (const l of links.sort((a, b) => b.value - a.value)) {
    const a = byId.get(l.from), b = byId.get(l.to);
    if (!a || !b) continue;
    const h0 = (l.value / a.value) * a.h, h1 = (l.value / b.value) * b.h, h = Math.min(h0, h1);
    const y0 = a.y + (outOff.get(a.id) ?? 0), y1 = b.y + (inOff.get(b.id) ?? 0);
    outOff.set(a.id, (outOff.get(a.id) ?? 0) + h0); inOff.set(b.id, (inOff.get(b.id) ?? 0) + h1);
    placed.push({ from: l.from, to: l.to, value: l.value, y0, y1, h });
  }
  return { nodes, links: placed, steps };
}

/** Indian states and union territories on a tile grid (column, row): a readable "map" without geography files. */
export const STATE_TILES: Record<string, [number, number, string]> = {
  "Jammu And Kashmir": [3, 0, "JK"], Ladakh: [4, 0, "LA"], "Himachal Pradesh": [3, 1, "HP"], Punjab: [2, 1, "PB"], Chandigarh: [2, 2, "CH"],
  Uttarakhand: [4, 1, "UK"], Haryana: [3, 2, "HR"], Delhi: [4, 2, "DL"], Rajasthan: [2, 3, "RJ"], "Uttar Pradesh": [5, 2, "UP"],
  Bihar: [7, 3, "BR"], Sikkim: [8, 2, "SK"], "Arunachal Pradesh": [10, 2, "AR"], Assam: [9, 3, "AS"], Nagaland: [10, 3, "NL"], Meghalaya: [8, 3, "ML"],
  Manipur: [10, 4, "MN"], Mizoram: [9, 5, "MZ"], Tripura: [8, 4, "TR"], "West Bengal": [7, 4, "WB"], Jharkhand: [6, 4, "JH"], Odisha: [6, 5, "OD"],
  Chhattisgarh: [5, 4, "CG"], "Madhya Pradesh": [4, 3, "MP"], Gujarat: [1, 4, "GJ"], "Dadra And Nagar Haveli And Daman And Diu": [1, 5, "DN"],
  Maharashtra: [3, 5, "MH"], Telangana: [4, 5, "TS"], "Andhra Pradesh": [4, 6, "AP"], Goa: [2, 6, "GA"], Karnataka: [3, 6, "KA"], "Tamil Nadu": [4, 7, "TN"],
  Kerala: [3, 7, "KL"], Puducherry: [5, 7, "PY"], Lakshadweep: [1, 7, "LD"], "Andaman And Nicobar Islands": [8, 7, "AN"],
};

// ---------- forms ----------
export const WidgetSchema = z.object({
  id: z.string().regex(/^[A-Za-z0-9_-]{1,20}$/),
  type: z.enum(WIDGET_TYPES),
  title: z.string().max(80).optional(),
  metric: z.string().optional(),
  metrics: z.array(z.string()).max(12).optional(),
  dims: z.array(z.string()).max(2).optional(),
  steps: z.array(z.string()).max(4).optional(),
  filters: z.record(z.string(), z.array(z.string())).optional(),
  period: z.enum(PERIODS).optional(),
  date_basis: z.enum(DATE_BASES).optional(),
  sort: z.string().optional(),
  target: z.number().optional(),
  text: z.string().max(1000).optional(),
  w: z.number().int().min(1).max(12),
  h: z.number().int().min(1).max(4),
});
export const DashboardSchema = z.object({
  id: z.number().int().positive().nullable(),
  name: z.string().trim().min(1, "Give the dashboard a name").max(80),
  description: z.string().max(300).optional(),
  period: z.enum(PERIODS),
  filters: z.record(z.string(), z.array(z.string())),
  widgets: z.array(WidgetSchema).max(40),
});

/** What a widget still needs before it can be saved (shown in the builder). */
export function widgetProblem(w: Widget): string | null {
  if (["sla_timers", "alerts"].includes(w.type)) return null;
  if (w.type === "text") return w.text?.trim() ? null : "Write the note";
  if (["table", "funnel"].includes(w.type)) return w.metrics?.length ? null : "Choose at least one metric";
  if (!w.metric) return "Choose a metric";
  if (w.type === "sankey") return (w.steps?.length ?? 0) >= 2 ? null : "Choose at least two steps";
  if (["heatmap", "stacked"].includes(w.type) && (w.dims?.length ?? 0) !== 2) return "Choose two breakdowns";
  if (["bar", "line", "leaderboard", "map"].includes(w.type) && (w.dims?.length ?? 0) < 1) return "Choose a breakdown";
  if (w.type === "map" && w.dims?.[0] !== "state") return "A map is broken down by state";
  return null;
}

/** The breakdowns every metric of a widget shares (the same rule dashboard_check_widgets applies on save). */
export function widgetDims(w: Widget, metrics: CatalogueMetric[]): string[] {
  const keys = [w.metric, ...(w.metrics ?? [])].filter((k): k is string => !!k);
  const ms = metrics.filter((x) => keys.includes(x.key));
  return ms.length ? ms.map((x) => x.dims).reduce((a, b) => a.filter((d) => b.includes(d))) : [];
}

/** The fact views behind a metric: its own, or for a calculated metric the facts of every base metric in its formula. */
export function metricFacts(m: CatalogueMetric, metrics: CatalogueMetric[]): string[] {
  if (m.fact) return [m.fact];
  const bases = (Array.isArray(m.formula) ? (m.formula as { m?: string }[]) : []).map((t) => t?.m).filter((k): k is string => !!k);
  return [...new Set(bases.flatMap((k) => { const b = metrics.find((x) => x.key === k); return b?.fact ? [b.fact] : []; }))];
}

/** The date bases every metric of a widget can be dated by (the rule dashboard_check_widgets applies to date_basis on save):
 *  every base metric's fact must name a column for the basis in DATE_BASIS_COLUMN. */
export function widgetDateBases(w: Widget, metrics: CatalogueMetric[]): DateBasis[] {
  const keys = [w.metric, ...(w.metrics ?? [])].filter((k): k is string => !!k);
  const ms = metrics.filter((x) => keys.includes(x.key));
  if (!ms.length) return [];
  const facts = ms.flatMap((m) => { const f = metricFacts(m, metrics); return f.length ? f : ["?"]; });
  return DATE_BASES.filter((b) => facts.every((f) => !!DATE_BASIS_COLUMN[f]?.[b]));
}

/** widgetProblem, plus a breakdown or step that one of the chosen metrics cannot be broken down by, or a date basis one of them cannot be dated by. */
export function widgetProblemIn(w: Widget, metrics: CatalogueMetric[]): string | null {
  const p = widgetProblem(w);
  if (p || ["text", "sla_timers", "alerts"].includes(w.type)) return p;
  const ok = widgetDims(w, metrics);
  const bad = [...(w.dims ?? []), ...(w.steps ?? [])].find((d) => !ok.includes(d));
  if (bad) return `${DIM_LABEL[bad] ?? bad} is not a breakdown of every chosen metric`;
  if (w.date_basis && !widgetDateBases(w, metrics).includes(w.date_basis)) return `Not every chosen metric can be counted by the ${DATE_BASIS_LABEL[w.date_basis].toLowerCase()} date`;
  return null;
}

/** Breakdown keys that mean different columns on different facts (a status of a lead is not the status of an SLA). */
export const AMBIGUOUS_DIMS = ["status", "stage", "kind", "channel"];
/** Dashboard-wide filter choices: the dims of the metrics in use, minus time grains, minus ambiguous keys that more than one fact uses. */
export function dashboardFilterDims(widgets: Widget[], metrics: CatalogueMetric[]): string[] {
  const used = new Set(widgets.flatMap((w) => [w.metric, ...(w.metrics ?? [])].filter(Boolean) as string[]));
  const ms = metrics.filter((m) => used.has(m.key));
  const factOf = (m: CatalogueMetric) => m.fact ?? (() => { const b = (Array.isArray(m.formula) ? (m.formula as { m?: string }[]) : []).find((t) => t?.m)?.m; return metrics.find((x) => x.key === b)?.fact ?? `calc:${m.key}`; })();
  const factsWith = (d: string) => new Set(ms.filter((m) => m.dims.includes(d)).map(factOf)).size;
  return [...new Set(ms.flatMap((m) => m.dims))].filter((d) => !TIME_DIMS.has(d) && !(AMBIGUOUS_DIMS.includes(d) && factsWith(d) > 1)).sort();
}

/** Parses the period and filter controls from the URL. */
export function viewParams(sp: Record<string, string | string[] | undefined>, fallback: Period): { period: Period; filters: Record<string, string[]> | null } {
  const period = PERIODS.includes(sp.period as Period) ? (sp.period as Period) : fallback;
  let filters: Record<string, string[]> | null = null;
  if (typeof sp.filters === "string") {
    try {
      const f = z.record(z.string().regex(/^[a-z_]{2,30}$/), z.array(z.string().max(200)).max(50)).safeParse(JSON.parse(sp.filters));
      if (f.success) filters = f.data;
    } catch { /* ignore */ }
  }
  return { period, filters };
}
