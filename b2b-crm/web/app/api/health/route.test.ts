import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The real Supabase client runs here; only the network is replaced, so these are the answers the installed client gives.
const fetchMock = vi.fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>();
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const HEALTHY = { ok: true, at: "2026-11-10T10:00:00+00:00", jobs: { stale: 0, last_run_failed: 0 }, deliveries: { dead_7d: 0, waiting_over_1h: 0 }, b2c_sync: { cursor_age_seconds: 12 } };
const call = async () => (await import("./route")).GET();

describe("GET /api/health", () => {
  beforeEach(() => {
    vi.resetModules(); // each test starts without a cached reading
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "test-publishable-key";
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("answers 200 with the database's reading when it says ok", async () => {
    fetchMock.mockResolvedValue(json(HEALTHY));
    const res = await call();
    expect(res.status).toBe(200);
    expect(res.headers.get("Cache-Control")).toBe("no-store");
    expect(await res.json()).toEqual(HEALTHY);
    expect(String(fetchMock.mock.calls[0]?.[0])).toBe("https://example.supabase.co/rest/v1/rpc/health_check");
  });

  it("answers 503 with the same reading when it says not ok", async () => {
    const unhealthy = { ...HEALTHY, ok: false, jobs: { stale: 2, last_run_failed: 1 } };
    fetchMock.mockResolvedValue(json(unhealthy));
    const res = await call();
    expect(res.status).toBe(503);
    expect(res.headers.get("Cache-Control")).toBe("no-store");
    expect(await res.json()).toEqual(unhealthy);
  });

  it("answers 503 when the database call fails", async () => {
    fetchMock.mockResolvedValue(json({ code: "57014", message: "canceling statement due to statement timeout", details: null, hint: null }, 500));
    const res = await call();
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ ok: false, error: "database not answering" });
  });

  it("gives the database 3 s, then answers 503", async () => {
    const realTimeout = AbortSignal.timeout.bind(AbortSignal);
    const timeout = vi.spyOn(AbortSignal, "timeout").mockImplementation(() => realTimeout(20)); // 3 s in the route, 20 ms here
    // a database that never answers: the call ends only when its signal aborts
    fetchMock.mockImplementation((_input, init) => new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal?.reason));
    }));
    const res = await call();
    expect(timeout).toHaveBeenCalledWith(3_000);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ ok: false, error: "database not answering" });
    expect(fetchMock).toHaveBeenCalledTimes(1); // an aborted call is not tried again
  });

  it("serves one reading for 15 s, then reads again", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-10T10:00:00Z"));
    fetchMock.mockImplementation(async () => json(HEALTHY));
    const { GET } = await import("./route");
    expect((await GET()).status).toBe(200);
    vi.setSystemTime(new Date("2026-11-10T10:00:15Z"));
    fetchMock.mockImplementation(async () => json({ ...HEALTHY, ok: false }));
    const again = await GET();
    expect(again.status).toBe(200); // still the first reading
    expect(await again.json()).toEqual(HEALTHY);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    vi.setSystemTime(new Date("2026-11-10T10:00:15.001Z"));
    expect((await GET()).status).toBe(503);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("is bounded at 10 s", async () => {
    expect((await import("./route")).maxDuration).toBe(10);
  });
});
