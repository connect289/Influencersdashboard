import { describe, expect, it } from "vitest";
import { amountInWords, formatInr, isoDate, monthLabel, stateOfGstin, statementRows, suggestStatementMapping, tierWatch } from "./money";

describe("formatInr", () => {
  it("formats rupees the Indian way, with a real minus", () => {
    expect(formatInr(5310000)).toBe("₹53,10,000");
    expect(formatInr(-15000)).toBe("−₹15,000");
    expect(formatInr(1234.5, true)).toBe("₹1,234.50");
    expect(formatInr(null)).toBe("—");
  });
});

describe("amountInWords", () => {
  it("uses lakh and crore", () => {
    expect(amountInWords(53100)).toBe("Rupees Fifty Three Thousand One Hundred Only");
    expect(amountInWords(1250000.5)).toBe("Rupees Twelve Lakh Fifty Thousand and Fifty Paise Only");
    expect(amountInWords(30000000)).toBe("Rupees Three Crore Only");
    expect(amountInWords(0)).toBe("Rupees Zero Only");
  });
});

describe("tierWatch", () => {
  const tiers = [{ from_pct: 0, pct: 22.42 }, { from_pct: 7, pct: 20.42 }, { from_pct: 9, pct: 18.42 }];
  it("finds the current tier and the enrolments to the next", () => {
    expect(tierWatch(tiers, 100, 5)).toEqual({ conversion_pct: 5, current: tiers[0], next: tiers[1], enrollments_to_next: 2 });
    expect(tierWatch(tiers, 100, 8)?.current).toEqual(tiers[1]);
    expect(tierWatch(tiers, 100, 12)?.next).toBe(null);
    expect(tierWatch(tiers, 0, 0)).toEqual({ conversion_pct: null, current: tiers[0], next: tiers[1], enrollments_to_next: null });
    expect(tierWatch(null, 10, 1)).toBe(null);
  });
});

describe("dates and GSTIN", () => {
  it("reads day-first dates", () => {
    expect(isoDate("20/09/2026")).toBe("2026-09-20");
    expect(isoDate("2026-09-20")).toBe("2026-09-20");
    expect(isoDate("20 Sep 2026")).toBe("2026-09-20");
    expect(isoDate("31/02/2026")).toBe(null);
    expect(monthLabel("2026-09")).toBe("Sep 2026");
  });
  it("takes the state from a GSTIN", () => {
    expect(stateOfGstin("29BBBBB1111B1Z5")).toBe("29");
    expect(stateOfGstin("29BBB")).toBe(null);
  });
});

describe("statement upload", () => {
  it("suggests columns and builds rows", () => {
    const headers = ["Sr", "Student Name", "Mobile", "Eduwit Ref", "Course", "Admission Date", "Commission Payable"];
    const map = suggestStatementMapping(headers);
    expect(map).toEqual({ reference: "Eduwit Ref", phone: "Mobile", name: "Student Name", programme: "Course", enrolled_on: "Admission Date", amount_inr: "Commission Payable" });
    const rows = statementRows([
      { "Student Name": "Asha", Mobile: "98765 43210", "Eduwit Ref": "EDW-1", Course: "MBA", "Admission Date": "20/09/2026", "Commission Payable": "30,000" },
      { "Student Name": "", Mobile: "", "Eduwit Ref": "", Course: "", "Admission Date": "", "Commission Payable": "Total 30,000" },
    ], map);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ reference: "EDW-1", phone: "98765 43210", enrolled_on: "2026-09-20", amount_inr: "30,000" });
  });
});
