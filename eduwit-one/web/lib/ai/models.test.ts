import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { acceptsEffort, AnthropicModelClient, ModelError } from "./client.ts";
import { aiSettingsSchema, costOf, fallbackRoute, route, worstCaseInr } from "./models.ts";

const seeded = aiSettingsSchema.parse(
  (JSON.parse(readFileSync(new URL("../../../config/settings.json", import.meta.url), "utf8")) as { ai: unknown }).ai,
);

describe("routing", () => {
  it("parses the seeded AI settings: Claude on every tier, each model priced", () => {
    expect(seeded.models).toEqual({ quick: "claude-haiku-5-5", regular: "claude-sonnet-5-5", deep: "claude-opus-5-5" });
    for (const m of [...Object.values(seeded.models), seeded.refusal_fallback]) {
      expect(m && seeded.prices[m], String(m)).toBeTruthy();
    }
  });

  it("picks the tier from the hint, then the routing table, with that tier's model and effort", () => {
    expect(route(seeded, "classify", null)).toMatchObject({ tier: "quick", model: "claude-haiku-5-5", effort: "low" });
    expect(route(seeded, "triage", null)).toMatchObject({
      tier: "regular",
      model: "claude-sonnet-5-5",
      effort: "medium",
    });
    expect(route(seeded, "triage", "deep")).toMatchObject({ tier: "deep", model: "claude-opus-5-5", effort: "high" });
  });

  it("refuses a model that has no price", () => {
    const ai = { ...seeded, models: { ...seeded.models, regular: "claude-unpriced" } };
    expect(route(ai, "triage", null)).toMatchObject({ error: "no_price" });
  });

  it("falls back to the fallback tier when a tier has no model, and says so when none has", () => {
    const ai = { ...seeded, models: { ...seeded.models, deep: null } };
    expect(route(ai, "explain", null)).toMatchObject({ tier: "regular", model: "claude-sonnet-5-5" });
    expect(route({ ...ai, models: { quick: null, regular: null, deep: null } }, "explain", null)).toMatchObject({
      error: "no_model",
    });
  });

  it("has a refusal fallback only when it is set, priced and another model", () => {
    const r = route(seeded, "triage", null);
    if ("error" in r) throw new Error(r.detail);
    expect(fallbackRoute(seeded, r)).toMatchObject({ tier: "regular", model: "claude-opus-4-8", price: { input: 5 } });
    expect(fallbackRoute({ ...seeded, refusal_fallback: null }, r)).toBeNull();
    expect(fallbackRoute({ ...seeded, refusal_fallback: "claude-unpriced" }, r)).toBeNull();
    expect(fallbackRoute({ ...seeded, refusal_fallback: "claude-sonnet-5-5" }, r)).toBeNull();
  });
});

describe("cost", () => {
  const p = { input: 4, output: 20, cache_read: 0.2, cache_write: 5 };

  it("adds the four token kinds and rounds rupees up to the paisa", () => {
    const c = costOf(p, { input: 10_000, output: 2_000, cacheRead: 50_000, cacheWrite: 0 }, 85);
    expect(c.usd).toBeCloseTo(0.09, 6);
    expect(c.inr).toBe(7.65);
    expect(costOf(p, { input: 1, output: 0, cacheRead: 0, cacheWrite: 0 }, 85).inr).toBe(0.01);
    expect(costOf(p, { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, 85).inr).toBe(0);
  });

  it("bounds a call by its whole output allowance and its input at the dearest rate", () => {
    // 30,000 characters → 15,000 tokens at the cache-write rate (5) + 16,000 output tokens (20) = $0.395
    expect(worstCaseInr(p, 30_000, 16_000, 85)).toBe(33.58);
  });
});

const schema = z.object({ summary: z.string(), confidence: z.enum(["low", "medium", "high"]) });
const req = {
  model: "m",
  system: "rules",
  user: "data",
  schema,
  maxTokens: 1000,
  effort: "medium" as const,
  timeoutMs: 5000,
};

describe("Anthropic client", () => {
  it("sends the system prompt cached, the JSON schema and the effort, and reads the usage", async () => {
    const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
    const fetchStub = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), body: JSON.parse(String(init?.body)) as Record<string, unknown> });
      return new Response(
        JSON.stringify({
          id: "msg_1",
          type: "message",
          role: "assistant",
          model: "claude-sonnet-5-5",
          content: [{ type: "text", text: '{"summary":"s","confidence":"low"}' }],
          stop_reason: "end_turn",
          stop_sequence: null,
          usage: { input_tokens: 120, output_tokens: 30, cache_read_input_tokens: 900, cache_creation_input_tokens: 0 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    });
    const c = new AnthropicModelClient("sk-test", { fetch: fetchStub as unknown as typeof fetch });
    const a = await c.complete({ ...req, model: "claude-sonnet-5-5" });
    expect(a).toMatchObject({
      text: '{"summary":"s","confidence":"low"}',
      model: "claude-sonnet-5-5",
      stop: "end",
      usage: { input: 120, output: 30, cacheRead: 900, cacheWrite: 0 },
    });
    const body = calls[0]?.body ?? {};
    expect(calls[0]?.url).toContain("/v1/messages");
    expect(body.system).toEqual([{ type: "text", text: "rules", cache_control: { type: "ephemeral" } }]);
    expect(body.messages).toEqual([{ role: "user", content: "data" }]);
    expect(body).not.toHaveProperty("thinking");
    const oc = body.output_config as { effort: string; format: { type: string; schema: Record<string, unknown> } };
    expect(oc.effort).toBe("medium");
    expect(oc.format.type).toBe("json_schema");
    expect(oc.format.schema).toMatchObject({ type: "object", additionalProperties: false });
  });

  it("leaves effort out for a tier without one, and maps a refused key to a final error", async () => {
    let body: Record<string, unknown> = {};
    const refuse = vi.fn(async (_u: string | URL | Request, init?: RequestInit) => {
      body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(JSON.stringify({ type: "error", error: { type: "authentication_error", message: "x" } }), {
        status: 401,
        headers: { "content-type": "application/json" },
      });
    });
    const c = new AnthropicModelClient("bad", { fetch: refuse as unknown as typeof fetch });
    const err = await c.complete({ ...req, effort: null }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ModelError);
    expect((err as ModelError).retry).toBe(false);
    expect((err as ModelError).message).not.toContain("bad");
    expect(body.output_config).not.toHaveProperty("effort");
  });
});

describe("effort", () => {
  it("is sent to current models and left out for those that refuse it", () => {
    for (const m of ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-opus-4-8"])
      expect(acceptsEffort(m), m).toBe(true);
    for (const m of [
      "claude-haiku-4-5-20251001",
      "claude-sonnet-4-5",
      "claude-opus-4-1",
      "claude-sonnet-4-20250514",
      "claude-3-5-haiku",
    ])
      expect(acceptsEffort(m), m).toBe(false);
  });
});
