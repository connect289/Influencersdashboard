import { describe, expect, it, vi } from "vitest";
import {
  applicableFilters, dashboardFilterDims, dateBasisParam, delta, dimLabel, drillHref, formatValue, formulaText, gaugeTargetInput, gaugeTargetValue, metricFacts, parseFormula, pivot,
  rowFilters, sankeyLayout, viewParams, widgetDateBases, widgetDims, widgetProblem, widgetProblemIn,
  DashboardSchema, DATE_BASES, DATE_BASIS_COLUMN, DATE_BASIS_LABEL, DIM_LABEL, STATE_TILES, WidgetSchema, type CatalogueMetric, type MetricResult,
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
  it("labels every Addendum 3 breakdown (C70, C90, C103)", () => {
    // the keys m31o's metric_dimensions adds on fact_leads and fact_allocations, and the lead dimensions now on allocations, SLAs, enrolments and money
    const a3 = ["sub_source", "programme", "b2c_reason", "hold_kind", "partner_barred", "consent_state", "platform", "score_stage", "origin", "paid", "from_b2c", "run_kind",
                "channel", "form", "utm_source", "utm_medium", "city", "university", "specialization", "temperature", "sub_stage", "lost_reason", "source", "campaign", "state",
                "segment", "course", "level", "mode", "routing_mode", "attempt_no", "lead_status", "language"];
    for (const k of a3) expect(DIM_LABEL[k], k).toBeTruthy();
    expect(DIM_LABEL.sub_source).toBe("Sub-source");
    expect(DIM_LABEL.programme).toBe("Programme");
    expect(DIM_LABEL.b2c_reason).toBe("Why sent to B2C");
    expect(DIM_LABEL.score_stage).toBe("Scoring stage");
    expect(DIM_LABEL.run_kind).toBe("Run / recommendation type");
    // 'stage' keeps meaning the stage a lead reached (C90)
    expect(DIM_LABEL.stage).toBe("Stage");
    // values of the new breakdowns read as words, not codes
    expect(dimLabel("score_stage", "B")).toBe("Stage B");
    expect(dimLabel("partner_barred", "true")).toBe("Yes");
    expect(dimLabel("from_b2c", "false")).toBe("No");
    expect(dimLabel("b2c_reason", "no_partner_offers_programme")).toBe("No partner offers this programme");
    expect(dimLabel("hold_kind", "selling")).toBe("With B2C sales");
    expect(dimLabel("consent_state", "refused")).toBe("Student said NO to sharing");
    expect(dimLabel("origin", "requalify")).toBe("Re-qualified from B2C nurture");
    expect(dimLabel("origin", "something_new")).toBe("something new");
  });
  it("builds drill links and row filters", () => {
    expect(drillHref("leads", { state: ["Delhi"] }, "a", "b")).toBe("/dashboards/drill?metric=leads&filters=%7B%22state%22%3A%5B%22Delhi%22%5D%7D&from=a&to=b");
    expect(drillHref("leads", {}, undefined, undefined, "year")).toBe("/dashboards/drill?metric=leads&period=year");
    expect(drillHref("leads", {}, "a", "b", "7d")).toBe("/dashboards/drill?metric=leads&from=a&to=b&period=7d");
    // the widget's date basis travels with the link; none or null adds nothing
    expect(drillHref("leads", {}, "a", "b", "7d", "accepted")).toBe("/dashboards/drill?metric=leads&from=a&to=b&period=7d&date_basis=accepted");
    expect(drillHref("leads", { state: ["Delhi"] }, undefined, undefined, undefined, "enrolled")).toBe("/dashboards/drill?metric=leads&filters=%7B%22state%22%3A%5B%22Delhi%22%5D%7D&date_basis=enrolled");
    expect(drillHref("leads", {}, "a", "b", "7d", null)).toBe("/dashboards/drill?metric=leads&from=a&to=b&period=7d");
    expect(dateBasisParam("accepted")).toBe("accepted");
    expect(dateBasisParam("shipped")).toBeUndefined();
    expect(dateBasisParam(["accepted"])).toBeUndefined();
    expect(dateBasisParam(undefined)).toBeUndefined();
    expect(rowFilters({ segment: ["x"] }, ["week", "partner"], ["2026-10-05", "4"])).toEqual({ segment: ["x"], week: ["2026-10-05"], partner: ["4"] });
    // a heatmap cell keeps its time bucket
    expect(rowFilters({}, ["sla", "week"], ["first_attempt", "2026-09-28"])).toEqual({ sla: ["first_attempt"], week: ["2026-09-28"] });
    // a null bucket filters on '(none)'
    expect(rowFilters({}, ["campaign"], [null])).toEqual({ campaign: [""] });
    expect(rowFilters({ campaign: ["x"] }, ["campaign"], null)).toEqual({ campaign: ["x"] });
  });
  it("keeps only the dashboard filters a metric can use", () => {
    expect(applicableFilters({ source: ["facebook"], platform: ["meta"] }, ["platform", "stage", "day"])).toEqual({ platform: ["meta"] });
    expect(applicableFilters({ platform: "meta", stage: [1, "x"], day: ["2026-10-01"] }, ["platform", "stage", "day"])).toEqual({ day: ["2026-10-01"] });
    expect(applicableFilters({ platform: ["meta"] }, [])).toEqual({});
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
  const cm = (key: string, fact: string | null, dims: string[], formula: unknown = null): CatalogueMetric => ({
    key, label: key, unit: "count", area: "x", higher_is_better: true, description: null, calculated: fact === null, fact, dims, formula,
  });
  it("checks breakdowns against every chosen metric", () => {
    const cat = [cm("leads", "fact_leads", ["source", "destination", "partner", "day"]), cm("allocations", "fact_allocations", ["partner", "status", "day"])];
    expect(widgetDims({ id: "a", type: "table", metrics: ["leads", "allocations"], w: 12, h: 2 }, cat)).toEqual(["partner", "day"]);
    expect(widgetDims({ id: "a", type: "kpi", w: 3, h: 1 }, cat)).toEqual([]);
    expect(widgetProblemIn({ id: "a", type: "table", metrics: ["leads", "allocations"], dims: ["destination"], w: 12, h: 2 }, cat))
      .toBe("Destination is not a breakdown of every chosen metric");
    expect(widgetProblemIn({ id: "a", type: "table", metrics: ["leads", "allocations"], dims: ["partner"], w: 12, h: 2 }, cat)).toBeNull();
    expect(widgetProblemIn({ id: "a", type: "sankey", metric: "allocations", steps: ["partner", "source"], w: 6, h: 2 }, cat))
      .toBe("Source is not a breakdown of every chosen metric");
    expect(widgetProblemIn({ id: "a", type: "table", w: 12, h: 2 }, cat)).toBe("Choose at least one metric");
    expect(widgetProblemIn({ id: "a", type: "alerts", dims: ["x"], w: 6, h: 2 }, cat)).toBeNull();
  });
  it("offers a date basis only when every chosen metric can be dated by it (C70)", () => {
    const cat = [
      cm("leads", "fact_leads", ["source", "day"]), cm("allocations", "fact_allocations", ["partner", "day"]), cm("enrolments", "fact_enrollments", ["partner", "day"]),
      cm("sla_compliance", "fact_sla", ["partner", "day"]),
      cm("per_alloc", null, ["day"], [{ m: "leads" }, { m: "allocations" }, { op: "/" }]),
      cm("orphan", null, ["day"], [{ m: "nope" }]),
    ];
    const kpi = (metric: string, date_basis?: "created" | "routed" | "accepted" | "enrolled") => ({ id: "a", type: "kpi" as const, metric, date_basis, w: 3, h: 1 });
    const table = (metrics: string[], date_basis?: "created" | "routed" | "accepted" | "enrolled") => ({ id: "t", type: "table" as const, metrics, dims: ["day"], date_basis, w: 12, h: 2 });
    expect(DATE_BASES).toEqual(["created", "routed", "accepted", "enrolled"]);
    expect(Object.keys(DATE_BASIS_LABEL)).toEqual([...DATE_BASES]);
    // the same table as b2b.metric_date_col
    expect(DATE_BASIS_COLUMN.fact_leads).toEqual({ created: "created_at", routed: "routed_at", accepted: "accepted_at", enrolled: "enrolled_at" });
    expect(DATE_BASIS_COLUMN.fact_allocations).toEqual({ created: "created_at", routed: "created_at", accepted: "accepted_at" });
    expect(DATE_BASIS_COLUMN.fact_enrollments).toEqual({ created: "created_at", enrolled: "enrolled_at" });
    expect(metricFacts(cat[4]!, cat)).toEqual(["fact_leads", "fact_allocations"]);
    expect(metricFacts(cat[0]!, cat)).toEqual(["fact_leads"]);
    expect(widgetDateBases(kpi("leads"), cat)).toEqual(["created", "routed", "accepted", "enrolled"]);
    expect(widgetDateBases(kpi("allocations"), cat)).toEqual(["created", "routed", "accepted"]);
    expect(widgetDateBases(kpi("sla_compliance"), cat)).toEqual([]);
    expect(widgetDateBases(kpi("per_alloc"), cat)).toEqual(["created", "routed", "accepted"]);
    expect(widgetDateBases(kpi("orphan"), cat)).toEqual([]);
    expect(widgetDateBases(table(["leads", "enrolments"]), cat)).toEqual(["created", "enrolled"]);
    expect(widgetDateBases({ id: "a", type: "kpi", w: 3, h: 1 }, cat)).toEqual([]);
    // the builder's message mirrors dashboard_check_widgets' "<label> cannot be dated by <basis>"
    expect(widgetProblemIn(kpi("allocations", "enrolled"), cat)).toBe("Not every chosen metric can be counted by the enrolled date");
    expect(widgetProblemIn(kpi("allocations", "accepted"), cat)).toBeNull();
    expect(widgetProblemIn(table(["leads", "allocations"], "enrolled"), cat)).toBe("Not every chosen metric can be counted by the enrolled date");
    expect(widgetProblemIn(table(["leads", "allocations"], "routed"), cat)).toBeNull();
    // a breakdown problem is reported before the date basis
    expect(widgetProblemIn({ ...kpi("allocations", "enrolled"), type: "bar", dims: ["source"] }, cat)).toBe("Source is not a breakdown of every chosen metric");
    // the saved shape carries date_basis and refuses an unknown one, like the SQL (22023 'unknown date basis')
    expect(WidgetSchema.safeParse({ id: "a", type: "kpi", metric: "leads", date_basis: "routed", w: 3, h: 1 }).success).toBe(true);
    expect(WidgetSchema.safeParse({ id: "a", type: "kpi", metric: "leads", date_basis: "shipped", w: 3, h: 1 }).success).toBe(false);
    expect(WidgetSchema.safeParse({ id: "a", type: "kpi", metric: "leads", w: 3, h: 1 }).success).toBe(true);
  });
  it("offers only unambiguous dashboard filters", () => {
    const cat = [
      cm("allocations", "fact_allocations", ["partner", "status", "day"]),
      cm("sla_compliance", "fact_sla", ["partner", "status"]),
      cm("alloc_calc", null, ["partner", "status"], [{ m: "allocations" }]),
    ];
    const w = (...ks: string[]) => ks.map((k, i) => ({ id: `w${i}`, type: "kpi" as const, metric: k, w: 3, h: 1 }));
    expect(dashboardFilterDims(w("allocations", "sla_compliance"), cat)).toEqual(["partner"]);
    expect(dashboardFilterDims(w("allocations"), cat)).toEqual(["partner", "status"]);
    expect(dashboardFilterDims(w("allocations", "alloc_calc"), cat)).toEqual(["partner", "status"]);
  });
  it("shows pct gauge targets in percent and stores them as fractions", () => {
    expect(gaugeTargetValue("90", "pct")).toBe(0.9);
    expect(gaugeTargetValue("90", "count")).toBe(90);
    expect(gaugeTargetValue("", "pct")).toBeUndefined();
    expect(gaugeTargetValue("abc", "pct")).toBeUndefined();
    expect(gaugeTargetInput(0.07, "pct")).toBe("7");
    expect(gaugeTargetInput(0.57, "pct")).toBe("57");
    expect(gaugeTargetInput(0.29, "pct")).toBe("29");
    expect(gaugeTargetInput(undefined, "pct")).toBe("");
    expect(gaugeTargetInput(1200, "inr")).toBe("1200");
  });
  it("validates a dashboard", () => {
    expect(DashboardSchema.safeParse({ id: null, name: "Mine", period: "30d", filters: {}, widgets: [{ id: "a", type: "kpi", metric: "leads", w: 13, h: 1 }] }).success).toBe(false);
    expect(DashboardSchema.safeParse({ id: null, name: "Mine", period: "30d", filters: {}, widgets: [{ id: "a", type: "kpi", metric: "leads", w: 3, h: 1 }] }).success).toBe(true);
  });
  it("reads period and filters from the URL safely", () => {
    expect(viewParams({ period: "7d", filters: '{"state":["Delhi"]}' }, "30d")).toEqual({ period: "7d", filters: { state: ["Delhi"] } });
    expect(viewParams({ period: "nope", filters: "{bad" }, "30d")).toEqual({ period: "30d", filters: null });
    expect(viewParams({ filters: '{"x; drop":["a"]}' }, "30d").filters).toBeNull();
    expect(viewParams({ filters: "null" }, "30d").filters).toBeNull();
    expect(viewParams({ filters: '{"source":"x"}' }, "30d").filters).toBeNull();
    expect(viewParams({ filters: '["a"]' }, "30d").filters).toBeNull();
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
