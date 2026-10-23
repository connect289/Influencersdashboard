import { describe, expect, it } from "vitest";
import { buildCsp, clientIp, isAllowedEmail, isIdleExpired, safeNext } from "./security.ts";

describe("safeNext", () => {
  it("keeps same-origin paths and refuses everything that could leave the app", () => {
    expect(safeNext("/incidents/4?x=1")).toBe("/incidents/4?x=1");
    for (const bad of [
      "//evil.test",
      "/\\evil.test",
      "https://evil.test",
      "javascript:alert(1)",
      "/a\nb",
      "",
      null,
      undefined,
      "x".repeat(600),
    ]) {
      expect(safeNext(bad)).toBe("/");
    }
  });
});

describe("isIdleExpired", () => {
  it("is idle only past the limit, and never on a missing or bad value", () => {
    expect(isIdleExpired("1000", 1000 + 12 * 3600 + 1)).toBe(true);
    expect(isIdleExpired("1000", 1000 + 12 * 3600)).toBe(false);
    expect(isIdleExpired(undefined, 10)).toBe(false);
    expect(isIdleExpired("abc", 10)).toBe(false);
  });
});

describe("buildCsp", () => {
  it("allows scripts only with the nonce and talks only to this app", () => {
    const csp = buildCsp("n0nce", false);
    expect(csp).toContain("script-src 'self' 'nonce-n0nce' 'strict-dynamic'");
    expect(csp).toContain("connect-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toContain("unsafe-eval");
  });
});

describe("clientIp and the domain check", () => {
  it("reads the forwarded address and refuses junk", () => {
    expect(clientIp(new Headers({ "x-forwarded-for": "203.0.113.9, 10.0.0.1" }))).toBe("203.0.113.9");
    expect(clientIp(new Headers({ "x-forwarded-for": "<script>" }))).toBeNull();
  });
  it("accepts only the company domain", () => {
    expect(isAllowedEmail("Connect@Eduwit.in")).toBe(true);
    expect(isAllowedEmail("someone@gmail.com")).toBe(false);
    expect(isAllowedEmail("x@eduwit.in.evil.test")).toBe(false);
    expect(isAllowedEmail("@eduwit.in")).toBe(false);
  });
});
