import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { DbError } from "../db.ts";
import { ModelError, ScriptedModelClient } from "./client.ts";
import type { AiDb, CallRecord, Claim } from "./db.ts";
import { PROMPTS } from "./prompts.generated.ts";
import { runTask, runWorker, type WorkerDeps } from "./worker.ts";

// The worker against a scripted model and a fake database: what it sends (masked, within budget), what it files,
// and the verdict it records in every way a task can end.

const claudeAi = (
  JSON.parse(readFileSync(new URL("../../../config/settings.json", import.meta.url), "utf8")) as {
    ai: Record<string, unknown>;
  }
).ai;

type Verdict =
  | { kind: "finish"; result: Record<string, unknown>; calls: CallRecord[] }
  | { kind: "fail"; error: string; calls: CallRecord[]; retry: boolean }
  | { kind: "defer"; reason: string; minutes: number };

class FakeAiDb implements AiDb {
  verdicts: Verdict[] = [];
  recorded: CallRecord[] = [];
  remaining = 500;
  tools: Array<{ name: string; args: Record<string, unknown> }> = [];
  claims: Claim[];
  finishError: Error | null = null;
  toolAnswer: (name: string) => unknown = () => ({ ok: true, data: [] });

  constructor(claims: Claim[] = []) {
    this.claims = [...claims];
  }

  async claim() {
    return this.claims.shift() ?? null;
  }
  async recordCalls(_t: number, _h: string, calls: CallRecord[]) {
    this.recorded.push(...calls);
    this.remaining -= calls.reduce((n, c) => n + (c.cost_inr ?? 0), 0);
    return { remaining_inr: this.remaining };
  }
  async finish(_t: number, _h: string, result: Record<string, unknown>, calls: CallRecord[]) {
    if (this.finishError) throw this.finishError;
    this.verdicts.push({ kind: "finish", result, calls });
  }
  async fail(_t: number, _h: string, error: string, calls: CallRecord[], retry: boolean) {
    this.verdicts.push({ kind: "fail", error, calls, retry });
    return retry ? "pending" : "failed";
  }
  async defer(_t: number, _h: string, reason: string, minutes: number) {
    this.verdicts.push({ kind: "defer", reason, minutes });
  }
  async tool(_t: number, _h: string, name: string, args: Record<string, unknown>) {
    this.tools.push({ name, args });
    return this.toolAnswer(name);
  }
  async aiSettings() {
    return claudeAi;
  }
}

const incidentContext = {
  incident: {
    id: 5,
    check_id: "WITTY-02",
    app: "witty",
    severity: "P1",
    title: "Witty replies are slow",
    evidence: { value: { p95_ms: 41000, sample_phone: "+91 98765 43210", by: "priya@gmail.com" } },
  },
  check: { id: "WITTY-02", title: "Witty replies are slow", rule_sql: "select …" },
  messages: [{ at: "2026-10-24T02:00:00Z", direction: "out", text: "Hi Priya, call 9876543210 please" }],
  student_name: "Priya Sharma",
};

const claim = (over: Partial<Claim["task"]> = {}, rest: Partial<Omit<Claim, "task">> = {}): Claim => ({
  task: { id: 1, kind: "triage", input: {}, model_hint: null, attempts: 1, incident_id: 5, ...over },
  ai: claudeAi,
  budget: { spent_inr: 0, cap_inr: 500, remaining_inr: 500, task_spent_inr: 0 },
  context: incidentContext,
  ...rest,
});

const triage = {
  summary: "Witty's replies take 41 s at p95 since 07:30 IST.",
  likely_cause: "Gemini latency",
  next_steps: ["Look at the n8n executions"],
  checks_to_watch: ["WITTY-05"],
  confidence: "medium",
  propose_fix: false,
};

function deps(db: FakeAiDb, client: ScriptedModelClient | null, over: Partial<WorkerDeps> = {}): WorkerDeps {
  return {
    db,
    client,
    holder: "ai-test",
    deadline: Date.now() + 240_000,
    ...over,
  };
}

describe("a task that succeeds", () => {
  it("sends the masked data with the kind's prompt, files the answer with its meta, and records the call's cost", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [
      { json: triage, usage: { input: 3000, output: 400, cacheRead: 0, cacheWrite: 0 }, model: "claude-sonnet-5-5" },
    ]);
    expect(await runTask(claim(), deps(db, model))).toBe("done");
    const req = model.requests[0];
    expect(req?.model).toBe("claude-sonnet-5-5");
    expect(req?.effort).toBe("medium");
    expect(req?.system).toContain(PROMPTS.triage.text);
    expect(req?.user).toContain("Incident #5.");
    expect(req?.user).toContain("…3210");
    expect(req?.user).not.toMatch(/98765|priya@|Priya Sharma|Hi Priya/);
    expect(req?.user).toContain("@gmail.com");
    const v = db.verdicts[0];
    expect(v?.kind).toBe("finish");
    if (v?.kind !== "finish") return;
    expect(v.result).toMatchObject({
      summary: triage.summary,
      meta: {
        provider: "anthropic",
        model: "claude-sonnet-5-5",
        tier: "regular",
        prompt_version: PROMPTS.triage.version,
      },
    });
    // 3,000 in at $2 + 400 out at $10 = $0.01 → ₹0.85; recorded as the call ended, so the verdict carries none.
    expect(v.calls).toEqual([]);
    expect(db.recorded).toEqual([
      expect.objectContaining({
        ok: true,
        input_tokens: 3000,
        output_tokens: 400,
        cost_usd: 0.01,
        cost_inr: 0.85,
        purpose: "triage",
      }),
    ]);
  });

  it("repairs one answer that does not match the schema", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ json: { summary: "x" } }, { json: triage }]);
    expect(await runTask(claim(), deps(db, model))).toBe("done");
    expect(model.requests[1]?.user).toContain("did not match the required JSON");
    expect(db.recorded).toHaveLength(2);
  });

  it("quotes Witty's messages only for explain with excerpts allowed, and masks them", async () => {
    const explain = {
      explanation: "e",
      likely_cause: "c",
      timeline: [{ at: "07:30", what: "slow" }],
      confidence: "low",
    };
    for (const allow of [false, true]) {
      const db = new FakeAiDb();
      const model = new ScriptedModelClient("anthropic", [{ json: explain }]);
      const c = claim({ kind: "explain" }, { ai: { ...claudeAi, allow_message_excerpts: allow } });
      expect(await runTask(c, deps(db, model))).toBe("done");
      const user = model.requests[0]?.user ?? "";
      expect(user.includes("call …3210 please")).toBe(allow);
      expect(user).not.toContain("9876543210");
    }
  });
});

describe("a task that cannot run yet", () => {
  it("waits when the tier's model has no price", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", []);
    const unpriced = {
      ...claudeAi,
      models: { quick: "claude-haiku-5-5", regular: "claude-unpriced", deep: "claude-opus-5-5" },
    };
    expect(await runTask(claim({}, { ai: unpriced }), deps(db, model))).toBe("deferred");
    expect(db.verdicts[0]).toMatchObject({
      kind: "defer",
      reason: expect.stringContaining("has no price"),
      minutes: 30,
    });
    expect(model.requests).toHaveLength(0);
  });

  it("waits when there is no key for the provider", async () => {
    const db = new FakeAiDb();
    expect(await runTask(claim(), deps(db, null))).toBe("deferred");
    expect(db.verdicts[0]).toMatchObject({ kind: "defer", reason: "setup: no Anthropic key (Setup item ai_key)" });
  });

  it("waits when the call's worst case is more than what is left today", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ json: triage }]);
    const c = claim({}, { budget: { spent_inr: 499.5, cap_inr: 500, remaining_inr: 0.5, task_spent_inr: 0 } });
    expect(await runTask(c, deps(db, model))).toBe("deferred");
    expect(db.verdicts[0]).toMatchObject({
      kind: "defer",
      reason: expect.stringMatching(/^budget \(cap reached\): .*₹0\.50 is left today$/),
      minutes: 15,
    });
    expect(model.requests).toHaveLength(0);
  });

  it("fails without a call when one call could pass the per-task cap", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ json: triage }]);
    const c = claim({}, { ai: { ...claudeAi, per_task_cap_inr: 1 } });
    expect(await runTask(c, deps(db, model))).toBe("failed");
    expect(db.verdicts[0]).toMatchObject({
      kind: "fail",
      retry: false,
      error: expect.stringContaining("per-task cap ₹1.00"),
    });
    expect(model.requests).toHaveLength(0);
  });
});

describe("a task that fails", () => {
  it("retries a rate limit, recording the failed call", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [new ModelError("anthropic: rate limited (429)", true, 429)]);
    expect(await runTask(claim(), deps(db, model))).toBe("retry");
    expect(db.verdicts[0]).toMatchObject({ kind: "fail", retry: true });
    expect(db.recorded).toEqual([expect.objectContaining({ ok: false, error: "anthropic: rate limited (429)" })]);
    expect(db.recorded[0]?.cost_inr).toBeUndefined();
  });

  it("does not retry a refused key, a refusal or a cut-off answer, and keeps their cost", async () => {
    for (const [answer, error] of [
      [new ModelError("anthropic: the key was refused (401)", false, 401), "the key was refused"],
      [{ text: '{"summary": "', stop: "max_tokens" as const }, "cut off"],
    ] as const) {
      const db = new FakeAiDb();
      expect(await runTask(claim(), deps(db, new ScriptedModelClient("anthropic", [answer])))).toBe("failed");
      expect(db.verdicts[0]).toMatchObject({ kind: "fail", retry: false, error: expect.stringContaining(error) });
    }
  });

  it("asks the refusal fallback once when the model declines, and fails when both decline", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ json: triage, stop: "refusal" }, { json: triage }]);
    expect(await runTask(claim(), deps(db, model))).toBe("done");
    expect(model.requests.map((r) => r.model)).toEqual(["claude-sonnet-5-5", "claude-opus-4-8"]);
    expect(db.recorded.map((c) => [c.purpose, c.ok])).toEqual([
      ["triage", false],
      ["triage:fallback", true],
    ]);
    const v = db.verdicts[0];
    expect(v?.kind === "finish" && v.result).toMatchObject({ meta: { model: "claude-opus-4-8" } });

    const both = new FakeAiDb();
    const refuse = { json: triage, stop: "refusal" as const };
    expect(await runTask(claim(), deps(both, new ScriptedModelClient("anthropic", [refuse, refuse])))).toBe("failed");
    expect(both.verdicts[0]).toMatchObject({
      kind: "fail",
      retry: false,
      error: expect.stringContaining("both declined"),
    });

    const none = new FakeAiDb();
    const c = claim({}, { ai: { ...claudeAi, refusal_fallback: null } });
    expect(await runTask(c, deps(none, new ScriptedModelClient("anthropic", [refuse])))).toBe("failed");
    expect(none.verdicts[0]).toMatchObject({ kind: "fail", error: "the model declined to answer" });
  });

  it("waits for the next credits when the Anthropic balance runs out, and says so", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [
      new ModelError("anthropic: the API credit balance is too low", false, 400, true),
    ]);
    expect(await runTask(claim(), deps(db, model))).toBe("deferred");
    expect(db.verdicts[0]).toMatchObject({
      kind: "defer",
      reason: expect.stringMatching(/^budget \(credits exhausted\)/),
      minutes: 60,
    });
  });

  it("counts a call that got no answer (a timeout) at its worst case", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [
      new ModelError("anthropic: no answer (network or timeout)", true),
    ]);
    expect(await runTask(claim(), deps(db, model))).toBe("retry");
    expect(db.recorded[0]).toMatchObject({ ok: false, error: expect.stringContaining("counted at its worst case") });
    expect(db.recorded[0]?.cost_inr ?? 0).toBeGreaterThan(0);
  });

  it("holds the per-task cap across attempts (review M6)", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ json: triage }]);
    const c = claim(
      { attempts: 3 },
      { budget: { spent_inr: 60, cap_inr: 500, remaining_inr: 440, task_spent_inr: 49.5 } },
    );
    expect(await runTask(c, deps(db, model))).toBe("failed");
    expect(db.verdicts[0]).toMatchObject({ kind: "fail", error: expect.stringContaining("per-task cap ₹50.00") });
    expect(model.requests).toHaveLength(0);
  });

  it("uses the budget the database reports after each call, not the claim's", async () => {
    const db = new FakeAiDb();
    db.remaining = 0.2; // another task spent the rest of the day while this one ran
    const model = new ScriptedModelClient("anthropic", [{ json: { summary: "x" } }, { json: triage }]);
    expect(await runTask(claim(), deps(db, model))).toBe("deferred");
    expect(model.requests).toHaveLength(1);
    expect(db.verdicts[0]).toMatchObject({ kind: "defer", reason: expect.stringContaining("budget (cap reached)") });
  });

  it("retries after two answers that do not match", async () => {
    const db = new FakeAiDb();
    const model = new ScriptedModelClient("anthropic", [{ text: "not json" }, { json: { summary: 1 } }]);
    expect(await runTask(claim(), deps(db, model))).toBe("retry");
    expect(db.verdicts[0]).toMatchObject({
      kind: "fail",
      retry: true,
      error: expect.stringContaining("did not match"),
    });
  });

  it("fails, keeping the calls, when the database refuses the answer", async () => {
    const db = new FakeAiDb();
    db.finishError = new DbError("ai_finish", "23503");
    expect(await runTask(claim(), deps(db, new ScriptedModelClient("anthropic", [{ json: triage }])))).toBe("failed");
    expect(db.verdicts[0]).toMatchObject({
      kind: "fail",
      retry: false,
      error: "the answer could not be filed (23503)",
    });
    expect(db.recorded).toHaveLength(1);
  });
});

describe("Ask", () => {
  const askClaim = claim(
    { kind: "ask", incident_id: null, input: { question: "Why is Witty slow? Call me on 9876543210" } },
    { context: { question: "Why is Witty slow? Call me on 9876543210", today_ist: "2026-10-24" } },
  );

  it("runs the tools it asks for, masks what they return, and answers with the queries", async () => {
    const db = new FakeAiDb();
    db.toolAnswer = () => ({ ok: true, data: [{ id: 5, title: "slow", reporter: "a@b.co", phone: "9123456780" }] });
    const n8n = { executions: async () => [{ id: "1", status: "error", startedAt: null, stoppedAt: null }] };
    const model = new ScriptedModelClient("anthropic", [
      {
        json: {
          calls: [
            { tool: "incidents", args_json: '{"app": "witty"}' },
            { tool: "n8n_executions", args_json: '{"limit": 99}' },
            { tool: "check", args_json: "not json" },
          ],
          answer: null,
        },
      },
      { json: { calls: [], answer: "WITTY-02 is open: replies take 41 s." } },
    ]);
    expect(await runTask(askClaim, deps(db, model, { n8n }))).toBe("done");
    expect(model.requests[0]?.user).toContain("Question: Why is Witty slow? Call me on …3210");
    expect(db.tools).toEqual([{ name: "incidents", args: { app: "witty" } }]);
    const second = model.requests[1]?.user ?? "";
    expect(second).toContain("### incidents");
    expect(second).toContain("…6780");
    expect(second).not.toContain("9123456780");
    expect(second).not.toContain("a@b.co");
    expect(second).toContain('"status":"error"');
    const v = db.verdicts[0];
    expect(v?.kind === "finish" && v.result).toMatchObject({
      answer: "WITTY-02 is open: replies take 41 s.",
      queries: [
        { tool: "incidents", ok: true, rows: 1 },
        { tool: "n8n_executions", ok: true, rows: 1 },
        { tool: "check", ok: false, error: "the arguments were not a JSON object" },
      ],
    });
  });

  it("masks a tool's error text, and skips tools when time runs short", async () => {
    const db = new FakeAiDb();
    db.toolAnswer = () => ({ ok: false, error: 'invalid input syntax for type bigint: "9876543210"' });
    const model = new ScriptedModelClient("anthropic", [
      { json: { calls: [{ tool: "incident", args_json: '{"id": "9876543210"}' }], answer: null } },
      { json: { calls: [], answer: "No such incident." } },
    ]);
    expect(await runTask(askClaim, deps(db, model))).toBe("done");
    const second = model.requests[1]?.user ?? "";
    expect(second).toContain("…3210");
    expect(second).not.toContain("9876543210");
    const v = db.verdicts[0];
    expect(JSON.stringify(v?.kind === "finish" && v.result)).not.toContain("9876543210");

    const late = new FakeAiDb();
    const model2 = new ScriptedModelClient("anthropic", [
      { json: { calls: [{ tool: "health", args_json: "{}" }], answer: null } },
      { json: { calls: [], answer: "Could not check." } },
    ]);
    // The clock jumps once the first round has answered: the tool call is skipped, the answer still comes.
    const t = Date.now();
    const clock = () => (model2.requests.length >= 1 ? t + 200_000 : t);
    expect(await runTask(askClaim, deps(late, model2, { now: clock, deadline: t + 240_000 }))).toBe("done");
    expect(late.tools).toHaveLength(0);
    expect(late.verdicts[0]?.kind === "finish" && late.verdicts[0].result).toMatchObject({
      queries: [{ tool: "health", ok: false, error: "skipped: the worker ran out of time" }],
    });
  });

  it("must answer in the third round", async () => {
    const db = new FakeAiDb();
    const more = { json: { calls: [{ tool: "health", args_json: "{}" }], answer: null } };
    const model = new ScriptedModelClient("anthropic", [more, more, { json: { answer: "Everything is up." } }]);
    expect(await runTask(askClaim, deps(db, model))).toBe("done");
    expect(model.requests[2]?.user).toContain("This is the last round");
    expect(db.recorded).toHaveLength(3);
  });
});

describe("runWorker", () => {
  it("claims until nothing is due, and starts nothing in the last 90 s", async () => {
    const db = new FakeAiDb([claim({ id: 1 }), claim({ id: 2 })]);
    const model = new ScriptedModelClient("anthropic", [{ json: triage }, { json: triage }]);
    expect(await runWorker(deps(db, model))).toEqual({ claimed: 2, done: 2, failed: 0, retry: 0, deferred: 0 });
    const late = new FakeAiDb([claim()]);
    expect(await runWorker(deps(late, model, { deadline: Date.now() + 60_000 }))).toMatchObject({ claimed: 0 });
  });
});
