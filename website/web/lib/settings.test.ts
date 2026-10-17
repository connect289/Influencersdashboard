import { describe, expect, it } from "vitest";
import { DEFAULT_SETTINGS, parseSettings } from "./settings";

describe("settings parsing", () => {
  it("defaults keep Witty off and phone OTP off (owner decisions)", () => {
    expect(DEFAULT_SETTINGS.web_advisor_enabled).toBe(false);
    expect(DEFAULT_SETTINGS.require_phone_otp).toBe(false);
    expect(DEFAULT_SETTINGS.default_theme).toBe("system");
  });
  it("reads valid values and falls back per key on invalid ones", () => {
    const s = parseSettings({
      web_advisor_enabled: true,
      design_concept: "z",
      counsellor_phone: "+911234567890",
      unknown: 1,
    });
    expect(s.web_advisor_enabled).toBe(true);
    expect(s.design_concept).toBe("a");
    expect(s.counsellor_phone).toBe("+911234567890");
  });
});
