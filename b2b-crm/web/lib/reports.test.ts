import { describe, expect, it } from "vitest";
import { reconcileBreakdowns, ReportDefSchema } from "./reports";

describe("reconcileBreakdowns", () => {
  it("drops breakdowns the chosen metrics cannot use", () => {
    expect(reconcileBreakdowns(["platform", "month"], { dims: ["partner"], rowDim: "partner", colDim: "month" })).toEqual({ dims: [], rowDim: "platform", colDim: "month" });
  });
  it("keeps valid breakdowns unchanged", () => {
    expect(reconcileBreakdowns(["partner", "month"], { dims: ["partner"], rowDim: "partner", colDim: "month" })).toEqual({ dims: ["partner"], rowDim: "partner", colDim: "month" });
  });
  it("never puts the same breakdown on rows and columns", () => {
    expect(reconcileBreakdowns(["month"], { dims: [], rowDim: "partner", colDim: "month" })).toEqual({ dims: [], rowDim: "month", colDim: "" });
  });
  it("clears everything when nothing is allowed", () => {
    expect(reconcileBreakdowns([], { dims: ["partner"], rowDim: "partner", colDim: "month" })).toEqual({ dims: [], rowDim: "", colDim: "" });
  });
});

describe("ReportDefSchema, tabular", () => {
  const tabular = (limit: number) => ({ kind: "tabular", definition: { fact: "fact_capi", columns: ["created_at", "cpe"], filters: {}, period: "30d", sort: "cpe", desc: false, limit } });
  it("accepts sort, order and a row limit up to 5,000", () => {
    const r = ReportDefSchema.safeParse(tabular(5000));
    expect(r.success).toBe(true);
    expect(r.success && r.data.kind === "tabular" ? [r.data.definition.sort, r.data.definition.desc, r.data.definition.limit] : null).toEqual(["cpe", false, 5000]);
  });
  it("rejects a row limit above 5,000", () => {
    expect(ReportDefSchema.safeParse(tabular(5001)).success).toBe(false);
  });
});
