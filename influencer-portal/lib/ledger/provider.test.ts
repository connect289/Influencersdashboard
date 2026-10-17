import { describe, expect, it } from "vitest";
import { bankFileProvider, payoutProvider } from "./provider";

const row = {
  beneficiary_name: "Riya Sharma",
  account_number: "50100123456789",
  ifsc: "hdfc0001234",
  net_paise: 9_000_00,
  payout_ref: "PO-2026-27-00002",
  email: null,
  creator_code: "riyalearns",
};

describe("payout providers", () => {
  it("defaults to the bank file, which moves no money", () => {
    expect(payoutProvider()).toBe(bankFileProvider);
    expect(payoutProvider("")).toBe(bankFileProvider);
    expect(bankFileProvider.movesMoney).toBe(false);
  });

  it("refuses providers that are not built", () => {
    expect(() => payoutProvider("razorpayx")).toThrow(/unknown payout provider/);
  });

  it("returns the bank file named after the batch, CSV or TSV by delimiter", () => {
    const csv = bankFileProvider.dispatch("PB-2026-27-0001", [row], {
      delimiter: ",",
      header: false,
      columns: ["account_number", "ifsc", "amount_inr"],
    });
    expect(csv).toEqual({
      kind: "file",
      filename: "PB-2026-27-0001.csv",
      contentType: "text/csv; charset=utf-8",
      body: expect.stringContaining("50100123456789,HDFC0001234,9000.00") as string,
    });
    const tsv = bankFileProvider.dispatch("PB-2026-27-0001", [row], {
      delimiter: "\t",
      header: true,
      columns: ["amount_inr"],
    });
    expect(tsv).toMatchObject({
      filename: "PB-2026-27-0001.tsv",
      contentType: "text/tab-separated-values; charset=utf-8",
    });
  });
});
