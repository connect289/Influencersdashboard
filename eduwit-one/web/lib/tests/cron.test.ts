import { describe, expect, it } from "vitest";
import { cronMatches, lastScheduled, parseCron, testDue } from "./cron.ts";

const at = (iso: string) => new Date(iso);

describe("cron", () => {
  it("matches steps, ranges and lists", () => {
    expect(cronMatches(parseCron("*/30 * * * *"), at("2026-10-23T10:30:00Z"))).toBe(true);
    expect(cronMatches(parseCron("*/30 * * * *"), at("2026-10-23T10:31:00Z"))).toBe(false);
    expect(cronMatches(parseCron("0 */2 * * *"), at("2026-10-23T14:00:00Z"))).toBe(true);
    expect(cronMatches(parseCron("0 */2 * * *"), at("2026-10-23T15:00:00Z"))).toBe(false);
    expect(cronMatches(parseCron("5 3 * * 1-5"), at("2026-10-23T03:05:00Z"))).toBe(true); // a Friday
    expect(cronMatches(parseCron("5 3 * * 0,6"), at("2026-10-23T03:05:00Z"))).toBe(false);
    expect(cronMatches(parseCron("0 0 1 * 7"), at("2026-10-25T00:00:00Z"))).toBe(true); // a Sunday, not the 1st
  });
  it("refuses what it cannot read", () => {
    for (const bad of ["* * * *", "61 * * * *", "*/0 * * * *", "a * * * *", "5-1 * * * *"]) {
      expect(() => parseCron(bad)).toThrow();
    }
  });
  it("finds the last slot and runs a missed slot once", () => {
    expect(lastScheduled(parseCron("0 * * * *"), at("2026-10-23T10:42:13Z"))?.toISOString()).toBe(
      "2026-10-23T10:00:00.000Z",
    );
    expect(testDue("0 * * * *", null, at("2026-10-23T10:42:00Z"))).toBe(true);
    expect(testDue("0 * * * *", "2026-10-23T10:00:20Z", at("2026-10-23T10:42:00Z"))).toBe(false);
    expect(testDue("0 * * * *", "2026-10-23T08:00:20Z", at("2026-10-23T10:42:00Z"))).toBe(true);
  });
});
