import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

const { chunkText, geminiModel, geminiProvider, geminiUsage, readSse, DEFAULT_GEMINI_MODEL } = await import("./gemini");
const { modelProvider } = await import("./model");
const { resetEnvCache } = await import("../env");

const KEYS = ["APP_ENV", "GEMINI_API_KEY", "ANTHROPIC_API_KEY", "WEB_ADVISOR_PROVIDER", "SUPABASE_SECRET_KEY", "WEB_SESSION_SECRET", "WEB_INTERNAL_KEY"] as const;
const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
function setEnv(v: Partial<Record<(typeof KEYS)[number], string>>) {
  for (const k of KEYS) delete process.env[k];
  Object.assign(process.env, v);
  resetEnvCache();
}
const deployed = { SUPABASE_SECRET_KEY: "x".repeat(40), WEB_SESSION_SECRET: "s".repeat(40), WEB_INTERNAL_KEY: "k".repeat(40) };

afterEach(() => {
  for (const k of KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  resetEnvCache();
  vi.unstubAllGlobals();
});

function sse(lines: string[], splitAt = 7): ReadableStream<Uint8Array> {
  const bytes = new TextEncoder().encode(lines.map((l) => `data: ${l}\r\n\r\n`).join(""));
  return new ReadableStream({
    start(c) {
      for (let i = 0; i < bytes.length; i += splitAt) c.enqueue(bytes.slice(i, i + splitAt));
      c.close();
    },
  });
}

describe("gemini helpers", () => {
  it("keeps Gemini model names and replaces others with Witty's model", () => {
    expect(geminiModel("gemini-3.6-flash")).toBe("gemini-3.6-flash");
    expect(geminiModel("claude-sonnet-5-5")).toBe(DEFAULT_GEMINI_MODEL);
  });
  it("never returns thought parts", () => {
    expect(chunkText({ candidates: [{ content: { parts: [{ text: "secret plan", thought: true }, { text: "Hi" }, { text: " there" }] } }] })).toBe("Hi there");
    expect(chunkText({})).toBe("");
  });
  it("counts thinking tokens as output and prices cached input lower", () => {
    const u = geminiUsage({ promptTokenCount: 1000, cachedContentTokenCount: 400, candidatesTokenCount: 50, thoughtsTokenCount: 150 });
    expect(u).toMatchObject({ prompt_tokens: 1000, cached_tokens: 400, output_tokens: 200 });
    expect(u.cost_usd).toBeGreaterThan(0);
    expect(geminiUsage(undefined)).toEqual({ prompt_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0 });
  });
  it("reads server-sent events split across network chunks", async () => {
    const seen: string[] = [];
    await readSse(sse([JSON.stringify({ candidates: [{ content: { parts: [{ text: "Namaste" }] } }] }), JSON.stringify({ candidates: [{ content: { parts: [{ text: "!" }] } }] })], 5), (c) => seen.push(chunkText(c)));
    expect(seen).toEqual(["Namaste", "!"]);
  });
});

describe("gemini provider", () => {
  it("extracts JSON with the key in a header (never in the URL) and Witty's model", async () => {
    setEnv({ GEMINI_API_KEY: "test-key" });
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"facts":[]}' }] } }], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 3 }, modelVersion: "gemini-3.6-flash" })));
    vi.stubGlobal("fetch", fetchMock);
    const r = await geminiProvider.extract({ model: "claude-haiku-5-5", system: "sys", input: { a: 1 }, signal: new AbortController().signal });
    expect(r.text).toBe('{"facts":[]}');
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toContain("/models/gemini-3.6-flash:generateContent");
    expect(url).not.toContain("test-key");
    expect((init.headers as Record<string, string>)["x-goog-api-key"]).toBe("test-key");
    const body = JSON.parse(String(init.body));
    expect(body.generationConfig.responseMimeType).toBe("application/json");
    expect(body.systemInstruction.parts[0].text).toBe("sys");
  });
  it("streams the counsellor reply as it arrives", async () => {
    setEnv({ GEMINI_API_KEY: "test-key" });
    vi.stubGlobal("fetch", vi.fn(async () => new Response(sse([
      JSON.stringify({ candidates: [{ content: { parts: [{ text: "thinking…", thought: true }] } }] }),
      JSON.stringify({ candidates: [{ content: { parts: [{ text: "Here are " }] } }] }),
      JSON.stringify({ candidates: [{ content: { parts: [{ text: "3 options." }] } }], usageMetadata: { promptTokenCount: 20, candidatesTokenCount: 4 } }),
    ]))));
    const deltas: string[] = [];
    const r = await geminiProvider.counsel({ model: "gemini-3.6-flash", system: "s", input: {}, signal: new AbortController().signal, onText: (d) => deltas.push(d) });
    expect(deltas).toEqual(["Here are ", "3 options."]);
    expect(r.text).toBe("Here are 3 options.");
    expect(r.usage.output_tokens).toBe(4);
  });
  it("turns an API error into an error without the key", async () => {
    setEnv({ GEMINI_API_KEY: "test-key" });
    vi.stubGlobal("fetch", vi.fn(async () => new Response('{"error":{"message":"quota exceeded"}}', { status: 429 })));
    await expect(geminiProvider.extract({ model: "gemini-3.6-flash", system: "s", input: {}, signal: new AbortController().signal })).rejects.toThrow(/gemini 429: .*quota/);
  });
});

describe("provider choice", () => {
  it("prefers Gemini, then Claude, and honours an explicit choice", () => {
    setEnv({ GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a" });
    expect(modelProvider().name).toBe("gemini");
    setEnv({ GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a", WEB_ADVISOR_PROVIDER: "claude" });
    expect(modelProvider().name).toBe("claude");
    setEnv({ ANTHROPIC_API_KEY: "a" });
    expect(modelProvider().name).toBe("claude");
  });
  it("uses the scripted mock only on a developer machine, never on a deployed site", () => {
    setEnv({});
    expect(modelProvider().name).toBe("mock");
    setEnv({ APP_ENV: "preview", ...deployed });
    expect(() => modelProvider()).toThrow(/GEMINI_API_KEY or ANTHROPIC_API_KEY/);
    setEnv({ APP_ENV: "preview", WEB_ADVISOR_PROVIDER: "mock", ...deployed });
    expect(() => modelProvider()).toThrow();
  });
});
