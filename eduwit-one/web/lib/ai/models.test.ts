import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { resetBreakers } from "../http.ts";
import { AnthropicModelClient, GeminiModelClient, ModelError } from "./client.ts";
import { aiSettingsSchema, costOf, route, worstCaseInr } from "./models.ts";

const seeded = aiSettingsSchema.parse(
  (JSON.parse(readFileSync(new URL("../../../config/settings.json", import.meta.url), "utf8")) as { ai: unknown }).ai,
);

describe("routing", () => {
  it("parses the seeded AI settings", () => {
    expect(seeded.provider.regular).toBe("gemini");
    expect(seeded.prices["claude-opus-5-5"]).toMatchObject({ input: 4, output: 20 });
  });

  it("refuses a model that has no price (the seed's Gemini model until the owner sets one)", () => {
    expect(route(seeded, "triage", null)).toMatchObject({ error: "no_price" });
  });

  it("picks the tier from the hint, then the routing table, and the model from the tier's provider", () => {
    const ai = { ...seeded, provider: { quick: "anthropic", regular: "anthropic", deep: "anthropic" } as const };
    expect(route(ai, "classify", null)).toMatchObject({
      tier: "quick",
      model: "claude-haiku-4-5-20251001",
      effort: null,
    });
    expect(route(ai, "triage", null)).toMatchObject({ tier: "regular", model: "claude-sonnet-5-5", effort: "medium" });
    expect(route(ai, "triage", "deep")).toMatchObject({ tier: "deep", model: "claude-opus-5-5", effort: "high" });
  });

  it("falls back to the fallback tier when a tier has no model, and says so when none has", () => {
    const ai = {
      ...seeded,
      prices: { ...seeded.prices, "gemini-3.6-flash": { input: 0.75, output: 3.75, cache_read: 0, cache_write: 0 } },
    };
    expect(route(ai, "explain", null)).toMatchObject({
      tier: "regular",
      provider: "gemini",
      model: "gemini-3.6-flash",
    });
    const none = { ...ai, models: { ...ai.models, gemini: { quick: null, regular: null, deep: null } } };
    expect(route(none, "explain", null)).toMatchObject({ error: "no_model" });
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

describe("Gemini client", () => {
  it("asks for JSON with the schema in the message and counts cached and thinking tokens", async () => {
    resetBreakers();
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{ text: "thinking…", thought: true }, { text: '{"summary":"s","confidence":"high"}' }],
              },
              finishReason: "STOP",
            },
          ],
          usageMetadata: {
            promptTokenCount: 1000,
            candidatesTokenCount: 50,
            cachedContentTokenCount: 400,
            thoughtsTokenCount: 70,
          },
          modelVersion: "gemini-3.6-flash",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    const a = await new GeminiModelClient("key").complete({ ...req, model: "gemini-3.6-flash" });
    expect(a).toMatchObject({
      text: '{"summary":"s","confidence":"high"}',
      stop: "end",
      usage: { input: 600, output: 120, cacheRead: 400, cacheWrite: 0 },
    });
    const [url, init] = fetchSpy.mock.calls[0] ?? [];
    expect(String(url)).toBe(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
    );
    expect(String(url)).not.toContain("key");
    const body = JSON.parse(String(init?.body)) as {
      generationConfig: Record<string, unknown>;
      contents: Array<{ parts: Array<{ text: string }> }>;
    };
    expect(body.generationConfig).toEqual({ responseMimeType: "application/json", maxOutputTokens: 1000 });
    expect(body.contents[0]?.parts[0]?.text).toContain('"confidence"');
    fetchSpy.mockRestore();
  });

  it("reads a safety stop as a refusal", async () => {
    resetBreakers();
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ candidates: [{ finishReason: "SAFETY" }] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const a = await new GeminiModelClient("key").complete(req);
    expect(a.stop).toBe("refusal");
    fetchSpy.mockRestore();
  });
});
