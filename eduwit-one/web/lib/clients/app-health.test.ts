import { describe, expect, it } from "vitest";
import { healthSummary } from "./app-health.ts";

describe("what a health body says about itself (D-134)", () => {
  it("names the parts a body reports as not ok: Spark's levels, the portal's booleans", () => {
    expect(
      healthSummary({ ok: true, status: "degraded", checks: { config: "ok", sending: "bad", connectors: "warn" } }),
    ).toEqual({
      status: "degraded",
      failing: ["sending", "connectors"],
    });
    expect(healthSummary({ status: "degraded", checks: { db: true, storage: false, queue: true } })).toEqual({
      status: "degraded",
      failing: ["storage"],
    });
  });

  it("keeps nothing from a body but plain names: no detail, no odd keys, no long words", () => {
    const s = healthSummary({
      status: "ok but see https://x",
      checks: { "a b": "bad", Upper: "bad", sending: { level: "bad", phone: "91900" }, ok_part: "ok" },
    });
    expect(s).toEqual({ failing: [] });
    expect(healthSummary({ ok: true })).toBeUndefined();
    const many = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`p${i}`, "bad"]));
    expect(healthSummary({ checks: many })?.failing).toHaveLength(20);
  });
});
