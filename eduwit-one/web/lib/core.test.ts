import { afterEach, describe, expect, it, vi } from "vitest";
import { breakerOpen, fetchJson, HttpError, resetBreakers } from "./http.ts";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.resetModules();
  resetBreakers();
});

describe("fetchJson", () => {
  it("does not retry a 4xx and opens the breaker after repeated failures", async () => {
    const fetchMock = vi.fn(async () => new Response("no", { status: 403 }));
    vi.stubGlobal("fetch", fetchMock);
    const policy = { timeoutMs: 100, retries: 2, breakerFailures: 2, breakerCooldownMs: 60_000 };
    await expect(fetchJson("t", "https://x.test/a", {}, policy)).rejects.toMatchObject({
      category: "status",
      status: 403,
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await expect(fetchJson("t", "https://x.test/a", {}, policy)).rejects.toBeInstanceOf(HttpError);
    expect(breakerOpen("t")).toBe(true);
    await expect(fetchJson("t", "https://x.test/a", {}, policy)).rejects.toMatchObject({ category: "breaker_open" });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("retries a 503 and returns the JSON of the next answer", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response("busy", { status: 503 }))
      .mockResolvedValueOnce(Response.json({ a: 1 }));
    vi.stubGlobal("fetch", fetchMock);
    const r = await fetchJson(
      "r",
      "https://x.test/b",
      {},
      { timeoutMs: 100, retries: 1, breakerFailures: 3, breakerCooldownMs: 1 },
    );
    expect(r.json).toEqual({ a: 1 });
  });

  it("never puts the URL or the body in the error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("secret-body", { status: 404 })),
    );
    const err = await fetchJson(
      "e",
      "https://user:pw@x.test/c?token=abc",
      {},
      { timeoutMs: 100, retries: 0, breakerFailures: 9, breakerCooldownMs: 1 },
    ).catch((e: unknown) => e);
    expect(String(err)).not.toMatch(/pw|token|secret-body/);
  });
});

describe("internal bearer check", () => {
  const req = (auth?: string) =>
    new Request("https://one.test/api/internal/tick", { headers: auth ? { authorization: auth } : {} });

  it("accepts only the configured key", async () => {
    vi.stubEnv("ONE_INTERNAL_KEY", "k".repeat(40));
    const { internalAuthorized } = await import("./auth.ts");
    expect(await internalAuthorized(req(`Bearer ${"k".repeat(40)}`))).toBe(true);
    expect(await internalAuthorized(req(`Bearer ${"k".repeat(39)}x`))).toBe(false);
    expect(await internalAuthorized(req())).toBe(false);
  });

  it("refuses everything when no key is configured", async () => {
    vi.stubEnv("ONE_INTERNAL_KEY", "");
    const { internalAuthorized } = await import("./auth.ts");
    expect(await internalAuthorized(req("Bearer anything-at-all-here-xxxxxxxxxxxxxxx"))).toBe(false);
  });
});

describe("watchdog verdict", () => {
  it("is down when the last finished tick is old, unknown, or an alert email has waited ten minutes", async () => {
    const { watchdogOk } = await import("./watchdog.ts");
    expect(watchdogOk({ tick_age_s: 30, app_age_s: 40, delivery_wait_s: null })).toBe(true);
    expect(watchdogOk({ tick_age_s: 30, app_age_s: 40, delivery_wait_s: 599 })).toBe(true);
    expect(watchdogOk({ tick_age_s: 30, app_age_s: 40, delivery_wait_s: 600 })).toBe(false);
    expect(watchdogOk({ tick_age_s: 300, app_age_s: 40, delivery_wait_s: null })).toBe(false);
    expect(watchdogOk({ tick_age_s: null, app_age_s: null, delivery_wait_s: null })).toBe(false);
    expect(watchdogOk(undefined)).toBe(false);
  });
});
