import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { aiSettingsSchema } from "../models.ts";
import { INCIDENTS, QUESTIONS } from "./fixtures.ts";
import { leaksIn, ReferenceClient, runEval, summarise } from "./run.ts";

// The eval harness itself: with the reference client (a perfect answerer) every item scores 1 and no planted contact
// reaches a request or an answer. A real run (npm run ai:eval) then measures the model, not the harness.

const seeded = (
  JSON.parse(readFileSync(new URL("../../../../config/settings.json", import.meta.url), "utf8")) as { ai: unknown }
).ai;
const ai = aiSettingsSchema.parse({
  ...(seeded as Record<string, unknown>),
  provider: { quick: "anthropic", regular: "anthropic", deep: "anthropic" },
});

describe("the eval set", () => {
  it("has 30 incidents and 10 questions, with unique ids", () => {
    expect(INCIDENTS).toHaveLength(30);
    expect(QUESTIONS).toHaveLength(10);
    expect(new Set([...INCIDENTS, ...QUESTIONS].map((x) => x.id)).size).toBe(40);
  });

  it("scores the reference answers 100% with no leak, on every tier", async () => {
    for (const tier of ["quick", "regular", "deep"] as const) {
      const report = await runEval(ai, tier, new ReferenceClient("anthropic"));
      const s = summarise(report);
      const misses = report.items.filter((i) => i.score < 1 || i.leaks.length);
      expect(misses, JSON.stringify(misses.slice(0, 3))).toEqual([]);
      expect(s).toMatchObject({ items: 70, filed: 70, overall: 1, leaks: 0 });
    }
  });

  it("would catch a leak", () => {
    expect(leaksIn(["call +91 98111-22233"])).toEqual(["9811122233"]);
    expect(leaksIn(["riya kapoor said"])).toEqual(["Riya Kapoor"]);
    expect(leaksIn(["…2233 and @gmail.com"])).toEqual([]);
  });
});
