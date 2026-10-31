import { describe, expect, it } from "vitest";
import { ceilingError } from "./ceilings";
import { DEFAULT_SETTINGS, parseSettings } from "../settings";

describe("site-wide ceilings (web14)", () => {
  it("accept whole numbers of codes per hour, including 0", () => {
    expect(ceilingError("code_send_hourly_cap", 200)).toBeNull();
    expect(ceilingError("code_send_hourly_cap", 0)).toBeNull();
    for (const bad of [-1, 2.5, Number.NaN, "200", null])
      expect(ceilingError("code_send_hourly_cap", bad)).toMatch(/whole number/);
  });
  it("accept a daily Witty ceiling of turns and spend", () => {
    expect(ceilingError("web_advisor_daily_cap", { turns: 2000, cost_usd: 25 })).toBeNull();
    for (const bad of [null, [], { turns: 10 }, { turns: -1, cost_usd: 5 }, { turns: 10, cost_usd: "5" }])
      expect(ceilingError("web_advisor_daily_cap", bad)).toMatch(/turns/);
  });
  it("leave other settings alone", () => {
    expect(ceilingError("announcement", null)).toBeNull();
  });
  it("have safe defaults when the database has no value or a bad one", () => {
    expect(DEFAULT_SETTINGS.code_send_hourly_cap).toBe(200);
    expect(DEFAULT_SETTINGS.web_advisor_daily_cap).toEqual({ turns: 2000, cost_usd: 25 });
    expect(parseSettings({ code_send_hourly_cap: "lots", web_advisor_daily_cap: { turns: "x" } })).toMatchObject({
      code_send_hourly_cap: 200,
      web_advisor_daily_cap: { turns: 2000, cost_usd: 25 },
    });
  });
});
