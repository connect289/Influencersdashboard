import { describe, expect, it } from "vitest";
import { READ_LIMIT, WatchdogGate, watchdogOk } from "./watchdog.ts";

describe("watchdogOk", () => {
  it("is down on a stale tick, a waiting alert or no reading", () => {
    expect(watchdogOk({ tick_age_s: 60, app_age_s: 30, delivery_wait_s: null })).toBe(true);
    expect(watchdogOk({ tick_age_s: 300, app_age_s: 30, delivery_wait_s: null })).toBe(false);
    expect(watchdogOk({ tick_age_s: 60, app_age_s: 30, delivery_wait_s: 600 })).toBe(false);
    expect(watchdogOk(undefined)).toBe(false);
  });
});

describe("WatchdogGate (security review m5, D-137)", () => {
  it("answers from the cache for 10 s with the same verdict, then reads again", () => {
    const g = new WatchdogGate();
    expect(g.take(1_000)).toEqual({ kind: "fresh" });
    g.remember(false, 1_000);
    expect(g.take(1_000 + 9_999)).toEqual({ kind: "cached", ok: false });
    expect(g.take(1_000 + 10_000)).toEqual({ kind: "fresh" });
    g.remember(true, 11_000);
    expect(g.take(12_000)).toEqual({ kind: "cached", ok: true });
  });

  it("past the read limit answers with the last verdict, however old, instead of refusing", () => {
    const g = new WatchdogGate();
    // Each read's verdict expires before the next request, so every request asks for a read.
    for (let i = 0; i < READ_LIMIT; i++) {
      expect(g.take(i * 1_000)).toEqual({ kind: "fresh" });
      g.remember(true, i * 1_000 - 20_000);
    }
    expect(g.take(20_000)).toEqual({ kind: "cached", ok: true });
    expect(g.take(59_999)).toEqual({ kind: "cached", ok: true });
    // The oldest read ages out of the window: a new read is granted.
    expect(g.take(60_000)).toEqual({ kind: "fresh" });
  });

  it("over the limit with nothing ever read, says it does not know", () => {
    const g = new WatchdogGate();
    for (let i = 0; i < READ_LIMIT; i++) expect(g.take(i)).toEqual({ kind: "fresh" });
    expect(g.take(READ_LIMIT)).toEqual({ kind: "unknown" });
  });
});

describe("WatchdogGate.verdictFor", () => {
  it("a flood of requests cannot turn a good verdict into a failure, and reads stay capped", async () => {
    const g = new WatchdogGate();
    let reads = 0;
    let t = 0;
    const read = async () => {
      reads++;
      return true;
    };
    // 300 requests over a minute, 200 ms apart (an attacker's 5 a second).
    const answers: boolean[] = [];
    for (let i = 0; i < 300; i++, t += 200) answers.push(await g.verdictFor(t, read, () => t));
    expect(answers.every(Boolean)).toBe(true);
    expect(reads).toBeLessThanOrEqual(7); // one per 10 s
  });

  it("serves the real status of a down verdict too", async () => {
    const g = new WatchdogGate();
    expect(
      await g.verdictFor(
        0,
        async () => false,
        () => 0,
      ),
    ).toBe(false);
    expect(
      await g.verdictFor(
        5_000,
        async () => true,
        () => 5_000,
      ),
    ).toBe(false);
  });

  it("shares a read in flight: a burst at once costs one database read", async () => {
    const g = new WatchdogGate();
    let reads = 0;
    let release: (v: boolean) => void = () => {};
    const read = () => {
      reads++;
      return new Promise<boolean>((r) => (release = r));
    };
    const burst = Array.from({ length: 50 }, () => g.verdictFor(0, read, () => 0));
    release(true);
    expect(await Promise.all(burst)).toEqual(Array(50).fill(true));
    expect(reads).toBe(1);
  });

  it("a read that throws is down, and is cached like any verdict", async () => {
    const g = new WatchdogGate();
    expect(
      await g.verdictFor(
        0,
        async () => {
          throw new Error("database unreachable");
        },
        () => 0,
      ),
    ).toBe(false);
    expect(g.take(1_000)).toEqual({ kind: "cached", ok: false });
  });
});
