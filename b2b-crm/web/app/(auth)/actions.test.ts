import { beforeEach, describe, expect, it, vi } from "vitest";

// M34i: the password step locks per email and client IP; the code step (after a correct password) asks for step "totp",
// which counts only failed codes, so strangers' wrong passwords never block the Admin's second factor.
const auth = vi.hoisted(() => ({
  isLocked: vi.fn(),
  recordSignIn: vi.fn(),
  fetchMe: vi.fn(),
  acceptTeamInvite: vi.fn(),
  isAllowlistedEmail: vi.fn(),
}));
const sb = vi.hoisted(() => ({
  signInWithPassword: vi.fn(),
  signOut: vi.fn(),
  listFactors: vi.fn(),
  challengeAndVerify: vi.fn(),
}));

vi.mock("@/lib/auth", () => auth);
vi.mock("@/lib/env", () => ({ siteUrl: () => "https://crm.example.in" }));
vi.mock("next/headers", () => ({
  headers: async () => new Headers({ "x-forwarded-for": "203.0.113.7, 10.0.0.1", "user-agent": "vitest" }),
}));
vi.mock("next/navigation", () => ({ redirect: (to: string) => { throw new Error(`redirect:${to}`); } }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: {
      signInWithPassword: sb.signInWithPassword,
      signOut: sb.signOut,
      mfa: { listFactors: sb.listFactors, challengeAndVerify: sb.challengeAndVerify },
    },
  }),
}));

import { signInWithPassword, verifyTotp } from "./actions";

const ME = { user_id: "u1", email: "connect@eduwit.in", aal: "aal1", allowlisted: true, role: "admin", require_totp: true, is_admin: false };
const form = (v: Record<string, string>) => {
  const f = new FormData();
  for (const [k, x] of Object.entries(v)) f.set(k, x);
  return f;
};

beforeEach(() => {
  for (const f of [...Object.values(auth), ...Object.values(sb)]) f.mockReset();
  auth.fetchMe.mockResolvedValue({ me: ME });
  sb.listFactors.mockResolvedValue({ data: { totp: [{ id: "f1", status: "verified" }] } });
});

describe("signInWithPassword lockout (M34i)", () => {
  it("checks the lock for this email and client IP at the password step", async () => {
    auth.isLocked.mockResolvedValue(false);
    sb.signInWithPassword.mockResolvedValue({ data: { user: null }, error: { code: "invalid_credentials" } });
    const out = await signInWithPassword(undefined, form({ email: "Connect@Eduwit.in", password: "wrong" }));
    expect(out).toEqual({ error: "Email or password is incorrect." });
    expect(auth.isLocked).toHaveBeenCalledWith("connect@eduwit.in", "203.0.113.7", "password");
    expect(auth.recordSignIn).toHaveBeenCalledWith(expect.objectContaining({ outcome: "failed_password", ip: "203.0.113.7" }));
  });
  it("refuses without trying the password while this IP is locked, and logs it", async () => {
    auth.isLocked.mockResolvedValue(true);
    const out = await signInWithPassword(undefined, form({ email: "connect@eduwit.in", password: "x" }));
    expect(out?.error).toMatch(/locked for 15 minutes/);
    expect(sb.signInWithPassword).not.toHaveBeenCalled();
    expect(auth.recordSignIn).toHaveBeenCalledWith(expect.objectContaining({ outcome: "locked", method: "password", ip: "203.0.113.7" }));
  });
});

describe("verifyTotp lockout (M34i)", () => {
  it("asks for the code step's lock, never the password step's", async () => {
    auth.isLocked.mockResolvedValue(false);
    sb.challengeAndVerify.mockResolvedValue({ error: null });
    await expect(verifyTotp(undefined, form({ code: "123456", next: "/leads" }))).rejects.toThrow("redirect:/leads");
    expect(auth.isLocked).toHaveBeenCalledTimes(1);
    expect(auth.isLocked).toHaveBeenCalledWith("connect@eduwit.in", "203.0.113.7", "totp");
    expect(auth.recordSignIn).toHaveBeenCalledWith(expect.objectContaining({ method: "totp", outcome: "success" }));
  });
  it("a wrong code is logged as failed_totp and checked again at the code step", async () => {
    auth.isLocked.mockResolvedValue(false);
    sb.challengeAndVerify.mockResolvedValue({ error: { code: "mfa_verification_failed" } });
    const out = await verifyTotp(undefined, form({ code: "000000" }));
    expect(out?.error).toMatch(/did not match/);
    expect(auth.recordSignIn).toHaveBeenCalledWith(expect.objectContaining({ outcome: "failed_totp" }));
    expect(auth.isLocked.mock.calls.map((c) => c[2])).toEqual(["totp", "totp"]);
  });
  it("signs out and sends to /login when the code step is locked", async () => {
    auth.isLocked.mockResolvedValue(true);
    await expect(verifyTotp(undefined, form({ code: "123456" }))).rejects.toThrow("redirect:/login?error=locked");
    expect(sb.signOut).toHaveBeenCalled();
    expect(sb.challengeAndVerify).not.toHaveBeenCalled();
  });
});
