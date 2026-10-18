import { describe, expect, it } from "vitest";
import { bankFile, narration, rupeesPlain, type BankRow } from "./bank-file";
import { gstinCheckChar, invoiceProblems, validGstin } from "./invoice";
import { parseBankDate, parseUtrFile } from "./utr";

const row: BankRow = {
  beneficiary_name: "Riya Sharma",
  account_number: "001234567890",
  ifsc: "hdfc0001234",
  net_paise: 1_234_550,
  payout_ref: "PO-2026-27-00042",
  email: "riya@example.test",
  creator_code: "RIYALEARNS",
};

describe("bank file", () => {
  it("formats amounts as plain rupees with two decimals", () => {
    expect(rupeesPlain(1_234_550)).toBe("12345.50");
    expect(rupeesPlain(5)).toBe("0.05");
    expect(() => rupeesPlain(-1)).toThrow();
    expect(() => rupeesPlain(1.5)).toThrow();
  });

  it("writes the configured columns and delimiter, with or without a header", () => {
    const csv = bankFile([row], {
      delimiter: ",",
      header: true,
      columns: ["beneficiary_name", "account_number", "ifsc", "amount_inr", "narration"],
    });
    expect(csv).toBe(
      "Beneficiary name,Account number,IFSC,Amount,Narration\r\nRiya Sharma,001234567890,HDFC0001234,12345.50,Eduwit payout PO 2026 27 00042\r\n",
    );
    const piped = bankFile([row], {
      delimiter: "|",
      header: false,
      columns: ["payout_ref", "amount_inr", "creator_code"],
    });
    expect(piped).toBe("PO-2026-27-00042|12345.50|RIYALEARNS\r\n");
  });

  it("cleans names banks would reject and keeps narrations short", () => {
    const csv = bankFile([{ ...row, beneficiary_name: 'Riya "RS" Sharma, MBA' }], {
      delimiter: ";",
      header: false,
      columns: ["beneficiary_name"],
    });
    expect(csv).toBe("Riya RS Sharma MBA\r\n");
    expect(narration("PO-2026-27-00042-EXTRA-LONG").length).toBeLessThanOrEqual(30);
  });

  it("refuses zero or negative payouts", () => {
    expect(() =>
      bankFile([{ ...row, net_paise: 0 }], {
        delimiter: ",",
        header: false,
        columns: ["amount_inr", "ifsc", "payout_ref"],
      }),
    ).toThrow();
  });
});

describe("UTR file", () => {
  it("reads common date shapes and refuses impossible dates", () => {
    expect(parseBankDate("2026-11-30")).toBe("2026-11-30");
    expect(parseBankDate("30/11/2026")).toBe("2026-11-30");
    expect(parseBankDate("30-11-2026")).toBe("2026-11-30");
    expect(parseBankDate("31/11/2026")).toBeNull();
    expect(parseBankDate("11/30")).toBeNull();
  });

  it("accepts header variants and normalises case", () => {
    const r = parseUtrFile(
      "Reference,UTR Number,Value date\npo-2026-27-00042,hdfcn52026113012345,30/11/2026\n",
      "2026-12-01",
    );
    expect(r.errors).toEqual([]);
    expect(r.rows).toEqual([{ payout_ref: "PO-2026-27-00042", utr: "HDFCN52026113012345", paid_on: "2026-11-30" }]);
  });

  it("reports every bad row and applies nothing", () => {
    const text = [
      "payout_ref,utr,paid_on",
      "PO-2026-27-00001,HDFCN52026113012345,2026-11-30",
      "BAD,HDFCN52026113012346,2026-11-30",
      "PO-2026-27-00002,short,2026-11-30",
      "PO-2026-27-00003,HDFCN52026113012347,2026-13-01",
      "PO-2026-27-00004,HDFCN52026113012348,2026-12-25",
      "PO-2026-27-00001,HDFCN52026113012349,2026-11-30",
    ].join("\n");
    const r = parseUtrFile(text, "2026-12-01");
    expect(r.rows).toEqual([]);
    expect(r.errors).toEqual([
      { line: 3, code: "bad_ref" },
      { line: 4, code: "bad_utr" },
      { line: 5, code: "bad_date" },
      { line: 6, code: "future_date" },
      { line: 7, code: "duplicate" },
    ]);
  });

  it("needs the three columns and a readable file", () => {
    expect(parseUtrFile("ref,utr\nPO-2026-27-00001,X\n", "2026-12-01").errors).toEqual([
      { line: 1, code: "missing_column" },
    ]);
    expect(parseUtrFile('ref,utr,date\n"unterminated', "2026-12-01").errors).toEqual([{ line: 1, code: "file" }]);
  });
});

describe("GST invoice", () => {
  const stem = "27ABCPS1234K1Z";
  const gstin = stem + gstinCheckChar(stem);

  it("checks the GSTIN check character", () => {
    expect(validGstin(gstin)).toBe(true);
    expect(validGstin(gstin.toLowerCase())).toBe(true);
    const wrong = stem + (gstin.endsWith("A") ? "B" : "A");
    expect(validGstin(wrong)).toBe(false);
    expect(validGstin("27ABCPS1234K1X5")).toBe(false);
  });

  const payout = { gst_base_paise: 10_000_00, gst_paise: 1_800_00, created_on: "2026-11-25" };
  const inv = { number: "RS/26-27/007", issued_on: "2026-11-28", gstin, taxable_paise: 10_000_00, gst_paise: 1_800_00 };

  it("accepts a matching invoice, within ₹1 of rounding", () => {
    expect(invoiceProblems(inv, payout, gstin, "2026-12-01")).toEqual([]);
    expect(invoiceProblems({ ...inv, gst_paise: 1_800_99 }, payout, gstin, "2026-12-01")).toEqual([]);
  });

  it("lists every problem", () => {
    const other = "29ABCPS1234K1Z";
    expect(
      invoiceProblems(
        {
          number: "NO SPACES ALLOWED!",
          issued_on: "2026-12-05",
          gstin: other + gstinCheckChar(other),
          taxable_paise: 9_000_00,
          gst_paise: 1_000_00,
        },
        payout,
        gstin,
        "2026-12-01",
      ),
    ).toEqual(["number", "date_future", "gstin_mismatch", "taxable_mismatch", "gst_mismatch"]);
    expect(invoiceProblems({ ...inv, issued_on: "2026-11-01", gstin: "BAD" }, payout, gstin, "2026-12-01")).toEqual([
      "date_before_payout",
      "gstin_invalid",
    ]);
  });
});
