import { describe, expect, it } from "vitest";
import type { LedgerLine } from "./engine";
import { componentOf, DEFAULT_TDS_SECTIONS, estimateTax, type TaxInput } from "./tax";

const l = (type: LedgerLine["type"], amount: number, direction: "credit" | "debit" = "credit") => ({
  type,
  direction,
  amount_paise: amount,
});
const base: Omit<TaxInput, "lines"> = {
  sections: DEFAULT_TDS_SECTIONS,
  has_pan: true,
  gst: { registered: false, rate_bps: 1800 },
};
const section = (r: ReturnType<typeof estimateTax>, code: string) => r.sections.find((s) => s.code === code);

describe("estimateTax", () => {
  it("applies 194H above the FY threshold and leaves fees under theirs untaxed", () => {
    const r = estimateTax({ ...base, lines: [l("commission", 25_000_00), l("milestone", 40_000_00)] });
    expect(section(r, "194H")).toMatchObject({ base_paise: 25_000_00, taxable_paise: 25_000_00, tds_paise: 500_00 });
    expect(section(r, "194J")).toMatchObject({ base_paise: 40_000_00, taxable_paise: 0, tds_paise: 0 });
    expect(r).toMatchObject({ gross_paise: 65_000_00, tds_paise: 500_00, gst_paise: 0, net_paise: 64_500_00 });
  });

  it("catches up on the FY's untaxed amounts when the threshold is first crossed", () => {
    const lines = [l("fixed_fee", 25_000_00)];
    const untaxed = estimateTax({ ...base, lines, fy_prior: { "194J": { base_paise: 30_000_00, taxed: false } } });
    expect(section(untaxed, "194J")).toMatchObject({ taxable_paise: 55_000_00, tds_paise: 5_500_00 });
    const taxed = estimateTax({ ...base, lines, fy_prior: { "194J": { base_paise: 60_000_00, taxed: true } } });
    expect(section(taxed, "194J")).toMatchObject({ taxable_paise: 25_000_00, tds_paise: 2_500_00 });
  });

  it("charges the higher rate without a PAN (206AA)", () => {
    const r = estimateTax({ ...base, has_pan: false, lines: [l("commission", 25_000_00)] });
    expect(section(r, "194H")).toMatchObject({ rate_bps: 2000, tds_paise: 5_000_00 });
  });

  it("nets clawbacks and engine adjustments into commission, never below zero", () => {
    expect(componentOf({ type: "clawback" })).toBe("commission");
    expect(componentOf({ type: "adjustment" })).toBe("commission");
    expect(componentOf({ type: "usage_fee" })).toBe("usage_fee");
    const r = estimateTax({ ...base, lines: [l("commission", 30_000_00), l("clawback", 12_000_00, "debit")] });
    expect(section(r, "194H")).toMatchObject({ base_paise: 18_000_00, tds_paise: 0 });
    const neg = estimateTax({ ...base, lines: [l("commission", 1_000_00), l("clawback", 3_000_00, "debit")] });
    expect(neg.sections).toEqual([]);
    expect(neg.gross_paise).toBe(-2_000_00);
  });

  it("adds GST for a registered creator, excluding reimbursements, and computes TDS without GST", () => {
    const r = estimateTax({
      ...base,
      gst: { registered: true, rate_bps: 1800 },
      lines: [l("milestone", 60_000_00), l("reimbursement", 5_000_00)],
    });
    expect(r.gst_paise).toBe(10_800_00);
    expect(section(r, "194J")?.tds_paise).toBe(6_000_00);
    expect(r.unmapped_paise).toBe(5_000_00);
    expect(r.net_paise).toBe(65_000_00 + 10_800_00 - 6_000_00);
  });

  it("reports 194R on barter as Eduwit's liability without deducting it", () => {
    const r = estimateTax({ ...base, lines: [], non_cash_paise: 30_000_00 });
    expect(r).toMatchObject({ gross_paise: 0, tds_paise: 0, eduwit_tds_paise: 3_000_00, net_paise: 0 });
  });

  it("supports a per-transaction threshold", () => {
    const r = estimateTax({
      ...base,
      sections: [
        {
          code: "194C",
          label: "Contract",
          rate_bps: 100,
          no_pan_rate_bps: 2000,
          single_threshold_paise: 30_000_00,
          fy_threshold_paise: 1_00_000_00,
          components: ["fixed_fee"],
          borne_by: "creator",
        },
      ],
      lines: [l("fixed_fee", 35_000_00)],
    });
    expect(r.tds_paise).toBe(350_00);
  });

  it("maps each component to the first section that lists it", () => {
    const h = DEFAULT_TDS_SECTIONS.slice(0, 1);
    const r = estimateTax({
      ...base,
      sections: [...h, ...h.map((x) => ({ ...x, code: "dup" }))],
      lines: [l("commission", 25_000_00)],
    });
    expect(r.sections.map((s) => s.code)).toEqual(["194H"]);
  });
});
