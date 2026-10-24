import { describe, expect, it } from "vitest";
import {
  buildCsp,
  clientIp,
  internalRequestAuthorized,
  internalToken,
  internalTokenValid,
  isAllowedEmail,
  isIdleExpired,
  safeNext,
  seenFresh,
  seenKey,
  seenValue,
  signedInAt,
} from "./security.ts";

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

describe("the signed idle cookie (S5)", () => {
  const key = "k".repeat(40);
  const base = { key, sessionId: "s1", now: 10_000, limit: 3600, signedInAt: null };
  it("is fresh only when signed for this session and within the limit", async () => {
    const v = await seenValue(key, "s1", 9_000);
    expect(await seenFresh({ ...base, value: v })).toBe(true);
    expect(await seenFresh({ ...base, value: v, now: 9_000 + 3601 })).toBe(false);
    expect(await seenFresh({ ...base, value: await seenValue(key, "s2", 9_000) })).toBe(false);
    expect(await seenFresh({ ...base, value: "9999.forged" })).toBe(false);
    expect(await seenFresh({ ...base, value: "9999" })).toBe(false);
  });
  it("counts a missing cookie as idle, except just after signing in", async () => {
    expect(await seenFresh({ ...base, value: undefined })).toBe(false);
    expect(await seenFresh({ ...base, value: undefined, signedInAt: 10_000 - 60 })).toBe(true);
    expect(await seenFresh({ ...base, value: undefined, signedInAt: 10_000 - 3600 })).toBe(false);
  });
  it("reads the sign-in time from amr, not from a refreshable iat", () => {
    expect(
      signedInAt({
        amr: [
          { method: "oauth", timestamp: 100 },
          { method: "otp", timestamp: 200 },
        ],
      }),
    ).toBe(200);
    expect(signedInAt({})).toBeNull();
  });
});

describe("the idle cookie's derived key (m6)", () => {
  it("differs from the internal key and signs and checks the cookie", async () => {
    const raw = "k".repeat(40);
    const derived = await seenKey(raw);
    expect(derived).not.toBe(raw);
    expect(derived).toMatch(/^[0-9a-f]{64}$/);
    expect(await seenKey(raw)).toBe(derived);
    const base = { sessionId: "s1", now: 10_000, limit: 3600, signedInAt: null };
    const v = await seenValue(derived, "s1", 9_000);
    expect(await seenFresh({ ...base, key: derived, value: v })).toBe(true);
    expect(await seenFresh({ ...base, key: raw, value: v })).toBe(false);
  });
});

describe("the internal routes' short-lived token (m6)", () => {
  const key = "k".repeat(40);
  const path = "/api/internal/tick";
  const ts = 1_700_000_000;

  it("accepts a token for this path signed with the key, within 90 s either way", async () => {
    const t = await internalToken(key, path, ts);
    expect(t).toMatch(/^1700000000\.[0-9a-f]{64}$/);
    expect(await internalTokenValid(key, path, t, ts)).toBe(true);
    expect(await internalTokenValid(key, path, t, ts + 90)).toBe(true);
    expect(await internalTokenValid(key, path, t, ts - 90)).toBe(true);
  });

  it("refuses an expired token, another path's, another key's and junk", async () => {
    const t = await internalToken(key, path, ts);
    expect(await internalTokenValid(key, path, t, ts + 91)).toBe(false);
    expect(await internalTokenValid(key, "/api/internal/ai/run", t, ts)).toBe(false);
    expect(await internalTokenValid("j".repeat(40), path, t, ts)).toBe(false);
    expect(await internalTokenValid(key, path, `${ts}.${"0".repeat(64)}`, ts)).toBe(false);
    expect(await internalTokenValid(key, path, "1700000000.nothex", ts)).toBe(false);
    expect(await internalTokenValid(key, path, undefined, ts)).toBe(false);
  });

  it("still accepts the static bearer, and nothing when no key is configured", async () => {
    const base = { key, authorization: null, token: null, pathname: path, nowSeconds: ts };
    expect(await internalRequestAuthorized({ ...base, authorization: `Bearer ${key}` })).toBe(true);
    expect(await internalRequestAuthorized({ ...base, authorization: `Bearer ${"j".repeat(40)}` })).toBe(false);
    expect(await internalRequestAuthorized({ ...base, authorization: key })).toBe(false);
    expect(await internalRequestAuthorized({ ...base, token: await internalToken(key, path, ts) })).toBe(true);
    expect(await internalRequestAuthorized({ ...base, key: undefined, authorization: `Bearer ${key}` })).toBe(false);
    expect(await internalRequestAuthorized(base)).toBe(false);
  });
});
