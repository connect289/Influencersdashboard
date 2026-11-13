// The delivery job records every outcome and fails when it cannot: a sent copy is never left looking queued, and a
// retry sends with the same idempotency key.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProviderError } from "@/lib/notify/types";

const h = vi.hoisted(() => ({
  results: [] as { p_id: number; p_status: string; p_error?: string }[],
  resultError: null as null | { message: string },
  sends: [] as { to: string; idempotencyKey?: string }[],
  sendError: null as Error | null,
  liveMode: "on",
}));

function query(result: unknown) {
  const q = {
    select: () => q,
    eq: () => q,
    limit: () => q,
    maybeSingle: () => Promise.resolve(result),
    then: (ok: (v: unknown) => unknown) => Promise.resolve(result).then(ok),
  };
  return q;
}

vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({
    from: (table: string) => {
      if (table === "notifications")
        return query({
          data: {
            id: "11111111-1111-4111-8111-111111111111",
            user_id: "22222222-2222-4222-8222-222222222222",
            event: "payout.paid",
            title: "Paid",
            body: "Your payout was paid.",
            link: "/creator/earnings",
            data: {},
          },
          error: null,
        });
      if (table === "notification_deliveries") return query({ data: [{ id: 7, channel: "email" }], error: null });
      return query({ data: null, error: null });
    },
    rpc: (name: string, args: { p_id: number; p_status: string; p_error?: string }) => {
      if (name === "delivery_result") {
        h.results.push(args);
        return Promise.resolve({ data: null, error: h.resultError });
      }
      return Promise.resolve({ data: null, error: null });
    },
    auth: { admin: { getUserById: () => Promise.resolve({ data: { user: { email: "riya@example.test" } } }) } },
  }),
}));
vi.mock("@/lib/env", () => ({
  env: () => ({ LIVE_MODE: h.liveMode, NEXT_PUBLIC_SITE_URL: "https://portal.example" }),
}));
vi.mock("@/lib/notify/email", () => ({
  emailProvider: () => ({
    name: "mock",
    send: (m: { to: string; idempotencyKey?: string }) => {
      if (h.sendError) return Promise.reject(h.sendError);
      h.sends.push(m);
      return Promise.resolve({ provider: "mock", id: "m-1" });
    },
  }),
}));
vi.mock("@/lib/notify/whatsapp", () => ({ whatsAppProvider: () => ({ name: "mock-wa" }) }));
vi.mock("@/lib/log", () => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  errorMessage: (e: unknown) => (e instanceof Error ? e.message : String(e)),
}));

import { notifyDeliver } from "./notify-deliver";

const job = {
  id: 1,
  kind: "notify.deliver",
  payload: { notification_id: "11111111-1111-4111-8111-111111111111" },
  attempts: 1,
  max_attempts: 8,
};

beforeEach(() => {
  h.results = [];
  h.resultError = null;
  h.sends = [];
  h.sendError = null;
  h.liveMode = "on";
});

describe("notify.deliver", () => {
  it("sends with the delivery's idempotency key and records it as sent", async () => {
    await notifyDeliver(job);
    expect(h.sends).toEqual([expect.objectContaining({ to: "riya@example.test", idempotencyKey: "delivery:7" })]);
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "sent" })]);
  });

  it("fails the job when the sent copy cannot be recorded", async () => {
    h.resultError = { message: "connection reset" };
    await expect(notifyDeliver(job)).rejects.toThrow(/could not record delivery 7 as sent/);
    expect(h.sends).toHaveLength(1);
  });

  it("fails the job when live mode is off and the skip cannot be recorded", async () => {
    h.liveMode = "off";
    h.resultError = { message: "timeout" };
    await expect(notifyDeliver(job)).rejects.toThrow(/as skipped/);
    expect(h.sends).toHaveLength(0);
  });

  it("keeps a retryable failure queued and fails the job so it runs again", async () => {
    h.sendError = new ProviderError("HTTP 409: concurrent request", true);
    await expect(notifyDeliver(job)).rejects.toThrow(/409/);
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "queued" })]);
  });

  it("marks a permanent failure failed without failing the job", async () => {
    h.sendError = new ProviderError("HTTP 422: invalid address", false);
    await notifyDeliver(job);
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "failed" })]);
  });
});
