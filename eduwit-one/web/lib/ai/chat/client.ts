import Anthropic from "@anthropic-ai/sdk";
import { ModelError } from "../client.ts";
import type { Effort, Usage } from "../models.ts";

// The chat's model client: Claude through the Anthropic SDK with tool use and streaming (D-094). One call sends the
// system prompt, the conversation and the tool definitions, streams the text as it comes, and returns the final
// message's blocks (text and tool calls) with its usage. Errors are the worker's ModelError, so the budget code is one.

export type ChatToolDefinition = { name: string; description: string; input_schema: Record<string, unknown> };

export type ChatBlock =
  { type: "text"; text: string } | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> };

export type ChatContent =
  | string
  | Array<
      | { type: "text"; text: string }
      | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
      | { type: "tool_result"; tool_use_id: string; content: string; is_error?: boolean }
    >;

export type ChatMessage = { role: "user" | "assistant"; content: ChatContent };

export type ChatRequest = {
  model: string;
  system: string;
  messages: ChatMessage[];
  tools: ChatToolDefinition[];
  maxTokens: number;
  effort: Effort | null;
  timeoutMs: number;
  /** Text deltas as they stream; the final message still carries the whole text. */
  onText?: (delta: string) => void;
};

export type ChatAnswer = {
  blocks: ChatBlock[];
  model: string;
  usage: Usage;
  stop: "end" | "tool_use" | "max_tokens" | "refusal" | "other";
  latencyMs: number;
};

export interface ChatModelClient {
  chat(req: ChatRequest): Promise<ChatAnswer>;
}

/** Characters the request will send, for the worst-case cost check (prompt, tools and conversation). */
export function requestChars(req: Pick<ChatRequest, "system" | "messages" | "tools">): number {
  return req.system.length + JSON.stringify(req.messages).length + JSON.stringify(req.tools).length;
}

function statusError(status: number | undefined): ModelError {
  if (status === 401 || status === 403)
    return new ModelError(`anthropic: the key was refused (${status})`, false, status);
  if (status === 404) return new ModelError("anthropic: unknown model (404)", false, status);
  if (status === 429) return new ModelError("anthropic: rate limited (429)", true, status);
  if (status !== undefined && status >= 500) return new ModelError(`anthropic: server error (${status})`, true, status);
  if (status !== undefined) return new ModelError(`anthropic: request refused (${status})`, false, status);
  return new ModelError("anthropic: no answer (network or timeout)", true);
}

export class AnthropicChatClient implements ChatModelClient {
  private readonly client: Anthropic;

  constructor(apiKey: string, opts: { fetch?: typeof fetch } = {}) {
    // No SDK retry: a retried call past the route's deadline would run twice and be billed twice.
    this.client = new Anthropic({ apiKey, maxRetries: 0, ...(opts.fetch ? { fetch: opts.fetch } : {}) });
  }

  async chat(req: ChatRequest): Promise<ChatAnswer> {
    const started = Date.now();
    let res: Anthropic.Message;
    try {
      const stream = this.client.messages.stream(
        {
          model: req.model,
          max_tokens: req.maxTokens,
          // Tools, then the system prompt, are the stable prefix: cached from the second turn on.
          system: [{ type: "text", text: req.system, cache_control: { type: "ephemeral" } }],
          tools: req.tools.map((t) => ({
            name: t.name,
            description: t.description,
            input_schema: t.input_schema as Anthropic.Tool["input_schema"],
          })),
          messages: req.messages as Anthropic.MessageParam[],
          ...(req.effort ? { output_config: { effort: req.effort } } : {}),
        },
        { timeout: req.timeoutMs },
      );
      if (req.onText) stream.on("text", (delta) => req.onText?.(delta));
      res = await stream.finalMessage();
    } catch (e) {
      if (e instanceof Anthropic.APIConnectionError) throw statusError(undefined);
      if (e instanceof Anthropic.BadRequestError && /credit balance/i.test(e.message)) {
        throw new ModelError("anthropic: the API credit balance is too low", false, 400, true);
      }
      if (e instanceof Anthropic.APIError) throw statusError(e.status);
      throw new ModelError("anthropic: the call failed", true);
    }
    const blocks: ChatBlock[] = [];
    for (const b of res.content) {
      if (b.type === "text") blocks.push({ type: "text", text: b.text });
      else if (b.type === "tool_use") {
        const input = typeof b.input === "object" && b.input !== null ? (b.input as Record<string, unknown>) : {};
        blocks.push({ type: "tool_use", id: b.id, name: b.name, input });
      }
    }
    const stop =
      res.stop_reason === "end_turn" || res.stop_reason === "stop_sequence"
        ? "end"
        : res.stop_reason === "tool_use"
          ? "tool_use"
          : res.stop_reason === "max_tokens"
            ? "max_tokens"
            : res.stop_reason === "refusal"
              ? "refusal"
              : "other";
    return {
      blocks,
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
}

/** A scripted client for the unit tests: answers in order, each a message or an error. */
export class ScriptedChatClient implements ChatModelClient {
  readonly requests: ChatRequest[] = [];
  private readonly script: Array<(Partial<ChatAnswer> & { text?: string }) | Error>;

  constructor(script: Array<(Partial<ChatAnswer> & { text?: string }) | Error>) {
    this.script = [...script];
  }

  async chat(req: ChatRequest): Promise<ChatAnswer> {
    this.requests.push(req);
    const next = this.script.shift();
    if (!next) throw new ModelError("scripted: no answer left", false);
    if (next instanceof Error) throw next;
    const blocks = next.blocks ?? [{ type: "text", text: next.text ?? "" }];
    for (const b of blocks) if (b.type === "text" && req.onText) req.onText(b.text);
    return {
      blocks,
      model: next.model ?? req.model,
      usage: next.usage ?? { input: Math.ceil(requestChars(req) / 4), output: 200, cacheRead: 0, cacheWrite: 0 },
      stop: next.stop ?? (blocks.some((b) => b.type === "tool_use") ? "tool_use" : "end"),
      latencyMs: next.latencyMs ?? 5,
    };
  }
}
