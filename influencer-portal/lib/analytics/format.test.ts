import { describe, expect, it } from "vitest";
import { EMPTY, formatChange, formatMetric } from "./format";

describe("formatMetric", () => {
  it("formats by unit with Indian grouping", () => {
    expect(formatMetric("count", 1234567)).toBe("12,34,567");
    expect(formatMetric("money", 1_23_456_78)).toBe("₹1,23,457");
    expect(formatMetric("money", 1_23_456_78, { whole: false })).toBe("₹1,23,456.78");
    expect(formatMetric("percent", 0.125)).toBe("12.5%");
    expect(formatMetric("percent", 0.4)).toBe("40%");
    expect(formatMetric("percent", 1.4)).toBe("140%");
    expect(formatMetric("ratio", 2.4)).toBe("2.4×");
    expect(formatMetric("date", "2026-10-19")).toMatch(/19 Oct 2026/);
  });

  it("shows a dash for missing values", () => {
    expect(formatMetric("percent", null)).toBe(EMPTY);
    expect(formatMetric("money", null)).toBe(EMPTY);
  });
});

describe("formatChange", () => {
  it("signs relative changes", () => {
    expect(formatChange(0.123)).toBe("+12%");
    expect(formatChange(-0.05)).toBe("−5%");
    expect(formatChange(0.001)).toBe("0%");
    expect(formatChange(null)).toBeNull();
  });
});
