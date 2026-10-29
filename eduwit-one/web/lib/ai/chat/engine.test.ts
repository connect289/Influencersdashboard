import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { CallRecord } from "../db.ts";
import { ModelError } from "../client.ts";
import { ScriptedChatClient, type ChatRequest } from "./client.ts";
import type { AssistantContent, ChatDb, Decided, HistoryItem, TurnStart } from "./db.ts";
import { historyMessages, runTurn, SECRET_REFUSAL, type ChatDeps, type ChatEvent } from "./engine.ts";

// The turn against a scripted model and a fake database: what reaches the model (masked, with the tools of the role),
// what runs at once, what becomes an action card, what is stored, and how a turn ends in every way it can.

const ai = (
  JSON.parse(readFileSync(new URL("../../../../config/settings.json", import.meta.url), "utf8")) as { ai: unknown }
).ai;

class FakeChatDb implements ChatDb {
  started: Array<{ thread: number | null; text: string }> = [];
  finished: Array<{ status: string; error: string | null; assistant: AssistantContent }> = [];
  proposed: Array<{ tool: string; args: Record<string, unknown>; summary: string; risk: string }> = [];
  history: HistoryItem[] = [];
  role: "owner" | "engineer" = "owner";
  remaining = 200;
  startError: Error | null = null;

  async turnStart(thread: number | null, text: string): Promise<TurnStart> {
    if (this.startError) throw this.startError;
    this.started.push({ thread, text });
    return {
      thread_id: thread ?? 7,
      message_id: 11,
      task_id: 99,
      me: { email: "connect@eduwit.in", role: this.role },
      ai,
      budget: { spent_inr: 0, cap_inr: 250, remaining_inr: this.remaining },
      history: this.history,
      snapshot: { now_ist: "2026-10-29 10:00", open_incidents: { P1: 1, P2: 2, P3: 0 } },
    };
  }
  async turnFinish(
    _t: number,
    _h: string,
    assistant: AssistantContent,
    status: "done" | "failed",
    error: string | null,
  ) {
    this.finished.push({ status, error, assistant });
    return 12;
  }
  async actionPropose(
    _t: number,
    _h: string,
    tool: string,
    args: Record<string, unknown>,
    summary: string,
    risk: string,
  ) {
    this.proposed.push({ tool, args, summary, risk });
    return this.proposed.length;
  }
  async actionDecide(): Promise<Decided> {
    throw new Error("not in the engine");
  }
  async actionResult() {
    return "done";
  }
}

class FakeAi {
  recorded: CallRecord[] = [];
  tools: Array<{ name: string; args: Record<string, unknown> }> = [];
  answer: (name: string) => unknown = () => ({ ok: true, data: [{ id: 1, phone: "9876543210", title: "x" }] });
  remaining = 200;
  async recordCalls(_t: number, _h: string, calls: CallRecord[]) {
    this.recorded.push(...calls);
    this.remaining -= calls.reduce((n, c) => n + (c.cost_inr ?? 0), 0);
    return { remaining_inr: this.remaining };
  }
  async tool(_t: number, _h: string, name: string, args: Record<string, unknown>) {
    this.tools.push({ name, args });
    return this.answer(name);
  }
}

function run(client: ScriptedChatClient | null, over: Partial<ChatDeps> = {}, text = "What needs me now?") {
  const chat = new FakeChatDb();
  const aiDb = new FakeAi();
  const acts: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const events: ChatEvent[] = [];
  const deps: ChatDeps = {
    chat,
    ai: aiDb,
    client,
    act: async (fn, args) => {
      acts.push({ fn, args });
      return { ok: true };
    },
    validateSetup: async (item) => ({ ok: item === "n8n_api", detail: item === "n8n_api" ? "n8n answered" : "no key" }),
    holder: "chat-test0001",
    deadline: Date.now() + 150_000,
    ...over,
  };
  return {
    chat,
    aiDb,
    acts,
    events,
    go: () => runTurn({ thread: null, text }, deps, (e) => events.push(e)),
    deps,
  };
}

const toolUse = (id: string, name: string, input: Record<string, unknown>) => ({
  type: "tool_use" as const,
  id,
  name,
  input,
});
const usage = { input: 2000, output: 300, cacheRead: 0, cacheWrite: 0 };

describe("a turn that answers", () => {
  it("sends the masked message with the role's tools, streams the text, stores the answer and records the cost", async () => {
    const model = new ScriptedChatClient([{ text: "Two incidents are open; WITTY-02 since 09:40 IST.", usage }]);
    const { chat, aiDb, events, go } = run(model, {}, "What is open? The lead on 9876543210 asked");
    await go();
    const req = model.requests[0] as ChatRequest;
    expect(req.messages.at(-1)).toEqual({ role: "user", content: "What is open? The lead on …3210 asked" });
    expect(req.system).toContain("connect@eduwit.in, role owner");
    expect(req.system).toContain('"P1":1');
    expect(req.tools.map((t) => t.name)).toContain("set_fix");
    expect(events.map((e) => e.t)).toEqual(["start", "text", "done"]);
    const done = events.find((e) => e.t === "done");
    expect(done && done.t === "done" && done.text).toContain("WITTY-02");
    expect(chat.finished).toHaveLength(1);
    expect(chat.finished[0]?.status).toBe("done");
    expect(chat.finished[0]?.assistant.meta?.calls).toBe(1);
    expect(aiDb.recorded).toHaveLength(1);
    expect(aiDb.recorded[0]).toMatchObject({ provider: "anthropic", purpose: "chat:1", ok: true });
    expect(aiDb.recorded[0]?.cost_inr).toBeGreaterThan(0);
  });

  it("runs read tools and auto acts at once, masks what comes back, and gives the model the results", async () => {
    const model = new ScriptedChatClient([
      {
        blocks: [
          { type: "text", text: "Let me look." },
          toolUse("t1", "incidents", { status: "open", app: "witty" }),
          toolUse("t2", "acknowledge_incident", { id: 1 }),
          toolUse("t3", "runbook", { query: "rotate n8n key" }),
        ],
        usage,
      },
      { text: "Incident #1 is acknowledged. Rotate the key as the runbook says.", usage },
    ]);
    const { chat, aiDb, acts, events, go } = run(model);
    await go();
    expect(aiDb.tools).toEqual([{ name: "incidents", args: { status: "open", app: "witty" } }]);
    expect(acts).toEqual([{ fn: "ui_ack", args: { p_id: 1 } }]);
    const second = model.requests[1] as ChatRequest;
    const results = second.messages.at(-1)?.content;
    expect(Array.isArray(results)).toBe(true);
    const text = JSON.stringify(results);
    expect(text).not.toContain("9876543210");
    expect(text).toContain("3210");
    expect(text).toContain("RUNBOOK");
    expect(events.filter((e) => e.t === "tool").map((e) => (e.t === "tool" ? `${e.name}:${e.status}` : ""))).toEqual([
      "incidents:running",
      "incidents:ok",
      "acknowledge_incident:running",
      "acknowledge_incident:ok",
      "runbook:running",
      "runbook:ok",
    ]);
    expect(chat.finished[0]?.assistant.tools.map((t) => t.name)).toEqual([
      "incidents",
      "acknowledge_incident",
      "runbook",
    ]);
    expect(JSON.stringify(chat.finished[0]?.assistant.tools)).not.toContain("9876543210");
    expect(aiDb.recorded).toHaveLength(2);
  });

  it("turns a confirmable act into an action card and tells the model it has not run", async () => {
    const model = new ScriptedChatClient([
      {
        blocks: [
          toolUse("t1", "mute", { target_type: "check", target: "WITTY-04", minutes: 60, reason: "deploy at 10" }),
        ],
        usage,
      },
      { text: "I have proposed muting WITTY-04 for an hour; confirm the card to apply it.", usage },
    ]);
    const { chat, acts, events, go } = run(model);
    await go();
    expect(acts).toEqual([]);
    expect(chat.proposed).toEqual([
      {
        tool: "mute",
        args: { target_type: "check", target: "WITTY-04", minutes: 60, reason: "deploy at 10" },
        summary: "Mute check WITTY-04 for 60 minutes",
        risk: "medium",
      },
    ]);
    const card = events.find((e) => e.t === "action");
    expect(card && card.t === "action" && card.action).toMatchObject({ id: 1, tool: "mute", risk: "medium" });
    const second = model.requests[1] as ChatRequest;
    expect(JSON.stringify(second.messages.at(-1)?.content)).toContain("has not run");
    expect(chat.finished[0]?.assistant.actions).toEqual([1]);
  });

  it("answers a secret request with a Vault card the model never sees into", async () => {
    const model = new ScriptedChatClient([
      { blocks: [toolUse("t1", "request_secret", { name: "one_n8n_key", item: "n8n_api" })], usage },
      { text: "Paste the n8n key into the card above.", usage },
    ]);
    const { events, go } = run(model);
    await go();
    expect(events.find((e) => e.t === "secret")).toEqual({ t: "secret", name: "one_n8n_key", item: "n8n_api" });
  });

  it("refuses bad arguments and unknown tools as data for the model, without running anything", async () => {
    const model = new ScriptedChatClient([
      {
        blocks: [toolUse("t1", "mute", { target_type: "lead", target: "x" }), toolUse("t2", "drop_everything", {})],
        usage,
      },
      { text: "I could not do that.", usage },
    ]);
    const { chat, acts, go } = run(model);
    await go();
    expect(acts).toEqual([]);
    expect(chat.proposed).toEqual([]);
    const second = model.requests[1] as ChatRequest;
    const text = JSON.stringify(second.messages.at(-1)?.content);
    expect(text).toContain("arguments:");
    expect(text).toContain("unknown tool drop_everything");
  });

  it("does not offer an engineer the owner-only acts", async () => {
    const model = new ScriptedChatClient([{ text: "ok", usage }]);
    const r = run(model);
    r.chat.role = "engineer";
    await r.go();
    const names = (model.requests[0] as ChatRequest).tools.map((t) => t.name);
    expect(names).not.toContain("set_fix");
    expect(names).toContain("acknowledge_incident");
  });

  it("runs a Setup validator as an act and reports the verdict", async () => {
    const model = new ScriptedChatClient([
      { blocks: [toolUse("t1", "validate_setup", { item: "n8n_api" })], usage },
      { text: "n8n is validated.", usage },
    ]);
    const { go, events } = run(model);
    await go();
    expect(JSON.stringify((model.requests[1] as ChatRequest).messages.at(-1)?.content)).toContain("n8n answered");
    expect(events.some((e) => e.t === "tool" && e.name === "validate_setup" && e.status === "ok")).toBe(true);
  });
});

describe("a turn that cannot or should not run", () => {
  it("refuses a message that looks like a secret before anything is stored or sent", async () => {
    const model = new ScriptedChatClient([{ text: "never", usage }]);
    const { chat, events, go } = run(model, {}, "my key is sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789");
    await go();
    expect(chat.started).toEqual([]);
    expect(model.requests).toEqual([]);
    expect(events).toEqual([{ t: "refused", message: SECRET_REFUSAL }]);
  });

  it("says when the AI is not switched on, without opening a turn", async () => {
    const { chat, events, go } = run(null);
    await go();
    expect(chat.started).toEqual([]);
    expect(events[0]?.t).toBe("error");
  });

  it("fails the turn when a call would pass the day's budget, and records nothing", async () => {
    const model = new ScriptedChatClient([{ text: "x", usage }]);
    const r = run(model);
    r.chat.remaining = 0.01;
    await r.go();
    expect(model.requests).toEqual([]);
    expect(r.chat.finished[0]?.status).toBe("failed");
    expect(r.chat.finished[0]?.error).toMatch(/^budget \(cap reached\)/);
    expect(r.events.at(-1)?.t).toBe("error");
  });

  it("records a failed call, counted at its worst case when no status came back, and fails the turn", async () => {
    const model = new ScriptedChatClient([new ModelError("anthropic: no answer (network or timeout)", true)]);
    const { chat, aiDb, go } = run(model);
    await go();
    expect(aiDb.recorded).toHaveLength(1);
    expect(aiDb.recorded[0]?.ok).toBe(false);
    expect(aiDb.recorded[0]?.cost_inr).toBeGreaterThan(0);
    expect(chat.finished[0]?.status).toBe("failed");
  });

  it("stops at the tool-call limit and still answers", async () => {
    const many = Array.from({ length: 17 }, (_, i) => toolUse(`t${i}`, "health", {}));
    const model = new ScriptedChatClient([
      { blocks: many, usage },
      { text: "Here is what I found.", usage },
    ]);
    const { aiDb, go } = run(model);
    await go();
    expect(aiDb.tools).toHaveLength(16);
    const second = model.requests[1] as ChatRequest;
    expect(JSON.stringify(second.messages.at(-1)?.content)).toContain("no more tool calls");
  });

  it("keeps the text it got when the turn fails after a tool round", async () => {
    const model = new ScriptedChatClient([
      { blocks: [{ type: "text", text: "Checking." }, toolUse("t1", "health", {})], usage },
      new ModelError("anthropic: rate limited (429)", true, 429),
    ]);
    const { chat, go } = run(model);
    await go();
    expect(chat.finished[0]?.status).toBe("failed");
    expect(chat.finished[0]?.assistant.text).toBe("Checking.");
  });
});

describe("historyMessages", () => {
  it("folds actions into the person's side, alternates roles and starts with the person", () => {
    const h: HistoryItem[] = [
      { role: "assistant", content: { text: "orphan" } },
      { role: "user", content: { text: "mute WITTY-04" } },
      {
        role: "assistant",
        content: { text: "Proposed.", tools: [{ name: "mute", args: { target: "WITTY-04" }, ok: true, rows: 0 }] },
      },
      {
        role: "action",
        content: { action_id: 3, tool: "mute", status: "done", summary: "Mute check WITTY-04 for 60 minutes" },
      },
      { role: "user", content: { text: "thanks" } },
    ];
    const m = historyMessages(h);
    expect(m.map((x) => x.role)).toEqual(["user", "assistant", "user"]);
    expect(m[1]?.content).toContain("[Tools used: mute(");
    expect(m[2]?.content).toBe("[Action #3 (mute): done — Mute check WITTY-04 for 60 minutes]\n\nthanks");
  });

  it("drops the oldest turns when the history is too long", () => {
    const h: HistoryItem[] = Array.from({ length: 10 }, (_, i) => ({
      role: i % 2 ? "assistant" : "user",
      content: { text: `${i}:${"x".repeat(100)}` },
    }));
    const m = historyMessages(h, 450);
    expect(m.length).toBeLessThan(10);
    expect(m[0]?.role).toBe("user");
  });
});
