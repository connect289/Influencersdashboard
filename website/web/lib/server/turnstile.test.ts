import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const state = { shared: false, headroom: true };
vi.mock("./env", () => ({
  env: () => ({ TURNSTILE_SECRET_KEY: "0x4AAAAAAA-real-looking-secret" }),
  isProduction: () => true,
}));
vi.mock("./kv", () => ({ kvShared: () => state.shared }));
const rateLimit = vi.fn(async () => ({ ok: state.headroom, remaining: state.headroom ? 1 : 0 }));
vi.mock("./rate-limit", () => ({
  rateLimit,
  LIMITS: { turnstileUnreachablePerIp: { name: "turnstile_down_ip", limit: 5, windowSeconds: 3600 } },
}));

const { verifyTurnstile } = await import("./turnstile");

const networkError = () => Promise.reject(new TypeError("fetch failed"));
const html502 = () => Promise.resolve(new Response("<html>Bad gateway</html>", { status: 502 }));

describe("Turnstile when Cloudflare is unreachable (D-095)", () => {
  beforeEach(() => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    rateLimit.mockClear();
  });
  afterEach(() => vi.unstubAllGlobals());

  it("fails closed without the shared store (network error and non-JSON 5xx)", async () => {
    state.shared = false;
    for (const f of [networkError, html502]) {
      vi.stubGlobal("fetch", vi.fn(f));
      expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: false, mocked: false, unreachable: true });
    }
    expect(rateLimit).not.toHaveBeenCalled();
  });

  it("fails open with the shared store while the IP has headroom, closed once it has none", async () => {
    state.shared = true;
    state.headroom = true;
    vi.stubGlobal("fetch", vi.fn(networkError));
    expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: true, mocked: false });
    expect(rateLimit).toHaveBeenCalledWith(expect.objectContaining({ name: "turnstile_down_ip" }), "203.0.113.9");
    state.headroom = false;
    vi.stubGlobal("fetch", vi.fn(html502));
    expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: false, mocked: false, unreachable: true });
  });

  it("a normal answer is used as is; a non-JSON non-5xx answer is a failure, not a pass", async () => {
    state.shared = true;
    state.headroom = true;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => Response.json({ success: true })),
    );
    expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: true, mocked: false });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => Response.json({ success: false, "error-codes": ["invalid-input-response"] })),
    );
    expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: false, mocked: false });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("oops", { status: 200 })),
    );
    expect(await verifyTurnstile("tok", "203.0.113.9")).toEqual({ ok: false, mocked: false });
    expect(rateLimit).not.toHaveBeenCalled();
  });

  it("no token is a failure without asking Cloudflare", async () => {
    const f = vi.fn(networkError);
    vi.stubGlobal("fetch", f);
    expect(await verifyTurnstile(undefined, "203.0.113.9")).toEqual({ ok: false, mocked: false });
    expect(f).not.toHaveBeenCalled();
  });
});
