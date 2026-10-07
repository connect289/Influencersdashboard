import { describe, expect, it, vi } from "vitest";
import {
  delta, dimLabel, drillHref, formatValue, formulaText, parseFormula, pivot, rowFilters, sankeyLayout, viewParams, widgetProblem,
  DashboardSchema, STATE_TILES, type MetricResult,
} from "./analytics";
import { ask, periodBounds } from "./ai/ask";
import { decodeDef, encodeDef, ReportDefSchema } from "./reports";

const res = (rows: MetricResult["rows"], dims: string[] = ["partner"]): MetricResult => ({
  metric: { key: "allocations", label: "Leads routed", unit: "count", area: "Routing", higher_is_better: true, description: null, calculated: false },
  dims, from: "2026-09-07T00:00:00Z", to: "2026-10-07T00:00:00Z", rows, total: { value: 10, prev: 8 }, labels: { partner: { "4": "Acme" } },
});

describe("formatting", () => {
  it("formats by unit", () => {
    expect(formatValue(0.1234, "pct")).toBe("12%");
    expect(formatValue(0.034, "pct")).toBe("3.4%");
    expect(formatValue(123456, "inr")).toBe("₹1,23,456");
    expect(formatValue(1234567, "inr", true)).toBe("₹12.3 L");
    expect(formatValue(2.25, "hours")).toBe("2.3 h");
    expect(formatValue(null, "count")).toBe("—");
  });
  it("words deltas with direction and tone", () => {
    expect(delta(12, 10, true, "count")).toEqual({ text: "+20%", tone: "good" });
    expect(delta(0.3, 0.2, false, "pct")).toEqual({ text: "+10.0 pts", tone: "bad" });
    expect(delta(5, 0, true, "count")).toEqual({ text: "+5", tone: "good" });
    expect(delta(5, 5, true, "count")?.tone).toBe("flat");
    expect(delta(5, null, true, "count")).toBeNull();
    expect(delta(0.3804, 0.3806, true, "pct")).toEqual({ text: "no change", tone: "flat" });
    expect(delta(1001, 1000, true, "count")).toEqual({ text: "no change", tone: "flat" });
  });
  it("labels breakdown values", () => {
    expect(dimLabel("partner", "4", res([]).labels)).toBe("Acme");
    expect(dimLabel("partner", "9")).toBe("Partner #9");
    expect(dimLabel("segment", "mba|PG|*")).toBe("MBA · PG · any");
    expect(dimLabel("holdout", "true")).toBe("Yes");
    expect(dimLabel("lead_status", null)).toBe("(none)");
  });
  it("builds drill links and row filters", () => {
    expect(drillHref("leads", { state: ["Delhi"] }, "a", "b")).toBe("/dashboards/drill?metric=leads&filters=%7B%22state%22%3A%5B%22Delhi%22%5D%7D&from=a&to=b");
    expect(rowFilters({ segment: ["x"] }, ["week", "partner"], ["2026-10-05", "4"])).toEqual({ segment: ["x"], partner: ["4"] });
  });
});

describe("formula parser", () => {
  const known = new Set(["commission_realised", "allocations", "leads"]);
  it("parses with precedence and brackets, and prints back", () => {
    const t = parseFormula("commission_realised / (allocations + leads) * 100", known);
    expect(t).toEqual([{ m: "commission_realised" }, { m: "allocations" }, { m: "leads" }, { op: "+" }, { op: "/" }, { n: 100 }, { op: "*" }]);
    expect(formulaText(t as never)).toBe("commission_realised / (allocations + leads) * 100");
    expect(formulaText(parseFormula("leads - allocations - leads", known) as never)).toBe("leads - allocations - leads");
  });
  it("refuses what is not a formula", () => {
    expect(parseFormula("", known)).toMatch(/Write a formula/);
    expect(parseFormula("leads +", known)).toBe("The formula ends with an operator");
    expect(parseFormula("leads allocations", known)).toBe("Missing an operator before allocations");
    expect(parseFormula("(leads", known)).toBe("Unbalanced brackets");
    expect(parseFormula("revenue / leads", known)).toBe("Unknown metric: revenue");
    expect(parseFormula("leads; drop", known)).toBe("Not allowed: ;");
    expect(parseFormula("2 * 3", known)).toBe("Use at least one metric");
  });
});

describe("chart helpers", () => {
  it("pivots two breakdowns", () => {
    const p = pivot(res([{ d: ["a", "x"], value: 1, prev: null }, { d: ["a", "y"], value: 3, prev: null }, { d: ["b", "x"], value: 2, prev: null }], ["k", "c"]));
    expect(p.rows).toEqual(["a", "b"]);
    expect(p.cols).toEqual(["x", "y"]);
    expect(p.get("b", "y")).toBeNull();
    expect(p.max).toBe(3);
  });
  it("lays out a Sankey with conserved flows", () => {
    const s1 = res([{ d: ["web", "4"], value: 6, prev: null }, { d: ["wa", "4"], value: 4, prev: null }], ["source", "partner"]);
    const s2 = res([{ d: ["4", "contacted"], value: 7, prev: null }, { d: ["4", "none"], value: 3, prev: null }], ["partner", "stage"]);
    const l = sankeyLayout([s1, s2], 100);
    expect(l.steps).toBe(3);
    expect(l.nodes.find((n) => n.id === "1:4")?.value).toBe(10);
    expect(l.links).toHaveLength(4);
    expect(l.nodes.filter((n) => n.step === 0).reduce((a, n) => a + n.h, 0)).toBeLessThanOrEqual(100);
  });
  it("places every state on its own tile", () => {
    const tiles = Object.values(STATE_TILES).map(([x, y]) => `${x},${y}`);
    expect(new Set(tiles).size).toBe(tiles.length);
    expect(STATE_TILES["Delhi"]?.[2]).toBe("DL");
  });
});

describe("widgets and dashboards", () => {
  it("says what a widget still needs", () => {
    expect(widgetProblem({ id: "a", type: "kpi", w: 3, h: 1 })).toBe("Choose a metric");
    expect(widgetProblem({ id: "a", type: "bar", metric: "leads", w: 3, h: 1 })).toBe("Choose a breakdown");
    expect(widgetProblem({ id: "a", type: "heatmap", metric: "leads", dims: ["state"], w: 3, h: 1 })).toBe("Choose two breakdowns");
    expect(widgetProblem({ id: "a", type: "map", metric: "leads", dims: ["source"], w: 3, h: 1 })).toBe("A map is broken down by state");
    expect(widgetProblem({ id: "a", type: "table", w: 3, h: 1 })).toBe("Choose at least one metric");
    expect(widgetProblem({ id: "a", type: "alerts", w: 3, h: 1 })).toBeNull();
    expect(widgetProblem({ id: "a", type: "sankey", metric: "allocations", steps: ["source", "partner"], w: 6, h: 2 })).toBeNull();
  });
  it("validates a dashboard", () => {
    expect(DashboardSchema.safeParse({ id: null, name: "Mine", period: "30d", filters: {}, widgets: [{ id: "a", type: "kpi", metric: "leads", w: 13, h: 1 }] }).success).toBe(false);
    expect(DashboardSchema.safeParse({ id: null, name: "Mine", period: "30d", filters: {}, widgets: [{ id: "a", type: "kpi", metric: "leads", w: 3, h: 1 }] }).success).toBe(true);
  });
  it("reads period and filters from the URL safely", () => {
    expect(viewParams({ period: "7d", filters: '{"state":["Delhi"]}' }, "30d")).toEqual({ period: "7d", filters: { state: ["Delhi"] } });
    expect(viewParams({ period: "nope", filters: "{bad" }, "30d")).toEqual({ period: "30d", filters: null });
    expect(viewParams({ filters: '{"x; drop":["a"]}' }, "30d").filters).toBeNull();
  });
});

describe("reports", () => {
  it("round-trips a definition through the URL", () => {
    const d = ReportDefSchema.parse({ kind: "summary", definition: { metrics: ["leads"], dims: ["source"], filters: {}, period: "30d" } });
    expect(decodeDef(encodeDef(d))).toEqual(d);
    expect(decodeDef("garbage")).toBeNull();
    expect(ReportDefSchema.safeParse({ kind: "matrix", definition: { metric: "leads", row_dim: "state", col_dim: "state", filters: {}, period: "30d" } }).success).toBe(false);
  });
});

describe("ask the CRM", () => {
  it("computes IST period starts", () => {
    const now = new Date("2026-10-07T04:00:00Z"); // 09:30 IST
    expect(periodBounds("today", now).from).toBe("2026-10-06T18:30:00.000Z");
    expect(periodBounds("month", now).from).toBe("2026-09-30T18:30:00.000Z");
    expect(periodBounds(undefined, now).from).toBe("2026-09-07T04:00:00.000Z");
  });
  it("answers through the metric layer and validates numbers", async () => {
    const query = vi.fn(async () => ({ total: { value: 42, prev: 30 }, rows: [] }));
    const db = { catalogue: async () => ({ metrics: [{ key: "leads", label: "Leads", unit: "count", area: "Intake", dims: ["source"], description: null }] }), query };
    const replies = [
      { stop_reason: "tool_use", content: [{ type: "tool_use", id: "1", name: "query_metric", input: { metric: "leads", period: "7d" } }] },
      { stop_reason: "tool_use", content: [{ type: "tool_use", id: "2", name: "submit_answer", input: { answer: "42 leads in the last 7 days, up from 30.", sources: [{ metric: "leads", period: "7d" }] } }] },
    ];
    const r = await ask("How many leads this week?", "claude-sonnet-5-5", db, vi.fn(async () => replies.shift()!));
    expect(r.validation.ok).toBe(true);
    expect(r.answer).toContain("42 leads");
    expect(query).toHaveBeenCalledWith(expect.objectContaining({ metric: "leads", compare: "previous" }));
    const bad = await ask("x?", "m", db, vi.fn(async () => ({ stop_reason: "tool_use", content: [{ type: "tool_use", id: "3", name: "submit_answer", input: { answer: "About 55 leads." } }] })));
    expect(bad.validation).toMatchObject({ ok: false, unverified: ["55"] });
  });
});
