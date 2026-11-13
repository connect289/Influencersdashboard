import { beforeEach, describe, expect, it, vi } from "vitest";

// M34j: POST /u/<lead>/<token>/one-click, the List-Unsubscribe-Post address (RFC 8058). Input checks come first and reach
// the database only for a link of the right shape with the one-click form; the answer never says whether a token was valid.
const rpc = vi.hoisted(() => vi.fn());
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({ rpc: (fn: string, args: unknown) => ({ abortSignal: () => rpc(fn, args) }) }),
}));

import { GET, POST } from "./route";

const TOKEN = "0123456789abcdef0123456789abcdef01234567";
const ctx = (lead: string, token: string) => ({ params: Promise.resolve({ lead, token }) });
const post = (init: RequestInit = {}, lead = "4821", token = TOKEN) =>
  POST(new Request(`https://crm.example/u/${lead}/${token}/one-click`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", "x-forwarded-for": "203.0.113.7, 10.0.0.1" },
    body: "List-Unsubscribe=One-Click",
    ...init,
  }), ctx(lead, token));

describe("POST /u/[lead]/[token]/one-click", () => {
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockResolvedValue({ data: true, error: null });
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  it("records the opt-out for the one-click form, without cookies or a CSRF token", async () => {
    const res = await post();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("set-cookie")).toBeNull();
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("unsubscribe", { p_lead: "4821", p_token: TOKEN, p_channel: "email", p_ip: "203.0.113.7", p_source: "one_click" });
  });

  it("accepts the multipart form too", async () => {
    const form = new FormData();
    form.set("List-Unsubscribe", "One-Click");
    const res = await POST(new Request(`https://crm.example/u/4821/${TOKEN}/one-click`, { method: "POST", body: form }), ctx("4821", TOKEN));
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith("unsubscribe", expect.objectContaining({ p_ip: null, p_source: "one_click" }));
  });

  it("answers a token that is not this lead's exactly like a valid one", async () => {
    const valid = await post();
    rpc.mockResolvedValue({ data: false, error: null });
    const invalid = await post();
    expect(invalid.status).toBe(valid.status);
    expect(await invalid.json()).toEqual(await valid.json());
    expect([...invalid.headers.entries()].sort()).toEqual([...valid.headers.entries()].sort());
  });

  it("answers 404 for an address of the wrong shape, without asking the database", async () => {
    for (const [lead, token] of [["abc", TOKEN], ["0", TOKEN], ["-4", TOKEN], ["1234567890123456789", TOKEN], ["4821", "short"],
      ["4821", TOKEN.toUpperCase()], ["4821", `${TOKEN}0`], ["4821", TOKEN.slice(0, 39) + "z"]] as const) {
      const res = await post({}, lead, token);
      expect(res.status).toBe(404);
      expect(await res.json()).toEqual({ ok: false, error: "not an unsubscribe link" });
    }
    expect(rpc).not.toHaveBeenCalled();
  });

  it("answers 400 unless the body is the one-click form, without asking the database", async () => {
    const bodies: RequestInit[] = [
      { body: "" },
      { body: "List-Unsubscribe=Yes" },
      { body: "list-unsubscribe=One-Click" },
      { body: "unsubscribe=1" },
      { body: JSON.stringify({ "List-Unsubscribe": "One-Click" }), headers: { "content-type": "application/json" } },
      { body: "List-Unsubscribe=One-Click", headers: { "content-type": "text/plain" } },
      { body: `List-Unsubscribe=One-Click&pad=${"x".repeat(3000)}`, headers: { "content-type": "application/x-www-form-urlencoded", "content-length": "3033" } },
    ];
    for (const init of bodies) {
      const res = await post(init);
      expect(res.status).toBe(400);
      expect((await res.json()).ok).toBe(false);
    }
    expect(rpc).not.toHaveBeenCalled();
  });

  it("passes the database's rate limit on as 429 with Retry-After", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "P0429", message: "rate limited: too many unsubscribe requests", hint: "retry after 31 seconds" } });
    const res = await post();
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("31");
    expect(await res.json()).toEqual({ ok: false, error: "rate limited: too many requests", error_code: "rate_limited", retry_after: 31 });
  });

  it("answers 503 when the database does not answer, so the mail provider can retry", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST301", message: "upstream" } });
    expect((await post()).status).toBe(503);
    rpc.mockRejectedValue(new Error("fetch failed"));
    const res = await post();
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ ok: false, error: "the request could not be recorded, try again shortly" });
  });

  it("ignores a malformed caller address rather than passing it on", async () => {
    await post({ headers: { "content-type": "application/x-www-form-urlencoded", "x-forwarded-for": "<script>, 10.0.0.1" } });
    expect(rpc).toHaveBeenCalledWith("unsubscribe", expect.objectContaining({ p_ip: null }));
  });
});

describe("GET /u/[lead]/[token]/one-click", () => {
  beforeEach(() => rpc.mockReset());

  it("sends a mail client that opens the address to the confirm page, and unsubscribes nobody", async () => {
    const res = await GET(new Request(`https://evil.example/u/4821/${TOKEN}/one-click`), ctx("4821", TOKEN));
    expect(res.status).toBe(303);
    expect(res.headers.get("location")).toBe(`/u/4821/${TOKEN}`); // relative: never built from the request's host
    expect(rpc).not.toHaveBeenCalled();
  });

  it("answers 404 for an address of the wrong shape", async () => {
    const res = await GET(new Request("https://crm.example/u/x/y/one-click"), ctx("x", "//evil.example"));
    expect(res.status).toBe(404);
    expect(res.headers.get("location")).toBeNull();
    expect(rpc).not.toHaveBeenCalled();
  });
});
