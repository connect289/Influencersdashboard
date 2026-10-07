import type { Messages, Usage } from "./worker";
import { validateNumbers, type Validation } from "./validate";

/**
 * "Ask the CRM" (spec B7.8.2, B14.3): a natural-language question answered only through the metric layer's read-only
 * tools, never free SQL. The answer is shown only when every number in it came from a tool result, with its sources.
 */

export const ASK_PROMPT_VERSION = "ask-2026-10-07.1";

export const ASK_SYSTEM = `You answer questions about Eduwit's B2B partner CRM (student leads routed to partner companies that sell
online and distance degree programmes; Eduwit earns commission on enrolments). You can only read data through the tools:
list_metrics shows what can be measured and how it can be broken down; query_metric returns a metric's value for a period
with optional breakdowns and filters, and the previous period's value. There is no personal data (no names, phones or e-mails).

Rules:
- Every number in your answer must appear in a tool result of this conversation (rounding is fine). Do not compute new
  numbers yourself; if a ratio or difference is needed, look for a metric that gives it or say you cannot compute it.
- Say which period you used. Use Indian formatting for rupees.
- If the data cannot answer the question, say so plainly and suggest the closest thing it can answer.
- Finish by calling submit_answer once, with a short answer (a few sentences or a short list) and the queries it rests on.`;

const PERIOD_ENUM = ["today", "7d", "30d", "90d", "month", "quarter", "year"];

export const ASK_TOOLS = [
  { name: "list_metrics", description: "Every metric: key, label, unit, area and the breakdowns it supports.", input_schema: { type: "object", properties: { area: { type: "string" } }, additionalProperties: false } },
  { name: "query_metric", description: "A metric's value over a period, optionally broken down (up to 2 breakdowns) and filtered, with the previous period.",
    input_schema: { type: "object", properties: {
      metric: { type: "string" }, dims: { type: "array", items: { type: "string" }, maxItems: 2 },
      filters: { type: "object", additionalProperties: { type: "array", items: { type: "string" } } },
      period: { type: "string", enum: PERIOD_ENUM }, limit: { type: "integer", minimum: 1, maximum: 50 },
    }, required: ["metric"], additionalProperties: false } },
  { name: "submit_answer", description: "Your final answer. Call once.", input_schema: { type: "object", properties: {
      answer: { type: "string" },
      sources: { type: "array", items: { type: "object", properties: { metric: { type: "string" }, dims: { type: "array", items: { type: "string" } }, filters: { type: "object" }, period: { type: "string" } } } },
    }, required: ["answer"] } },
];

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

export async function ask(question: string, model: string, db: AskDb, messages: Messages, maxTurns = 6): Promise<AskResult> {
  const usage: Usage = { in: 0, out: 0, cache_read: 0, cache_write: 0 };
  const outputs: unknown[] = [];
  const calls: { name: string; input: unknown }[] = [];
  const tools = ASK_TOOLS.map((t, i) => (i === ASK_TOOLS.length - 1 ? { ...t, cache_control: { type: "ephemeral" } } : t));
  const msgs: { role: "user" | "assistant"; content: unknown }[] = [{ role: "user", content: `Today is ${new Date().toISOString().slice(0, 10)}. Question: ${question}` }];
  try {
    for (let turn = 0; turn < maxTurns; turn++) {
      const res = await messages({ model, max_tokens: 1500, system: [{ type: "text", text: ASK_SYSTEM, cache_control: { type: "ephemeral" } }], tools, messages: msgs,
                                   ...(turn === maxTurns - 1 ? { tool_choice: { type: "tool", name: "submit_answer" } } : {}) });
      usage.in += res.usage?.input_tokens ?? 0; usage.out += res.usage?.output_tokens ?? 0;
      usage.cache_read += res.usage?.cache_read_input_tokens ?? 0; usage.cache_write += res.usage?.cache_creation_input_tokens ?? 0;
      msgs.push({ role: "assistant", content: res.content });
      const uses = res.content.filter((b) => b.type === "tool_use");
      if (!uses.length) { msgs.push({ role: "user", content: "Call submit_answer now." }); continue; }
      const results: unknown[] = [];
      for (const u of uses) {
        const input = (u.input ?? {}) as Record<string, unknown>;
        calls.push({ name: u.name ?? "", input });
        if (u.name === "submit_answer") {
          const answer = typeof input.answer === "string" ? input.answer.trim().slice(0, 4000) : "";
          const sources = Array.isArray(input.sources) ? (input.sources as AskSource[]).slice(0, 10) : [];
          const validation = validateNumbers(answer, outputs);
          return { answer: answer || null, sources, validation, usage, tool_calls: calls };
        }
        let out: unknown;
        try {
          if (u.name === "list_metrics") {
            const c = await db.catalogue();
            out = c.metrics.filter((m) => !input.area || m.area === input.area).map((m) => ({ key: m.key, label: m.label, unit: m.unit, area: m.area, dims: m.dims }));
          } else if (u.name === "query_metric") {
            const { from, to } = periodBounds(typeof input.period === "string" ? input.period : undefined);
            out = await db.query({ metric: input.metric, dims: input.dims ?? [], filters: input.filters ?? {}, from, to, compare: "previous", limit: Math.min(Number(input.limit) || 20, 50) });
            // the question's own numbers (period, limit) count as sources too
            outputs.push({ input, output: out });
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
