import { describe, expect, it } from "vitest";
import { delta, effectiveSpec, fmtValue, resolveRange, resultTable, SpecSchema, type Result } from "./analytics";

const NOW = new Date("2026-10-14T21:27:00Z"); // 15 Oct 02:57 IST

describe("ranges", () => {
  it("counts in IST days", () => {
    expect(resolveRange("7d", NOW)).toEqual({ from: "2026-10-09", to: "2026-10-15" });
    expect(resolveRange("mtd", NOW)).toEqual({ from: "2026-10-01", to: "2026-10-15" });
    expect(resolveRange("lm", NOW)).toEqual({ from: "2026-09-01", to: "2026-09-30" });
    expect(resolveRange("custom", NOW, { from: "2026-01-01", to: "2026-01-31" })).toEqual({ from: "2026-01-01", to: "2026-01-31" });
  });
  it("applies dashboard filters on top of the widget's own", () => {
    const s = effectiveSpec({ id: "a", title: "x", viz: "kpi", spec: { metrics: ["handoffs"], filters: [{ dim: "lane", op: "eq", value: "sales" }] } },
      { range: "30d", compare: "previous", filters: [{ dim: "source", op: "eq", value: "meta" }] }, true, NOW);
    expect(s.filters).toHaveLength(2);
    expect(s.compare).toBe("previous");
    expect(s.test).toBe(true);
    expect(s.from).toBe("2026-09-16");
  });
});

describe("spec schema", () => {
  it("takes keys, never SQL", () => {
    expect(SpecSchema.safeParse({ metrics: ["enrollments"], dims: ["counsellor"] }).success).toBe(true);
    expect(SpecSchema.safeParse({ metrics: ["count(*) from users"] }).success).toBe(false);
    expect(SpecSchema.safeParse({ metrics: ["a"], filters: [{ dim: "f.owner_id", op: "eq", value: "x" }] }).success).toBe(false);
    expect(SpecSchema.safeParse({ metrics: [] }).success).toBe(false);
  });
});

describe("formatting", () => {
  it("formats by kind", () => {
    expect(fmtValue(1234567, "money")).toBe("₹12,34,567");
    expect(fmtValue(1234567, "money", true)).toBe("₹12.35 L");
    expect(fmtValue(12.345, "pct")).toBe("12.3%");
    expect(fmtValue(150, "minutes")).toBe("2.5 h");
    expect(fmtValue(null, "count")).toBe("–");
  });
  it("reads deltas by direction", () => {
    expect(delta(110, 100, true)).toEqual({ text: "+10%", good: true });
    expect(delta(110, 100, false)).toEqual({ text: "+10%", good: false });
    expect(delta(5, 0, true)).toEqual({ text: "new", good: true });
    expect(delta(null, 3, true)).toBeNull();
  });
  it("tabulates results", () => {
    const r = { rows: [{ k: ["Priya"], enrollments: 2, enrollments__cmp: 1 }], metrics: ["enrollments"], dims: ["counsellor"], compare: { from: "", to: "" } } as unknown as Result;
    const t = resultTable(r, { counsellor: "Counsellor", enrollments: "Enrolments" });
    expect(t.columns).toEqual(["Counsellor", "Enrolments", "Enrolments (previous)"]);
    expect(t.rows[0]).toEqual({ Counsellor: "Priya", Enrolments: 2, "Enrolments (previous)": 1 });
  });
});
