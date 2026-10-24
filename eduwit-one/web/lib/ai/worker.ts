import { z } from "zod";
import { DbError } from "../db.ts";
import { ModelError, type ModelClient } from "./client.ts";
import type { AiDb, CallRecord, Claim } from "./db.ts";
import { aiSettingsSchema, costOf, route, worstCaseInr, type AiSettings, type Provider, type Route } from "./models.ts";
import { maskForAi, maskText } from "./pii.ts";
import { PROMPTS, SYSTEM_PROMPT } from "./prompts.generated.ts";
import { askFinalSchema, askRoundSchema, MAX_TOKENS, SCHEMAS } from "./schemas.ts";

// The AI worker (spec §11), called by the database each minute while a task is due (one.ai_step, D-075). It claims a
// task, picks the model from the settings, masks the data the database sent (lib/ai/pii.ts), checks that the call's
// worst case fits the per-task cap and what is left today, calls the model, validates the answer against the kind's
// schema (one repair attempt), and files it; the database decides what the answer may change. Every call is recorded
// with its tokens and cost, whatever the outcome. Nothing here logs a prompt, an answer or a key.

export type N8nReader = {
  executions(
    limit: number,
  ): Promise<Array<{ id: string; status: string; startedAt: string | null; stoppedAt: string | null }>>;
};

export type WorkerDeps = {
  db: AiDb;
  clientFor(provider: Provider): ModelClient | null;
  /** Witty's n8n executions for Ask (status and times only), when the n8n key is set. */
  n8n?: N8nReader | null;
  holder: string;
  /** Wall-clock end of this invocation (epoch ms). */
  deadline: number;
  now?: () => number;
};

export type Outcome = "done" | "failed" | "retry" | "deferred";
export type WorkerSummary = { claimed: number; done: number; failed: number; retry: number; deferred: number };

/** A task is not started with less time than this left, and a call is not made with less than CALL_MIN_MS. */
const START_MIN_MS = 90_000;
const CALL_MIN_MS = 20_000;
const CALL_TIMEOUT_MS = { quick: 60_000, regular: 120_000, deep: 180_000 } as const;
const CONTEXT_MAX_CHARS = 150_000;
const TOOL_RESULT_CHARS = 8_000;
const ASK_ROUNDS = 3;
const ASK_CALLS_MAX = 12;
const CLAIMS_MAX = 50;

class Stop extends Error {
  readonly how: "fail" | "retry" | "defer";
  readonly minutes: number;

  constructor(how: "fail" | "retry" | "defer", message: string, minutes = 30) {
    super(message);
    this.how = how;
    this.minutes = minutes;
  }
}

const inr = (n: number) => `₹${n.toFixed(2)}`;

/** One task's calls: the route, the spend so far, and the call with its checks. */
class TaskCalls {
  readonly calls: CallRecord[] = [];
  spentInr = 0;

  private readonly claim: Claim;
  private readonly ai: AiSettings;
  private readonly r: Route;
  private readonly client: ModelClient;
  private readonly deps: WorkerDeps;

  constructor(claim: Claim, ai: AiSettings, r: Route, client: ModelClient, deps: WorkerDeps) {
    this.claim = claim;
    this.ai = ai;
    this.r = r;
    this.client = client;
    this.deps = deps;
  }

  private now() {
    return (this.deps.now ?? Date.now)();
  }

  async json<S extends z.ZodType>(
    schema: S,
    system: string,
    user: string,
    maxTokens: number,
    purpose: string,
    version: string,
  ): Promise<z.infer<S>> {
    let issue = "";
    for (let attempt = 0; attempt < 2; attempt++) {
      const message =
        attempt === 0
          ? user
          : `${user}\n\nYour previous answer did not match the required JSON: ${issue}. Answer again with one JSON object only.`;
      const text = await this.call(schema, system, message, maxTokens, purpose, version);
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        issue = "it was not valid JSON";
        continue;
      }
      const r = schema.safeParse(parsed);
      if (r.success) return r.data;
      issue = r.error.issues
        .slice(0, 3)
        .map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`)
        .join("; ")
        .slice(0, 300);
    }
    throw new Stop("retry", `the answer did not match the schema twice (${issue})`);
  }

  private async call(
    schema: z.ZodType,
    system: string,
    user: string,
    maxTokens: number,
    purpose: string,
    version: string,
  ) {
    const { ai, r } = this;
    const schemaChars = r.provider === "gemini" ? JSON.stringify(z.toJSONSchema(schema)).length : 0;
    const worst = worstCaseInr(r.price, system.length + user.length + schemaChars, maxTokens, ai.usd_inr);
    if (this.spentInr + worst > ai.per_task_cap_inr) {
      throw new Stop(
        "fail",
        `this call could cost up to ${inr(worst)}, which would take the task past the per-task cap ${inr(ai.per_task_cap_inr)} (Settings → AI)`,
      );
    }
    const left = this.claim.budget.remaining_inr - this.spentInr;
    if (worst > left) {
      throw new Stop(
        "defer",
        `budget: this call could cost up to ${inr(worst)} and ${inr(Math.max(left, 0))} is left today`,
        15,
      );
    }
    const timeLeft = this.deps.deadline - this.now() - 5_000;
    if (timeLeft < CALL_MIN_MS) throw new Stop("retry", "the worker ran out of time before the call");
    const base = { provider: r.provider, model: r.model, purpose, prompt_version: version };
    let answer;
    try {
      answer = await this.client.complete({
        model: r.model,
        system,
        user,
        schema,
        maxTokens,
        effort: r.effort,
        timeoutMs: Math.min(CALL_TIMEOUT_MS[r.tier], timeLeft),
      });
    } catch (e) {
      const err = e instanceof ModelError ? e : new ModelError("the model call failed", true);
      this.calls.push({ ...base, ok: false, error: err.message });
      throw new Stop(err.retry ? "retry" : "fail", err.message);
    }
    const cost = costOf(r.price, answer.usage, ai.usd_inr);
    this.spentInr += cost.inr;
    const stopError =
      answer.stop === "refusal"
        ? "the model declined to answer"
        : answer.stop === "max_tokens"
          ? `the answer was cut off at the ${maxTokens}-token allowance`
          : null;
    this.calls.push({
      ...base,
      model: answer.model,
      input_tokens: answer.usage.input,
      output_tokens: answer.usage.output,
      cache_read: answer.usage.cacheRead,
      cost_usd: cost.usd,
      cost_inr: cost.inr,
      latency_ms: answer.latencyMs,
      ok: stopError === null,
      error: stopError,
    });
    if (stopError) throw new Stop("fail", stopError);
    return answer.text;
  }
}

function userMessage(claim: Claim, data: unknown): string {
  const json = JSON.stringify(data, null, 1);
  if (json.length > CONTEXT_MAX_CHARS)
    throw new Stop("fail", `the task's data is too large (${json.length} characters)`);
  const t = claim.task;
  const head =
    t.kind === "brief"
      ? `The brief for ${String(t.input.for_date ?? "?")}, about the IST day before it.`
      : t.incident_id !== null
        ? `Incident #${t.incident_id}.`
        : "The data for this task.";
  return `${head}\n\nData (JSON, contact details masked):\n${json}`;
}

const clamp = (v: unknown, lo: number, hi: number, dflt: number) => {
  const n = typeof v === "number" ? Math.trunc(v) : dflt;
  return Math.min(Math.max(Number.isFinite(n) ? n : dflt, lo), hi);
};

type Query = { tool: string; args: Record<string, unknown>; ok: boolean; rows: number; error?: string };

async function runTool(
  claim: Claim,
  deps: WorkerDeps,
  tool: string,
  argsJson: string,
): Promise<{ q: Query; text: string }> {
  let args: Record<string, unknown> = {};
  try {
    const parsed: unknown = argsJson.trim() ? JSON.parse(argsJson) : {};
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error("not an object");
    args = parsed as Record<string, unknown>;
  } catch {
    const q = { tool, args: {}, ok: false, rows: 0, error: "the arguments were not a JSON object" };
    return { q, text: JSON.stringify(q) };
  }
  let result: { ok: boolean; data?: unknown; error?: string };
  try {
    if (tool === "n8n_executions") {
      if (!deps.n8n) {
        result = { ok: false, error: "n8n is not configured (Setup item n8n_api)" };
      } else {
        const status = typeof args.status === "string" ? args.status : null;
        const rows = await deps.n8n.executions(clamp(args.limit, 1, 20, 10));
        result = { ok: true, data: rows.filter((r) => !status || r.status === status) };
      }
    } else {
      result = z
        .object({ ok: z.boolean(), data: z.unknown().optional(), error: z.string().optional() })
        .parse(await deps.db.tool(claim.task.id, deps.holder, tool, args));
    }
  } catch (e) {
    result = { ok: false, error: e instanceof DbError ? e.message : "the tool failed" };
  }
  const data = maskForAi(result.data ?? null);
  const rows = Array.isArray(data) ? data.length : data && typeof data === "object" ? 1 : 0;
  const q: Query = { tool, args, ok: result.ok, rows, ...(result.error ? { error: result.error } : {}) };
  let text = JSON.stringify(result.ok ? data : { error: result.error });
  if (text.length > TOOL_RESULT_CHARS) text = `${text.slice(0, TOOL_RESULT_CHARS)}… [cut: ask for a smaller range]`;
  return { q, text };
}

async function ask(claim: Claim, deps: WorkerDeps, tc: TaskCalls): Promise<Record<string, unknown>> {
  const ctx = (claim.context ?? {}) as Record<string, unknown>;
  const question = maskText(String(ctx.question ?? "")).slice(0, 2000);
  const system = `${SYSTEM_PROMPT}\n\n${PROMPTS.ask.text}`;
  const version = PROMPTS.ask.version;
  const queries: Query[] = [];
  const results: string[] = [];
  for (let round = 1; round <= ASK_ROUNDS; round++) {
    const last = round === ASK_ROUNDS;
    const user = [
      `Question: ${question}`,
      `Today (IST): ${String(ctx.today_ist ?? "")}`,
      results.length ? `Tool results so far:\n${results.join("\n\n")}` : "No tools have been called yet.",
      last ? "This is the last round: answer now, from the results above." : `Round ${round} of ${ASK_ROUNDS}.`,
    ].join("\n\n");
    if (last) {
      const out = await tc.json(askFinalSchema, system, user, MAX_TOKENS.ask, `ask:${round}`, version);
      return { answer: out.answer, queries };
    }
    const out = await tc.json(askRoundSchema, system, user, MAX_TOKENS.ask_round, `ask:${round}`, version);
    if (out.calls.length === 0 && out.answer) return { answer: out.answer, queries };
    for (const c of out.calls) {
      if (queries.length >= ASK_CALLS_MAX) break;
      const { q, text } = await runTool(claim, deps, c.tool, c.args_json);
      queries.push(q);
      results.push(`### ${c.tool} ${JSON.stringify(q.args)}\n${text}`);
    }
    if (out.calls.length === 0) results.push("(no tools were asked for)");
  }
  throw new Stop("retry", "Ask ended without an answer");
}

/** Runs one claimed task to its verdict, which it records. */
export async function runTask(claim: Claim, deps: WorkerDeps): Promise<Outcome> {
  const { db, holder } = deps;
  const t = claim.task;
  const settings = aiSettingsSchema.safeParse(claim.ai);
  if (!settings.success) {
    await db.defer(t.id, holder, "setup: the AI settings cannot be read (Settings → AI)", 30);
    return "deferred";
  }
  const ai = settings.data;
  const r = route(ai, t.kind, t.model_hint);
  if ("error" in r) {
    await db.defer(t.id, holder, `setup: ${r.detail}`, 30);
    return "deferred";
  }
  const client = deps.clientFor(r.provider);
  if (!client) {
    await db.defer(t.id, holder, `setup: no ${r.provider} key (Setup item ai_key)`, 30);
    return "deferred";
  }
  const tc = new TaskCalls(claim, ai, r, client, deps);
  let result: Record<string, unknown>;
  let version: string;
  try {
    if (t.kind === "ask") {
      version = PROMPTS.ask.version;
      result = await ask(claim, deps, tc);
    } else {
      const ctx = (claim.context ?? {}) as { incident?: { app?: unknown } };
      const excerpts = t.kind === "explain" && ai.allow_message_excerpts && ctx.incident?.app === "witty";
      const data = maskForAi(claim.context, { excerpts });
      const prompt = PROMPTS[t.kind];
      version = prompt.version;
      const system = `${SYSTEM_PROMPT}\n\n${prompt.text}`;
      const out = await tc.json(SCHEMAS[t.kind], system, userMessage(claim, data), MAX_TOKENS[t.kind], t.kind, version);
      result = out as Record<string, unknown>;
    }
  } catch (e) {
    const stop = e instanceof Stop ? e : new Stop("retry", "the task failed");
    // Spend already made is recorded with the verdict: a deferral after a call becomes a retry, which records it.
    if (stop.how === "defer" && tc.calls.length === 0) {
      await db.defer(t.id, holder, stop.message, stop.minutes);
      return "deferred";
    }
    const status = await db.fail(t.id, holder, stop.message, tc.calls, stop.how !== "fail");
    return status === "pending" ? "retry" : "failed";
  }
  const filed = {
    ...result,
    meta: { provider: r.provider, model: tc.calls.at(-1)?.model ?? r.model, tier: r.tier, prompt_version: version },
  };
  try {
    await db.finish(t.id, holder, filed, tc.calls);
    return "done";
  } catch (e) {
    const code = e instanceof DbError ? (e.code ?? "error") : "error";
    await db.fail(t.id, holder, `the answer could not be filed (${code})`, tc.calls, false);
    return "failed";
  }
}

/** Claims and runs tasks until none is due or the time is nearly up. */
export async function runWorker(deps: WorkerDeps): Promise<WorkerSummary> {
  const now = deps.now ?? Date.now;
  const summary: WorkerSummary = { claimed: 0, done: 0, failed: 0, retry: 0, deferred: 0 };
  // A deferred task is not offered again for its wait, so the loop always moves on; the cap bounds one invocation.
  while (summary.claimed < CLAIMS_MAX && deps.deadline - now() > START_MIN_MS) {
    const claim = await deps.db.claim(deps.holder);
    if (!claim) break;
    summary.claimed++;
    summary[await runTask(claim, deps)]++;
  }
  return summary;
}
