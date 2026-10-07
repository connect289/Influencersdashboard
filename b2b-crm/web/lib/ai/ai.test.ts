import { describe, expect, it, vi } from "vitest";
import { normaliseReport, reportText, systemPrompt, SUBMIT_TOOL, DATA_TOOLS } from "./prompts";
import { collectNumbers, extractNumbers, matches, validateNumbers } from "./validate";
import { costUsd, runOnce, type Db, type Messages } from "./worker";

describe("number validator", () => {
  it("extracts numbers as written and skips dates, ids and segment keys", () => {
    const xs = extractNumbers("Partner A: 14.5% of 1,240 leads, ₹2,300 NCPL on 2026-10-07 (run #12, v3, L-ab12cd34) in mba|PG|Online");
    expect(xs.map((x) => x.text)).toEqual(["14.5%", "1,240", "₹2,300"]);
    expect(xs[0]).toMatchObject({ value: 14.5, decimals: 1, percent: true });
    expect(xs[2]!.value).toBe(2300);
  });

  it("matches rounding and percentages of fractions", () => {
    expect(matches({ text: "14.5%", value: 14.5, decimals: 1, percent: true }, 0.14474)).toBe(true);
    expect(matches({ text: "14%", value: 14, decimals: 0, percent: true }, 0.14474)).toBe(true);
    expect(matches({ text: "2,300", value: 2300, decimals: 0, percent: false }, 2299.6)).toBe(true);
    expect(matches({ text: "2,310", value: 2310, decimals: 0, percent: false }, 2299.6)).toBe(false);
  });

  it("collects numbers from nested tool outputs, including numeric strings", () => {
    expect(collectNumbers({ a: [1, { b: "2.5" }], c: "won 62% of draws", d: null }).sort()).toEqual([1, 2.5, 62]);
  });

  it("rejects numbers no tool returned, allows proposed values", () => {
    const tools = [{ segments: [{ segment: "mba|PG|Online", avg_enrolment_rate: 0.0612, matured: 41 }] }, { ncpl_now: 1830.5, ncpl_new: 1904.2 }];
    const ok = validateNumbers("MBA converts at 6.1% over 41 matured leads; NCPL would move from ₹1,831 to ₹1,904. Set exploration to 25%.", tools, [{ value: 0.25 }]);
    expect(ok).toEqual({ ok: true, checked: 5, unverified: [] });
    const bad = validateNumbers("NCPL would rise by 74 rupees, about 4%.", tools);
    expect(bad.ok).toBe(false);
    expect(bad.unverified).toEqual(["74", "4%"]);
  });
});

describe("prompts", () => {
  it("never offers write tools and states the number rule", () => {
    expect(DATA_TOOLS.map((t) => t.name)).not.toContain("submit_report");
    expect(DATA_TOOLS.every((t) => !/save|update|delete|apply/.test(t.name))).toBe(true);
    expect(systemPrompt("optimise")).toContain("Every number you write must come from a tool result");
    expect(SUBMIT_TOOL.input_schema.required).toEqual(["summary", "findings", "recommendations"]);
  });

  it("normalises a report and drops incomplete items", () => {
    const r = normaliseReport({ summary: " ok ", findings: [{ title: "t", detail: "d" }, { title: "" }], recommendations: [{ title: "x" }, { title: "y", rationale: "z", change: { lever: "exploration_share" } }] });
    expect(r).toMatchObject({ summary: "ok", findings: [{ title: "t", detail: "d" }], recommendations: [{ title: "y", rationale: "z", change: { lever: "exploration_share" } }] });
    expect(normaliseReport({ findings: [] })).toBeNull();
    expect(reportText(r!)).toBe("ok\nt\nd\ny\nz\n");
  });
});

function fakeDb(over: Partial<Db> = {}): Db & { finished: Record<string, unknown>[]; failed: string[]; tools: string[] } {
  const finished: Record<string, unknown>[] = [];
  const failed: string[] = [];
  const tools: string[] = [];
  return {
    finished, failed, tools,
    claim: vi.fn(async () => ({ run: { id: 7, kind: "optimise" as const, trigger: "manual", model: "claude-sonnet-5-5", context: {} },
                                limits: { max_turns: 4, max_tokens: 1000, budget_left_usd: 1 }, price_per_mtok: { in: 3, out: 15 } })),
    tool: vi.fn(async (_id: number, name: string) => { tools.push(name); return { call_no: tools.length, output: { segments: [{ segment: "mba|PG|Online", matured: 41, avg_enrolment_rate: 0.0612 }] } }; }),
    finish: vi.fn(async (_id: number, body: Record<string, unknown>) => { finished.push(body); return { status: "done" }; }),
    fail: vi.fn(async (_id: number, e: string) => { failed.push(e); return {}; }),
    ...over,
  };
}

const usage = { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 500, cache_creation_input_tokens: 0 };

describe("worker loop", () => {
  it("calls tools, then files a validated report", async () => {
    const db = fakeDb();
    const replies = [
      { stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "a", name: "segment_scorecards", input: {} }] },
      { stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "b", name: "submit_report", input: {
        summary: "MBA has 41 matured leads at 6.1%.", findings: [{ title: "MBA", detail: "6.1% enrol." }], recommendations: [] } }] },
    ];
    const messages: Messages = vi.fn(async () => replies.shift()!);
    const r = await runOnce(db, messages);
    expect(r).toMatchObject({ run: 7, status: "done" });
    expect(db.tools).toEqual(["segment_scorecards"]);
    const body = db.finished[0]!;
    expect(body.validation).toEqual({ ok: true, checked: 3, unverified: [] });
    expect(body.usage).toEqual({ in: 2000, out: 400, cache_read: 1000, cache_write: 0 });
    // the system prompt and the tool list are cached
    const first = (messages as unknown as { mock: { calls: [Record<string, unknown>][] } }).mock.calls[0]![0];
    expect((first.system as { cache_control?: unknown }[])[0]!.cache_control).toEqual({ type: "ephemeral" });
    expect((first.tools as { cache_control?: unknown }[]).at(-1)!.cache_control).toEqual({ type: "ephemeral" });
  });

  it("marks a report with invented numbers rejected", async () => {
    const db = fakeDb();
    const replies = [{ stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "b", name: "submit_report", input: {
      summary: "Uplift is 12%.", findings: [], recommendations: [] } }] }];
    const r = await runOnce(db, vi.fn(async () => replies.shift()!));
    expect(r.status).toBe("rejected");
    expect((db.finished[0]!.validation as { unverified: string[] }).unverified).toEqual(["12%"]);
  });

  it("forces submit_report on the last turn and fails cleanly on API errors", async () => {
    const db = fakeDb();
    const messages: Messages = vi.fn(async (body) => {
      if (body.tool_choice) return { stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "z", name: "submit_report", input: { summary: "Nothing to change.", findings: [], recommendations: [] } }] };
      return { stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "a", name: "alerts", input: {} }] };
    });
    expect((await runOnce(db, messages)).status).toBe("done");
    expect(db.tools).toHaveLength(3);

    const db2 = fakeDb();
    const r = await runOnce(db2, vi.fn(async () => { throw new Error("Anthropic API: overloaded"); }));
    expect(r.status).toBe("failed");
    expect(db2.failed).toEqual(["Anthropic API: overloaded"]);
  });

  it("refuses unknown tools and stops at the budget", async () => {
    const db = fakeDb({ claim: vi.fn(async () => ({ run: { id: 8, kind: "light_check" as const, trigger: "light", model: "m", context: {} },
                                                      limits: { max_turns: 5, max_tokens: 500, budget_left_usd: 0.001 }, price_per_mtok: { in: 3, out: 15 } })) });
    const messages: Messages = vi.fn(async () => ({ stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "x", name: "drop_tables", input: {} }] }));
    const r = await runOnce(db, messages);
    expect(r.status).toBe("failed");
    expect(db.failed[0]).toContain("daily budget");
    expect(db.tools).toEqual([]);
  });

  it("does nothing when nothing is queued", async () => {
    const db = fakeDb({ claim: vi.fn(async () => ({ run: null, why: "the optimiser is off" })) });
    expect(await runOnce(db, vi.fn())).toEqual({ run: null, status: "the optimiser is off" });
  });

  it("prices usage", () => {
    expect(costUsd({ in: 1_000_000, out: 100_000, cache_read: 1_000_000, cache_write: 0 }, { in: 3, out: 15, cache_read: 0.3 })).toBeCloseTo(4.8);
  });
});
