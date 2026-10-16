import { z } from "zod";

/**
 * The analytics spec (spec B13): metric and dimension KEYS from the database catalogue (b2c.metric_defs, b2c.dim_defs),
 * filters on dimensions, a date range and a comparison. The database validates it and adds the role's scope; nothing
 * here (or from Claude) can name a table or write SQL.
 */
export const FilterSchema = z.object({
  dim: z.string().regex(/^[a-z_]+$/),
  op: z.enum(["eq", "neq", "in", "not_in", "contains", "is_null", "not_null"]),
  value: z.union([z.string(), z.array(z.string())]).optional(),
});
export const SpecSchema = z.object({
  metrics: z.array(z.string().regex(/^[a-z_]+$/)).min(1).max(6),
  dims: z.array(z.string().regex(/^[a-z_]+$/)).max(2).optional(),
  filters: z.array(FilterSchema).max(10).optional(),
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  compare: z.enum(["previous", "year"]).nullable().optional(),
  limit: z.number().int().min(1).max(5000).optional(),
  test: z.boolean().optional(),
});
export type Spec = z.infer<typeof SpecSchema>;
export type Filter = z.infer<typeof FilterSchema>;

export const VIZ = ["kpi", "line", "bar", "stacked", "funnel", "cohort", "table", "pivot", "leaderboard", "gauge", "map", "text"] as const;
export type Viz = (typeof VIZ)[number];
export type Widget = { id: string; title: string; viz: Viz; w?: number; spec: Spec; note?: string };
export type DashFilters = { range?: string; from?: string; to?: string; compare?: "previous" | "year" | null; filters?: Filter[] };
export type Dashboard = {
  id: number; key: string | null; name: string; description: string | null; owner_id: string | null; roles: string[]; widgets: Widget[]; filters: DashFilters;
  mine?: boolean; standard?: boolean; home?: boolean;
};
export type MetricDef = { key: string; label: string; area: string; source: string; fmt: Fmt; description: string | null; as_of_now: boolean; counts_leads: boolean; higher_is_better: boolean };
export type DimDef = { key: string; label: string; sources: string[] | null };
export type Catalog = { group: "admin" | "marketing" | "sales"; scope: string; metrics: MetricDef[]; dims: DimDef[] };
export type Fmt = "count" | "money" | "pct" | "minutes" | "days" | "number";
export type ResultRow = { k: (string | null)[] } & Record<string, unknown>;
export type Result = {
  rows: ResultRow[]; metrics: string[]; dims: string[]; from: string; to: string; compare: { from: string; to: string } | null; test: boolean; scope: string;
  sql: { metric: string; sql: string }[]; defs: { key: string; label: string; fmt: Fmt; higher_is_better: boolean; counts_leads: boolean }[] | null;
};

export const RANGES: { key: string; label: string; days?: number }[] = [
  { key: "7d", label: "Last 7 days", days: 7 }, { key: "30d", label: "Last 30 days", days: 30 }, { key: "90d", label: "Last 90 days", days: 90 },
  { key: "365d", label: "Last 12 months", days: 365 }, { key: "mtd", label: "This month" }, { key: "lm", label: "Last month" }, { key: "custom", label: "Custom" },
];

/** IST calendar date (YYYY-MM-DD) of an instant. */
export function istDate(d: Date): string {
  return new Date(d.getTime() + 330 * 60_000).toISOString().slice(0, 10);
}
function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** The from/to of a named range, in IST days, inclusive. */
export function resolveRange(range: string | undefined, now = new Date(), custom?: { from?: string; to?: string }): { from: string; to: string } {
  const today = istDate(now);
  if (range === "custom" && custom?.from && custom?.to) return { from: custom.from, to: custom.to };
  if (range === "mtd") return { from: `${today.slice(0, 7)}-01`, to: today };
  if (range === "lm") {
    const first = `${today.slice(0, 7)}-01`;
    const lastPrev = addDays(first, -1);
    return { from: `${lastPrev.slice(0, 7)}-01`, to: lastPrev };
  }
  const days = RANGES.find((r) => r.key === range)?.days ?? 30;
  return { from: addDays(today, -(days - 1)), to: today };
}

/** A widget's spec with the dashboard's range, comparison and filters applied (the widget's own filters stay). */
export function effectiveSpec(w: Widget, f: DashFilters, test = false, now = new Date()): Spec {
  const r = resolveRange(f.range, now, f);
  return {
    ...w.spec,
    from: w.spec.from ?? r.from,
    to: w.spec.to ?? r.to,
    compare: w.viz === "kpi" || w.viz === "gauge" ? (f.compare ?? null) : null,
    filters: [...(w.spec.filters ?? []), ...(f.filters ?? [])],
    test,
  };
}

export function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** A value as the screens show it: Indian grouping for money, compact above 1,000 where asked. */
export function fmtValue(v: unknown, fmt: Fmt, compact = false): string {
  const n = num(v);
  if (n === null) return "–";
  if (fmt === "pct") return `${n.toLocaleString("en-IN", { maximumFractionDigits: 1 })}%`;
  if (fmt === "minutes") return n >= 120 ? `${(n / 60).toLocaleString("en-IN", { maximumFractionDigits: 1 })} h` : `${Math.round(n)} min`;
  if (fmt === "days") return `${n.toLocaleString("en-IN", { maximumFractionDigits: 1 })} d`;
  if (fmt === "money") {
    if (compact && Math.abs(n) >= 1e7) return `₹${(n / 1e7).toLocaleString("en-IN", { maximumFractionDigits: 2 })} Cr`;
    if (compact && Math.abs(n) >= 1e5) return `₹${(n / 1e5).toLocaleString("en-IN", { maximumFractionDigits: 2 })} L`;
    return `₹${n.toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;
  }
  if (compact && Math.abs(n) >= 1000) return n.toLocaleString("en-IN", { notation: "compact", maximumFractionDigits: 1 });
  return n.toLocaleString("en-IN", { maximumFractionDigits: fmt === "number" ? 1 : 0 });
}

/** Signed change against the comparison period, and whether it is good news for this metric. */
export function delta(cur: unknown, prev: unknown, higherIsBetter: boolean): { text: string; good: boolean | null } | null {
  const c = num(cur), p = num(prev);
  if (c === null || p === null) return null;
  if (p === 0) return c === 0 ? { text: "no change", good: null } : { text: "new", good: higherIsBetter ? c > 0 : c < 0 };
  const pct = ((c - p) / Math.abs(p)) * 100;
  if (Math.abs(pct) < 0.5) return { text: "no change", good: null };
  return { text: `${pct > 0 ? "+" : ""}${pct.toFixed(Math.abs(pct) < 10 ? 1 : 0)}%`, good: pct > 0 === higherIsBetter };
}

/** Result rows as a table (dimensions first, then each metric and its comparison), for CSV and the table view. */
export function resultTable(r: Result, labels: Record<string, string>): { columns: string[]; rows: Record<string, unknown>[] } {
  const dims = r.dims.map((d) => labels[d] ?? d);
  const mets = r.metrics.flatMap((m) => (r.compare ? [m, `${m}__cmp`] : [m]));
  const columns = [...dims, ...mets.map((m) => (m.endsWith("__cmp") ? `${labels[m.slice(0, -5)] ?? m} (previous)` : labels[m] ?? m))];
  const rows = r.rows.map((row) => {
    const o: Record<string, unknown> = {};
    r.dims.forEach((_, i) => { o[dims[i] ?? String(i)] = row.k[i] ?? "(none)"; });
    mets.forEach((m, i) => { o[columns[dims.length + i] ?? m] = row[m] ?? null; });
    return o;
  });
  return { columns, rows };
}
