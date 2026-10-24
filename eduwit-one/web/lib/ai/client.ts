import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import { fetchJson, HttpError } from "../http.ts";
import type { Effort, Provider, Usage } from "./models.ts";

// One interface for both providers (D-004). A call sends a system prompt and one user message and gets JSON back:
// Claude through the Anthropic SDK with structured outputs, Gemini through its REST API in JSON mode with the schema
// in the message. The worker validates every answer with the same zod schema either way, so neither provider is
// trusted to have kept the shape. Errors say whether a later retry can help; they never carry a key or a body.

export type ModelRequest = {
  model: string;
  system: string;
  user: string;
  schema: z.ZodType;
  maxTokens: number;
  effort: Effort | null;
  timeoutMs: number;
};

export type ModelAnswer = {
  text: string;
  /** The model that answered, as the provider reports it. */
  model: string;
  usage: Usage;
  stop: "end" | "max_tokens" | "refusal" | "other";
  latencyMs: number;
};

export class ModelError extends Error {
  readonly retry: boolean;
  readonly status: number | undefined;

  constructor(message: string, retry: boolean, status?: number) {
    super(message);
    this.retry = retry;
    this.status = status;
  }
}

export interface ModelClient {
  readonly provider: Provider;
  complete(req: ModelRequest): Promise<ModelAnswer>;
  /** A free call that proves the key and the model name (the Setup item's validator). */
  check(model: string): Promise<{ ok: boolean; detail: string }>;
}

function statusError(provider: Provider, status: number | undefined): ModelError {
  if (status === 401 || status === 403)
    return new ModelError(`${provider}: the key was refused (${status})`, false, status);
  if (status === 404) return new ModelError(`${provider}: unknown model (404)`, false, status);
  if (status === 429) return new ModelError(`${provider}: rate limited (429)`, true, status);
  if (status !== undefined && status >= 500)
    return new ModelError(`${provider}: server error (${status})`, true, status);
  if (status !== undefined) return new ModelError(`${provider}: request refused (${status})`, false, status);
  return new ModelError(`${provider}: no answer (network or timeout)`, true);
}

export class AnthropicModelClient implements ModelClient {
  readonly provider = "anthropic" as const;
  private readonly client: Anthropic;

  /** `fetch` is for the unit tests, which check the request without a network. */
  constructor(apiKey: string, opts: { fetch?: typeof fetch } = {}) {
    this.client = new Anthropic({ apiKey, maxRetries: 1, ...(opts.fetch ? { fetch: opts.fetch } : {}) });
  }

  async complete(req: ModelRequest): Promise<ModelAnswer> {
    const started = Date.now();
    let res: Anthropic.Message;
    try {
      res = await this.client.messages.create(
        {
          model: req.model,
          max_tokens: req.maxTokens,
          // The system prompt is the stable prefix (shared rules, then the task's prompt); it is cached when it is long
          // enough to be, and the per-task data follows it in the user message.
          system: [{ type: "text", text: req.system, cache_control: { type: "ephemeral" } }],
          messages: [{ role: "user", content: req.user }],
          output_config: { format: zodOutputFormat(req.schema), ...(req.effort ? { effort: req.effort } : {}) },
        },
        { timeout: req.timeoutMs },
      );
    } catch (e) {
      if (e instanceof Anthropic.APIConnectionError) throw statusError("anthropic", undefined);
      if (e instanceof Anthropic.APIError) throw statusError("anthropic", e.status);
      throw new ModelError("anthropic: the call failed", true);
    }
    const text = res.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");
    const stop =
      res.stop_reason === "end_turn" || res.stop_reason === "stop_sequence"
        ? "end"
        : res.stop_reason === "max_tokens"
          ? "max_tokens"
          : res.stop_reason === "refusal"
            ? "refusal"
            : "other";
    return {
      text,
      model: res.model,
      usage: {
        input: res.usage.input_tokens,
        output: res.usage.output_tokens,
        cacheRead: res.usage.cache_read_input_tokens ?? 0,
        cacheWrite: res.usage.cache_creation_input_tokens ?? 0,
      },
      stop,
      latencyMs: Date.now() - started,
    };
  }

  async check(model: string) {
    try {
      const m = await this.client.models.retrieve(model, null, { timeout: 10_000 });
      return { ok: true, detail: `Anthropic answered: ${m.id} is available to this key` };
    } catch (e) {
      const err =
        e instanceof Anthropic.APIError ? statusError("anthropic", e.status) : statusError("anthropic", undefined);
      return { ok: false, detail: err.message };
    }
  }
}

const geminiAnswer = z.object({
  candidates: z
    .array(
      z.object({
        content: z
          .object({
            parts: z.array(z.object({ text: z.string().optional(), thought: z.boolean().optional() })).default([]),
          })
          .optional(),
        finishReason: z.string().optional(),
      }),
    )
    .default([]),
  promptFeedback: z.object({ blockReason: z.string().optional() }).optional(),
  usageMetadata: z
    .object({
      promptTokenCount: z.number().default(0),
      candidatesTokenCount: z.number().default(0),
      cachedContentTokenCount: z.number().default(0),
      thoughtsTokenCount: z.number().default(0),
    })
    .default({ promptTokenCount: 0, candidatesTokenCount: 0, cachedContentTokenCount: 0, thoughtsTokenCount: 0 }),
  modelVersion: z.string().optional(),
});

const REFUSALS = new Set(["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY"]);

export const GEMINI_API = "https://generativelanguage.googleapis.com/v1beta";

export class GeminiModelClient implements ModelClient {
  readonly provider = "gemini" as const;
  private readonly apiKey: string;
  private readonly base: string;

  constructor(apiKey: string, base = GEMINI_API) {
    this.apiKey = apiKey;
    this.base = base.replace(/\/$/, "");
  }

  async complete(req: ModelRequest): Promise<ModelAnswer> {
    const started = Date.now();
    // JSON mode with the schema in the message: the worker's zod check is the authority on the shape.
    const schema = JSON.stringify(z.toJSONSchema(req.schema));
    let json: unknown;
    try {
      ({ json } = await fetchJson(
        "gemini",
        `${this.base}/models/${encodeURIComponent(req.model)}:generateContent`,
        {
          method: "POST",
          headers: { "x-goog-api-key": this.apiKey },
          body: {
            systemInstruction: { parts: [{ text: req.system }] },
            contents: [
              {
                role: "user",
                parts: [{ text: `${req.user}\n\nAnswer with one JSON object matching this JSON Schema:\n${schema}` }],
              },
            ],
            generationConfig: { responseMimeType: "application/json", maxOutputTokens: req.maxTokens },
          },
        },
        { timeoutMs: req.timeoutMs, retries: 0, breakerFailures: 3, breakerCooldownMs: 120_000 },
      ));
    } catch (e) {
      throw e instanceof HttpError ? statusError("gemini", e.status) : statusError("gemini", undefined);
    }
    const r = geminiAnswer.safeParse(json);
    if (!r.success) throw new ModelError("gemini: unreadable answer", true);
    const a = r.data;
    const c = a.candidates[0];
    const text = (c?.content?.parts ?? [])
      .filter((p) => !p.thought)
      .map((p) => p.text ?? "")
      .join("");
    const reason = c?.finishReason ?? "";
    const stop =
      a.promptFeedback?.blockReason || REFUSALS.has(reason)
        ? "refusal"
        : reason === "MAX_TOKENS"
          ? "max_tokens"
          : reason === "STOP" || reason === ""
            ? "end"
            : "other";
    const u = a.usageMetadata;
    return {
      text,
      model: a.modelVersion ?? req.model,
      // Gemini counts cached tokens inside the prompt count and bills thinking as output.
      usage: {
        input: Math.max(0, u.promptTokenCount - u.cachedContentTokenCount),
        output: u.candidatesTokenCount + u.thoughtsTokenCount,
        cacheRead: u.cachedContentTokenCount,
        cacheWrite: 0,
      },
      stop,
      latencyMs: Date.now() - started,
    };
  }

  async check(model: string) {
    try {
      await fetchJson(
        "gemini",
        `${this.base}/models/${encodeURIComponent(model)}`,
        { headers: { "x-goog-api-key": this.apiKey } },
        { timeoutMs: 10_000, retries: 0, breakerFailures: 3, breakerCooldownMs: 120_000 },
      );
      return { ok: true, detail: `Gemini answered: ${model} is available to this key` };
    } catch (e) {
      return {
        ok: false,
        detail: (e instanceof HttpError ? statusError("gemini", e.status) : statusError("gemini", undefined)).message,
      };
    }
  }
}

/** A scripted client for the unit tests and the offline eval: answers in order, each a value or an error. */
export class ScriptedModelClient implements ModelClient {
  readonly provider: Provider;
  readonly requests: ModelRequest[] = [];
  private readonly script: Array<(Partial<ModelAnswer> & { json?: unknown }) | Error>;

  constructor(provider: Provider, script: Array<(Partial<ModelAnswer> & { json?: unknown }) | Error>) {
    this.provider = provider;
    this.script = [...script];
  }

  async complete(req: ModelRequest): Promise<ModelAnswer> {
    this.requests.push(req);
    const next = this.script.shift();
    if (!next) throw new ModelError("scripted: no answer left", false);
    if (next instanceof Error) throw next;
    return {
      text: next.text ?? JSON.stringify(next.json ?? {}),
      model: next.model ?? req.model,
      usage: next.usage ?? {
        input: Math.ceil((req.system.length + req.user.length) / 4),
        output: 200,
        cacheRead: 0,
        cacheWrite: 0,
      },
      stop: next.stop ?? "end",
      latencyMs: next.latencyMs ?? 5,
    };
  }

  async check(model: string) {
    return { ok: true, detail: `scripted: ${model}` };
  }
}
