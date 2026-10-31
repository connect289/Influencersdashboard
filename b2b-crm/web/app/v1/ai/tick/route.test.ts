import { beforeEach, describe, expect, it, vi } from "vitest";
import { carriesKey, presentedKey } from "@/lib/worker-auth";

const rpc = vi.fn();
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ schema: () => ({ rpc }) }) }));

const KEY = "eb2b_test_worker_key_0123456789abcdef";
const call = async (headers?: Record<string, string>) => {
  const { POST } = await import("./route");
  return POST(new Request("https://crm.example/v1/ai/tick", { method: "POST", headers }));
};

describe("M34f: /v1/ai/tick answers only the worker key", () => {
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockResolvedValue({ data: { ok: true, result: { run: null } }, error: null });
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "test-publishable-key";
    process.env.AI_WORKER_KEY = KEY;
    process.env.ANTHROPIC_API_KEY = "test-anthropic-key";
  });

  it("refuses a call without the key, and touches nothing", async () => {
    const res = await call();
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("refuses a wrong key, and says nothing about the server", async () => {
    const res = await call({ authorization: `Bearer ${KEY}x` });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ ok: false, error: "unauthorized" });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("refuses everyone while AI_WORKER_KEY is not set", async () => {
    delete process.env.AI_WORKER_KEY;
    const res = await call({ authorization: "Bearer anything-at-all-0123456789" });
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("runs for the worker key, as the database sends it", async () => {
    const res = await call({ authorization: `Bearer ${KEY}` });
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith("api_ai_claim", expect.objectContaining({ p_key: KEY }));
  });
});

describe("worker key helpers", () => {
  it("reads a Bearer token or x-internal-key", () => {
    expect(presentedKey(new Headers({ authorization: "Bearer abc" }))).toBe("abc");
    expect(presentedKey(new Headers({ "x-internal-key": "xyz" }))).toBe("xyz");
    expect(presentedKey(new Headers({ authorization: "Basic abc" }))).toBe("");
  });
  it("matches only the exact key", () => {
    expect(carriesKey(new Headers({ authorization: `Bearer ${KEY}` }), KEY)).toBe(true);
    expect(carriesKey(new Headers({ authorization: "Bearer short" }), KEY)).toBe(false);
    expect(carriesKey(new Headers(), KEY)).toBe(false);
    expect(carriesKey(new Headers({ authorization: `Bearer ${KEY}` }), undefined)).toBe(false);
  });
});
