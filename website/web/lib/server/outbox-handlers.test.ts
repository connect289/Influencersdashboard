import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidateTag: vi.fn() }));
const rpc = vi.fn(async (..._a: unknown[]): Promise<unknown> => undefined);
vi.mock("./db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));
const send = vi.fn(async (..._a: unknown[]) => ({ id: "m1" }));
vi.mock("./email", () => ({ email: () => ({ send }) }));
vi.mock("./capi", () => ({ sendCapi: vi.fn() }));
vi.mock("./settings", () => ({ getSettings: vi.fn(async () => ({ counsellor_whatsapp: "+919999999999" })) }));
vi.mock("./env", () => ({ siteUrl: (p = "") => `https://example.test${p}`, env: () => ({}), isDeployed: () => false }));

await import("./outbox-handlers");
const { runOutbox } = await import("./outbox");

const doneJob = (sent: string[] = []) => ({
  id: 31,
  kind: "email_confirmation",
  dedupe_key: "privacy_done:5",
  payload: { kind: "privacy_done", request: "delete", email: "student@example.com" },
  attempts: 1,
  request_id: null,
  sent_steps: sent,
});
const claims = (jobs: unknown[]) =>
  rpc.mockImplementation(async (...a: unknown[]) => (a[0] === "web_outbox_claim" ? jobs : undefined));

describe("the last email of an erasure (D-096)", () => {
  beforeEach(() => {
    rpc.mockReset();
    send.mockClear();
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
  });
  it("is sent to the requester, then the job is emptied and closed", async () => {
    claims([doneJob()]);
    await expect(runOutbox()).resolves.toEqual({ claimed: 1, done: 1, failed: 0 });
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0]).toBe("student@example.com");
    expect((send.mock.calls[0]?.[1] as { subject: string }).subject).toBe("Your data has been deleted");
    const calls = rpc.mock.calls.map((c) => c[0]);
    expect(calls).toEqual(["web_outbox_claim", "web_outbox_mark_sent", "web_outbox_scrub", "web_outbox_done"]);
    expect(rpc).toHaveBeenCalledWith("web_outbox_scrub", { p_id: 31 });
  });
  it("if emptying fails the job is retried, and the retry does not send the email again", async () => {
    rpc.mockImplementation(async (...a: unknown[]) => {
      if (a[0] === "web_outbox_claim") return [doneJob()];
      if (a[0] === "web_outbox_scrub") throw new Error("timeout");
      return undefined;
    });
    await expect(runOutbox()).resolves.toEqual({ claimed: 1, done: 0, failed: 1 });
    expect(send).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("web_outbox_fail", { p_id: 31, p_error: "timeout" });
    rpc.mockReset();
    claims([doneJob(["email"])]);
    await expect(runOutbox()).resolves.toEqual({ claimed: 1, done: 1, failed: 0 });
    expect(send).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("web_outbox_scrub", { p_id: 31 });
  });
});
