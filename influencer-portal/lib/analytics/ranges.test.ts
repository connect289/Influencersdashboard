import { describe, expect, it } from "vitest";
import {
  bucketFor,
  bucketStart,
  bucketStarts,
  fillSeries,
  fyStart,
  makeRange,
  MAX_RANGE_DAYS,
  parseRange,
  rangeParams,
  RANGE_PRESETS,
} from "./ranges";

const TODAY = "2026-10-17"; // a Saturday

describe("date range presets", () => {
  it.each([
    ["today", "2026-10-17", "2026-10-17", 1],
    ["7d", "2026-10-11", "2026-10-17", 7],
    ["30d", "2026-09-18", "2026-10-17", 30],
    ["90d", "2026-07-20", "2026-10-17", 90],
    ["this_month", "2026-10-01", "2026-10-17", 17],
    ["last_month", "2026-09-01", "2026-09-30", 30],
    ["this_fy", "2026-04-01", "2026-10-17", 200],
  ] as const)("%s runs from %s to %s (%i days)", (preset, from, to, days) => {
    expect(makeRange(preset, TODAY)).toMatchObject({ preset, from, to, days });
  });

  it("compares with the same number of days just before", () => {
    expect(makeRange("7d", TODAY).previous).toEqual({ from: "2026-10-04", to: "2026-10-10" });
    expect(makeRange("last_month", TODAY).previous).toEqual({ from: "2026-08-02", to: "2026-08-31" });
    expect(makeRange("today", TODAY).previous).toEqual({ from: "2026-10-16", to: "2026-10-16" });
  });

  it("handles January and the start of a financial year", () => {
    expect(makeRange("last_month", "2027-01-05")).toMatchObject({ from: "2026-12-01", to: "2026-12-31" });
    expect(fyStart("2027-03-31")).toBe("2026-04-01");
    expect(fyStart("2027-04-01")).toBe("2027-04-01");
    expect(makeRange("this_fy", "2027-04-01")).toMatchObject({ from: "2027-04-01", days: 1 });
  });

  it("cleans custom ranges: swapped, future and too long", () => {
    expect(makeRange("custom", TODAY, { from: "2026-10-10", to: "2026-10-01" })).toMatchObject({
      from: "2026-10-01",
      to: "2026-10-01",
    });
    expect(makeRange("custom", TODAY, { from: "2026-10-01", to: "2027-01-01" })).toMatchObject({ to: TODAY });
    expect(makeRange("custom", TODAY, { from: "2020-01-01", to: TODAY }).days).toBe(MAX_RANGE_DAYS);
    expect(makeRange("custom", TODAY, { from: "nope", to: TODAY }).preset).toBe("30d");
  });

  it("reads the URL and writes it back", () => {
    expect(parseRange({}, TODAY)).toMatchObject({ preset: "30d", compare: true });
    expect(parseRange({ range: "bogus", compare: "0" }, TODAY)).toMatchObject({ preset: "30d", compare: false });
    const custom = parseRange({ range: "custom", from: "2026-09-01", to: "2026-09-15" }, TODAY);
    expect(rangeParams(custom)).toEqual({ range: "custom", from: "2026-09-01", to: "2026-09-15" });
    expect(rangeParams(parseRange({}, TODAY))).toEqual({});
    for (const p of RANGE_PRESETS.filter((x) => x !== "custom"))
      expect(parseRange(rangeParams(makeRange(p, TODAY)), TODAY).preset).toBe(p);
    // A custom range without dates falls back to the default.
    expect(makeRange("custom", TODAY).preset).toBe("30d");
  });
});

describe("buckets and series", () => {
  it("uses days, weeks or months by length", () => {
    expect([bucketFor(1), bucketFor(62), bucketFor(63), bucketFor(366), bucketFor(367)]).toEqual([
      "day",
      "day",
      "week",
      "week",
      "month",
    ]);
  });

  it("starts weeks on Monday and months on the 1st", () => {
    expect(bucketStart(TODAY, "week")).toBe("2026-10-12");
    expect(bucketStart("2026-10-12", "week")).toBe("2026-10-12");
    expect(bucketStart(TODAY, "month")).toBe("2026-10-01");
    expect(bucketStarts("2026-11-20", "2027-02-03", "month")).toEqual([
      "2026-11-01",
      "2026-12-01",
      "2027-01-01",
      "2027-02-01",
    ]);
  });

  it("fills gaps with zeros and adds points in the same bucket", () => {
    expect(
      fillSeries(
        [
          { at: "2026-10-13", value: 2 },
          { at: "2026-10-15T10:00:00Z", value: 1 },
          { at: "2026-10-15", value: 3 },
        ],
        "2026-10-13",
        "2026-10-16",
        "day",
      ),
    ).toEqual([
      { at: "2026-10-13", value: 2 },
      { at: "2026-10-14", value: 0 },
      { at: "2026-10-15", value: 4 },
      { at: "2026-10-16", value: 0 },
    ]);
  });
});
