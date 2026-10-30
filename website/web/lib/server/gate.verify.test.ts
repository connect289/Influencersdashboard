import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({
  headers: async () => new Headers({ "x-forwarded-for": "203.0.113.7", "user-agent": "vitest" }),
  cookies: async () => ({ get: () => undefined, set: vi.fn(), delete: vi.fn() }),
}));
const rpc = vi.fn(async (fn: string): Promise<unknown> => {
  if (fn === "web_gate_attempt_info")
    return { key: "enquiry:abcdefgh12", surface: "enquiry", email: "asha@example.com" };
  if (fn === "web_gate_verify")
    return { ok: true, status: "verified", session_id: "6f1c2b9e-4d3a-4b8e-9f0a-1c2d3e4f5a6b", lead_id: 4242 };
  if (fn === "web_application_open") return { ok: true, reference: "EDW-26-ABCDE" };
  throw new Error(`unexpected rpc ${fn}`);
});
vi.mock("./db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));

const { verifyCode } = await import("./gate");

describe("verifyCode", () => {
  it("never hands the CRM's lead id to the browser", async () => {
    const r = await verifyCode("0d6c3b9a-1e2f-4a5b-8c7d-9e0f1a2b3c4d", "123456");
    expect(r).toEqual({
      status: "verified",
      attemptId: "0d6c3b9a-1e2f-4a5b-8c7d-9e0f1a2b3c4d",
      reference: "EDW-26-ABCDE",
    });
    expect(JSON.stringify(r)).not.toContain("4242");
  });
});
