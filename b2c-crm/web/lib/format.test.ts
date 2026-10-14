import { describe, expect, it } from "vitest";
import { fromLocalInput, inr, istDay, maskPhone, quickTimes, toLocalInput, when } from "./format";
import { internalKeyOk } from "./internal";

describe("IST display", () => {
  const now = new Date("2026-10-14T06:00:00Z"); // 11:30 IST
  it("names today and tomorrow in India time", () => {
    expect(when("2026-10-14T12:30:00Z", now)).toBe("Today 18:00");
    expect(when("2026-10-15T04:30:00Z", now)).toBe("Tomorrow 10:00");
    expect(when("2026-10-13T20:00:00Z", now)).toBe("Today 01:30");
  });
  it("round-trips a datetime-local value as IST", () => {
    expect(fromLocalInput("2026-10-15T10:30")).toBe("2026-10-15T05:00:00.000Z");
    expect(toLocalInput(new Date("2026-10-15T05:00:00Z"))).toBe("2026-10-15T10:30");
    expect(fromLocalInput("garbage")).toBeNull();
  });
  it("offers this evening only while it is still ahead", () => {
    expect(quickTimes(now).map((q) => q.label)).toEqual(["In 3 hours", "Today 18:00", "Tomorrow 10:00", "In 2 days"]);
    expect(quickTimes(new Date("2026-10-14T13:00:00Z")).map((q) => q.label)).not.toContain("Today 18:00");
  });
  it("uses the IST day near midnight", () => {
    expect(istDay(new Date("2026-10-14T19:00:00Z"))).toBe("2026-10-15");
  });
  it("formats rupees and phones", () => {
    expect(inr(179000)).toBe("₹1,79,000");
    expect(inr(null)).toBe("—");
    expect(maskPhone("919876543210")).toBe("+91 98765 43210");
  });
});

describe("internal key", () => {
  it("needs a long key that matches exactly", () => {
    const k = "k".repeat(40);
    expect(internalKeyOk(k, k)).toBe(true);
    expect(internalKeyOk(k + "x", k)).toBe(false);
    expect(internalKeyOk(null, k)).toBe(false);
    expect(internalKeyOk("short", "short")).toBe(false);
  });
});
