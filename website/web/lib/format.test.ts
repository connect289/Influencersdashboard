import { describe, expect, it } from "vitest";
import { formatDate, formatDuration, formatInr, formatInrCompact, formatInrRange } from "./format";

describe("money formatting (Indian grouping)", () => {
  it("formats full rupees with lakh grouping", () => {
    expect(formatInr(100000)).toBe("₹1,00,000");
    expect(formatInr(1234567)).toBe("₹12,34,567");
    expect(formatInr(85000.4)).toBe("₹85,000");
  });
  it("formats compact values in K, lakh and crore", () => {
    expect(formatInrCompact(950)).toBe("₹950");
    expect(formatInrCompact(85000)).toBe("₹85K");
    expect(formatInrCompact(120000)).toBe("₹1.2 lakh");
    expect(formatInrCompact(125000)).toBe("₹1.25 lakh");
    expect(formatInrCompact(25000000)).toBe("₹2.5 crore");
  });
  it("formats ranges and collapses equal ends", () => {
    expect(formatInrRange(85000, 120000)).toBe("₹85K – ₹1.2 lakh");
    expect(formatInrRange(100000, 100000)).toBe("₹1 lakh");
  });
});

describe("durations and dates", () => {
  it("formats months as years where whole", () => {
    expect(formatDuration(24)).toBe("2 years");
    expect(formatDuration(12)).toBe("1 year");
    expect(formatDuration(18)).toBe("1 year 6 months");
    expect(formatDuration(6)).toBe("6 months");
  });
  it("formats verification dates for India", () => {
    expect(formatDate("2026-09-30T16:19:26Z")).toMatch(/^30 Sept? 2026$/);
  });
});
