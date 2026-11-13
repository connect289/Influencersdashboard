import { describe, expect, it } from "vitest";
import { codesCheck } from "./health";

describe("health: code ceilings (D-095)", () => {
  it("is ok with no ceiling reached and no refusals", () => {
    expect(
      codesCheck({
        last_hour: 3,
        last_24h: 40,
        hourly_cap: 200,
        daily_cap: 1500,
        at_cap: null,
        refused_24h: { hourly: 0, daily: 0 },
      }),
    ).toMatchObject({
      ok: true,
      daily_cap: 1500,
      ceiling_refusals_24h: { hourly: 0, daily: 0 },
    });
  });
  it("is not ok at a ceiling or after refusals", () => {
    expect(codesCheck({ at_cap: "daily", refused_24h: { daily: 4 } })).toMatchObject({
      ok: false,
      at_cap: "daily",
      ceiling_refusals_24h: { hourly: 0, daily: 4 },
    });
    expect(codesCheck({ at_cap: null, refused_24h: { hourly: 1 } }).ok).toBe(false);
  });
  it("tolerates a missing block (an older database)", () => {
    expect(codesCheck(undefined)).toMatchObject({ ok: true, at_cap: null, last_hour: null });
  });
});
