import { z } from "zod";
import { DbError } from "../../db.ts";
import { UiError } from "../../ui/api.ts";
import { ModelError } from "../client.ts";
import type { AiDb, CallRecord } from "../db.ts";
import { aiSettingsSchema, costOf, route, worstCaseInr, type AiSettings, type Route } from "../models.ts";
import { maskForAi, maskText } from "../pii.ts";
import { PROMPTS, SYSTEM_PROMPT } from "../prompts.generated.ts";
import { localReadTool, type N8nReader } from "../read-tools.ts";
import { MAX_TOKENS } from "../schemas.ts";
import { requestChars, type ChatBlock, type ChatMessage, type ChatModelClient } from "./client.ts";
import type { AssistantContent, ChatDb, HistoryItem, TurnStart } from "./db.ts";
import { looksLikeSecret } from "./secrets.ts";
import { DB_READ_TOOLS, toolDefinition, toolsFor, type ActTool, type ChatTool, type Risk } from "./tools.ts";

// One turn of the command centre (D-094). The person's message opens a turn in the database (masked, budget checked,
// one 'chat' task held by this holder), the model is called with the conversation and the tools until it answers
// without asking for a tool, and the answer is stored. Read tools run at once; a low-risk act runs at once as the
// signed-in person; every other act becomes an action card the person confirms in the chat; a secret is never seen by
// the model. Every model call is recorded against the task with its cost, within the same caps as the worker's tasks.

export type ChatEvent =
  | { t: "start"; thread_id: number; message_id: number; task_id: number }
  | { t: "text"; d: string }
  | {
      t: "tool";
      name: string;
      args: Record<string, unknown>;
      status: "running" | "ok" | "error";
      rows?: number;
      error?: string;
    }
  | { t: "action"; action: { id: number; tool: string; args: Record<string, unknown>; summary: string; risk: Risk } }
  | { t: "secret"; name: string; item?: string }
  | { t: "done"; message_id: number; text: string; calls: number; cost_inr: number }
  | { t: "refused"; message: string }
  | { t: "error"; message: string };

export type ChatDeps = {
  chat: ChatDb;
  ai: Pick<AiDb, "recordCalls" | "tool" | "reserve">;
  /** The Claude client, or null when no key is set. */
  client: ChatModelClient | null;
  n8n?: N8nReader | null;
  /** Runs a one.ui_* page function as the signed-in person (the acts that run at once). */
  act: (fn: string, args: Record<string, unknown>, requestId: string) => Promise<unknown>;
  /** Runs a Setup item's validator and records the verdict (the validate_setup act). */
  validateSetup?: (item: string) => Promise<{ ok: boolean; detail: string }>;
  holder: string;
  /** Wall-clock end of this request (epoch ms). */
  deadline: number;
  now?: () => number;
};

export type Emit = (e: ChatEvent) => void;

const MAX_ROUNDS = 8;
const MAX_TOOL_CALLS = 16;
const TOOL_RESULT_CHARS = 8_000;
const HISTORY_CHARS = 60_000;
const CONTEXT_MAX_CHARS = 150_000;
const CALL_MIN_MS = 15_000;
const CALL_TIMEOUT_MS = 90_000;

class Stop extends Error {}

const inr = (n: number) => `₹${n.toFixed(2)}`;

export const SECRET_REFUSAL =
  "That looks like a key, a token or a password. I did not send it to the model and I have not kept it. " +
  "Paste it into the Vault card for its Setup item instead (ask me to open the card, or use Settings → Setup), " +
  "and if it was a real secret rotate it, because it was typed into a browser.";

/**
 * The conversation so far as the model's messages: alternating roles, actions folded into the person's side. Every
 * stored value is masked here with the app's maskText (D-105), as the new message is: this is the model's input, which
 * the app masks whatever produced it (spec §11).
 */
export function historyMessages(history: HistoryItem[], maxChars = HISTORY_CHARS): ChatMessage[] {
  const parts: Array<{ role: "user" | "assistant"; text: string }> = [];
  const m = (v: unknown) => maskText(String(v ?? ""));
  for (const h of history) {
    const c = h.content;
    if (h.role === "user") {
      parts.push({ role: "user", text: m(c.text) });
    } else if (h.role === "assistant") {
      const tools = Array.isArray(c.tools) ? (c.tools as Array<Record<string, unknown>>) : [];
      const used = tools.length
        ? `\n\n[Tools used: ${tools
            .map(
              (t) =>
                `${String(t.name)}(${m(JSON.stringify(t.args ?? {}))}) → ${t.ok ? `${String(t.rows ?? 0)} rows` : "error"}`,
            )
            .join("; ")}]`
        : "";
      parts.push({
        role: "assistant",
        text: `${m(c.text)}${c.error ? ` [turn failed: ${m(c.error)}]` : ""}${used}`,
      });
    } else {
      parts.push({
        role: "user",
        text: `[Action #${String(c.action_id)} (${String(c.tool)}): ${String(c.status)}${c.error ? `, ${m(c.error)}` : ""} — ${m(c.summary)}]`,
      });
    }
  }
  // Oldest first is dropped until the history fits.
  let total = parts.reduce((n, p) => n + p.text.length, 0);
  while (parts.length > 1 && total > maxChars) total -= parts.shift()?.text.length ?? 0;
  // The API wants user and assistant to alternate and the first to be the person's.
  const merged: ChatMessage[] = [];
  for (const p of parts) {
    const last = merged.at(-1);
    if (last && last.role === p.role && typeof last.content === "string") last.content = `${last.content}\n\n${p.text}`;
    else merged.push({ role: p.role, content: p.text });
  }
  while (merged[0]?.role === "assistant") merged.shift();
  return merged;
}

function systemPrompt(turn: TurnStart, tools: ChatTool[]): string {
  const acts = tools.filter((t): t is ActTool => t.kind === "act");
  const auto = acts.filter((t) => !t.confirm).map((t) => t.name);
  const confirm = acts.filter((t) => t.confirm).map((t) => t.name);
  return [
    SYSTEM_PROMPT,
    PROMPTS.chat.text,
    `The person: ${turn.me.email}, role ${turn.me.role}.`,
    `Acts that run at once: ${auto.join(", ")}. Acts that first show an action card for the person to confirm: ${confirm.join(", ")}.`,
    `The console now (IST ${String(turn.snapshot.now_ist ?? "")}): ${JSON.stringify(turn.snapshot)}`,
  ].join("\n\n");
}

type ToolRow = AssistantContent["tools"][number];

/** One tool call's answer for the model, bounded and masked, plus the row the conversation keeps. */
function toolText(
  name: string,
  args: Record<string, unknown>,
  result: { ok: boolean; data?: unknown; error?: string },
) {
  const data = maskForAi(result.data ?? null);
  const rows = Array.isArray(data) ? data.length : data && typeof data === "object" ? 1 : 0;
  const error = result.error ? maskText(result.error).slice(0, 300) : undefined;
  let text = JSON.stringify(result.ok ? data : { error });
  if (text.length > TOOL_RESULT_CHARS) text = `${text.slice(0, TOOL_RESULT_CHARS)}… [cut: ask for a smaller range]`;
  const row: ToolRow = {
    name,
    args: maskForAi(args) as Record<string, unknown>,
    ok: result.ok,
    rows,
    result: text.slice(0, 3000),
    ...(error ? { error } : {}),
  };
  return { text, row };
}

class Budget {
  readonly calls: CallRecord[] = [];
  spentInr = 0;
  remainingInr: number;
  private readonly ai: AiSettings;

  constructor(ai: AiSettings, remaining: number) {
    this.ai = ai;
    this.remainingInr = remaining;
  }

  check(r: Route, chars: number, maxTokens: number) {
    const worst = worstCaseInr(r.price, chars, maxTokens, this.ai.usd_inr);
    if (this.spentInr + worst > this.ai.per_task_cap_inr) {
      throw new Stop(
        `this turn has reached its cap: the next call could cost up to ${inr(worst)}, past the per-task cap ${inr(this.ai.per_task_cap_inr)} (Settings → AI). Start a new conversation or ask for less at a time`,
      );
    }
    if (worst > this.remainingInr) {
      throw new Stop(
        `budget (cap reached): the next call could cost up to ${inr(worst)} and ${inr(Math.max(this.remainingInr, 0))} is left today`,
      );
    }
    return worst;
  }

  /**
   * The call's worst case, reserved in the database before it runs (D-118): turns and worker tasks in parallel cannot
   * pass the day's cap together. The call's record settles it. No answer from the database, no call.
   */
  async reserve(deps: ChatDeps, task: number, worst: number) {
    let r: { ok: boolean; remaining_inr: number };
    try {
      r = await deps.ai.reserve(task, deps.holder, worst);
    } catch {
      throw new Stop("the call's budget could not be reserved; ask again");
    }
    if (!r.ok) {
      throw new Stop(
        `budget (cap reached): the next call could cost up to ${inr(worst)} and ${inr(Math.max(r.remaining_inr, 0))} is left today, counting the calls in flight`,
      );
    }
  }

  async record(deps: ChatDeps, task: number, c: CallRecord) {
    this.calls.push(c);
    this.spentInr += c.cost_inr ?? 0;
    try {
      this.remainingInr = (await deps.ai.recordCalls(task, deps.holder, [c])).remaining_inr;
    } catch {
      this.remainingInr -= c.cost_inr ?? 0;
    }
  }
}

async function runReadTool(
  tool: ChatTool,
  args: Record<string, unknown>,
  turn: TurnStart,
  deps: ChatDeps,
): Promise<{ ok: boolean; data?: unknown; error?: string }> {
  try {
    if (DB_READ_TOOLS.has(tool.name)) {
      return z
        .object({ ok: z.boolean(), data: z.unknown().optional(), error: z.string().optional() })
        .parse(await deps.ai.tool(turn.task_id, deps.holder, tool.name, args));
    }
    return (await localReadTool(tool.name, args, deps.n8n)) ?? { ok: false, error: `unknown tool ${tool.name}` };
  } catch (e) {
    return { ok: false, error: e instanceof DbError ? e.message : "the tool failed" };
  }
}

async function runAutoAct(
  tool: ActTool,
  args: Record<string, unknown>,
  deps: ChatDeps,
): Promise<{ ok: boolean; data?: unknown; error?: string }> {
  const call = tool.call(args);
  try {
    if ("local" in call) {
      if (!deps.validateSetup) return { ok: false, error: "validation is not available here" };
      const v = await deps.validateSetup(call.item);
      return { ok: v.ok, data: { validated: v.ok, detail: v.detail } };
    }
    const data = await deps.act(call.fn, call.args, crypto.randomUUID());
    return { ok: true, data };
  } catch (e) {
    if (e instanceof UiError) return { ok: false, error: e.message };
    return { ok: false, error: "the action failed" };
  }
}

/** Runs one turn: emits events as it goes and resolves when the turn is stored (done or failed). */
export async function runTurn(
  input: { thread: number | null; text: string },
  deps: ChatDeps,
  emit: Emit,
): Promise<void> {
  const now = deps.now ?? Date.now;
  const text = input.text.trim();
  if (looksLikeSecret(text)) {
    emit({ t: "refused", message: SECRET_REFUSAL });
    return;
  }
  if (!deps.client) {
    emit({
      t: "error",
      message: "The AI is not switched on yet: save an Anthropic key on Settings → Setup (item ai_key).",
    });
    return;
  }
  let turn: TurnStart;
  try {
    turn = await deps.chat.turnStart(input.thread, text, deps.holder, crypto.randomUUID());
  } catch (e) {
    emit({
      t: "error",
      message: e instanceof UiError ? e.message : "The conversation could not be opened. Try again.",
    });
    return;
  }
  emit({ t: "start", thread_id: turn.thread_id, message_id: turn.message_id, task_id: turn.task_id });

  const settings = aiSettingsSchema.safeParse(turn.ai);
  const r = settings.success ? route(settings.data, "chat", null) : null;
  const assistant: AssistantContent = { text: "", tools: [], actions: [] };
  const finish = async (status: "done" | "failed", error: string | null) => {
    let messageId = 0;
    try {
      messageId = await deps.chat.turnFinish(turn.task_id, deps.holder, assistant, status, error);
    } catch {
      // The turn stays open and is failed by the next turn (10 minutes); the person still sees the answer.
    }
    if (status === "done") {
      const cost = assistant.meta?.cost_inr ?? 0;
      emit({
        t: "done",
        message_id: messageId,
        text: assistant.text,
        calls: assistant.meta?.calls ?? 0,
        cost_inr: cost,
      });
    } else {
      emit({ t: "error", message: error ?? "The turn failed." });
    }
  };
  if (!settings.success || !r) return finish("failed", "setup: the AI settings cannot be read (Settings → AI)");
  if ("error" in r) return finish("failed", `setup: ${r.detail}`);
  const ai = settings.data;
  const tools = toolsFor(turn.me.role);
  const defs = tools.map(toolDefinition);
  const system = systemPrompt(turn, tools);
  const messages: ChatMessage[] = [...historyMessages(turn.history), { role: "user", content: maskText(text) }];
  const budget = new Budget(ai, turn.budget.remaining_inr);
  const texts: string[] = [];
  let toolCalls = 0;
  let model = r.model;
  try {
    for (let round = 1; round <= MAX_ROUNDS; round++) {
      const req = { model: r.model, system, messages, tools: defs, maxTokens: MAX_TOKENS.chat, effort: r.effort };
      const chars = requestChars(req);
      if (chars > CONTEXT_MAX_CHARS)
        throw new Stop("this conversation has grown too long for one turn; start a new one");
      const worstCall = budget.check(r, chars, MAX_TOKENS.chat);
      const timeLeft = deps.deadline - now() - 3_000;
      if (timeLeft < CALL_MIN_MS) throw new Stop("the turn ran out of time before the answer; ask again");
      await budget.reserve(deps, turn.task_id, worstCall);
      const base = {
        provider: "anthropic" as const,
        model: r.model,
        purpose: `chat:${round}`,
        prompt_version: PROMPTS.chat.version,
      };
      let answer;
      try {
        answer = await deps.client.chat({
          ...req,
          timeoutMs: Math.min(CALL_TIMEOUT_MS, timeLeft),
          onText: (d) => emit({ t: "text", d }),
        });
      } catch (e) {
        const err = e instanceof ModelError ? e : new ModelError("the model call failed", true);
        const unknown = err.status === undefined;
        const worst = worstCaseInr(r.price, chars, MAX_TOKENS.chat, ai.usd_inr);
        await budget.record(deps, turn.task_id, {
          ...base,
          ok: false,
          error: unknown ? `${err.message}; counted at its worst case` : err.message,
          ...(unknown && !err.credits
            ? { cost_inr: worst, cost_usd: Math.round((worst / ai.usd_inr) * 1e5) / 1e5 }
            : {}),
        });
        throw new Stop(
          err.credits ? "budget (credits exhausted): the Anthropic API credit balance is too low" : err.message,
        );
      }
      const cost = costOf(r.price, answer.usage, ai.usd_inr);
      model = answer.model;
      await budget.record(deps, turn.task_id, {
        ...base,
        model: answer.model,
        input_tokens: answer.usage.input,
        output_tokens: answer.usage.output,
        cache_read: answer.usage.cacheRead,
        cost_usd: cost.usd,
        cost_inr: cost.inr,
        latency_ms: answer.latencyMs,
        ok: answer.stop !== "refusal" && answer.stop !== "max_tokens",
        error:
          answer.stop === "refusal"
            ? "the model declined to answer"
            : answer.stop === "max_tokens"
              ? "the answer was cut off"
              : null,
      });
      for (const b of answer.blocks) if (b.type === "text" && b.text.trim()) texts.push(b.text.trim());
      if (answer.stop === "refusal") throw new Stop("the model declined to answer this");
      const uses = answer.blocks.filter((b): b is ChatBlock & { type: "tool_use" } => b.type === "tool_use");
      if (uses.length === 0 || answer.stop !== "tool_use") {
        if (answer.stop === "max_tokens")
          texts.push("(The answer was cut off at its length allowance; ask for the rest.)");
        break;
      }
      messages.push({ role: "assistant", content: answer.blocks });
      const results: Array<{ type: "tool_result"; tool_use_id: string; content: string; is_error?: boolean }> = [];
      for (const u of uses) {
        toolCalls++;
        const tool = tools.find((t) => t.name === u.name);
        let content: string;
        let isError = false;
        if (!tool) {
          content = JSON.stringify({ error: `unknown tool ${u.name}` });
          isError = true;
        } else if (toolCalls > MAX_TOOL_CALLS) {
          content = JSON.stringify({ error: "no more tool calls in this turn: answer with what you have" });
          isError = true;
        } else {
          const parsed = tool.input.safeParse(u.input);
          if (!parsed.success) {
            const issue = parsed.error.issues
              .slice(0, 3)
              .map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`)
              .join("; ");
            content = JSON.stringify({ error: `arguments: ${issue}` });
            isError = true;
            assistant.tools.push({
              name: u.name,
              args: maskForAi(u.input) as Record<string, unknown>,
              ok: false,
              rows: 0,
              result: "",
              error: `arguments: ${issue}`.slice(0, 300),
            });
          } else {
            const args = parsed.data as Record<string, unknown>;
            if (tool.kind === "read") {
              emit({ t: "tool", name: tool.name, args: maskForAi(args) as Record<string, unknown>, status: "running" });
              const res = await runReadTool(tool, args, turn, deps);
              const { text: t, row } = toolText(tool.name, args, res);
              content = t;
              isError = !res.ok;
              assistant.tools.push(row);
              emit({
                t: "tool",
                name: tool.name,
                args: row.args,
                status: res.ok ? "ok" : "error",
                rows: row.rows,
                ...(row.error ? { error: row.error } : {}),
              });
            } else if (tool.kind === "secret") {
              emit({ t: "secret", name: String(args.name), ...(args.item ? { item: String(args.item) } : {}) });
              content = JSON.stringify({
                shown: true,
                note: "a Vault card is in the chat; the person pastes the value there and you never see it",
              });
              assistant.tools.push({ name: tool.name, args, ok: true, rows: 0, result: "card shown" });
            } else if (tool.confirm) {
              const summary = tool.summary(args);
              try {
                const id = await deps.chat.actionPropose(
                  turn.task_id,
                  deps.holder,
                  tool.name,
                  args,
                  summary,
                  tool.risk,
                );
                assistant.actions.push(id);
                emit({ t: "action", action: { id, tool: tool.name, args, summary, risk: tool.risk } });
                content = JSON.stringify({
                  proposed: true,
                  action_id: id,
                  summary,
                  note: "waiting for the person's confirmation in the chat; it has not run. Do not say it is done",
                });
                assistant.tools.push({ name: tool.name, args, ok: true, rows: 0, result: `proposed as action #${id}` });
              } catch (e) {
                const error = e instanceof UiError ? e.message : "the action could not be proposed";
                content = JSON.stringify({ error });
                isError = true;
                assistant.tools.push({ name: tool.name, args, ok: false, rows: 0, result: "", error });
              }
            } else {
              emit({ t: "tool", name: tool.name, args, status: "running" });
              const res = await runAutoAct(tool, args, deps);
              const { text: t, row } = toolText(tool.name, args, res);
              content = t;
              isError = !res.ok;
              assistant.tools.push(row);
              emit({
                t: "tool",
                name: tool.name,
                args,
                status: res.ok ? "ok" : "error",
                rows: row.rows,
                ...(row.error ? { error: row.error } : {}),
              });
            }
          }
        }
        results.push({ type: "tool_result", tool_use_id: u.id, content, ...(isError ? { is_error: true } : {}) });
      }
      messages.push({ role: "user", content: results });
      if (round === MAX_ROUNDS) texts.push("(I stopped after several rounds of tools; ask again for the rest.)");
    }
  } catch (e) {
    const message = e instanceof Stop ? e.message : "the turn failed";
    assistant.text = texts.join("\n\n");
    assistant.meta = {
      model,
      tier: r.tier,
      prompt_version: PROMPTS.chat.version,
      calls: budget.calls.length,
      cost_inr: budget.spentInr,
    };
    return finish("failed", message);
  }
  assistant.text = texts.join("\n\n") || "(no answer)";
  assistant.meta = {
    model,
    tier: r.tier,
    prompt_version: PROMPTS.chat.version,
    calls: budget.calls.length,
    cost_inr: budget.spentInr,
  };
  return finish("done", null);
}
