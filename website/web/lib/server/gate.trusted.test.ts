import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({
  headers: async () => new Headers({ "x-forwarded-for": "203.0.113.10", "user-agent": "vitest" }),
  cookies: async () => ({ get: () => undefined, set: vi.fn(), delete: vi.fn() }),
}));
const student = {
  studentId: "0d6c3b9a-1e2f-4a5b-8c7d-9e0f1a2b3c4d",
  sessionId: "s",
  email: "asha@example.com",
  name: "Asha Rao",
  phone: "+919876543211",
  leadId: 1,
};
vi.mock("./student-session", () => ({
  currentStudent: async () => student,
  deviceId: async () => "device-1",
  setStudentSession: vi.fn(),
}));
const limited: string[] = [];
vi.mock("./rate-limit", () => ({
  hashId: (v: string) => v,
  LIMITS: {
    emailCodeSendPerIp: { name: "code_ip" },
    emailCodeSendPerDevice: { name: "code_device" },
    emailCodeSendPerEmail: { name: "code_email" },
  },
  rateLimit: vi.fn(async (l: { name: string }, id: string) => {
    limited.push(`${l.name}:${id}`);
    return { ok: true, remaining: 1 };
  }),
}));
const rpc = vi.fn(async (fn: string): Promise<unknown> => {
  if (fn === "web_gate_start_trusted") return { ok: true, status: "verified", attempt_id: "a1", session_id: "s2" };
  if (fn === "web_gate_start") return { ok: true, status: "code_sent", attempt_id: "a2" };
  if (fn === "web_application_open") return { ok: true, reference: "EDW-26-ABCDE" };
  throw new Error(`unexpected rpc ${fn}`);
});
vi.mock("./db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));

const gate = await import("./gate");
const { CONSENT } = await import("@/content/consent");
const sent: string[] = [];
gate.setEmailVerifier({ name: "test", sendCode: async (to) => void sent.push(to) });

const input = (phone: string, email = "asha@example.com") => ({
  surface: "enquiry" as const,
  name: "Asha Rao",
  phone,
  email,
  consentVersion: CONSENT.form.version,
  age: 25,
  idempotencyKey: `key-${phone.replace(/\D/g, "")}-${email.length}`,
});

describe("signed-in path and per-inbox limits (D-095)", () => {
  it("skips the code only with the phone number on the account", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    const first = await gate.startVerification(input("98765 43211"));
    expect(first).toMatchObject({ status: "verified" });
    expect(rpc).toHaveBeenCalledWith("web_gate_start_trusted", expect.anything());
    rpc.mockClear();
    const other = await gate.startVerification(input("9123456789"));
    expect(other).toMatchObject({ status: "code_sent" });
    expect(rpc.mock.calls.map((c) => c[0])).toEqual(["web_gate_start"]);
    expect(sent).toEqual(["asha@example.com"]);
  });
  it("counts the per-email limit on the inbox, keeps the address as typed", async () => {
    limited.length = 0;
    sent.length = 0;
    await gate.startVerification(input("9123456780", "Asha.R+Fees@GoogleMail.com"));
    expect(limited).toContain("code_email:ashar@gmail.com");
    expect(sent).toEqual(["asha.r+fees@googlemail.com"]);
  });
});

describe("age and parent/guardian consent (privacy policy, 19 Nov 2026)", () => {
  it("refuses a missing age and an under-18 without the guardian consent, before anything is stored", async () => {
    rpc.mockClear();
    const noAge = await gate.startVerification({ ...input("9123456781"), age: undefined });
    expect(noAge).toMatchObject({ status: "error", reason: "age" });
    const minor = await gate.startVerification({ ...input("9123456782"), age: 16 });
    expect(minor).toMatchObject({ status: "error", reason: "guardian" });
    const wrongVersion = await gate.startVerification({ ...input("9123456783"), age: 16, guardianConsentVersion: "old" });
    expect(wrongVersion).toMatchObject({ status: "error", reason: "guardian" });
    expect(rpc).not.toHaveBeenCalled();
  });
  it("sends the age, and the guardian consent version only for a minor", async () => {
    rpc.mockClear();
    await gate.startVerification({ ...input("9123456784"), age: 16, guardianConsentVersion: CONSENT.guardian.version });
    expect(rpc).toHaveBeenCalledWith(
      "web_gate_start",
      expect.objectContaining({ p: expect.objectContaining({ age: 16, guardian_consent_version: CONSENT.guardian.version }) }),
    );
    rpc.mockClear();
    await gate.startVerification({ ...input("9123456785"), age: 30, guardianConsentVersion: CONSENT.guardian.version });
    expect(rpc).toHaveBeenCalledWith(
      "web_gate_start",
      expect.objectContaining({ p: expect.objectContaining({ age: 30, guardian_consent_version: null }) }),
    );
  });
});
