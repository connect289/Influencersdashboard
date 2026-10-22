import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { env, isDeployed } from "../env";
import { geminiProvider } from "./gemini";
import { mockProvider } from "./mock";

/**
 * Model providers for web_advisor (docs/AGENT_ARCHITECTURE.md §3.3). Gemini (D-083, Witty's own model family) or Claude
 * with prompt caching (the system prompt is a cached prefix); the scripted mock runs only on a developer machine or in
 * CI without a key (S-14), never on a deployed site. Models come from web_settings (`web_advisor_models`), never code.
 */
export interface ModelUsage {
  prompt_tokens: number;
  cached_tokens: number;
  output_tokens: number;
  cost_usd: number;
}
export interface ModelProvider {
  readonly name: "claude" | "gemini" | "mock";
  extract(o: { model: string; system: string; input: unknown; signal: AbortSignal }): Promise<{ text: string; usage: ModelUsage; model: string }>;
  counsel(o: { model: string; system: string; input: unknown; signal: AbortSignal; onText: (delta: string) => void }): Promise<{ text: string; usage: ModelUsage; model: string }>;
}

/** Approximate list prices per million tokens (USD) for cost tracking only; cache reads at 10% of input. */
const PRICE: { match: RegExp; input: number; output: number }[] = [
  { match: /haiku/i, input: 1, output: 5 },
  { match: /sonnet/i, input: 3, output: 15 },
  { match: /opus/i, input: 15, output: 75 },
];
export function costUsd(model: string, u: { input_tokens?: number; cache_read_input_tokens?: number | null; cache_creation_input_tokens?: number | null; output_tokens?: number }): number {
  const p = PRICE.find((x) => x.match.test(model)) ?? PRICE[1]!;
  const inTok = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) * 1.25 + (u.cache_read_input_tokens ?? 0) * 0.1;
  return Math.round(((inTok * p.input + (u.output_tokens ?? 0) * p.output) / 1e6) * 1e5) / 1e5;
}

function usageOf(model: string, u: Anthropic.Usage | Anthropic.MessageDeltaUsage | undefined, start?: Anthropic.Usage): ModelUsage {
  const input = (start?.input_tokens ?? 0) + ((u as Anthropic.Usage | undefined)?.input_tokens ?? 0);
  const cached = start?.cache_read_input_tokens ?? (u as Anthropic.Usage | undefined)?.cache_read_input_tokens ?? 0;
  const created = start?.cache_creation_input_tokens ?? (u as Anthropic.Usage | undefined)?.cache_creation_input_tokens ?? 0;
  const output = u?.output_tokens ?? 0;
  return {
    prompt_tokens: input + (cached ?? 0) + (created ?? 0),
    cached_tokens: cached ?? 0,
    output_tokens: output,
    cost_usd: costUsd(model, { input_tokens: input, cache_read_input_tokens: cached, cache_creation_input_tokens: created, output_tokens: output }),
  };
}

let client: Anthropic | null = null;
function anthropic(): Anthropic {
  client ??= new Anthropic({ apiKey: env().ANTHROPIC_API_KEY, baseURL: env().WEB_ANTHROPIC_BASE_URL, maxRetries: 1 });
  return client;
}

const system = (text: string) => [{ type: "text" as const, text, cache_control: { type: "ephemeral" as const } }];

const claudeProvider: ModelProvider = {
  name: "claude",
  async extract({ model, system: sys, input, signal }) {
    const r = await anthropic().messages.create(
      { model, max_tokens: 700, temperature: 0, system: system(sys), messages: [{ role: "user", content: JSON.stringify(input) }] },
      { signal },
    );
    const text = r.content.map((c) => (c.type === "text" ? c.text : "")).join("");
    return { text, usage: usageOf(model, r.usage), model: r.model };
  },
  async counsel({ model, system: sys, input, signal, onText }) {
    const stream = anthropic().messages.stream(
      { model, max_tokens: 600, temperature: 0.4, system: system(sys), messages: [{ role: "user", content: JSON.stringify(input) }] },
      { signal },
    );
    let text = "";
    stream.on("text", (d) => {
      text += d;
      onText(d);
    });
    const final = await stream.finalMessage();
    return { text, usage: usageOf(model, final.usage), model: final.model };
  },
};

/**
 * WEB_ADVISOR_PROVIDER: "gemini" / "claude" pin a provider; "auto" prefers Gemini when its key is set, then Claude.
 * A deployed site (production or preview) never falls back to the scripted mock: without a key the turn fails and the
 * student is offered a counsellor.
 */
export function modelProvider(): ModelProvider {
  const e = env();
  const p = e.WEB_ADVISOR_PROVIDER;
  if (p === "mock" && !isDeployed()) return mockProvider;
  if ((p === "gemini" || p === "auto") && e.GEMINI_API_KEY) return geminiProvider;
  if ((p === "claude" || p === "auto") && e.ANTHROPIC_API_KEY) return claudeProvider;
  if (isDeployed()) throw new Error("No model key for web_advisor: set GEMINI_API_KEY or ANTHROPIC_API_KEY (S-14)");
  return mockProvider;
}
