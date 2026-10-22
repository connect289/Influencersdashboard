import "server-only";
import { env } from "../env";
import type { ModelProvider, ModelUsage } from "./model";

/**
 * Gemini provider for web_advisor (D-083): the same model family as Witty on WhatsApp (gemini-3.6-flash), called over
 * the Generative Language REST API (no SDK). Extractor: one JSON response. Counsellor: server-sent events, streamed to
 * the student as they arrive. Thought parts (thinking models) are never shown or stored.
 */
export const DEFAULT_GEMINI_MODEL = "gemini-3.6-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta";

/** Approximate Flash list prices per million tokens (USD), for cost tracking only; cached input at 25%. */
const PRICE = { input: 0.3, output: 2.5 };

interface GeminiUsage {
  promptTokenCount?: number;
  cachedContentTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
}
interface GeminiChunk {
  candidates?: { content?: { parts?: { text?: string; thought?: boolean }[] } }[];
  usageMetadata?: GeminiUsage;
  modelVersion?: string;
}

/** Settings may still name a Claude model; Gemini only accepts its own model names. */
export function geminiModel(model: string): string {
  return /^gemini-/i.test(model) ? model : DEFAULT_GEMINI_MODEL;
}

export function geminiUsage(u: GeminiUsage | undefined): ModelUsage {
  const prompt = u?.promptTokenCount ?? 0;
  const cached = u?.cachedContentTokenCount ?? 0;
  const output = (u?.candidatesTokenCount ?? 0) + (u?.thoughtsTokenCount ?? 0);
  const cost = ((prompt - cached) * PRICE.input + cached * PRICE.input * 0.25 + output * PRICE.output) / 1e6;
  return { prompt_tokens: prompt, cached_tokens: cached, output_tokens: output, cost_usd: Math.round(cost * 1e5) / 1e5 };
}

/** Visible text of one response chunk (thought parts excluded). */
export function chunkText(c: GeminiChunk): string {
  return (c.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text ?? "").join("");
}

function body(system: string, input: unknown, gen: Record<string, unknown>) {
  return JSON.stringify({
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts: [{ text: JSON.stringify(input) }] }],
    generationConfig: gen,
  });
}

async function call(model: string, method: "generateContent" | "streamGenerateContent", payload: string, signal: AbortSignal) {
  const key = env().GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY is not set (S-14)");
  const url = `${env().WEB_GEMINI_BASE_URL ?? BASE}/models/${encodeURIComponent(model)}:${method}${method === "streamGenerateContent" ? "?alt=sse" : ""}`;
  const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json", "x-goog-api-key": key }, body: payload, signal });
  if (!res.ok) {
    // The error body names the problem (quota, model, safety); it never contains the key.
    const detail = (await res.text().catch(() => "")).slice(0, 300);
    throw new Error(`gemini ${res.status}: ${detail}`);
  }
  return res;
}

/** Reads a server-sent-event stream of Gemini chunks, calling onChunk for each `data:` line. */
export async function readSse(stream: ReadableStream<Uint8Array>, onChunk: (c: GeminiChunk) => void): Promise<void> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  const flush = (line: string) => {
    const t = line.trim();
    if (!t.startsWith("data:")) return;
    const data = t.slice(5).trim();
    if (!data || data === "[DONE]") return;
    onChunk(JSON.parse(data) as GeminiChunk);
  };
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let i: number;
    while ((i = buf.indexOf("\n")) >= 0) {
      flush(buf.slice(0, i));
      buf = buf.slice(i + 1);
    }
  }
  flush(buf + decoder.decode());
}

export const geminiProvider: ModelProvider = {
  name: "gemini",
  async extract({ model, system, input, signal }) {
    const m = geminiModel(model);
    const res = await call(m, "generateContent", body(system, input, { temperature: 0, maxOutputTokens: 2048, responseMimeType: "application/json" }), signal);
    const j = (await res.json()) as GeminiChunk;
    return { text: chunkText(j), usage: geminiUsage(j.usageMetadata), model: j.modelVersion ?? m };
  },
  async counsel({ model, system, input, signal, onText }) {
    const m = geminiModel(model);
    const res = await call(m, "streamGenerateContent", body(system, input, { temperature: 0.4, maxOutputTokens: 2048 }), signal);
    if (!res.body) throw new Error("gemini: empty stream");
    let text = "";
    let usage: GeminiUsage | undefined;
    let version = m;
    await readSse(res.body, (c) => {
      const d = chunkText(c);
      if (d) {
        text += d;
        onText(d);
      }
      if (c.usageMetadata) usage = c.usageMetadata;
      if (c.modelVersion) version = c.modelVersion;
    });
    return { text, usage: geminiUsage(usage), model: version };
  },
};
