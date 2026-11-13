// The delivery job records every outcome and fails when it cannot: a sent copy is never left looking queued, and a
// retry sends with the same idempotency key.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProviderError } from "@/lib/notify/types";

const h = vi.hoisted(() => ({
  results: [] as { p_id: number; p_status: string; p_error?: string }[],
  resultError: null as null | { message: string },
  sends: [] as { to: string; idempotencyKey?: string; html?: string; text?: string; listUnsubscribeUrl?: string }[],
  sendError: null as Error | null,
  liveMode: "on",
  event: "payout.paid",
  mandatory: true,
  secret: undefined as string | undefined,
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
            event: h.event,
            mandatory: h.mandatory,
            title: "Paid",
            body: "Your payout was paid.",
            link: "/creator/earnings",
            data: {},
          },
          error: null,
        });
      if (table === "notification_deliveries") return query({ data: [{ id: 7, channel: "email" }], error: null });
      if (table === "creator_accounts")
        return query({ data: { creators: { display_name: "Riya Sen", phone_e164: null } }, error: null });
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
  env: () => ({ LIVE_MODE: h.liveMode, NEXT_PUBLIC_SITE_URL: "https://portal.example", UNSUBSCRIBE_SECRET: h.secret }),
}));
vi.mock("@/lib/notify/email", () => ({
  emailProvider: () => ({
    name: "mock",
    send: (m: (typeof h.sends)[number]) => {
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

import { verifyUnsubscribe } from "@/lib/notify/unsubscribe";
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
  h.event = "payout.paid";
  h.mandatory = true;
  h.secret = undefined;
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

  // Unsubscribe links (D-198).
  const SECRET = "unit-test-unsubscribe-secret-0123456789abcdef";
  const USER = "22222222-2222-4222-8222-222222222222";

  it("an email a person can turn off carries the signed link and the one-click address", async () => {
    h.event = "campaign.invited";
    h.mandatory = false;
    h.secret = SECRET;
    await notifyDeliver(job);
    const sent = h.sends[0];
    const oneClick = sent?.listUnsubscribeUrl ?? "";
    expect(oneClick).toMatch(/^https:\/\/portal\.example\/unsubscribe\/v1\.[\w-]+\.[\w-]+\/one-click$/);
    const token = oneClick.split("/").at(-2) ?? "";
    expect(verifyUnsubscribe(SECRET, token)).toEqual({ userId: USER, category: "campaigns" });
    expect(sent?.html).toContain(`href="https://portal.example/unsubscribe/${token}"`);
    expect(sent?.text).toContain(`Stop these emails: https://portal.example/unsubscribe/${token}`);
    expect(sent?.html).toContain('href="https://portal.example/creator/notifications/settings"');
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "sent" })]);
  });

  it("a required notice carries no link and says it is required", async () => {
    h.secret = SECRET;
    await notifyDeliver(job);
    expect(h.sends[0]).not.toHaveProperty("listUnsubscribeUrl");
    expect(h.sends[0]?.html).not.toContain("/unsubscribe/");
    expect(h.sends[0]?.html).toContain("This is a required notice");
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "sent" })]);
  });

  it("a notification the sender marked required carries no link either", async () => {
    h.event = "campaign.invited";
    h.mandatory = true;
    h.secret = SECRET;
    await notifyDeliver(job);
    expect(h.sends[0]).not.toHaveProperty("listUnsubscribeUrl");
    expect(h.sends[0]?.html).not.toContain("/unsubscribe/");
  });

  it("without the signing secret the email is still sent, without the link", async () => {
    h.event = "campaign.invited";
    h.mandatory = false;
    await notifyDeliver(job);
    expect(h.sends).toHaveLength(1);
    expect(h.sends[0]).not.toHaveProperty("listUnsubscribeUrl");
    expect(h.sends[0]?.html).not.toContain("/unsubscribe/");
    expect(h.sends[0]?.html).not.toContain("required notice");
    expect(h.results).toEqual([expect.objectContaining({ p_id: 7, p_status: "sent" })]);
  });
});
