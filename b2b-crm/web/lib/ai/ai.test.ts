import { describe, expect, it, vi } from "vitest";
import { normaliseReport, reportText, systemPrompt, SUBMIT_TOOL, DATA_TOOLS } from "./prompts";
import { collectNumbers, extractNumbers, matches, validateNumbers } from "./validate";
import { anthropicMessages, costUsd, runOnce, type Db, type Messages } from "./worker";

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

  it("normalises a report's evidence to {tool, metric, scalar value}", () => {
    const r = normaliseReport({
      summary: "s",
      findings: [{ title: "t", detail: "d", evidence: [{ tool: "scorecards", metric: { a: 1 }, value: { b: 2 } }, "str", { metric: "leads", value: 5 }] }],
      recommendations: [{ title: "x", rationale: "y", evidence: [{ tool: "a".repeat(100), metric: " p_hat ", value: true }, null, [1, 2], { value: [3] }] }],
    });
    expect(r!.findings[0]!.evidence).toEqual([{ tool: "scorecards" }, { metric: "leads", value: 5 }]);
    expect(r!.recommendations[0]!.evidence).toEqual([{ tool: "a".repeat(60), metric: "p_hat", value: true }, {}]);
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

type Reply = Awaited<ReturnType<Messages>>;
const toolUse = (name: string, input: Record<string, unknown> = {}): Reply => ({ stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "a", name, input }] });
const submit = (input: Record<string, unknown>): Reply => ({ stop_reason: "tool_use", usage, content: [{ type: "tool_use", id: "s", name: "submit_report", input }] });
const nothing = { summary: "Nothing to change.", findings: [], recommendations: [] };

/** A fake Messages that keeps a deep copy of every request body (the worker keeps appending to the same array) and its timeout. */
function recorder(reply: (body: Record<string, unknown>, n: number) => Reply) {
  const bodies: Record<string, unknown>[] = [];
  const timeouts: (number | undefined)[] = [];
  const messages: Messages = vi.fn(async (body, timeoutMs) => {
    bodies.push(JSON.parse(JSON.stringify(body)) as Record<string, unknown>);
    timeouts.push(timeoutMs);
    return reply(body, bodies.length);
  });
  return { messages, bodies, timeouts };
}

type Msg = { role: string; content: unknown };
/** The last-turn note at the end of a request's newest user message, or null. */
function noteOf(body: Record<string, unknown>): string | null {
  const tail = (body.messages as Msg[]).at(-1)!;
  if (tail.role !== "user" || !Array.isArray(tail.content)) return null;
  const b = tail.content.at(-1) as { type?: string; text?: string } | undefined;
  return b?.type === "text" && /last turn/i.test(b.text ?? "") ? b.text! : null;
}
const notesIn = (body: Record<string, unknown>) => JSON.stringify(body.messages).split("This is your last turn.").length - 1;
const validationOf = (db: ReturnType<typeof fakeDb>) => db.finished[0]!.validation as { ok: boolean; checked: number; unverified: string[] };

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

  it("asks for submit_report on the last turn without forcing tool_choice, and fails cleanly on API errors", async () => {
    const db = fakeDb();
    const { messages, bodies } = recorder((body) => (noteOf(body) ? submit(nothing) : toolUse("alerts")));
    expect((await runOnce(db, messages)).status).toBe("done");
    expect(db.tools).toHaveLength(3);
    expect(bodies).toHaveLength(4);
    expect(bodies.every((b) => !("tool_choice" in b))).toBe(true);
    expect(bodies.map(noteOf)).toEqual([null, null, null, "This is your last turn. Call submit_report now with what you have."]);
    // the note follows the tool results in the newest user message
    expect(((bodies[3]!.messages as Msg[]).at(-1)!.content as { type: string }[]).map((b) => b.type)).toEqual(["tool_result", "text"]);

    // a Claude that never submits fails the run after the last turn
    const db1 = fakeDb();
    const never: Messages = vi.fn(async () => toolUse("alerts"));
    const r1 = await runOnce(db1, never);
    expect(r1.status).toBe("failed");
    expect(db1.failed).toEqual(["no report within the turn limit"]);
    expect((never as unknown as { mock: { calls: [Record<string, unknown>][] } }).mock.calls.every(([b]) => !("tool_choice" in b))).toBe(true);

    const db2 = fakeDb();
    const r = await runOnce(db2, vi.fn(async () => { throw new Error("Anthropic API: overloaded"); }));
    expect(r.status).toBe("failed");
    expect(db2.failed).toEqual(["Anthropic API: overloaded"]);
  });

  it("keeps the history append-only and at most 4 cache markers per request", async () => {
    const db = fakeDb();
    const { messages, bodies } = recorder((body) => (noteOf(body) ? submit(nothing) : toolUse("alerts")));
    expect((await runOnce(db, messages)).status).toBe("done");
    expect(bodies).toHaveLength(4);
    const markers = (v: unknown): number =>
      Array.isArray(v) ? v.reduce((n: number, x) => n + markers(x), 0)
        : v && typeof v === "object" ? Object.entries(v).reduce((n: number, [k, x]) => n + (k === "cache_control" ? 1 : 0) + markers(x), 0) : 0;
    for (const b of bodies) {
      expect(b.cache_control).toEqual({ type: "ephemeral" });
      expect(markers(b)).toBeLessThanOrEqual(4);
      expect(b.output_config).toEqual({ effort: "medium" });
    }
    for (let i = 1; i < bodies.length; i++) {
      const prev = bodies[i - 1]!, next = bodies[i]!;
      const sent = prev.messages as Msg[];
      expect((next.messages as Msg[]).length).toBeGreaterThan(sent.length);
      expect(JSON.stringify((next.messages as Msg[]).slice(0, sent.length))).toBe(JSON.stringify(sent));
      expect(JSON.stringify(next.system)).toBe(JSON.stringify(prev.system));
      expect(JSON.stringify(next.tools)).toBe(JSON.stringify(prev.tools));
    }
  });

  it("stops before a turn when out of time", async () => {
    const db = fakeDb();
    const messages: Messages = vi.fn();
    const r = await runOnce(db, messages, {}, Date.now() + 20_000);
    expect(messages).not.toHaveBeenCalled();
    expect(db.fail).toHaveBeenCalledTimes(1);
    expect(db.failed[0]).toContain("ran out of time");
    expect(r.status).toBe("failed");
  });

  it("per-turn timeout stays inside the deadline and asks for the report when time is short", async () => {
    const db = fakeDb();
    // under 120 s left: every turn is a last turn; Claude reads two tools first and then reports
    const { messages, bodies, timeouts } = recorder((_b, n) => (n < 3 ? toolUse("alerts") : submit(nothing)));
    const r = await runOnce(db, messages, {}, Date.now() + 100_000);
    expect(r.status).toBe("done");
    expect(timeouts).toHaveLength(3);
    for (const t of timeouts) expect(t! > 80_000 && t! <= 85_000).toBe(true);
    for (const b of bodies) {
      expect(b.tool_choice).toBeUndefined();
      expect(noteOf(b)).toContain("last turn");
    }
    // one note per user message: a message already sent is never given a second one
    expect(bodies.map(notesIn)).toEqual([1, 2, 3]);
    expect((bodies[0]!.messages as Msg[])[0]!.content).toEqual([
      { type: "text", text: expect.stringContaining("Run: optimise.") }, { type: "text", text: "This is your last turn. Call submit_report now with what you have." }]);
  });

  it("records usage when it stops for time", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(0);
      const db = fakeDb();
      const messages: Messages = vi.fn(async () => {
        vi.setSystemTime(230_000);
        return { stop_reason: "tool_use", usage: { input_tokens: 1000, output_tokens: 100 }, content: [{ type: "tool_use", id: "a", name: "alerts", input: {} }] };
      });
      const r = await runOnce(db, messages, {}, 260_000);
      expect(r.status).toBe("failed");
      expect(messages).toHaveBeenCalledTimes(1);
      expect(db.failed[0]).toContain("ran out of time");
      expect(db.fail).toHaveBeenCalledWith(7, expect.any(String), expect.objectContaining({ in: 1000, out: 100 }));
    } finally {
      vi.useRealTimers();
    }
  });

  it("fails a run cut off at max_tokens", async () => {
    const db = fakeDb();
    const r = await runOnce(db, vi.fn(async () => ({ stop_reason: "max_tokens", usage,
      content: [{ type: "tool_use", id: "b", name: "submit_report", input: { summary: "Partial" } }] })));
    expect(r.status).toBe("failed");
    expect(db.failed[0]).toContain("max_tokens");
    expect(db.finished).toEqual([]);
    expect(db.fail).toHaveBeenCalledWith(7, expect.stringContaining("max_tokens"), { in: 1000, out: 200, cache_read: 500, cache_write: 0 });
  });

  it("fails a refused run", async () => {
    const db = fakeDb();
    const r = await runOnce(db, vi.fn(async () => ({ stop_reason: "refusal", usage, content: [] })));
    expect(r.status).toBe("failed");
    expect(db.failed[0]).toContain("refusal");
    expect(db.finished).toEqual([]);
  });

  it("asks for medium effort on 5.x models", async () => {
    const sonnet = recorder(() => submit(nothing));
    await runOnce(fakeDb(), sonnet.messages);
    expect(sonnet.bodies[0]!.output_config).toEqual({ effort: "medium" });
    expect(sonnet.bodies[0]!.max_tokens).toBe(1000);

    const claimAs = (model: string, limits?: { max_turns: number; max_tokens: number; budget_left_usd: number }) =>
      fakeDb({ claim: vi.fn(async () => ({ run: { id: 9, kind: "light_check" as const, trigger: "light", model, context: {} }, limits, price_per_mtok: { in: 1, out: 5 } })) });
    const haiku = recorder(() => submit(nothing));
    await runOnce(claimAs("claude-haiku-4-5-20251001", { max_turns: 3, max_tokens: 800, budget_left_usd: 1 }), haiku.messages);
    expect("output_config" in haiku.bodies[0]!).toBe(false);
    expect(haiku.bodies[0]!.max_tokens).toBe(800);

    // without limits from the database: room for adaptive thinking
    const opus = recorder(() => submit(nothing));
    await runOnce(claimAs("claude-opus-5-5"), opus.messages);
    expect(opus.bodies[0]).toMatchObject({ max_tokens: 12000, output_config: { effort: "medium" } });
  });

  it("checks numbers in a pause reason", async () => {
    const db = fakeDb();
    const replies = [toolUse("partner_scorecards"), submit({ summary: "Partner B: duplicate rate 37.5%, SLA 22%.", findings: [],
      recommendations: [{ title: "Pause B", rationale: "see summary", change: { lever: "pause_draft", partner_id: 4, reason: "duplicate rate 37.5% and SLA 22%" } }] })];
    const r = await runOnce(db, vi.fn(async () => replies.shift()!));
    expect(r.status).toBe("rejected");
    expect(validationOf(db).unverified).toEqual(["37.5%", "22%"]);
    // the stored narrative is still the report text only
    expect(db.finished[0]!.narrative).toBe("Partner B: duplicate rate 37.5%, SLA 22%.\nPause B\nsee summary\n");

    // a number only in the reason or a rule's name is checked as well
    const db2 = fakeDb();
    const replies2 = [toolUse("partner_scorecards"), submit({ summary: "Two drafts.", findings: [], recommendations: [
      { title: "Pause B", rationale: "duplicates", change: { lever: "pause_draft", partner_id: 4, reason: "duplicate rate 37.5%" } },
      { title: "Narrow B", rationale: "fewer leads", change: { lever: "rule_draft", rule: { name: "B gets 18% of MBA", action: "narrow", partner_ids: [4] } } }] })];
    expect((await runOnce(db2, vi.fn(async () => replies2.shift()!))).status).toBe("rejected");
    expect(validationOf(db2).unverified).toEqual(["37.5%", "18%"]);
  });

  it("checks evidence values", async () => {
    const run = async (value: number) => {
      const db = fakeDb();
      const replies = [toolUse("partner_scorecards"), submit({ summary: "Partner scorecards read.", recommendations: [],
        findings: [{ title: "Enrolment", detail: "See the evidence.", evidence: [{ tool: "partner_scorecards", metric: "p_hat", value }] }] })];
      const r = await runOnce(db, vi.fn(async () => replies.shift()!));
      return { status: r.status, unverified: validationOf(db).unverified };
    };
    expect(await run(0.31)).toEqual({ status: "rejected", unverified: ["0.31"] });
    expect(await run(0.0612)).toEqual({ status: "done", unverified: [] });
  });

  it("allows proposed values", async () => {
    const db = fakeDb();
    const replies = [toolUse("segment_scorecards"), submit({ summary: "MBA has 41 matured leads.", findings: [], recommendations: [
      { title: "Explore more", rationale: "Set exploration to 25%", change: { lever: "exploration_share", segment: "mba|PG|Online", value: 0.25 } },
      { title: "Prefer partner 4", rationale: "A rule with priority 50 for partner 4", change: { lever: "rule_draft", rule: { name: "MBA to 4", action: "fix_partner", partner_ids: [4], priority: 50 } } },
      { title: "Rank it", rationale: "Give it priority 70", change: { lever: "rule_draft", rule: { name: "Ranked", action: "narrow", partner_ids: [4], priority: 70 } } },
    ] })];
    const r = await runOnce(db, vi.fn(async () => replies.shift()!));
    expect(r.status).toBe("done");
    expect(validationOf(db)).toMatchObject({ ok: true, unverified: [] });
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

  it("prices an unpriced run at the dearest list price", () => {
    expect(costUsd({ in: 1e6, out: 0, cache_read: 0, cache_write: 0 }, undefined)).toBe(4);
    expect(costUsd({ in: 0, out: 1e6, cache_read: 1e6, cache_write: 1e6 }, undefined)).toBeCloseTo(25.2);
  });
});

describe("Anthropic API client", () => {
  const ok = { content: [{ type: "text", text: "hi" }], stop_reason: "end_turn" };
  const setup = (opts: { retries?: number } = {}) => {
    const fetchImpl = vi.fn<(url: string, init: RequestInit) => Promise<Response>>();
    const sleep = vi.fn(async (_ms: number) => {});
    return { fetchImpl, sleep, messages: anthropicMessages("key", fetchImpl as unknown as typeof fetch, { ...opts, sleep }) };
  };
  const err = (status: number, message: string, headers: Record<string, string> = {}) =>
    new Response(JSON.stringify({ error: { message } }), { status, headers });

  it("retries an overload, then returns the reply, sending the same request", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockResolvedValueOnce(new Response('{"error":{"message":"overloaded"}}', { status: 529 })).mockResolvedValueOnce(Response.json(ok));
    await expect(messages({ model: "claude-sonnet-5-5", max_tokens: 10 })).resolves.toEqual(ok);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleep.mock.calls).toEqual([[1000]]);
    const [url, init] = fetchImpl.mock.calls[1]!;
    expect(url).toBe("https://api.anthropic.com/v1/messages");
    expect(init).toMatchObject({ method: "POST", body: JSON.stringify({ model: "claude-sonnet-5-5", max_tokens: 10 }) });
    expect((init.headers as Record<string, string>)["x-api-key"]).toBe("key");
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it("does not retry a bad request", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockResolvedValue(err(400, "tool_choice is not supported"));
    await expect(messages({})).rejects.toThrow("Anthropic API: tool_choice is not supported");
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("gives up after the retries, waiting as retry-after says", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockImplementation(async () => err(429, "rate limited", { "retry-after": "1" }));
    await expect(messages({})).rejects.toThrow("Anthropic API: rate limited");
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    expect(sleep.mock.calls).toEqual([[1000], [1000]]);
  });

  it("never retries its own timeout", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockRejectedValue(new DOMException("The operation was aborted due to timeout", "TimeoutError"));
    await expect(messages({})).rejects.toMatchObject({ name: "TimeoutError" });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("retries a network error", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockRejectedValueOnce(new TypeError("fetch failed")).mockResolvedValueOnce(Response.json(ok));
    await expect(messages({})).resolves.toEqual(ok);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleep.mock.calls).toEqual([[1000]]);
  });

  it("does not start a retry that would outlive the call's time budget", async () => {
    const { fetchImpl, sleep, messages } = setup();
    fetchImpl.mockImplementation(async () => err(503, "unavailable", { "retry-after": "30" }));
    await expect(messages({}, 20_000)).rejects.toThrow("Anthropic API: unavailable");
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });
});

describe("inbox labels", async () => {
  const { describeChange, simulationText, expiresText, editedChange, setupSteps } = await import("./labels");
  it("describes changes and simulations", () => {
    expect(describeChange({ lever: "exploration_share", segment: "mca|PG|Online", value: 0.3 })).toBe("Exploration share 30% for MCA · PG · Online");
    expect(describeChange({ lever: "partner_weight", partner_id: 4, value: 1.05 }, { "4": "SkillBridge" })).toBe("Weight SkillBridge at 105%");
    expect(describeChange(null)).toBe("No change: an observation");
    expect(simulationText({ simulated: true, decisions: 40, ncpl_now: 3400, ncpl_new: 4000, difference: 600, ci95: [-38, 1240], gain_pct: 17.6, enough: true }))
      .toBe("NCPL ₹3,400 → ₹4,000, +17.6% (95%: −₹38 to +₹1,240) on 40 decisions");
    expect(simulationText({ simulated: true, decisions: 0 })).toBe("No matured decisions to replay yet");
    expect(simulationText({ simulated: false, why: "cannot replay" })).toBe("cannot replay");
  });
  it("words expiry, edits and setup", () => {
    const now = new Date("2026-10-07T10:00:00Z");
    expect(expiresText("2026-10-13T11:00:00Z", now)).toBe("expires in 6 days");
    expect(expiresText("2026-10-07T09:00:00Z", now)).toBe("expired");
    expect(editedChange({ lever: "exploration_share", segment: "a|b|c", value: 0.5 }, "15")).toEqual({ lever: "exploration_share", segment: "a|b|c", value: 0.15 });
    expect(editedChange({ lever: "maturity_days", value: 60 }, "45")).toEqual({ lever: "maturity_days", value: 45 });
    expect(editedChange({ lever: "maturity_days", value: 60 }, "soon")).toBe("Enter a number");
    const steps = setupSteps({ settings: { enabled: false, worker_url: null } as never, worker: null, worker_key: false });
    expect(steps.filter((x) => x.done)).toHaveLength(0);
  });
});
