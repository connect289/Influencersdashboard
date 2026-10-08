import { describe, expect, it } from "vitest";
import {
  ADMIN_LEVER_RANGES, AI_LEVER_RANGES, AI_PRICE_KEYS, AiSettingsSchema, aiSettingsPayload, autopilotRuleText, changeLine, describeChange, DRAFT_LEVERS, EDITABLE_LEVERS,
  editable, editedChange, EFFORT_METRIC_LABEL, EFFORT_METRICS, evidenceHref, fromToText, LEVER_LABEL, leverRangeText, leverValueText, MlSettingsSchema,
  mlSettingsPayload, parseLeverValue, realisedText, reviewText, RUN_KIND_LABEL, RUN_NOW_KINDS, SETTING_LEVERS, simulationText, supportText,
  type Change, type Recommendation,
} from "./labels";
import { LEVERS } from "./prompts";

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

describe("Addendum 3 levers", () => {
  it("are the five settings and the two drafts, the same list the prompt offers", () => {
    expect([...SETTING_LEVERS]).toEqual(["effort_weights", "effort_bounds", "sla_floor", "half_life_days", "prior_weight"]);
    expect([...DRAFT_LEVERS]).toEqual(["rule_draft", "pause_draft"]);
    expect([...LEVERS]).toEqual([...SETTING_LEVERS, ...DRAFT_LEVERS]);
    for (const l of LEVERS) expect(LEVER_LABEL[l]).toBeTruthy();
    for (const retired of ["exploration_share", "segment_pin", "partner_weight", "share_cap", "maturity_days", "speed_factor", "reliability_factor"]) {
      expect(LEVERS as readonly string[]).not.toContain(retired);
    }
  });
  it("names the six effort metrics", () => {
    expect([...EFFORT_METRICS]).toEqual(["first_call", "attempts_72h", "connect_rate", "followup", "acts_per_open", "stale_share"]);
    for (const k of EFFORT_METRICS) expect(EFFORT_METRIC_LABEL[k]).toBeTruthy();
  });
  it("keeps the Admin's ranges wider than the AI's (C113)", () => {
    expect(ADMIN_LEVER_RANGES).toEqual({ half_life_days: [7, 120], prior_weight: [1, 100], effort_lo: [0.85, 1], effort_hi: [1, 1.15], sla_floor: [0.8, 1], weight: [0, 5] });
    expect(AI_LEVER_RANGES).toEqual({ half_life_days: [14, 60], prior_weight: [5, 50], effort_lo: [0.85, 1], effort_hi: [1, 1.15], sla_floor: [0.8, 1], weight: [0, 5] });
    expect(leverRangeText("half_life_days", AI_LEVER_RANGES)).toBe("14 to 60 days");
    expect(leverRangeText("prior_weight", ADMIN_LEVER_RANGES)).toBe("1 to 100 leads");
    expect(leverRangeText("sla_floor", AI_LEVER_RANGES)).toBe("80% to 100%");
    expect(leverRangeText("effort_bounds", ADMIN_LEVER_RANGES)).toBe("low 0.85–1.00, high 1.00–1.15");
    expect(leverRangeText("effort_weights", AI_LEVER_RANGES)).toBe("0 to 5 each, not all 0");
  });
});

describe("parseLeverValue (C23)", () => {
  it("rejects blanks and non-numbers with one message", () => {
    expect(parseLeverValue("", "pct")).toBe("Enter a number.");
    expect(parseLeverValue("   ", "num")).toBe("Enter a number.");
    expect(parseLeverValue("3O", "pct")).toBe("Enter a number.");
    expect(parseLeverValue("soon", "num")).toBe("Enter a number.");
    expect(parseLeverValue("Infinity", "num")).toBe("Enter a number.");
  });
  it("trims, strips one trailing % and divides percent units by 100", () => {
    expect(parseLeverValue("30%", "pct")).toBe(0.3);
    expect(parseLeverValue(" 85 ", "pct")).toBe(0.85);
    expect(parseLeverValue(" 10 ", "num")).toBe(10);
    expect(parseLeverValue("0.9", "num")).toBe(0.9);
    expect(parseLeverValue("12%", "num")).toBe(12);
    expect(parseLeverValue("12%%", "num")).toBe("Enter a number.");
  });
});

describe("inbox edits (C100)", () => {
  it("edits only the one-number levers", () => {
    expect([...EDITABLE_LEVERS]).toEqual(["sla_floor", "half_life_days", "prior_weight"]);
    expect(editable({ lever: "sla_floor", value: 0.9 })).toBe(true);
    expect(editable({ lever: "half_life_days", value: 30 })).toBe(true);
    expect(editable({ lever: "prior_weight", value: 20 })).toBe(true);
    expect(editable({ lever: "effort_weights", value: { first_call: 2 } })).toBe(false);
    expect(editable({ lever: "effort_bounds", value: [0.9, 1.1] })).toBe(false);
    expect(editable({ lever: "partner_weight" } as unknown as Change)).toBe(false);
    expect(editable({ lever: "pause_draft", partner_id: 4 })).toBe(false);
    expect(editable(null)).toBe(false);
  });
  it("takes the SLA floor as a percent or a fraction and stores a fraction", () => {
    const c: Change = { lever: "sla_floor", value: 0.9 };
    expect(editedChange(c, "85")).toEqual({ lever: "sla_floor", value: 0.85 });
    expect(editedChange(c, "0.85")).toEqual({ lever: "sla_floor", value: 0.85 });
    expect(editedChange(c, "85%")).toEqual({ lever: "sla_floor", value: 0.85 });
    expect(editedChange(c, "100")).toEqual({ lever: "sla_floor", value: 1 });
    expect(editedChange(c, " 0.8 ")).toEqual({ lever: "sla_floor", value: 0.8 });
    expect(editedChange(c, "87.56")).toEqual({ lever: "sla_floor", value: 0.876 });
    expect(editedChange(c, "1.05")).toBe("Enter 80 to 100 (%), e.g. 85");
    expect(editedChange(c, "79")).toBe("Enter 80 to 100 (%), e.g. 85");
    expect(editedChange(c, "0.5")).toBe("Enter 80 to 100 (%), e.g. 85");
    expect(editedChange(c, "")).toBe("Enter a number.");
    expect(editedChange(c, "soon")).toBe("Enter a number.");
  });
  it("takes days and leads as typed and refuses the other levers", () => {
    expect(editedChange({ lever: "half_life_days", value: 30 }, "45")).toEqual({ lever: "half_life_days", value: 45 });
    expect(editedChange({ lever: "half_life_days", value: 30 }, "45.5")).toBe("Enter whole days, e.g. 30");
    expect(editedChange({ lever: "prior_weight", value: 20 }, " 12.5 ")).toEqual({ lever: "prior_weight", value: 12.5 });
    expect(editedChange({ lever: "effort_bounds", value: [0.9, 1.1] }, "0.95")).toMatch(/cannot be edited/);
    expect(editedChange({ lever: "effort_weights", value: { first_call: 2 } }, "3")).toMatch(/cannot be edited/);
  });
});

describe("changes and values in words", () => {
  const names = { "4": "SkillBridge" };
  it("describes the A3 levers and the drafts", () => {
    expect(describeChange({ lever: "sla_floor", value: 0.85 })).toBe("SLA factor floor 85%");
    expect(describeChange({ lever: "effort_bounds", value: [0.9, 1.1] })).toBe("Effort factor 0.90–1.10");
    expect(describeChange({ lever: "effort_weights", value: { first_call: 2, stale_share: 0.5 } })).toBe("Effort weights: Minutes to the first call 2, Open leads quiet for 7 days 0.5");
    expect(describeChange({ lever: "effort_weights", value: { stale_share: 1, first_call: 2 } })).toBe("Effort weights: Minutes to the first call 2, Open leads quiet for 7 days 1");
    expect(describeChange({ lever: "half_life_days", value: 30 })).toBe("Recency half-life 30 days");
    expect(describeChange({ lever: "prior_weight", value: 20 })).toBe("Prior strength 20 leads");
    expect(describeChange({ lever: "pause_draft", partner_id: 4 }, names)).toBe("Pause SkillBridge");
    expect(describeChange({ lever: "pause_draft", partner_id: 9 })).toBe("Pause partner #9");
    expect(describeChange({ lever: "rule_draft", rule: { name: "MBA to 4", action: "fix_partner", partner_ids: [4], conditions: {} } })).toBe("Draft rule “MBA to 4” (created inactive)");
    expect(describeChange(null)).toBe("No change: an observation");
  });
  it("still reads a retired lever in the change log", () => {
    expect(describeChange({ lever: "exploration_share", segment: "mca|PG|Online", value: 0.3 } as unknown as Change)).toBe("exploration share (retired lever) for MCA · PG · Online");
    expect(describeChange({ lever: "partner_weight", partner_id: 4, value: 1.05 } as unknown as Change, names)).toBe("partner weight (retired lever)");
  });
  it("formats a lever's value in the Admin's units; null is the default", () => {
    expect(leverValueText("sla_floor", 0.85)).toBe("85%");
    expect(leverValueText("sla_floor", null)).toBe("default");
    expect(leverValueText("effort_bounds", [0.85, 1.15])).toBe("0.85–1.15");
    expect(leverValueText("half_life_days", 30)).toBe("30 days");
    expect(leverValueText("prior_weight", 12.5)).toBe("12.5 leads");
    expect(leverValueText("effort_weights", { connect_rate: 1 })).toBe("Connected ÷ calls 1");
    expect(leverValueText("effort_weights", {})).toBe("none");
    expect(leverValueText("effort_weights", { odd: 3 })).toBe("odd 3");
  });
  const rec = (patch: Partial<Recommendation>): Pick<Recommendation, "change" | "applied" | "run_id" | "check_result"> =>
    ({ run_id: 12, change: { lever: "sla_floor", value: 0.85 }, applied: null, ...patch });
  it("changeLine shows the applied value, with the proposal when edited (C42)", () => {
    expect(changeLine(rec({}))).toBe("SLA factor floor 85%");
    expect(changeLine(rec({ applied: { version: 7, from: 0.8, to: 0.85, change: { lever: "sla_floor", value: 0.85 }, edited: false } }))).toBe("SLA factor floor 85%");
    expect(changeLine(rec({ applied: { version: 7, from: 0.8, to: 0.9, change: { lever: "sla_floor", value: 0.9 }, edited: true } }))).toBe("SLA factor floor 90% (proposed: SLA factor floor 85%)");
    // an edited flag without the applied change still falls back to the proposal
    expect(changeLine(rec({ applied: { version: 7, edited: true } }))).toBe("SLA factor floor 85% (proposed: SLA factor floor 85%)");
    expect(changeLine(rec({ change: { lever: "pause_draft", partner_id: 4 }, applied: { rule_id: "x" } }), names)).toBe("Pause SkillBridge");
  });
  it("fromToText reads the slot before and after, null as default", () => {
    expect(fromToText(rec({ applied: { version: 7, path: ["ai", "sla_floor"], from: null, to: 0.85 } }))).toBe("default → 85%");
    expect(fromToText(rec({ change: { lever: "effort_bounds", value: [0.9, 1.1] }, applied: { from: [0.85, 1.15], to: [0.9, 1.1] } }))).toBe("0.85–1.15 → 0.90–1.10");
    expect(fromToText(rec({ change: { lever: "half_life_days", value: 30 }, applied: { path: ["ai", "half_life_days"], from: 45, to: 30 } }))).toBe("45 days → 30 days");
    expect(fromToText(rec({ applied: null }))).toBeNull();
    expect(fromToText(rec({ change: { lever: "pause_draft", partner_id: 4 }, applied: { rule_id: "r1" } }))).toBeNull();
  });
  it("evidenceHref points at the run and the tool's output", () => {
    expect(evidenceHref(rec({}), { tool: "partner_scorecards" })).toBe("/ai/runs/12#tool-partner_scorecards");
    expect(evidenceHref(rec({}), {})).toBe("/ai/runs/12");
  });
  it("realisedText words the realised effect, or nothing", () => {
    const realised = { before: { leads: 60, ncpl: 3400 }, after: { leads: 55, ncpl: 3900 }, holdout_before: { leads: 7, ncpl: 3300 }, holdout_after: { leads: 6, ncpl: 3350 }, did: 450, window_days: 14 };
    expect(realisedText(rec({ check_result: { verdict: "kept", realised } })))
      .toBe("Realised: ₹3,400 → ₹3,900 per lead (holdout ₹3,300 → ₹3,350; net effect +₹450) on 115 leads");
    expect(realisedText(rec({ check_result: { verdict: "kept", realised: { ...realised, holdout_after: { leads: 0, ncpl: null }, did: null } } })))
      .toBe("Realised: ₹3,400 → ₹3,900 per lead (holdout ₹3,300 → —; net effect not measurable) on 115 leads");
    expect(realisedText(rec({ check_result: { verdict: "waiting" } }))).toBeNull();
    expect(realisedText(rec({}))).toBeNull();
  });
  it("reviewText says why a worse change stayed", () => {
    expect(reviewText({ verdict: "worse", not_rolled_back: "retired by Addendum 3" })).toBe("7-day review: did worse than the holdout (not rolled back: retired by Addendum 3)");
    expect(reviewText({ verdict: "worse", auto_rolled_back: true })).toBe("7-day review: did worse than the holdout, rolled back automatically");
  });
});

describe("simulations in words", () => {
  const sim = { simulated: true, decisions: 40, ncpl_now: 3400, ncpl_new: 4000, difference: 600, ci95: [-38, 1240] as [number, number], gain_pct: 17.6, ess: 31.4, support: 0.62, min_support: 0.5, enough: true };
  it("keeps the NCPL line and adds the support separately", () => {
    expect(simulationText(sim)).toBe("NCPL ₹3,400 → ₹4,000, +17.6% (95%: −₹38 to +₹1,240) on 40 decisions");
    expect(supportText(sim)).toBe("Support 62% of 40 decisions (Autopilot needs 50%), effective sample 31");
    expect(supportText({ ...sim, min_support: undefined, ess: undefined })).toBe("Support 62% of 40 decisions");
    expect(supportText({ simulated: false, why: "x" })).toBeNull();
    expect(supportText(null)).toBeNull();
  });
  it("states Autopilot's rule with the support requirement", () => {
    expect(autopilotRuleText({ min_gain_pct: 4, max_per_day: 2, min_decisions: 30, min_support: 0.5 }))
      .toBe("Autopilot applies a setting change on its own only when its simulation shows at least 4% more net commission per lead on 30 or more matured decisions, with the 95% interval above zero and support of at least 50% (the share of replayed decisions the log can speak for); at most 2 a day. Drafts always wait for an Admin.");
    expect(autopilotRuleText(undefined)).toContain("at least 3% more");
    expect(autopilotRuleText(undefined)).toContain("support of at least 50%");
  });
  it("says why a simulation is not enough: few decisions or low support", () => {
    expect(simulationText({ ...sim, decisions: 12, enough: false })).toBe("NCPL ₹3,400 → ₹4,000, +17.6% (95%: −₹38 to +₹1,240) on 12 decisions: too few to rely on");
    expect(simulationText({ ...sim, support: 0.31, enough: false })).toBe("NCPL ₹3,400 → ₹4,000, +17.6% (95%: −₹38 to +₹1,240) on 40 decisions: support 31% is below the 50% Autopilot needs");
    expect(simulationText({ simulated: true, decisions: 0 })).toBe("No matured decisions to replay yet");
    expect(simulationText({ simulated: false, why: "the recency half-life cannot be replayed" })).toBe("the recency half-life cannot be replayed");
    expect(simulationText(null)).toBe("Not simulated");
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

describe("AI settings numbers (C63)", () => {
  const base: Record<string, string | undefined> = {
    mode: "advisory", min_gain_pct: "3", max_per_day: "3", daily_budget_usd: "5", worker_url: "",
    model_regular: "claude-sonnet-5-5", model_deep: "claude-opus-5-5", model_quick: "claude-haiku-5", reason: "new budget",
  };
  const issue = (patch: Record<string, string | undefined>, key: string) => {
    const r = AiSettingsSchema.safeParse({ ...base, ...patch });
    expect(r.success).toBe(false);
    return r.error?.issues.find((i) => i.path[0] === key)?.message;
  };
  it("a blank daily budget is an error, 0 is a budget", () => {
    expect(issue({ daily_budget_usd: "" }, "daily_budget_usd")).toBe("$0 to $200");
    expect(issue({ daily_budget_usd: "  " }, "daily_budget_usd")).toBe("$0 to $200");
    expect(issue({ daily_budget_usd: "201" }, "daily_budget_usd")).toBe("$0 to $200");
    expect(issue({ daily_budget_usd: undefined }, "daily_budget_usd")).toBeTruthy();
    expect(AiSettingsSchema.parse({ ...base, daily_budget_usd: "0" }).daily_budget_usd).toBe(0);
    expect(aiSettingsPayload(AiSettingsSchema.parse({ ...base, daily_budget_usd: "0" })).daily_budget_usd).toBe(0);
  });
  it("Autopilot's gain and cap keep their defaults when absent, but a blank is an error", () => {
    const d = AiSettingsSchema.parse({ ...base, min_gain_pct: undefined, max_per_day: undefined });
    expect(d.min_gain_pct).toBe(3);
    expect(d.max_per_day).toBe(3);
    expect(issue({ min_gain_pct: "" }, "min_gain_pct")).toBe("1 to 50%");
    expect(issue({ max_per_day: "" }, "max_per_day")).toBe("1 to 10");
    expect(issue({ min_gain_pct: "60" }, "min_gain_pct")).toBe("1 to 50%");
    expect(issue({ max_per_day: "2.5" }, "max_per_day")).toBe("1 to 10");
    expect(aiSettingsPayload(AiSettingsSchema.parse({ ...base, min_gain_pct: "4.5", max_per_day: "2" })).autopilot).toEqual({ min_gain_pct: 4.5, max_per_day: 2 });
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
