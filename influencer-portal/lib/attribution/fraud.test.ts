import { describe, expect, it } from "vitest";
import { creatorSignals, isOffHours, leadSignals, type FraudSettings } from "./fraud";

const s: FraudSettings = {
  velocity_leads_per_hour: 30,
  same_device_max_leads: 3,
  no_witty_reply_hours: 48,
  off_hours_start: "00:30",
  off_hours_end: "06:00",
  off_hours_burst: 5,
  junk_rate_pct: 40,
  min_sample: 10,
};

describe("lead signals", () => {
  it("flags the same device behind more leads than allowed", () => {
    expect(leadSignals({ same_device_leads: 3, age_hours: 1, student_replied: true }, s)).toEqual([]);
    expect(leadSignals({ same_device_leads: 4, age_hours: 1, student_replied: true }, s)).toEqual([
      { signal: "same_device", detail: { leads: 4, max: 3 } },
    ]);
  });
  it("flags a lead that never answered Witty after the threshold", () => {
    expect(leadSignals({ same_device_leads: 1, age_hours: 47.9, student_replied: false }, s)).toEqual([]);
    expect(leadSignals({ same_device_leads: 1, age_hours: 48.5, student_replied: false }, s)).toEqual([
      { signal: "no_witty_reply", detail: { hours: 48, threshold: 48 } },
    ]);
    expect(leadSignals({ same_device_leads: 1, age_hours: 500, student_replied: null }, s)).toEqual([]);
  });
});

describe("creator signals", () => {
  const quiet = { leads_last_hour: 2, off_hours_leads_24h: 0, closed_30d: 20, junk_30d: 1 };
  it("is quiet for normal activity", () => {
    expect(creatorSignals(quiet, s)).toEqual([]);
  });
  it("flags velocity, off-hours bursts and a high junk rate", () => {
    expect(creatorSignals({ ...quiet, leads_last_hour: 31 }, s).map((x) => x.signal)).toEqual(["velocity"]);
    expect(creatorSignals({ ...quiet, off_hours_leads_24h: 5 }, s).map((x) => x.signal)).toEqual(["off_hours_burst"]);
    expect(creatorSignals({ ...quiet, junk_30d: 8 }, s)).toEqual([
      { signal: "junk_rate", detail: { pct: 40, threshold: 40, sample: 20 } },
    ]);
  });
  it("needs a minimum sample before judging the junk rate", () => {
    expect(creatorSignals({ ...quiet, closed_30d: 9, junk_30d: 9 }, s)).toEqual([]);
  });
});

describe("off hours (IST)", () => {
  it("handles a window inside one day", () => {
    expect(isOffHours("2026-11-01T18:59:00Z", "00:30", "06:00")).toBe(false); // 00:29 IST
    expect(isOffHours("2026-11-01T19:00:00Z", "00:30", "06:00")).toBe(true); // 00:30 IST
    expect(isOffHours("2026-11-01T19:01:00Z", "00:30", "06:00")).toBe(true);
    expect(isOffHours("2026-11-02T00:29:00Z", "00:30", "06:00")).toBe(true); // 05:59 IST
    expect(isOffHours("2026-11-02T00:30:00Z", "00:30", "06:00")).toBe(false); // 06:00 IST
  });
  it("handles a window that wraps midnight", () => {
    expect(isOffHours("2026-11-01T18:00:00Z", "23:00", "05:00")).toBe(true); // 23:30 IST
    expect(isOffHours("2026-11-01T22:00:00Z", "23:00", "05:00")).toBe(true); // 03:30 IST
    expect(isOffHours("2026-11-02T06:00:00Z", "23:00", "05:00")).toBe(false); // 11:30 IST
  });
});
