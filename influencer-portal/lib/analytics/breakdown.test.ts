import { describe, expect, it } from "vitest";
import { EMPTY_TOTALS } from "./compute";
import { breakdownCsv, sortBreakdown, toBreakdown } from "./breakdown";

const rows = [
  {
    ...EMPTY_TOTALS,
    key: "instagram",
    leads: 10,
    qualified: 4,
    enrolled: 1,
    cost_paise: 5_000_00,
    revenue_paise: 12_000_00,
  },
  { ...EMPTY_TOTALS, key: null, cost_paise: 15_000_00 },
  { ...EMPTY_TOTALS, key: "youtube", leads: 20, attributions: 25, duplicates: 5 },
];

describe("breakdowns", () => {
  it("derives unit economics and quality per row", () => {
    const [ig] = toBreakdown(rows, (r) => r.key ?? "Not split");
    expect(ig).toMatchObject({
      label: "instagram",
      cost_per_lead_paise: 500_00,
      cost_per_enrollment_paise: 5_000_00,
      net_roi: 1.4,
      roas: 2.4,
      qualification_rate: 0.4,
    });
  });

  it("puts the most leads first and unsplit rows last", () => {
    expect(sortBreakdown(toBreakdown(rows, (r) => r.key ?? "Not split")).map((r) => r.key)).toEqual([
      "youtube",
      "instagram",
      null,
    ]);
  });

  it("exports rupees and percentages with blanks where undefined", () => {
    const csv = breakdownCsv(
      toBreakdown(rows, (r) => r.key ?? "Not split"),
      "Platform",
    );
    const lines = csv.trim().split("\r\n");
    expect(lines[0]).toMatch(/^Platform,Clicks,Leads/);
    expect(lines[1]).toBe("instagram,0,10,4,1,0,0,5000.00,12000.00,500.00,1250.00,5000.00,140.0,2.40,40.0,0.0,,10.0");
    expect(lines[2]).toBe("Not split,0,0,0,0,0,0,15000.00,0.00,,,,-100.0,0.00,,,,");
  });
});
