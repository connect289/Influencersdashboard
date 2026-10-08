import { afterEach, describe, expect, it, vi } from "vitest";
import { ask, ASK_PROMPT_VERSION, ASK_SYSTEM, ASK_TOOLS, periodBounds, type AskDb } from "./ask";
import type { Messages } from "./worker";

type Reply = Awaited<ReturnType<Messages>>;
type Body = Record<string, unknown> & { messages: { role: string; content: unknown }[]; system: unknown[]; tools: Record<string, unknown>[] };

const use = (id: string, name: string, input: unknown, usage?: Reply["usage"]): Reply =>
  ({ stop_reason: "tool_use", content: [{ type: "tool_use", id, name, input }], ...(usage ? { usage } : {}) });
const answer = (id: string, text: string, extra: Record<string, unknown> = {}): Reply => use(id, "submit_answer", { answer: text, ...extra });

/** A scripted Messages: replies in order; every body is copied as it was sent (msgs keeps growing after the call). */
function script(replies: Reply[], onCall?: (n: number) => void) {
  const bodies: Body[] = [];
  const timeouts: (number | undefined)[] = [];
  const fn = vi.fn(async (body: Record<string, unknown>, timeoutMs?: number): Promise<Reply> => {
    bodies.push(JSON.parse(JSON.stringify(body)) as Body);
    timeouts.push(timeoutMs);
    onCall?.(bodies.length);
    const r = replies.shift();
    if (!r) throw new Error("the script ran out of replies");
    return r;
  });
  return { fn, bodies, timeouts };
}

/** The tool_result blocks of the newest user message of a body (what Claude got back from the previous turn). */
const lastResults = (b: Body) => (b.messages[b.messages.length - 1]!.content as { type: string; content?: string }[]).filter((x) => x.type === "tool_result");
const lastBlocks = (b: Body) => b.messages[b.messages.length - 1]!.content as { type: string; text?: string }[];

const METRICS = [
  { key: "first_attempt_median", label: "First attempt (median)", unit: "minutes", area: "Partners", dims: ["partner", "counsellor"], description: null },
  { key: "leads", label: "Leads", unit: "count", area: "Intake", dims: ["source", "partner"], description: null },
];
function fakeDb(query: AskDb["query"] = async () => ({ total: { value: 42, prev: 30 }, rows: [] })) {
  const q = vi.fn(query);
  const db: AskDb = { catalogue: async () => ({ metrics: METRICS }), query: q };
  return { db, query: q };
}

afterEach(() => { vi.useRealTimers(); });

describe("ask: counsellor names never reach Claude (C33)", () => {
  it("drops counsellor from list_metrics and refuses a counsellor breakdown without querying", async () => {
    const { db, query } = fakeDb();
    const s = script([
      use("1", "list_metrics", {}),
      use("2", "query_metric", { metric: "first_attempt_median", dims: ["counsellor"] }),
      answer("3", "That breakdown is not available."),
    ]);
    const r = await ask("Which counsellors are slowest?", "claude-sonnet-5-5", db, s.fn);
    expect(s.fn).toHaveBeenCalledTimes(3);
    const listed = lastResults(s.bodies[1]!)[0]!.content!;
    expect(listed).not.toContain("counsellor");
    expect(JSON.parse(listed)).toEqual([
      { key: "first_attempt_median", label: "First attempt (median)", unit: "minutes", area: "Partners", dims: ["partner"] },
      { key: "leads", label: "Leads", unit: "count", area: "Intake", dims: ["source", "partner"] },
    ]);
    expect(query).not.toHaveBeenCalled();
    expect(lastResults(s.bodies[2]!)[0]!.content).toContain("not available to the assistant");
    expect(r.answer).toBe("That breakdown is not available.");
    expect(r.sources).toEqual([]);
  });

  it("refuses a counsellor filter the same way", async () => {
    const { db, query } = fakeDb();
    const s = script([use("1", "query_metric", { metric: "first_attempt_median", dims: ["partner"], filters: { counsellor: ["X"] } }), answer("2", "Not available.")]);
    const r = await ask("How fast is X?", "claude-sonnet-5-5", db, s.fn);
    expect(query).not.toHaveBeenCalled();
    expect(lastResults(s.bodies[1]!)[0]!.content).toContain("not available to the assistant");
    expect(r.sources).toEqual([]);
  });

  it("refuses counsellor sent as a bare string instead of a list", async () => {
    const { db, query } = fakeDb();
    const s = script([use("1", "query_metric", { metric: "first_attempt_median", dims: "counsellor" }), answer("2", "Not available.")]);
    await ask("Which counsellors?", "claude-sonnet-5-5", db, s.fn);
    expect(query).not.toHaveBeenCalled();
    expect(lastResults(s.bodies[1]!)[0]!.content).toContain("not available to the assistant");
  });

  it("still queries other breakdowns", async () => {
    const { db, query } = fakeDb();
    const s = script([use("1", "query_metric", { metric: "first_attempt_median", dims: ["partner"] }), answer("2", "42 minutes, up from 30.")]);
    const r = await ask("How fast do partners call?", "claude-sonnet-5-5", db, s.fn);
    expect(query).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledWith(expect.objectContaining({ metric: "first_attempt_median", dims: ["partner"] }));
    expect(r.validation.ok).toBe(true);
  });
});

describe("ask: stop reasons and effort (C39)", () => {
  it("fails a turn cut off at max_tokens, keeps its usage and runs none of its tools", async () => {
    const { db, query } = fakeDb();
    const s = script([{ stop_reason: "max_tokens", usage: { input_tokens: 1000, output_tokens: 8000 },
      content: [{ type: "tool_use", id: "1", name: "query_metric", input: { metric: "leads" } }] }]);
    const r = await ask("How many leads?", "claude-sonnet-5-5", db, s.fn);
    expect(r.answer).toBeNull();
    expect(r.error).toContain("cut off");
    expect(r.usage).toEqual({ in: 1000, out: 8000, cache_read: 0, cache_write: 0 });
    expect(query).not.toHaveBeenCalled();
    expect(r.tool_calls).toEqual([]);
  });

  it("fails a declined question", async () => {
    const { db } = fakeDb();
    const s = script([{ stop_reason: "refusal", content: [] }]);
    const r = await ask("How many leads?", "claude-sonnet-5-5", db, s.fn);
    expect(r.answer).toBeNull();
    expect(r.error).toContain("declined");
  });

  it("asks 5.x and 4.6+ Sonnet/Opus for low effort, with room for thinking; Haiku gets no effort", async () => {
    for (const model of ["claude-sonnet-5-5", "claude-opus-5-5", "claude-sonnet-4-6"]) {
      const s = script([answer("1", "No numbers here.")]);
      await ask("Hello there?", model, fakeDb().db, s.fn);
      expect(s.bodies[0]!.output_config).toEqual({ effort: "low" });
      expect(s.bodies[0]!.max_tokens).toBe(8000);
    }
    const h = script([answer("1", "No numbers here.")]);
    await ask("Hello there?", "claude-haiku-4-5-20251001", fakeDb().db, h.fn);
    expect(h.bodies[0]).not.toHaveProperty("output_config");
    expect(h.bodies[0]!.max_tokens).toBe(8000);
  });
});

describe("ask: sources are the queries that ran (C98)", () => {
  it("(a) ignores Claude's own source list", async () => {
    const { db } = fakeDb();
    const s = script([
      use("1", "query_metric", { metric: "leads", dims: ["source"], period: "month" }),
      answer("2", "42 leads this month.", { sources: [{ metric: "allocations", dims: "partner", period: "30d" }] }),
    ]);
    const r = await ask("Leads by source this month?", "claude-sonnet-5-5", db, s.fn);
    expect(r.sources).toEqual([{ metric: "leads", dims: ["source"], filters: {}, period: "month" }]);
  });

  it("(b) leaves out a query that failed", async () => {
    const { db, query } = fakeDb(async (p) => {
      if (p.metric === "nope") throw new Error("unknown metric nope");
      return { total: { value: 42, prev: 30 }, rows: [] };
    });
    const s = script([
      use("1", "query_metric", { metric: "nope", period: "7d" }),
      use("2", "query_metric", { metric: "leads", period: "7d" }),
      answer("3", "42 leads in the last 7 days."),
    ]);
    const r = await ask("Leads this week?", "claude-sonnet-5-5", db, s.fn);
    expect(query).toHaveBeenCalledTimes(2);
    expect(lastResults(s.bodies[1]!)[0]!.content).toContain("unknown metric nope");
    expect(r.sources).toEqual([{ metric: "leads", dims: [], filters: {}, period: "7d" }]);
  });

  it("(c) lists a query run twice once", async () => {
    const { db, query } = fakeDb();
    const s = script([
      use("1", "query_metric", { metric: "leads", dims: ["source"], period: "7d" }),
      use("2", "query_metric", { metric: "leads", dims: ["source"], period: "7d" }),
      answer("3", "42 leads."),
    ]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn);
    expect(query).toHaveBeenCalledTimes(2);
    expect(r.sources).toEqual([{ metric: "leads", dims: ["source"], filters: {}, period: "7d" }]);
  });

  it("shape-checks a source and keeps at most 10", async () => {
    const { db } = fakeDb();
    const many = Array.from({ length: 12 }, (_, i) => ({ type: "tool_use", id: `q${i}`, name: "query_metric", input: { metric: `m${i}` } }));
    const s = script([
      use("1", "query_metric", { metric: "leads", dims: ["source", "partner", "city"], filters: { partner: ["4", 5], bad: "x" }, period: "90d" }),
      { stop_reason: "tool_use", content: many },
      answer("3", "42 leads."),
    ]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn);
    expect(r.sources[0]).toEqual({ metric: "leads", dims: ["source", "partner"], filters: { partner: ["4", "5"] }, period: "90d" });
    expect(r.sources).toHaveLength(10);
  });
});

describe("ask: periods are named as queried (C99)", () => {
  it("puts the period's label into the tool result", async () => {
    const { db } = fakeDb(async () => ({ total: { value: 412, prev: 380 }, rows: [] }));
    const s = script([use("1", "query_metric", { metric: "leads", period: "year" }), answer("2", "412 enrolments in the last 12 months.")]);
    const r = await ask("Enrolments this year?", "claude-sonnet-5-5", db, s.fn);
    expect(lastResults(s.bodies[1]!)[0]!.content).toContain('"period_label":"Last 12 months"');
    expect(r.validation).toEqual({ ok: true, checked: 2, unverified: [] });
    expect(r.answer).toBe("412 enrolments in the last 12 months.");
  });

  it("does not accept a period that was not queried", async () => {
    const { db } = fakeDb(async () => ({ total: { value: 412, prev: 380 }, rows: [] }));
    const s = script([use("1", "query_metric", { metric: "leads", period: "30d" }), answer("2", "412 enrolments in the last 12 months.")]);
    const r = await ask("Enrolments this year?", "claude-sonnet-5-5", db, s.fn);
    expect(r.validation).toMatchObject({ ok: false, unverified: ["12"] });
  });

  it("queries an unknown period with the 30-day bounds and reports it as 30d", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-07T04:00:00Z"));
    const bounds = periodBounds("30d");
    expect(bounds).toEqual(periodBounds(undefined));
    for (const period of ["decade", "constructor"]) {
      const { db, query } = fakeDb();
      const s = script([use("1", "query_metric", { metric: "leads", period }), answer("2", "42 leads in the last 30 days.")]);
      const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn);
      expect(query).toHaveBeenCalledWith(expect.objectContaining({ from: bounds.from, to: bounds.to }));
      expect(r.sources).toEqual([{ metric: "leads", dims: [], filters: {}, period: "30d" }]);
      expect(lastResults(s.bodies[1]!)[0]!.content).toContain('"period_label":"Last 30 days"');
      expect(r.validation.ok).toBe(true);
    }
  });

  it("describes the periods to Claude", () => {
    const q = ASK_TOOLS.find((t) => t.name === "query_metric")!;
    const period = (q.input_schema.properties as unknown as Record<string, { enum?: string[]; description?: string }>).period!;
    expect(period.enum).toEqual(["today", "7d", "30d", "90d", "month", "quarter", "year"]);
    expect(period.description).toContain("last 12 months");
    expect(ASK_SYSTEM).toContain("period_label");
    expect(ASK_PROMPT_VERSION).toBe("ask-2026-10-07.2");
  });
});

describe("ask: caching and the last turn (C101, F4/F7)", () => {
  it("caches every request and only ever appends to the conversation", async () => {
    const { db } = fakeDb();
    const s = script([
      use("1", "list_metrics", {}),
      use("2", "query_metric", { metric: "leads", period: "7d" }),
      { stop_reason: "end_turn", content: [{ type: "text", text: "Thinking it over." }] },
      answer("4", "42 leads in the last 7 days."),
    ]);
    const r = await ask("Leads this week?", "claude-sonnet-5-5", db, s.fn);
    expect(r.answer).toBe("42 leads in the last 7 days.");
    expect(s.bodies).toHaveLength(4);
    for (const b of s.bodies) {
      expect(b.cache_control).toEqual({ type: "ephemeral" });
      expect(JSON.stringify(b).split('"cache_control"').length - 1).toBeLessThanOrEqual(4);
      expect(b).not.toHaveProperty("tool_choice");
    }
    for (let i = 1; i < s.bodies.length; i++) {
      const prev = s.bodies[i - 1]!, next = s.bodies[i]!;
      expect(JSON.stringify(next.messages.slice(0, prev.messages.length))).toBe(JSON.stringify(prev.messages));
      expect(JSON.stringify(next.system)).toBe(JSON.stringify(prev.system));
      expect(JSON.stringify(next.tools)).toBe(JSON.stringify(prev.tools));
    }
  });

  it("asks for the answer on the last turn with a note after the tool results, never a forced tool_choice", async () => {
    const { db } = fakeDb();
    const s = script([
      use("1", "query_metric", { metric: "leads", period: "7d" }),
      use("2", "query_metric", { metric: "leads", period: "30d" }),
      answer("3", "42 leads in the last 7 days."),
    ]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn, 3);
    expect(r.answer).toBe("42 leads in the last 7 days.");
    const note = (b: Body) => JSON.stringify(b.messages).includes("This is your last turn");
    expect(note(s.bodies[0]!)).toBe(false);
    expect(note(s.bodies[1]!)).toBe(false);
    const tail = lastBlocks(s.bodies[2]!);
    expect(tail.map((x) => x.type)).toEqual(["tool_result", "text"]);
    expect(tail[1]!.text).toBe("This is your last turn. Call submit_answer now with what you have.");
    for (const b of s.bodies) expect(b).not.toHaveProperty("tool_choice");
  });

  it("gives up after the last turn when Claude still does not answer", async () => {
    const { db } = fakeDb();
    const s = script([use("1", "query_metric", { metric: "leads" }), use("2", "query_metric", { metric: "leads" })]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn, 2);
    expect(r).toMatchObject({ answer: null, sources: [], error: "no answer within the turn limit" });
    // the second (last) turn carried the note, never a forced tool_choice (C3)
    expect(s.bodies).toHaveLength(2);
    expect(JSON.stringify(s.bodies[1]!.messages)).toContain("This is your last turn");
    for (const b of s.bodies) expect(b).not.toHaveProperty("tool_choice");
  });

  it("keeps a submit_answer that arrives together with a query, and runs no later tool", async () => {
    const { db, query } = fakeDb();
    const s = script([{ stop_reason: "tool_use", content: [
      { type: "tool_use", id: "1", name: "query_metric", input: { metric: "leads", period: "7d" } },
      { type: "tool_use", id: "2", name: "submit_answer", input: { answer: "42 leads in the last 7 days." } },
    ] }]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn, 3);
    expect(query).toHaveBeenCalledTimes(1);
    expect(r.answer).toBe("42 leads in the last 7 days.");
    expect(r.validation.ok).toBe(true);
    expect(r.sources).toEqual([{ metric: "leads", dims: [], filters: {}, period: "7d" }]);
  });
});

describe("ask: deadline", () => {
  it("does not start a turn with under 45 s left", async () => {
    const { db } = fakeDb();
    const s = script([answer("1", "x")]);
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn, 6, Date.now() + 20_000);
    expect(s.fn).not.toHaveBeenCalled();
    expect(r.answer).toBeNull();
    expect(r.error).toContain("out of time");
  });

  it("bounds each request by the time left and makes a short-on-time turn the last one", async () => {
    const { db } = fakeDb();
    const s = script([answer("1", "No numbers here.")]);
    await ask("Leads?", "claude-sonnet-5-5", db, s.fn, 6, Date.now() + 100_000);
    expect(s.timeouts[0]).toBeLessThanOrEqual(85_000);
    expect(s.timeouts[0]).toBeGreaterThan(80_000);
    // the first message is a plain string until the note is added; then it is the question's text plus the note
    expect(lastBlocks(s.bodies[0]!).map((x) => x.type)).toEqual(["text", "text"]);
    expect(lastBlocks(s.bodies[0]!)[0]!.text).toContain("Question: Leads?");
    expect(lastBlocks(s.bodies[0]!)[1]!.text).toContain("This is your last turn");
    expect(s.bodies[0]).not.toHaveProperty("tool_choice");
  });

  it("uses 240 s by default and records the usage of the turns before it ran out of time", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    const { db } = fakeDb();
    const clock = [100_000, 130_000, 230_000];
    const s = script([
      use("1", "query_metric", { metric: "leads" }, { input_tokens: 1000, output_tokens: 100 }),
      use("2", "query_metric", { metric: "leads", period: "7d" }, { input_tokens: 500, output_tokens: 50, cache_read_input_tokens: 900 }),
      use("3", "query_metric", { metric: "leads", period: "90d" }),
    ], (n) => vi.setSystemTime(clock[n - 1]!));
    const r = await ask("Leads?", "claude-sonnet-5-5", db, s.fn);
    // 240 s left: 180 s cap; 140 s left: 125 s and not yet the last turn; 110 s left: 95 s and the last turn
    expect(s.timeouts).toEqual([180_000, 125_000, 95_000]);
    expect(JSON.stringify(s.bodies[1]!.messages)).not.toContain("This is your last turn");
    expect(JSON.stringify(s.bodies[2]!.messages)).toContain("This is your last turn");
    // 10 s left after the third call: no fourth turn
    expect(s.fn).toHaveBeenCalledTimes(3);
    expect(r.error).toContain("out of time");
    expect(r.usage).toEqual({ in: 1500, out: 150, cache_read: 900, cache_write: 0 });
  });
});
