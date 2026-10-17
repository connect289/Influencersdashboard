import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: vi.fn() }));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));

const { adminCodeHash, hasRole, newCode, signMfa, verifyMfa } = await import("./admin");

describe("admin second factor", () => {
  it("codes are 6 digits", () => {
    for (let i = 0; i < 50; i++) expect(newCode()).toMatch(/^\d{6}$/);
  });
  it("code hashes are bound to the user", () => {
    expect(adminCodeHash("u1", "123456")).not.toBe(adminCodeHash("u2", "123456"));
    expect(adminCodeHash("u1", "123456")).toBe(adminCodeHash("u1", "123456"));
  });
  it("MFA proof is bound to user and session, expires, and resists tampering", () => {
    const now = 1_800_000_000_000;
    const v = signMfa("u1", "s1", now);
    expect(verifyMfa(v, "u1", "s1", now + 1000)).toBe(true);
    expect(verifyMfa(v, "u2", "s1", now)).toBe(false);
    expect(verifyMfa(v, "u1", "s2", now)).toBe(false);
    expect(verifyMfa(v, "u1", "s1", now + 13 * 3600_000)).toBe(false);
    expect(
      verifyMfa(
        v.replace(/.$/, (c) => (c === "A" ? "B" : "A")),
        "u1",
        "s1",
        now,
      ),
    ).toBe(false);
    expect(verifyMfa(undefined, "u1", "s1", now)).toBe(false);
  });
  it("roles are ordered", () => {
    expect(hasRole({ role: "super_admin" }, "content_editor")).toBe(true);
    expect(hasRole({ role: "viewer" }, "content_editor")).toBe(false);
  });
});
