import { describe, expect, it } from "vitest";
import { WatchdogGate, watchdogOk } from "./watchdog.ts";

describe("watchdogOk", () => {
  it("is down on a stale tick, a waiting alert or no reading", () => {
    expect(watchdogOk({ tick_age_s: 60, app_age_s: 30, delivery_wait_s: null })).toBe(true);
    expect(watchdogOk({ tick_age_s: 300, app_age_s: 30, delivery_wait_s: null })).toBe(false);
    expect(watchdogOk({ tick_age_s: 60, app_age_s: 30, delivery_wait_s: 600 })).toBe(false);
    expect(watchdogOk(undefined)).toBe(false);
  });
});

describe("WatchdogGate (security review m5)", () => {
  it("answers from the cache for 10 s with the same verdict, then reads again", () => {
    const g = new WatchdogGate();
    expect(g.take(1_000)).toEqual({ kind: "fresh" });
    g.remember(false, 1_000);
    expect(g.take(1_000 + 9_999)).toEqual({ kind: "cached", ok: false });
    expect(g.take(1_000 + 10_000)).toEqual({ kind: "fresh" });
    g.remember(true, 11_000);
    expect(g.take(12_000)).toEqual({ kind: "cached", ok: true });
  });

  it("refuses the 21st request within a minute on this instance, and lets requests through as old ones age out", () => {
    const g = new WatchdogGate();
    for (let i = 0; i < 20; i++) expect(g.take(i * 1_000).kind).not.toBe("limited");
    expect(g.take(20_000)).toEqual({ kind: "limited" });
    expect(g.take(59_999)).toEqual({ kind: "limited" });
    expect(g.take(60_000).kind).not.toBe("limited");
    expect(g.take(60_001)).toEqual({ kind: "limited" });
  });
});
