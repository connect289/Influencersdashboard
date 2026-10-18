import { describe, expect, it } from "vitest";
import {
  financialYear,
  formatCompact,
  formatDate,
  formatDateTime,
  formatPaise,
  formatRelative,
  fyQuarter,
  istParts,
} from "./format";

describe("money", () => {
  it.each([
    [12345600n, "₹1,23,456.00"],
    [1n, "₹0.01"],
    [0n, "₹0.00"],
    [-50050n, "-₹500.50"],
    [1000000000099n, "₹10,00,00,00,000.99"],
  ])("%s paise → %s", (p, out) => expect(formatPaise(p)).toBe(out));
  it("rounds whole rupees half up for display only", () => {
    expect(formatPaise(12350n, { whole: true })).toBe("₹124");
    expect(formatPaise(12349n, { whole: true })).toBe("₹123");
  });
  it("formats compact Indian units", () => {
    expect(formatCompact(1200)).toBe("1.2K");
    expect(formatCompact(340000)).toBe("3.4L");
    expect(formatCompact(11000000)).toBe("1.1Cr");
    expect(formatCompact(999)).toBe("999");
  });
});

describe("dates in IST", () => {
  it("shows the IST calendar date (UTC evening is the next day in India)", () => {
    expect(formatDate("2026-10-16T20:00:00Z")).toBe("17 Oct 2026");
    expect(formatDateTime("2026-10-16T20:00:00Z")).toBe("17 Oct 2026, 01:30 IST");
    expect(istParts("2026-03-31T19:00:00Z")).toEqual({ year: 2026, month: 4, day: 1 });
  });
  it("relative times", () => {
    const now = new Date("2026-10-16T12:00:00Z");
    expect(formatRelative("2026-10-16T10:00:00Z", now)).toBe("2 hours ago");
    expect(formatRelative("2026-10-19T12:00:00Z", now)).toBe("in 3 days");
    expect(formatRelative("2026-10-16T11:59:40Z", now)).toBe("just now");
  });
});

describe("Indian financial year", () => {
  it("starts on 1 April in IST", () => {
    expect(financialYear("2026-03-31T18:29:59Z")).toBe("2025-26"); // 23:59:59 IST on 31 Mar
    expect(financialYear("2026-03-31T18:30:00Z")).toBe("2026-27"); // 00:00 IST on 1 Apr
    expect(financialYear("2099-12-31T00:00:00Z")).toBe("2099-00");
  });
  it("quarters", () => {
    expect(fyQuarter("2026-04-01T00:00:00+05:30")).toBe("Q1");
    expect(fyQuarter("2026-09-30T12:00:00+05:30")).toBe("Q2");
    expect(fyQuarter("2026-12-31T12:00:00+05:30")).toBe("Q3");
    expect(fyQuarter("2027-03-31T12:00:00+05:30")).toBe("Q4");
  });
});
