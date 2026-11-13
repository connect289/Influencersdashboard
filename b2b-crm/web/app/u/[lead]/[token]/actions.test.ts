import { beforeEach, describe, expect, it, vi } from "vitest";

// M34j: the confirm button on /u/<lead>/<token>. The server action is a public POST: its two fields are checked again.
const rpc = vi.hoisted(() => vi.fn());
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({ rpc: (fn: string, args: unknown) => ({ abortSignal: () => rpc(fn, args) }) }),
}));
vi.mock("next/headers", () => ({ headers: async () => new Headers({ "x-forwarded-for": "203.0.113.9, 10.0.0.1" }) }));

import { confirmUnsubscribe } from "./actions";

const TOKEN = "0123456789abcdef0123456789abcdef01234567";
const form = (v: Record<string, string>) => {
  const f = new FormData();
  for (const [k, x] of Object.entries(v)) f.set(k, x);
  return f;
};

describe("confirmUnsubscribe", () => {
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockResolvedValue({ data: true, error: null });
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  it("records the opt-out as source 'link' with the caller's address", async () => {
    expect(await confirmUnsubscribe(undefined, form({ lead: "4821", token: TOKEN }))).toEqual({ status: "done" });
    expect(rpc).toHaveBeenCalledWith("unsubscribe", { p_lead: "4821", p_token: TOKEN, p_channel: "email", p_ip: "203.0.113.9", p_source: "link" });
  });

  it("shows the same result for a token that is not this lead's", async () => {
    rpc.mockResolvedValue({ data: false, error: null });
    expect(await confirmUnsubscribe(undefined, form({ lead: "4821", token: TOKEN }))).toEqual({ status: "done" });
  });

  it("refuses fields of the wrong shape without asking the database", async () => {
    for (const v of [{}, { lead: "4821" }, { token: TOKEN }, { lead: "abc", token: TOKEN }, { lead: "4821", token: "nope" }, { lead: "4821", token: TOKEN.toUpperCase() }]) {
      const state = await confirmUnsubscribe(undefined, form(v as Record<string, string>));
      expect(state?.status).toBe("error");
    }
    expect(rpc).not.toHaveBeenCalled();
  });

  it("asks the student to try again when the limit is reached or the database does not answer, and never says done", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "P0429", message: "rate limited", hint: "retry after 40 seconds" } });
    const busy = await confirmUnsubscribe(undefined, form({ lead: "4821", token: TOKEN }));
    expect(busy).toEqual({ status: "error", message: expect.stringContaining("wait a minute") });
    rpc.mockResolvedValue({ data: null, error: { code: "57014", message: "timeout" } });
    const down = await confirmUnsubscribe(undefined, form({ lead: "4821", token: TOKEN }));
    expect(down).toEqual({ status: "error", message: expect.stringContaining("try again") });
  });
});
