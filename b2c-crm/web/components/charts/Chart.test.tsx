import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { VIZ, type Result } from "@/lib/analytics";
import { CommissionLines } from "@/components/money/CommissionLines";
import type { CommissionLine } from "@/lib/money";
import { Chart, type Defs } from "./Chart";

const defs: Defs = {
  leads_new: { label: "New leads", fmt: "count", higher_is_better: true, counts_leads: true },
  enrolled: { label: "Enrolled", fmt: "count", higher_is_better: true, counts_leads: true },
  conv: { label: "Conversion", fmt: "pct", higher_is_better: true, counts_leads: false },
};
const base = { from: "2026-10-01", to: "2026-10-14", compare: null, test: false, scope: "all", sql: [], defs: null };
const oneDim: Result = { ...base, metrics: ["leads_new", "enrolled"], dims: ["day"], rows: [
  { k: ["2026-10-01"], leads_new: 4, enrolled: 1 }, { k: ["2026-10-02"], leads_new: 7, enrolled: 0 }, { k: [null], leads_new: 2, enrolled: 0 }] };
const twoDim: Result = { ...base, metrics: ["leads_new"], dims: ["day", "source"], rows: [
  { k: ["2026-10-01", "Witty"], leads_new: 3 }, { k: ["2026-10-01", "Website"], leads_new: 1 }, { k: ["2026-10-02", "Witty"], leads_new: 5 }] };
const kpi: Result = { ...base, metrics: ["conv"], dims: [], compare: { from: "2026-09-17", to: "2026-09-30" }, rows: [{ k: [], conv: 12.5, conv__cmp: 10 }] };

describe("charts", () => {
  it("draws every chart type without throwing, with a table toggle and drill buttons", () => {
    for (const viz of VIZ) {
      const r = viz === "kpi" || viz === "gauge" ? kpi : viz === "stacked" || viz === "pivot" ? twoDim : oneDim;
      const h = renderToStaticMarkup(<Chart viz={viz} result={r} defs={defs} dimLabels={{ day: "Day", source: "Source" }} onDrill={() => {}} note="A note" />);
      expect(h.length, viz).toBeGreaterThan(10);
      if (!["text", "kpi", "table", "gauge"].includes(viz)) expect(h, viz).toContain("Table");
    }
  });
  it("shows the comparison on a number and opens leads only for non-zero values", () => {
    const h = renderToStaticMarkup(<Chart viz="kpi" result={kpi} defs={defs} dimLabels={{}} onDrill={() => {}} />);
    expect(h).toContain("12.5%");
    expect(h).toContain("+25%");
    const t = renderToStaticMarkup(<Chart viz="table" result={oneDim} defs={defs} dimLabels={{ day: "Day" }} onDrill={() => {}} />);
    expect((t.match(/Open the leads behind this number/g) ?? []).length).toBe(4);
  });
  it("says so when there is no data", () => {
    expect(renderToStaticMarkup(<Chart viz="bar" result={{ ...oneDim, rows: [] }} defs={defs} dimLabels={{}} />)).toContain("No data");
  });
});

describe("commission lines", () => {
  it("show the programme, every partner considered with its rate, and the one used", () => {
    const rate = (v: number) => ({ id: "r", scope: "partner", rate_type: "percent", value: v, tiers: null, fee_base: "first_year", valid_from: "2026-01-01", gst_inclusive: false });
    const line: CommissionLine = { id: 1, kind: "booking", status: "provisional", amount: 22500, tds: 0, fee: 179000, base: 90000, rate: { pct: 25, base: 90000, amount: 22500 },
      rate_source: "partner", rate_used: { partner_id: 2, name: "Partner B", rate: rate(25) }, override: null, reason: null, run_id: null, due_on: null, flagged: false,
      partners: [{ partner_id: 1, name: "Partner A", rate: rate(20), computed: { pct: 20, base: 90000, amount: 18000 } }, { partner_id: 2, name: "Partner B", rate: rate(25), computed: { pct: 25, base: 90000, amount: 22500 } }],
      lead_id: 9, student: "Asha Test", programme: "Online MBA", university: "Amity", enrolled_on: "2026-09-02", enrollment_id: 9, enrollment_status: "verified", counsellor_id: "u", created_at: "2026-09-02", expected_settlement: "2026-10-05" };
    const h = renderToStaticMarkup(<CommissionLines lines={[line]} leadHref={(id) => `/s/leads/${id}`} />);
    for (const s of ["Online MBA", "Partner A", "Partner B (used)", "20% of the first-year fee", "25% of the first-year fee", "highest partner rate"]) expect(h).toContain(s);
  });
});
