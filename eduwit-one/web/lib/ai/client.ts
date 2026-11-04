import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import type { z } from "zod";
import type { Effort, Provider, Usage } from "./models.ts";

// The model client: Claude only (owner, 24 Oct; D-004), through the Anthropic SDK with structured outputs. A call sends
// a system prompt and one user message and gets JSON back; the worker still checks every answer against the kind's
// zod schema. Errors say whether a later retry can help; they never carry a key or a body.

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
  /** The account's API credit balance is used up (a subscription's monthly API credits, or prepaid credits). */
  readonly credits: boolean;

  constructor(message: string, retry: boolean, status?: number, credits = false) {
    super(message);
    this.retry = retry;
    this.status = status;
    this.credits = credits;
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

/**
 * Older Claude models reject the effort setting with a 400 (Haiku 4.5, Sonnet 4.5, the 4.0 and 4.1 models and Claude 3,
 * dated ids included), so it is left out for them (phase 6 review m2).
 */
export function acceptsEffort(model: string): boolean {
  return !/^claude-(3|haiku-4|sonnet-4-5|sonnet-4-0|sonnet-4-2|opus-4-0|opus-4-1|opus-4-2)/.test(model);
}

export class AnthropicModelClient implements ModelClient {
  readonly provider = "anthropic" as const;
  private readonly client: Anthropic;

  /**
   * No retry in the SDK: the task queue retries with a backoff, and an SDK retry would run a timed-out call twice past
   * the worker's deadline (phase 6 review M4). `fetch` is for the unit tests, which check the request offline.
   */
  constructor(apiKey: string, opts: { fetch?: typeof fetch } = {}) {
    this.client = new Anthropic({ apiKey, maxRetries: 0, ...(opts.fetch ? { fetch: opts.fetch } : {}) });
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
          output_config: {
            format: zodOutputFormat(req.schema),
            ...(req.effort && acceptsEffort(req.model) ? { effort: req.effort } : {}),
          },
        },
        { timeout: req.timeoutMs },
      );
    } catch (e) {
      if (e instanceof Anthropic.APIConnectionError) throw statusError("anthropic", undefined);
      // Anthropic answers 400 with "Your credit balance is too low…" when the credits are used up (D-078).
      if (e instanceof Anthropic.BadRequestError && /credit balance/i.test(e.message)) {
        throw new ModelError("anthropic: the API credit balance is too low", false, 400, true);
      }
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
