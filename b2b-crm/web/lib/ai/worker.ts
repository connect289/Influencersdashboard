import { createHash } from "node:crypto";
import { ALL_TOOLS, DATA_TOOL_NAMES, normaliseReport, PROMPT_FACTS, PROMPT_VERSION, reportText, systemPrompt, userPrompt, type Report, type RunKind } from "./prompts";
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
/** One Messages API call; timeoutMs bounds the whole call, retries included (the worker passes what its deadline leaves). */
export type Messages = (body: Record<string, unknown>, timeoutMs?: number) => Promise<{
  content: Block[]; stop_reason: string;
  usage?: { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number };
}>;

const MAX_TOOL_RESULT_CHARS = 24_000;

export function costUsd(u: Usage, p: Claimed["price_per_mtok"]): number {
  // api_ai_claim always returns a price (b2b.ai_price); this fallback is Opus 5.5's list price, so it never under-counts
  const pr = p ?? { in: 4, out: 20, cache_read: 0.2, cache_write: 5 };
  return (u.in * pr.in + u.out * pr.out + u.cache_read * (pr.cache_read ?? 0) + u.cache_write * (pr.cache_write ?? 0)) / 1_000_000;
}

const RETRY_STATUS = new Set([429, 500, 502, 503, 504, 529]);

/**
 * Anthropic's Messages API through fetch (no SDK): tools and the system prompt are cached between turns.
 * Rate limits and overloads (429, 5xx, 529) and network errors are retried a few times with back-off (retry-after when
 * given), but one call never outlives its time budget: a retry that would end within 5 s of it is not started, and the
 * call's own timeout is never retried. Used by the worker and by Ask the CRM.
 */
export function anthropicMessages(
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
  opts: { retries?: number; sleep?: (ms: number) => Promise<void> } = {},
): Messages {
  const retries = opts.retries ?? 2;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  return async (body, timeoutMs = 180_000) => {
    const until = Date.now() + (Number.isFinite(timeoutMs) ? Math.max(5_000, Math.min(180_000, timeoutMs)) : 180_000);
    const payload = JSON.stringify(body);
    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await fetchImpl("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
          body: payload,
          signal: AbortSignal.timeout(Math.max(1_000, until - Date.now())),
        });
      } catch (e) {
        const name = (e as { name?: unknown } | null)?.name;
        const wait = 1000 * 2 ** attempt;
        if (attempt < retries && name !== "TimeoutError" && name !== "AbortError" && Date.now() + wait < until - 5_000) {
          await sleep(wait);
          continue;
        }
        throw e;
      }
      const json = (await res.json().catch(() => null)) as Record<string, unknown> | null;
      if (res.ok && json) return json as Awaited<ReturnType<Messages>>;
      if (RETRY_STATUS.has(res.status) && attempt < retries) {
        const ra = Number(res.headers.get("retry-after"));
        const wait = Math.min(Number.isFinite(ra) && ra > 0 ? ra * 1000 : 1000 * 2 ** attempt, 20_000);
        if (Date.now() + wait < until - 5_000) {
          await sleep(wait);
          continue;
        }
      }
      const err = (json?.error as { message?: string } | undefined)?.message ?? `HTTP ${res.status}`;
      throw new Error(`Anthropic API: ${err}`);
    }
  };
}

/** The note added to the newest user message when Claude must report now (no forced tool_choice: Sonnet/Opus 5.5 reject it). */
const LAST_TURN_NOTE = "This is your last turn. Call submit_report now with what you have.";

/**
 * Claims and runs one queued run. deadline (epoch ms) is when this worker call must be done with Claude: a turn starts
 * only with 45 s left, each request gets what is left minus 15 s, and with under 120 s left the turn is the last one.
 */
export async function runOnce(
  db: Db, messages: Messages, info: Record<string, unknown> = {}, deadline = Number.POSITIVE_INFINITY,
): Promise<{ run: number | null; status: string; detail?: unknown }> {
  const claimed = await db.claim(info);
  if (!claimed.run) return { run: null, status: claimed.why ?? "nothing queued" };
  const run = claimed.run;
  const limits = claimed.limits ?? { max_turns: 8, max_tokens: 12000, budget_left_usd: 1 };
  const usage: Usage = { in: 0, out: 0, cache_read: 0, cache_write: 0 };
  const outputs: unknown[] = [];
  const tools = ALL_TOOLS.map((t, i) => (i === ALL_TOOLS.length - 1 ? { ...t, cache_control: { type: "ephemeral" } } : t));
  const system = [{ type: "text", text: systemPrompt(run.kind), cache_control: { type: "ephemeral" } }];
  const msgs: { role: "user" | "assistant"; content: unknown }[] = [{ role: "user", content: userPrompt(run.kind, run.context ?? {}) }];
  // Opus/Sonnet 4.6+ and 5.x take an effort level; Haiku 4.5 rejects it, so it gets none
  const effort = /^claude-(opus|sonnet)-(4-[6-9]|5)/.test(run.model) ? { output_config: { effort: "medium" } } : {};
  let report: Report | null = null;
  let nudged = false;

  try {
    for (let turn = 0; turn < limits.max_turns && !report; turn++) {
      if (costUsd(usage, claimed.price_per_mtok) >= limits.budget_left_usd) throw new Error("stopped: the daily budget would be exceeded");
      const left = deadline - Date.now();
      if (left < 45_000) throw new Error("stopped: this worker call ran out of time");
      // the last turn, or too little time for another tool round: ask for the report now. The note is appended to the
      // newest user message, which has not been sent yet; earlier messages, system and tools never change, so the cached
      // prefix and Claude's thinking blocks stay valid (append-only history)
      const last = turn === limits.max_turns - 1 || left < 120_000;
      if (last) {
        const note = { type: "text", text: LAST_TURN_NOTE };
        const tail = msgs[msgs.length - 1]!;
        if (tail.role !== "user") msgs.push({ role: "user", content: [note] });
        else tail.content = typeof tail.content === "string" ? [{ type: "text", text: tail.content }, note] : [...(tail.content as unknown[]), note];
      }
      // tool_choice stays auto (never forced); the top-level cache_control caches the growing conversation as well
      const res = await messages(
        { model: run.model, max_tokens: limits.max_tokens, system, tools, messages: msgs, cache_control: { type: "ephemeral" }, ...effort },
        Math.min(180_000, left - 15_000),
      );
      usage.in += res.usage?.input_tokens ?? 0;
      usage.out += res.usage?.output_tokens ?? 0;
      usage.cache_read += res.usage?.cache_read_input_tokens ?? 0;
      usage.cache_write += res.usage?.cache_creation_input_tokens ?? 0;
      // a cut-off or declined turn ends the run; its usage is already counted, so db.fail records the spend
      if (res.stop_reason === "max_tokens") throw new Error(`Claude was cut off at max_tokens (${limits.max_tokens}) before finishing a turn`);
      if (res.stop_reason === "refusal") throw new Error("Claude declined this run (refusal)");
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
        outputs.push({ input: c.input ?? {}, output: r.output });
        const text = JSON.stringify(r.output);
        results.push({ type: "tool_result", tool_use_id: c.id,
          content: text.length > MAX_TOOL_RESULT_CHARS ? text.slice(0, MAX_TOOL_RESULT_CHARS) + " …(truncated)" : text });
      }
      if (!report) msgs.push({ role: "user", content: results });
    }
    if (!report) throw new Error("no report within the turn limit");

    // Claude's proposed values (and a rule's ids and priority) are proposals, not data claims;
    // its free text (a pause reason, a rule name) and its evidence values are claims and are checked
    const proposed = report.recommendations.flatMap((r) => {
      const c = r.change;
      if (!c) return [];
      const rule = (c.rule ?? {}) as { conditions?: unknown; partner_ids?: unknown; priority?: unknown };
      return [c.value, c.partner_id, rule.conditions, rule.partner_ids, rule.priority];
    });
    const evidence = [...report.findings, ...report.recommendations].flatMap((x) => x.evidence ?? [])
      .map((e) => e?.value)
      .filter((v): v is string | number => typeof v === "number" || typeof v === "string").map(String);
    const changeText = report.recommendations.flatMap((r) => [
      String(r.change?.reason ?? ""), String((r.change?.rule as { name?: unknown } | null | undefined)?.name ?? "")]);
    const validation = validateNumbers([reportText(report), ...changeText, ...evidence].join("\n"), outputs, [proposed, { bounds: PROMPT_FACTS }]);
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
