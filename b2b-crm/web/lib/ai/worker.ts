import { createHash } from "node:crypto";
import { ALL_TOOLS, DATA_TOOL_NAMES, normaliseReport, PROMPT_VERSION, reportText, systemPrompt, userPrompt, type Report, type RunKind } from "./prompts";
import { validateNumbers } from "./validate";

/**
 * One optimiser run (spec B7.8.2): claim a queued run from the database, talk to Claude with the read-only tools,
 * validate the answer's numbers against the tool results, and hand everything back. The database prices the run,
 * checks each change against the bounds, simulates it and files it in the Advisory inbox.
 * Network and database calls are injected so the loop can be tested without either.
 */

export type Usage = { in: number; out: number; cache_read: number; cache_write: number };
export type Claimed = {
  run: { id: number; kind: RunKind; trigger: string; model: string; context: Record<string, unknown> } | null;
  why?: string;
  limits?: { max_turns: number; max_tokens: number; budget_left_usd: number };
  price_per_mtok?: { in: number; out: number; cache_read?: number; cache_write?: number };
};
export type Db = {
  claim(info: Record<string, unknown>): Promise<Claimed>;
  tool(runId: number, name: string, input: unknown): Promise<{ call_no: number; output: unknown }>;
  finish(runId: number, body: Record<string, unknown>): Promise<unknown>;
  fail(runId: number, error: string, usage: Usage): Promise<unknown>;
};
type Block = { type: string; id?: string; name?: string; input?: unknown; text?: string };
export type Messages = (body: Record<string, unknown>) => Promise<{
  content: Block[]; stop_reason: string;
  usage?: { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number };
}>;

const MAX_TOOL_RESULT_CHARS = 24_000;

export function costUsd(u: Usage, p: Claimed["price_per_mtok"]): number {
  const pr = p ?? { in: 3, out: 15, cache_read: 0.3, cache_write: 3.75 };
  return (u.in * pr.in + u.out * pr.out + u.cache_read * (pr.cache_read ?? 0) + u.cache_write * (pr.cache_write ?? 0)) / 1_000_000;
}

/** Anthropic's Messages API through fetch (no SDK): tools and the system prompt are cached between turns. */
export function anthropicMessages(apiKey: string, fetchImpl: typeof fetch = fetch): Messages {
  return async (body) => {
    const res = await fetchImpl("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(120_000),
    });
    const json = (await res.json().catch(() => null)) as Record<string, unknown> | null;
    if (!res.ok || !json) {
      const err = (json?.error as { message?: string } | undefined)?.message ?? `HTTP ${res.status}`;
      throw new Error(`Anthropic API: ${err}`);
    }
    return json as Awaited<ReturnType<Messages>>;
  };
}

export async function runOnce(db: Db, messages: Messages, info: Record<string, unknown> = {}): Promise<{ run: number | null; status: string; detail?: unknown }> {
  const claimed = await db.claim(info);
  if (!claimed.run) return { run: null, status: claimed.why ?? "nothing queued" };
  const run = claimed.run;
  const limits = claimed.limits ?? { max_turns: 8, max_tokens: 4000, budget_left_usd: 1 };
  const usage: Usage = { in: 0, out: 0, cache_read: 0, cache_write: 0 };
  const outputs: unknown[] = [];
  const tools = ALL_TOOLS.map((t, i) => (i === ALL_TOOLS.length - 1 ? { ...t, cache_control: { type: "ephemeral" } } : t));
  const system = [{ type: "text", text: systemPrompt(run.kind), cache_control: { type: "ephemeral" } }];
  const msgs: { role: "user" | "assistant"; content: unknown }[] = [{ role: "user", content: userPrompt(run.kind, run.context ?? {}) }];
  let report: Report | null = null;
  let nudged = false;

  try {
    for (let turn = 0; turn < limits.max_turns && !report; turn++) {
      if (costUsd(usage, claimed.price_per_mtok) >= limits.budget_left_usd) throw new Error("stopped: the daily budget would be exceeded");
      const last = turn === limits.max_turns - 1;
      const res = await messages({
        model: run.model, max_tokens: limits.max_tokens, system, tools, messages: msgs,
        ...(last ? { tool_choice: { type: "tool", name: "submit_report" } } : {}),
      });
      usage.in += res.usage?.input_tokens ?? 0;
      usage.out += res.usage?.output_tokens ?? 0;
      usage.cache_read += res.usage?.cache_read_input_tokens ?? 0;
      usage.cache_write += res.usage?.cache_creation_input_tokens ?? 0;
      msgs.push({ role: "assistant", content: res.content });

      const calls = res.content.filter((b) => b.type === "tool_use");
      if (calls.length === 0) {
        if (nudged) throw new Error("Claude ended without submitting a report");
        nudged = true;
        msgs.push({ role: "user", content: "Call submit_report now with your summary, findings and recommendations." });
        continue;
      }
      const results: unknown[] = [];
      for (const c of calls) {
        if (c.name === "submit_report") {
          report = normaliseReport(c.input);
          if (!report) throw new Error("submit_report was empty or malformed");
          results.push({ type: "tool_result", tool_use_id: c.id, content: "received" });
          continue;
        }
        if (!c.name || !DATA_TOOL_NAMES.has(c.name)) {
          results.push({ type: "tool_result", tool_use_id: c.id, is_error: true, content: `unknown tool ${c.name}` });
          continue;
        }
        const r = await db.tool(run.id, c.name, c.input ?? {});
        outputs.push(r.output);
        const text = JSON.stringify(r.output);
        results.push({ type: "tool_result", tool_use_id: c.id,
          content: text.length > MAX_TOOL_RESULT_CHARS ? text.slice(0, MAX_TOOL_RESULT_CHARS) + " …(truncated)" : text });
      }
      if (!report) msgs.push({ role: "user", content: results });
    }
    if (!report) throw new Error("no report within the turn limit");

    const allowed = [report.recommendations.map((r) => r.change ?? null), { bounds: [0, 0.5, 30, 90, 14, 60, 5, 50, 0.9, 1.1, 1, 100] }];
    const validation = validateNumbers(reportText(report), outputs, allowed);
    const inputHash = createHash("sha256").update(JSON.stringify(outputs)).digest("hex");
    const narrative = reportText(report);
    const detail = await db.finish(run.id, { narrative, output: report, usage, prompt_version: PROMPT_VERSION, input_hash: inputHash, validation });
    return { run: run.id, status: validation.ok ? "done" : "rejected", detail };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await db.fail(run.id, msg.slice(0, 900), usage);
    return { run: run.id, status: "failed", detail: msg };
  }
}
