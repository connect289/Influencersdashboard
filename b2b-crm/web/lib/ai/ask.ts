import { PERIODS, PERIOD_LABEL, type Period } from "../analytics";
import type { Messages, Usage } from "./worker";
import { validateNumbers, type Validation } from "./validate";

/**
 * "Ask the CRM" (spec B7.8.2, B14.3): a natural-language question answered only through the metric layer's read-only
 * tools, never free SQL. The answer is shown only when every number in it came from a tool result, with its sources.
 */

export const ASK_PROMPT_VERSION = "ask-2026-10-07.2";

export const ASK_SYSTEM = `You answer questions about Eduwit's B2B partner CRM (student leads routed to partner companies that sell
online and distance degree programmes; Eduwit earns commission on enrolments). You can only read data through the tools:
list_metrics shows what can be measured and how it can be broken down; query_metric returns a metric's value for a period
with optional breakdowns and filters, and the previous period's value. There is no personal data (no names, phones or e-mails).

Rules:
- Every number in your answer must appear in a tool result of this conversation (rounding is fine). Do not compute new
  numbers yourself; if a ratio or difference is needed, look for a metric that gives it or say you cannot compute it.
- Say which period you used. Use Indian formatting for rupees.
- Name the period with the period_label from the result (e.g. 'last 12 months', not 'this year').
- If the data cannot answer the question, say so plainly and suggest the closest thing it can answer.
- Finish by calling submit_answer once, with a short answer (a few sentences or a short list) and the queries it rests on.`;

const PERIOD_ENUM = [...PERIODS];

export const ASK_TOOLS = [
  { name: "list_metrics", description: "Every metric: key, label, unit, area and the breakdowns it supports.", input_schema: { type: "object", properties: { area: { type: "string" } }, additionalProperties: false } },
  { name: "query_metric", description: "A metric's value over a period, optionally broken down (up to 2 breakdowns) and filtered, with the previous period.",
    input_schema: { type: "object", properties: {
      metric: { type: "string" }, dims: { type: "array", items: { type: "string" }, maxItems: 2 },
      filters: { type: "object", additionalProperties: { type: "array", items: { type: "string" } } },
      period: { type: "string", enum: PERIOD_ENUM, description: "today = since midnight IST; 7d/30d/90d = rolling days; month = this calendar month to date (IST); quarter = this calendar quarter to date (IST); year = the last 12 months, rolling (not the calendar year). Default 30d. Describe the period with the period_label the result gives." },
      limit: { type: "integer", minimum: 1, maximum: 50 },
    }, required: ["metric"], additionalProperties: false } },
  { name: "submit_answer", description: "Your final answer. Call once.", input_schema: { type: "object", properties: {
      answer: { type: "string" },
      sources: { type: "array", items: { type: "object", properties: { metric: { type: "string" }, dims: { type: "array", items: { type: "string" } }, filters: { type: "object" }, period: { type: "string" } } } },
    }, required: ["answer"] } },
];

// people's names (partner counsellors): never sent to Claude (B7.8, B18)
const AI_BLOCKED_DIMS = new Set(["counsellor"]);

/** Added to the newest user message when Claude must answer now (no forced tool_choice: Sonnet/Opus 5.5 reject it). */
const LAST_TURN_NOTE = "This is your last turn. Call submit_answer now with what you have.";

export type AskDb = {
  catalogue(): Promise<{ metrics: { key: string; label: string; unit: string; area: string; dims: string[]; description: string | null }[] }>;
  query(p: Record<string, unknown>): Promise<unknown>;
};
export type AskSource = { metric: string; dims?: string[]; filters?: Record<string, string[]>; period?: string };
export type AskResult = { answer: string | null; sources: AskSource[]; validation: Validation; usage: Usage; tool_calls: { name: string; input: unknown }[]; error?: string };

/** The period for a query: the named period ending now, as from/to. */
export function periodBounds(period: string | undefined, now = new Date()): { from: string; to: string } {
  const to = now.toISOString();
  const ist = new Date(now.getTime() + 5.5 * 3600_000);
  const startOf = (y: number, m: number, d: number) => new Date(Date.UTC(y, m, d) - 5.5 * 3600_000).toISOString();
  switch (period) {
    case "today": return { from: startOf(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()), to };
    case "7d": return { from: new Date(now.getTime() - 7 * 86_400_000).toISOString(), to };
    case "90d": return { from: new Date(now.getTime() - 90 * 86_400_000).toISOString(), to };
    case "month": return { from: startOf(ist.getUTCFullYear(), ist.getUTCMonth(), 1), to };
    case "quarter": return { from: startOf(ist.getUTCFullYear(), Math.floor(ist.getUTCMonth() / 3) * 3, 1), to };
    case "year": return { from: new Date(now.getTime() - 365 * 86_400_000).toISOString(), to };
    default: return { from: new Date(now.getTime() - 30 * 86_400_000).toISOString(), to };
  }
}

/**
 * Answers one question. deadline (epoch ms, by default 240 s from the call) is when Ask must be done with Claude: a turn
 * starts only with 45 s left, each request gets what is left minus 15 s, and with under 120 s left the turn is the last one.
 */
export async function ask(
  question: string, model: string, db: AskDb, messages: Messages, maxTurns = 6, deadline = Date.now() + 240_000,
): Promise<AskResult> {
  const usage: Usage = { in: 0, out: 0, cache_read: 0, cache_write: 0 };
  const outputs: unknown[] = [];
  const calls: { name: string; input: unknown }[] = [];
  // the sources are the queries that actually ran (not Claude's own list), de-duplicated, at most 10
  const ran: AskSource[] = [];
  const seen = new Set<string>();
  const tools = ASK_TOOLS.map((t, i) => (i === ASK_TOOLS.length - 1 ? { ...t, cache_control: { type: "ephemeral" } } : t));
  const system = [{ type: "text", text: ASK_SYSTEM, cache_control: { type: "ephemeral" } }];
  const msgs: { role: "user" | "assistant"; content: unknown }[] = [{ role: "user", content: `Today is ${new Date().toISOString().slice(0, 10)}. Question: ${question}` }];
  // Opus/Sonnet 4.6+ and 5.x take an effort level (low is enough for a lookup); Haiku 4.5 rejects it, so it gets none
  const effort = /^claude-(opus|sonnet)-(4-[6-9]|5)/.test(model) ? { output_config: { effort: "low" } } : {};
  try {
    for (let turn = 0; turn < maxTurns; turn++) {
      const left = deadline - Date.now();
      if (left < 45_000) throw new Error("stopped: out of time for this question");
      // the last turn, or too little time for another tool round: ask for the answer now. The note is appended to the
      // newest user message, which has not been sent yet; earlier messages, system and tools never change, so the cached
      // prefix and Claude's thinking blocks stay valid (append-only history)
      const last = turn === maxTurns - 1 || left < 120_000;
      if (last) {
        const note = { type: "text", text: LAST_TURN_NOTE };
        const tail = msgs[msgs.length - 1]!;
        if (tail.role !== "user") msgs.push({ role: "user", content: [note] });
        else tail.content = typeof tail.content === "string" ? [{ type: "text", text: tail.content }, note] : [...(tail.content as unknown[]), note];
      }
      // tool_choice stays auto (never forced); the top-level cache_control caches the growing conversation as well
      const res = await messages(
        { model, max_tokens: 8000, system, tools, messages: msgs, cache_control: { type: "ephemeral" }, ...effort },
        Math.min(180_000, left - 15_000),
      );
      usage.in += res.usage?.input_tokens ?? 0; usage.out += res.usage?.output_tokens ?? 0;
      usage.cache_read += res.usage?.cache_read_input_tokens ?? 0; usage.cache_write += res.usage?.cache_creation_input_tokens ?? 0;
      // a cut-off or declined turn ends the question; its usage is already counted, so the log records the spend
      if (res.stop_reason === "max_tokens") throw new Error("the answer was cut off (max_tokens); try a narrower question");
      if (res.stop_reason === "refusal") throw new Error("Claude declined this question");
      msgs.push({ role: "assistant", content: res.content });
      const uses = res.content.filter((b) => b.type === "tool_use");
      if (!uses.length) { msgs.push({ role: "user", content: "Call submit_answer now." }); continue; }
      const results: unknown[] = [];
      for (const u of uses) {
        const input = (u.input ?? {}) as Record<string, unknown>;
        calls.push({ name: u.name ?? "", input });
        if (u.name === "submit_answer") {
          const answer = typeof input.answer === "string" ? input.answer.trim().slice(0, 4000) : "";
          const validation = validateNumbers(answer, outputs);
          return { answer: answer || null, sources: ran, validation, usage, tool_calls: calls };
        }
        let out: unknown;
        try {
          if (u.name === "list_metrics") {
            const c = await db.catalogue();
            out = c.metrics.filter((m) => !input.area || m.area === input.area)
              .map((m) => ({ key: m.key, label: m.label, unit: m.unit, area: m.area, dims: m.dims.filter((d) => !AI_BLOCKED_DIMS.has(d)) }));
          } else if (u.name === "query_metric") {
            const filters = input.filters && typeof input.filters === "object" ? (input.filters as object) : {};
            const asked = [...(Array.isArray(input.dims) ? input.dims : input.dims == null ? [] : [input.dims]), ...Object.keys(filters)];
            if (asked.some((d) => AI_BLOCKED_DIMS.has(String(d)))) {
              out = { error: "that breakdown is not available to the assistant" };
            } else {
              // an unknown or missing period is the default 30 days (periodBounds' default branch), and is reported as such
              const period: Period = typeof input.period === "string" && (PERIODS as readonly string[]).includes(input.period) ? (input.period as Period) : "30d";
              const { from, to } = periodBounds(period);
              const result = await db.query({ metric: input.metric, dims: input.dims ?? [], filters: input.filters ?? {}, from, to, compare: "previous", limit: Math.min(Number(input.limit) || 20, 50) });
              // the period's label goes into the result, so Claude names the period that was queried (and its numbers count)
              out = { period_label: PERIOD_LABEL[period], ...(result && typeof result === "object" && !Array.isArray(result) ? (result as Record<string, unknown>) : { value: result }) };
              // the question's own numbers (period, limit) count as sources too
              outputs.push({ input, output: out });
              const src: AskSource = {
                metric: String(input.metric ?? ""),
                dims: Array.isArray(input.dims) ? input.dims.slice(0, 2).map(String) : [],
                filters: input.filters && typeof input.filters === "object" && !Array.isArray(input.filters)
                  ? Object.fromEntries(Object.entries(input.filters as Record<string, unknown>).filter(([, v]) => Array.isArray(v)).map(([k, v]) => [k, (v as unknown[]).map(String)]))
                  : {},
                period,
              };
              const key = JSON.stringify(src);
              if (ran.length < 10 && !seen.has(key)) { seen.add(key); ran.push(src); }
            }
          } else out = { error: `unknown tool ${u.name}` };
        } catch (e) {
          out = { error: e instanceof Error ? e.message : "query failed" };
        }
        const text = JSON.stringify(out);
        results.push({ type: "tool_result", tool_use_id: u.id, content: text.length > 20_000 ? text.slice(0, 20_000) + " …(truncated)" : text });
      }
      msgs.push({ role: "user", content: results });
    }
    return { answer: null, sources: [], validation: { ok: false, checked: 0, unverified: [] }, usage, tool_calls: calls, error: "no answer within the turn limit" };
  } catch (e) {
    return { answer: null, sources: [], validation: { ok: false, checked: 0, unverified: [] }, usage, tool_calls: calls, error: e instanceof Error ? e.message : "failed" };
  }
}
