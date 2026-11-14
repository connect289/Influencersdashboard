import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  createErrorReporter,
  failureCode,
  FAILURE_PAUSE_MS,
  FLUSH_INTERVAL_MS,
  isHostedSupabaseUrl,
  MAX_COUNT,
  MAX_PAIRS,
  MIN_FLUSH_GAP_MS,
  OVERFLOW,
  reportingEnabled,
  reportItem,
  SEND_TIMEOUT_MS,
  type ErrorReportItem,
} from "./error-report";

type Send = (items: ErrorReportItem[], signal: AbortSignal) => Promise<void>;

function setup(over: { enabled?: () => boolean; send?: Send } = {}) {
  const sent: ErrorReportItem[][] = [];
  const failures: string[] = [];
  const send = vi.fn<Send>(
    over.send ??
      ((items) => {
        sent.push(items.map((i) => ({ ...i })));
        return Promise.resolve();
      }),
  );
  const reporter = createErrorReporter({
    enabled: over.enabled ?? (() => true),
    send,
    onFailure: (code) => failures.push(code),
  });
  return { reporter, send, sent, failures };
}

const boom = { route: "/leads/[id]", name: "TypeError", message: "no owner", digest: "1234567", kind: "render" };

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-11-13T10:00:00Z"));
});

afterEach(() => {
  vi.useRealTimers();
});

describe("createErrorReporter", () => {
  it("sends the first error at once and counts the rest of the minute into one report", async () => {
    const { reporter, send, sent } = setup();
    reporter.record(boom);
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toEqual([[{ ...boom, n: 1 }]]);

    reporter.record(boom);
    reporter.record(boom);
    reporter.record({ route: "/api/health", name: "Error", kind: "route" });
    reporter.record(boom);
    await vi.advanceTimersByTimeAsync(FLUSH_INTERVAL_MS - 1);
    expect(send).toHaveBeenCalledTimes(1);
    expect(reporter.pending()).toBe(2);

    await vi.advanceTimersByTimeAsync(1);
    expect(send).toHaveBeenCalledTimes(2);
    expect(sent[1]).toEqual([
      { ...boom, n: 3 },
      { route: "/api/health", name: "Error", n: 1, message: null, digest: null, kind: "route" },
    ]);
    expect(reporter.pending()).toBe(0);
  });

  it("flushes at most once a minute however many errors arrive", async () => {
    const { reporter, send } = setup();
    for (let second = 0; second < 180; second++) {
      reporter.record(boom);
      await vi.advanceTimersByTimeAsync(1000);
    }
    // At 0 s, 60 s and 120 s, and the tail when the third minute ends.
    expect(send).toHaveBeenCalledTimes(4);
    expect(send.mock.calls.flatMap(([items]) => items).reduce((sum, i) => sum + i.n, 0)).toBe(180);
  });

  it("flushes early when the pairs reach the cap, never under 5 seconds apart, and keeps the count of what does not fit", async () => {
    const { reporter, send, sent } = setup();
    reporter.record(boom);
    await vi.advanceTimersByTimeAsync(MIN_FLUSH_GAP_MS);
    for (let i = 0; i < MAX_PAIRS - 1; i++) reporter.record({ route: `/r/${i}`, name: "Error" });
    await vi.advanceTimersByTimeAsync(0);
    expect(send).toHaveBeenCalledTimes(2);
    expect(sent[1]).toHaveLength(MAX_PAIRS - 1);

    // Straight after a flush the cap cannot trigger another: the extra pairs share the overflow pair.
    for (let i = 0; i < MAX_PAIRS + 20; i++) reporter.record({ route: `/s/${i}`, name: "Error" });
    await vi.advanceTimersByTimeAsync(0);
    expect(send).toHaveBeenCalledTimes(2);
    expect(reporter.pending()).toBe(MAX_PAIRS);
    await vi.advanceTimersByTimeAsync(FLUSH_INTERVAL_MS);
    expect(send).toHaveBeenCalledTimes(3);
    const last = sent[2] ?? [];
    expect(last).toHaveLength(MAX_PAIRS);
    expect(last.find((i) => i.route === OVERFLOW)).toEqual({
      route: OVERFLOW,
      name: OVERFLOW,
      n: 21,
      message: null,
      digest: null,
      kind: null,
    });
    expect(last.reduce((sum, i) => sum + i.n, 0)).toBe(MAX_PAIRS + 20);
  });

  it("caps one pair's count", async () => {
    const { reporter, sent } = setup();
    reporter.record(boom);
    await vi.advanceTimersByTimeAsync(0);
    for (let i = 0; i < MAX_COUNT + 5; i++) reporter.record(boom);
    await vi.advanceTimersByTimeAsync(FLUSH_INTERVAL_MS);
    expect(sent[1]?.[0]?.n).toBe(MAX_COUNT);
  });

  it("never throws and never rejects: a failing, throwing or hanging send is dropped and reporting pauses", async () => {
    const calls: number[] = [];
    let mode: "reject" | "throw" | "hang" = "reject";
    const { reporter, send, failures } = setup({
      send: (items) => {
        calls.push(items.length);
        if (mode === "throw") throw new TypeError("fetch failed");
        if (mode === "hang") return new Promise<void>(() => undefined);
        return Promise.reject(Object.assign(new Error("relation does not exist: 9876543210"), { code: "PGRST202" }));
      },
    });
    expect(() => reporter.record(boom)).not.toThrow();
    await vi.advanceTimersByTimeAsync(0);
    expect(failures).toEqual(["PGRST202"]);

    // Paused: errors are counted, nothing is sent, and the failed batch is not sent again.
    for (let i = 0; i < 10; i++) reporter.record(boom);
    await vi.advanceTimersByTimeAsync(FAILURE_PAUSE_MS - 1);
    expect(send).toHaveBeenCalledTimes(1);
    mode = "throw";
    await vi.advanceTimersByTimeAsync(1);
    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[1]?.[0]).toEqual([{ ...boom, n: 10 }]);
    expect(failures).toEqual(["PGRST202", "TypeError"]);

    mode = "hang";
    reporter.record(boom);
    await vi.advanceTimersByTimeAsync(FAILURE_PAUSE_MS);
    expect(send).toHaveBeenCalledTimes(3);
    expect(send.mock.calls[2]?.[1].aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(SEND_TIMEOUT_MS);
    expect(send.mock.calls[2]?.[1].aborted).toBe(true);
    expect(failures).toEqual(["PGRST202", "TypeError", "timeout"]);
    await expect(reporter.flush()).resolves.toBeUndefined();
    expect(calls).toEqual([1, 1, 1]);
  });

  it("survives a failure handler and an enabled check that throw", async () => {
    const reporter = createErrorReporter({
      enabled: () => true,
      send: () => Promise.reject(new Error("no")),
      onFailure: () => {
        throw new Error("logging failed");
      },
    });
    expect(() => reporter.record(boom)).not.toThrow();
    await vi.advanceTimersByTimeAsync(0);
    const broken = createErrorReporter({
      enabled: () => {
        throw new Error("no environment");
      },
      send: () => Promise.resolve(),
    });
    expect(() => broken.record(boom)).not.toThrow();
    expect(broken.pending()).toBe(0);
  });

  it("does nothing when it is not enabled", async () => {
    const { reporter, send } = setup({ enabled: () => false });
    for (let i = 0; i < 100; i++) reporter.record(boom);
    await vi.advanceTimersByTimeAsync(FLUSH_INTERVAL_MS * 3);
    await reporter.flush();
    expect(send).not.toHaveBeenCalled();
    expect(reporter.pending()).toBe(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("does not send while a report is on its way", async () => {
    let release: () => void = () => undefined;
    const { reporter, send } = setup({ send: () => new Promise<void>((resolve) => (release = resolve)) });
    reporter.record(boom);
    reporter.record(boom);
    await reporter.flush();
    expect(send).toHaveBeenCalledTimes(1);
    release();
    await vi.advanceTimersByTimeAsync(FLUSH_INTERVAL_MS);
    expect(send).toHaveBeenCalledTimes(2);
  });
});

describe("reportItem", () => {
  it("keeps the route template without query or fragment, and cuts every field", () => {
    expect(reportItem({ route: "/leads/[id]?email=asha@example.com#top", name: "TypeError" })).toEqual({
      route: "/leads/[id]",
      name: "TypeError",
      message: null,
      digest: null,
      kind: null,
    });
    const long = reportItem({
      route: `/${"a".repeat(500)}`,
      name: "N".repeat(100),
      message: `  many\n  words ${"x".repeat(500)}`,
      digest: "d".repeat(100),
      kind: "k".repeat(100),
    });
    expect(long.route).toHaveLength(200);
    expect(long.name).toHaveLength(60);
    expect(long.message).toHaveLength(200);
    expect(long.message?.startsWith("many words x")).toBe(true);
    expect(long.digest).toHaveLength(64);
    expect(long.kind).toHaveLength(20);
  });

  it("replaces a name, digest or kind that is not one, and copes with nothing", () => {
    expect(
      reportItem({ route: "", name: "asha@example.com", digest: "a b", kind: "Render 1", message: "   " }),
    ).toEqual({
      route: "(unknown)",
      name: "Error",
      message: null,
      digest: null,
      kind: null,
    });
    expect(reportItem({ route: undefined as unknown as string, name: null }).route).toBe("(unknown)");
  });
});

describe("where it reports from", () => {
  it("only a hosted https Supabase address counts", () => {
    expect(isHostedSupabaseUrl("https://abcdefghijklmnopqrst.supabase.co")).toBe(true);
    expect(isHostedSupabaseUrl("https://db.example.com")).toBe(true);
    for (const url of [
      undefined,
      null,
      "",
      "not a url",
      "http://abcdefghijklmnopqrst.supabase.co",
      "http://127.0.0.1:54321",
      "https://127.0.0.1:54321",
      "http://localhost:54321",
      "https://localhost",
      "https://kong:8000",
      "https://host.docker.internal:54321",
      "https://supabase.local",
      "https://10.0.0.5",
      "https://192.168.1.10",
      "https://172.20.0.2",
      "https://[::1]:54321",
    ])
      expect(isHostedSupabaseUrl(url), String(url)).toBe(false);
  });

  it("needs a production build, the address and the service key", () => {
    const env = { nodeEnv: "production", url: "https://abcdefghijklmnopqrst.supabase.co", serviceKey: "k".repeat(40) };
    expect(reportingEnabled(env)).toBe(true);
    expect(reportingEnabled({ ...env, nodeEnv: "development" })).toBe(false);
    expect(reportingEnabled({ ...env, nodeEnv: "test" })).toBe(false);
    expect(reportingEnabled({ ...env, serviceKey: undefined })).toBe(false);
    expect(reportingEnabled({ ...env, serviceKey: "" })).toBe(false);
    expect(reportingEnabled({ ...env, url: undefined })).toBe(false);
    expect(reportingEnabled({ ...env, url: "http://127.0.0.1:54321" })).toBe(false);
  });

  it("names a failure by a code, never by its text", () => {
    expect(failureCode(Object.assign(new Error("x"), { code: "PGRST106" }))).toBe("PGRST106");
    expect(failureCode(new TypeError("fetch failed for asha@example.com"))).toBe("TypeError");
    expect(failureCode({ code: "has spaces and asha@example.com" })).toBe("error");
    expect(failureCode("plain")).toBe("error");
  });
});

describe("the file itself", () => {
  it("imports nothing and uses no Node-only API, so it also loads in the edge runtime", () => {
    const source = readFileSync(new URL("./error-report.ts", import.meta.url), "utf8");
    const code = source.replace(/^\s*\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
    expect(code).not.toMatch(/^\s*import\s/m);
    expect(code).not.toMatch(/\brequire\s*\(|\bprocess\.|\bBuffer\b|node:|server-only/);
  });
});
