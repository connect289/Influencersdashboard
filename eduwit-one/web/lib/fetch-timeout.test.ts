import { describe, expect, it } from "vitest";
import { DB_TIMEOUT_MS, fetchWithTimeout, timeoutSignal } from "./fetch-timeout.ts";

// Every database client's fetch ends at 15 s (D-137), and a caller's own signal still aborts sooner. Node's
// AbortSignal.timeout runs on its own timers, not the faked ones, so the waits here are real and short.

/** A fetch that never answers on its own: it settles only when its signal aborts. */
const hanging: typeof fetch = (input, init) =>
  new Promise<Response>((_resolve, reject) => {
    const signal = init?.signal ?? (input instanceof Request ? input.signal : undefined);
    if (!signal) return;
    signal.addEventListener("abort", () => reject(signal.reason), { once: true });
  });

describe("fetchWithTimeout", () => {
  it("is 15 s for the database clients", () => {
    expect(DB_TIMEOUT_MS).toBe(15_000);
  });

  it("gives up on a call that never answers, with a TimeoutError", async () => {
    const started = Date.now();
    await expect(
      fetchWithTimeout(30, hanging)("https://db.test/rest/v1/rpc/x", { method: "POST" }),
    ).rejects.toMatchObject({ name: "TimeoutError" });
    expect(Date.now() - started).toBeGreaterThanOrEqual(25);
  });

  it("keeps the request as it was and adds only the signal", async () => {
    const seen: Array<RequestInit | undefined> = [];
    const f = fetchWithTimeout(1_000, async (_input, init) => {
      seen.push(init);
      return new Response("{}");
    });
    await f("https://db.test/x", { method: "POST", headers: { apikey: "k" }, body: "{}" });
    expect(seen[0]).toMatchObject({ method: "POST", headers: { apikey: "k" }, body: "{}" });
    expect(seen[0]?.signal).toBeInstanceOf(AbortSignal);
    expect(seen[0]?.signal?.aborted).toBe(false);
  });

  it("respects the caller's own signal", async () => {
    const own = new AbortController();
    const p = fetchWithTimeout(60_000, hanging)("https://db.test/x", { signal: own.signal });
    own.abort(new Error("the caller left"));
    await expect(p).rejects.toThrow("the caller left");
  });

  it("and the signal of a Request passed in", async () => {
    const own = new AbortController();
    const p = fetchWithTimeout(60_000, hanging)(new Request("https://db.test/x", { signal: own.signal }));
    own.abort(new Error("gone"));
    await expect(p).rejects.toThrow();
  });
});

describe("timeoutSignal", () => {
  it("is the timeout alone without a caller's signal", async () => {
    const s = timeoutSignal(10);
    expect(s.aborted).toBe(false);
    await new Promise((r) => setTimeout(r, 40));
    expect(s.aborted).toBe(true);
  });

  it("combines both without AbortSignal.any, the first to abort winning", async () => {
    const any = AbortSignal.any;
    try {
      Object.defineProperty(AbortSignal, "any", { value: undefined, configurable: true, writable: true });
      const own = new AbortController();
      const s = timeoutSignal(60_000, own.signal);
      expect(s.aborted).toBe(false);
      own.abort("left");
      expect(s.aborted).toBe(true);
      expect(s.reason).toBe("left");
      const already = new AbortController();
      already.abort("before");
      expect(timeoutSignal(60_000, already.signal).reason).toBe("before");
      const t = timeoutSignal(10, new AbortController().signal);
      await new Promise((r) => setTimeout(r, 40));
      expect(t.aborted).toBe(true);
      expect((t.reason as Error).name).toBe("TimeoutError");
    } finally {
      Object.defineProperty(AbortSignal, "any", { value: any, configurable: true, writable: true });
    }
  });
});
