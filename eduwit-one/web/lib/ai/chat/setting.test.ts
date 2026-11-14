import { describe, expect, it } from "vitest";
import { settingForModel } from "./setting.ts";

// The setting read tool (D-139): the version a put_setting card must name comes back only with a value the model read
// whole. A value masking changed, or one too long for a tool result, comes back without a version, so no card can be
// built from it.

describe("settingForModel", () => {
  it("gives the whole value with its version", () => {
    const value = { slow_ms: 5000, parked_retry_h: 6, source_missing_opens_incident: true, tags: ["a", "b"] };
    expect(settingForModel("checks", { value, version: 7, owner_only: false })).toEqual({
      ok: true,
      data: { key: "checks", version: 7, owner_only: false, value },
    });
  });

  it("gives no version when masking changed the value", () => {
    const r = settingForModel("alerts", {
      value: { p1_inbox: "connect@eduwit.in", escalate_after_min: 30 },
      version: 4,
      owner_only: true,
    });
    expect(r.ok).toBe(true);
    const data = r.data as Record<string, unknown>;
    expect(data).not.toHaveProperty("version");
    expect(data.saveable_from_chat).toBe(false);
    expect(data.owner_only).toBe(true);
    expect(JSON.stringify(data)).not.toContain("connect@");
    expect(data.value).toEqual({ p1_inbox: "@eduwit.in", escalate_after_min: 30 });
    expect(String(data.hint)).toContain("/settings/alerts");
  });

  it("gives no version when a key was left out or a number looks like a phone", () => {
    for (const value of [{ limit: 3, notes: "kept by the owner" }, { waba_id: 123456789012345 }, { api_token: "x" }]) {
      const data = settingForModel("whatsapp", { value, version: 2, owner_only: true }).data as Record<string, unknown>;
      expect(data, JSON.stringify(value)).not.toHaveProperty("version");
      expect(data.saveable_from_chat).toBe(false);
    }
  });

  it("gives neither value nor version when the value is too long to read whole", () => {
    const value = Object.fromEntries(Array.from({ length: 700 }, (_, i) => [`limit_${i}`, i]));
    const data = settingForModel("thresholds", { value, version: 9, owner_only: true }).data as Record<string, unknown>;
    expect(data).not.toHaveProperty("version");
    expect(data).not.toHaveProperty("value");
    expect(String(data.hint)).toContain("too long");
  });

  it("says so when the key is not on the Settings page", () => {
    expect(settingForModel("setup", null)).toEqual({ ok: false, error: "no setting setup on the Settings page" });
  });
});
