import { describe, expect, it } from "vitest";
import type { OfferingDetails } from "@/lib/search/types";
import { bestIndex, compareRows } from "./compare";

const base = (over: Partial<OfferingDetails>): OfferingDetails =>
  ({
    id: 1, group_key: "mba:marketing", programme_id: "mba", programme_name: "MBA", level_id: "pg", level_short: "PG",
    spec_ids: ["marketing"], spec_name: "Marketing", university: { slug: "u", name: "U" }, fee: {}, programme_full: "",
    level_label: "", category_id: "", category_label: "", program_name: "", mode: "Online", ...over,
  }) as OfferingDetails;

describe("compare rows", () => {
  const a = base({ id: 1, fee: { total: 100000 }, naac_grade: "A+", duration_months: 24 });
  const b = base({ id: 2, fee: { total: 150000 }, naac_grade: "A++", duration_months: 24 });
  const rows = compareRows([a, b]);

  it("drops rows with no data for any offering", () => {
    expect(rows.find((r) => r.key === "fee_semester")).toBeUndefined();
    expect(rows.find((r) => r.key === "nirf")).toBeUndefined();
  });
  it("marks identical rows", () => {
    expect(rows.find((r) => r.key === "duration")?.identical).toBe(true);
    expect(rows.find((r) => r.key === "fee_total")?.identical).toBe(false);
  });
  it("highlights the lowest fee and the best NAAC", () => {
    expect(bestIndex(rows.find((r) => r.key === "fee_total")!)).toBe(0);
    expect(bestIndex(rows.find((r) => r.key === "naac")!)).toBe(1);
  });
  it("EMI is shown with every offering (D-015)", () => {
    expect(rows.find((r) => r.key === "emi")?.values).toEqual(["Easy EMI available", "Easy EMI available"]);
  });
  it("a row where only one offering has data is not identical", () => {
    const r = compareRows([base({ fee: { total: 1, yearly: 5 } }), base({ fee: { total: 1 } })]).find((x) => x.key === "fee_yearly");
    expect(r?.identical).toBe(false);
  });
});
