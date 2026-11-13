import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidateTag: vi.fn() }));
const rpc = vi.fn(async (): Promise<unknown> => undefined);
vi.mock("./db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));

const { isErased, onceOnly, registerOutboxHandler, runOutbox } = await import("./outbox");
const job = (steps: string[] = []) => ({
  id: 7,
  kind: "email_confirmation",
  dedupe_key: "k",
  payload: {},
  attempts: 1,
  request_id: null,
  sent_steps: steps,
});

describe("outbox steps that must not repeat (D-095)", () => {
  it("records a step right after it succeeds and skips it on a retry", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    const send = vi.fn(async () => ({ id: "m1" }));
    const j = job();
    await onceOnly(j, "email", send);
    expect(send).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("web_outbox_mark_sent", { p_id: 7, p_step: "email" });
    // the retry claims the job again with the recorded step
    await onceOnly(job(["email"]), "email", send);
    expect(send).toHaveBeenCalledTimes(1);
  });
  it("a failed send records nothing (the retry sends); a failed record does not fail the job", async () => {
    rpc.mockClear();
    await expect(onceOnly(job(), "email", async () => Promise.reject(new Error("smtp down")))).rejects.toThrow(
      "smtp down",
    );
    expect(rpc).not.toHaveBeenCalled();
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    rpc.mockRejectedValueOnce(new Error("timeout"));
    await expect(onceOnly(job(), "email", async () => ({ id: "m2" }))).resolves.toBeUndefined();
  });
});

describe("jobs emptied by a privacy erasure (D-096)", () => {
  it("are closed without running their handler", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    const handler = vi.fn(async () => undefined);
    registerOutboxHandler("email_confirmation", handler);
    const erased = { ...job(), id: 8, payload: { erased: true } };
    const live = { ...job(), id: 9, payload: { kind: "enquiry", email: "student@example.com" } };
    expect(isErased(erased)).toBe(true);
    expect(isErased(live)).toBe(false);
    expect(isErased({ payload: { erased: "true" } })).toBe(false);
    rpc.mockReset();
    rpc.mockImplementation(async (...a: unknown[]) => (a[0] === "web_outbox_claim" ? [erased, live] : undefined));
    await expect(runOutbox()).resolves.toEqual({ claimed: 2, done: 2, failed: 0 });
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler).toHaveBeenCalledWith(live);
    expect(rpc).toHaveBeenCalledWith("web_outbox_done", { p_id: 8 });
    expect(rpc).toHaveBeenCalledWith("web_outbox_done", { p_id: 9 });
  });
});
