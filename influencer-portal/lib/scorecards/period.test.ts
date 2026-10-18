import { describe, expect, it } from "vitest";
import { periodRange, previousPeriod } from "./period";

describe("scorecard periods", () => {
  it("covers the whole month", () => {
    expect(periodRange("2026-10")).toEqual({ from: "2026-10-01", to: "2026-10-31" });
    expect(periodRange("2028-02")).toEqual({ from: "2028-02-01", to: "2028-02-29" });
    expect(periodRange("2027-02")).toEqual({ from: "2027-02-01", to: "2027-02-28" });
  });

  it("knows the month just ended", () => {
    expect(previousPeriod("2026-11-01")).toBe("2026-10");
    expect(previousPeriod("2027-01-01")).toBe("2026-12");
  });
});
