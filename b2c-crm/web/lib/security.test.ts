import { describe, expect, it } from "vitest";
import { buildCsp, clientIp, isIdleExpired, passwordProblem, safeNext } from "./security";

describe("safeNext", () => {
  it("keeps same-origin paths", () => {
    expect(safeNext("/leads?view=today")).toBe("/leads?view=today");
    expect(safeNext("/")).toBe("/");
  });
  it("rejects anything that could leave the site", () => {
    for (const bad of ["//evil.com", "/\\evil.com", "https://evil.com", "evil.com", "javascript:alert(1)", "/\u0000x", "", null, undefined]) {
      expect(safeNext(bad as string)).toBe("/");
    }
    expect(safeNext("/" + "a".repeat(600))).toBe("/");
  });
});

describe("isIdleExpired", () => {
  const now = 1_800_000_000;
  it("expires after 12 hours of inactivity", () => {
    expect(isIdleExpired(String(now - 12 * 3600 - 1), now)).toBe(true);
    expect(isIdleExpired(String(now - 12 * 3600 + 60), now)).toBe(false);
  });
  it("treats a missing or malformed cookie as not idle", () => {
    expect(isIdleExpired(undefined, now)).toBe(false);
    expect(isIdleExpired("abc", now)).toBe(false);
    expect(isIdleExpired("-5", now)).toBe(false);
  });
});

describe("buildCsp", () => {
  const csp = buildCsp("abc123", "https://x.supabase.co", false);
  it("requires the nonce for scripts and allows no eval in production", () => {
    expect(csp).toContain("script-src 'self' 'nonce-abc123' 'strict-dynamic'");
    expect(csp).not.toContain("unsafe-eval");
  });
  it("allows Supabase over https and websockets only", () => {
    expect(csp).toContain("connect-src 'self' https://x.supabase.co wss://x.supabase.co");
  });
  it("blocks framing and plugins", () => {
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
  });
});

describe("clientIp", () => {
  it("takes the first forwarded address and rejects junk", () => {
    expect(clientIp(new Headers({ "x-forwarded-for": "203.0.113.7, 10.0.0.1" }))).toBe("203.0.113.7");
    expect(clientIp(new Headers({ "x-forwarded-for": "<script>" }))).toBeNull();
    expect(clientIp(new Headers())).toBeNull();
  });
});

describe("passwordProblem", () => {
  it("enforces length and confirmation", () => {
    expect(passwordProblem("short")).toMatch(/12/);
    expect(passwordProblem("a".repeat(129))).toMatch(/128/);
    expect(passwordProblem("correct horse battery", "different")).toMatch(/match/);
    expect(passwordProblem("correct horse battery", "correct horse battery")).toBeNull();
  });
});
