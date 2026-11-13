import { beforeEach, describe, expect, it, vi } from "vitest";

// M34j: the unsubscribe link's input checks, and how the one database call's answers are read.
const rpc = vi.hoisted(() => vi.fn());
const admin = vi.hoisted(() => ({ fail: false }));
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => {
    if (admin.fail) throw new Error("Missing environment variable SUPABASE_SERVICE_ROLE_KEY");
    return { rpc: (fn: string, args: unknown) => ({ abortSignal: () => rpc(fn, args) }) };
  },
}));

import { isOneClickBody, parseUnsubscribeLink, recordUnsubscribe, retryAfterSeconds } from "./unsubscribe";

const TOKEN = "0123456789abcdef0123456789abcdef01234567";
const LINK = { lead: "4821", token: TOKEN };

describe("parseUnsubscribeLink", () => {
  it("accepts a lead id and a 40-character lowercase hex token", () => {
    expect(parseUnsubscribeLink(LINK)).toEqual(LINK);
    expect(parseUnsubscribeLink({ lead: "999999999999999999", token: TOKEN })).not.toBeNull();
  });
  it("refuses any other lead id", () => {
    for (const lead of ["", "0", "012", "-1", "1.5", "1e3", "12a", " 12", "1234567890123456789", "١٢", "12/..", undefined, null, 12, ["12"]]) {
      expect(parseUnsubscribeLink({ lead, token: TOKEN })).toBeNull();
    }
  });
  it("refuses any other token", () => {
    for (const token of ["", TOKEN.slice(1), `${TOKEN}0`, TOKEN.toUpperCase(), TOKEN.replace("0", "g"), `${TOKEN.slice(0, 39)} `, `${TOKEN.slice(0, 39)}\n`,
      "../../../../../../../../../../../../etc/pw", undefined, null, 5, [TOKEN]]) {
      expect(parseUnsubscribeLink({ lead: "4821", token })).toBeNull();
    }
  });
});

describe("isOneClickBody (RFC 8058)", () => {
  const form = (v: Record<string, string>) => new URLSearchParams(v);
  it("accepts exactly List-Unsubscribe=One-Click", () => {
    expect(isOneClickBody(form({ "List-Unsubscribe": "One-Click" }))).toBe(true);
  });
  it("refuses an empty form, another value and another field", () => {
    expect(isOneClickBody(form({}))).toBe(false);
    expect(isOneClickBody(form({ "List-Unsubscribe": "one-click" }))).toBe(false);
    expect(isOneClickBody(form({ "List-Unsubscribe": "" }))).toBe(false);
    expect(isOneClickBody(form({ "list-unsubscribe": "One-Click" }))).toBe(false);
    expect(isOneClickBody(form({ unsubscribe: "1" }))).toBe(false);
  });
});

describe("retryAfterSeconds", () => {
  it("reads the hint of SQLSTATE P0429 and falls back to a minute", () => {
    expect(retryAfterSeconds("retry after 17 seconds")).toBe(17);
    for (const hint of [null, undefined, "", "soon", "retry after 0 seconds", "retry after 999 seconds"]) expect(retryAfterSeconds(hint)).toBe(60);
  });
});

describe("recordUnsubscribe", () => {
  const log = vi.spyOn(console, "error").mockImplementation(() => {});
  beforeEach(() => { rpc.mockReset(); log.mockClear(); admin.fail = false; });

  it("calls b2b.unsubscribe once, for email, with the lead id as text", async () => {
    rpc.mockResolvedValue({ data: true, error: null });
    expect(await recordUnsubscribe(LINK, "203.0.113.7", "one_click")).toEqual({ kind: "done" });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("unsubscribe", { p_lead: "4821", p_token: TOKEN, p_channel: "email", p_ip: "203.0.113.7", p_source: "one_click" });
  });
  it("answers a token that is not this lead's exactly like a valid one", async () => {
    rpc.mockResolvedValueOnce({ data: true, error: null }).mockResolvedValueOnce({ data: false, error: null });
    const valid = await recordUnsubscribe(LINK, null, "link");
    const invalid = await recordUnsubscribe(LINK, null, "link");
    expect(invalid).toEqual(valid);
    expect(log).not.toHaveBeenCalled();
  });
  it("reads the rate limit and its wait", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "P0429", message: "rate limited: too many unsubscribe requests", hint: "retry after 23 seconds" } });
    expect(await recordUnsubscribe(LINK, null, "link")).toEqual({ kind: "rate_limited", retryAfter: 23 });
  });
  it("treats any other failure as unavailable and logs a code, never the lead or the token", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "57014", message: `canceling statement for lead 4821 token ${TOKEN}` } });
    expect(await recordUnsubscribe(LINK, null, "link")).toEqual({ kind: "unavailable" });
    rpc.mockRejectedValue(new Error(`fetch failed for ${TOKEN}`));
    expect(await recordUnsubscribe(LINK, null, "link")).toEqual({ kind: "unavailable" });
    admin.fail = true;
    expect(await recordUnsubscribe(LINK, null, "link")).toEqual({ kind: "unavailable" });
    expect(log).toHaveBeenCalledTimes(3);
    const lines = log.mock.calls.map((c) => String(c[0]));
    expect(lines[0]).toBe(JSON.stringify({ event: "unsubscribe_failed", code: "57014" }));
    for (const line of lines) {
      expect(line).not.toContain(TOKEN);
      expect(line).not.toContain("4821");
    }
  });
});
