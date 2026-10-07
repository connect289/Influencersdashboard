import { describe, expect, it } from "vitest";
import {
  AI_PRICE_KEYS, AiSettingsSchema, aiSettingsPayload, MlSettingsSchema, mlSettingsPayload, RUN_KIND_LABEL, RUN_NOW_KINDS,
} from "./labels";

describe("run-now kinds", () => {
  it("lists only the kinds the Admin can queue, each labelled", () => {
    expect(RUN_NOW_KINDS).not.toContain("ask");
    expect([...RUN_NOW_KINDS]).toEqual(["light_check", "optimise", "deep_review", "weekly_report"]);
    for (const k of RUN_NOW_KINDS) expect(RUN_KIND_LABEL[k]).toBeTruthy();
  });
  it("still labels 'ask' runs in the run history", () => {
    expect(RUN_KIND_LABEL.ask).toBe("Ask the CRM");
  });
});

describe("model settings form", () => {
  const ok = { min_outcomes: "500", challenger_pct: "10", ece_fallback: "0.05", train_hour_ist: "2", reason: "turn off nightly" };
  const fails = (patch: Record<string, string>, key: string) => {
    const r = MlSettingsSchema.safeParse({ ...ok, ...patch });
    expect(r.success).toBe(false);
    expect(r.error?.issues.map((i) => i.path[0])).toContain(key);
  };
  it("rejects values outside the database's bounds", () => {
    fails({ challenger_pct: "60" }, "challenger_pct");
    fails({ ece_fallback: "0.5" }, "ece_fallback");
    fails({ train_hour_ist: "24" }, "train_hour_ist");
    fails({ min_outcomes: "50" }, "min_outcomes");
    fails({ reason: "ok" }, "reason");
  });
  it("sends a share and a JSON boolean for the nightly switch", () => {
    const r = MlSettingsSchema.safeParse(ok);
    expect(r.success).toBe(true);
    const p = mlSettingsPayload(r.data!);
    expect(p).toEqual({ min_outcomes: 500, challenger_share: 0.1, ece_fallback: 0.05, train_hour_ist: 2, auto_train: false });
    expect(typeof p.auto_train).toBe("boolean");
    expect(mlSettingsPayload(MlSettingsSchema.parse({ ...ok, auto_train: "on", challenger_pct: "12.5" }))).toMatchObject({ auto_train: true, challenger_share: 0.125 });
  });
});

describe("AI settings prices", () => {
  const base: Record<string, string | undefined> = {
    mode: "advisory", min_gain_pct: "3", max_per_day: "3", daily_budget_usd: "5", worker_url: "",
    model_regular: "claude-sonnet-5-5", model_deep: "claude-opus-5-5", model_quick: "claude-haiku-5", reason: "new prices",
  };
  // what the form sends: every price field, empty unless typed
  const form = (patch: Record<string, string>) => ({ ...base, ...Object.fromEntries(AI_PRICE_KEYS.map((k) => [k, ""])), ...patch });

  it("has the twelve price fields", () => {
    expect(AI_PRICE_KEYS).toHaveLength(12);
    expect(AI_PRICE_KEYS).toContain("price_quick_cache_write");
  });
  it("keys prices by the chosen model names; a role left blank adds none", () => {
    const d = AiSettingsSchema.parse(form({
      price_regular_in: "2", price_regular_out: "10", price_regular_cache_read: "0.2", price_regular_cache_write: "2.5",
      price_deep_in: "4", price_deep_out: "20",
    }));
    expect(aiSettingsPayload(d).prices_per_mtok).toEqual({
      "claude-sonnet-5-5": { in: 2, out: 10, cache_read: 0.2, cache_write: 2.5 },
      "claude-opus-5-5": { in: 4, out: 20 },
    });
  });
  it("sends no prices when none are given (older forms and databases)", () => {
    const d = AiSettingsSchema.parse(base);
    expect(aiSettingsPayload(d)).not.toHaveProperty("prices_per_mtok");
    expect(aiSettingsPayload(AiSettingsSchema.parse(form({}))).prices_per_mtok).toBeUndefined();
  });
  it("accepts 0 and rejects prices outside 0 to 1000 or not numbers", () => {
    expect(AiSettingsSchema.safeParse(form({ price_quick_in: "0", price_quick_out: "0" })).success).toBe(true);
    for (const v of ["-1", "1000.5", "abc"]) {
      const r = AiSettingsSchema.safeParse(form({ price_regular_in: v, price_regular_out: "10" }));
      expect(r.success).toBe(false);
      expect(r.error?.issues.find((i) => i.path[0] === "price_regular_in")?.message).toBe("0 to 1000");
    }
  });
  it("needs both in and out once any price of a model is given", () => {
    const r = AiSettingsSchema.safeParse(form({ price_deep_in: "4", price_deep_cache_read: "0.2" }));
    expect(r.success).toBe(false);
    expect(r.error?.issues.map((i) => i.path[0])).toEqual(["price_deep_out"]);
  });
  it("one model used for two roles has one price", () => {
    const same = { ...base, model_deep: "claude-sonnet-5-5" };
    const ok = AiSettingsSchema.parse({ ...same, price_regular_in: "2", price_regular_out: "10", price_deep_in: "2", price_deep_out: "10" });
    expect(aiSettingsPayload(ok).prices_per_mtok).toEqual({ "claude-sonnet-5-5": { in: 2, out: 10 } });
    const blankDeep = AiSettingsSchema.parse({ ...same, price_regular_in: "2", price_regular_out: "10" });
    expect(aiSettingsPayload(blankDeep).prices_per_mtok).toEqual({ "claude-sonnet-5-5": { in: 2, out: 10 } });
    const r = AiSettingsSchema.safeParse({ ...same, price_regular_in: "2", price_regular_out: "10", price_deep_in: "2", price_deep_out: "12" });
    expect(r.success).toBe(false);
    expect(r.error?.issues.map((i) => i.path[0])).toEqual(["price_deep_out"]);
  });
});
