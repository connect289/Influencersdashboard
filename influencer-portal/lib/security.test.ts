import { describe, expect, it } from "vitest";
import { breachedPassword, buildCsp, clientIp, isIdleExpired, pwnedCount, pwnedParts, rateIp, rateKey, retryAfter, safeEqual, safeNext } from "./security";

describe("safeNext", () => {
  it.each([
    ["/admin", "/admin"],
    ["/creator/leads?x=1", "/creator/leads?x=1"],
    ["//evil.com", "/"],
    ["/\\evil.com", "/"],
    ["https://evil.com", "/"],
    ["/a\nb", "/"],
    [null, "/"],
    ["/" + "a".repeat(600), "/"],
  ])("%s → %s", (input, out) => expect(safeNext(input)).toBe(out));
});

describe("idle timeout", () => {
  it("expires after 12 hours", () => {
    expect(isIdleExpired(String(1000), 1000 + 12 * 3600 + 1)).toBe(true);
    expect(isIdleExpired(String(1000), 1000 + 12 * 3600)).toBe(false);
  });
  it("treats a missing or bad value as not idle", () => {
    expect(isIdleExpired(undefined, 5)).toBe(false);
    expect(isIdleExpired("abc", 5)).toBe(false);
  });
});

describe("CSP", () => {
  it("requires the nonce and forbids framing", () => {
    const csp = buildCsp("abc", "https://x.supabase.co", false);
    expect(csp).toContain("'nonce-abc'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("wss://x.supabase.co");
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).toContain("upgrade-insecure-requests");
  });
  it("allows eval only in development", () => {
    expect(buildCsp("n", "http://127.0.0.1:54421", true)).toContain("'unsafe-eval'");
  });
});

describe("client addresses", () => {
  it("prefers the platform header", () => {
    expect(clientIp(new Headers({ "x-vercel-forwarded-for": "1.2.3.4", "x-forwarded-for": "9.9.9.9" }))).toBe("1.2.3.4");
  });
  it("rejects junk", () => {
    expect(clientIp(new Headers({ "x-forwarded-for": "<script>" }))).toBeNull();
  });
  it("groups IPv6 by /64 for rate limits", () => {
    expect(rateIp(new Headers({ "x-real-ip": "2001:db8:1:2:3:4:5:6" }))).toBe("2001:db8:1:2::/64");
    expect(rateIp(new Headers({ "x-real-ip": "::ffff:10.0.0.1" }))).toBe("10.0.0.1");
    expect(rateIp(new Headers())).toBe("unknown");
  });
  it("builds bounded keys", () => {
    expect(rateKey("staff_sign_in", "a b@c.com")).toBe("staff_sign_in:a_b@c.com");
    expect(rateKey("redirect", "x".repeat(400)).length).toBe(200);
  });
  it("computes Retry-After within the window", () => {
    expect(retryAfter(60, 61_000)).toBe(59);
  });
});

describe("secrets", () => {
  it("compares in constant time and correctly", () => {
    expect(safeEqual("abc", "abc")).toBe(true);
    expect(safeEqual("abc", "abd")).toBe(false);
    expect(safeEqual("abc", "abcd")).toBe(false);
  });
});

describe("breached passwords", () => {
  it("sends only the first five hash characters and finds the suffix", async () => {
    const { prefix, suffix } = pwnedParts("password123");
    let url = "";
    const fake = ((u: string) => {
      url = u;
      return Promise.resolve(new Response(`${suffix}:42\nAAAA:0`));
    }) as unknown as typeof fetch;
    const r = await breachedPassword("password123", fake);
    expect(url.endsWith(`/range/${prefix}`)).toBe(true);
    expect(r).toEqual({ checked: true, breached: true });
    expect(pwnedCount("X:1", "Y")).toBe(0);
  });
  it("fails open when the service is down", async () => {
    const down = (() => Promise.reject(new Error("offline"))) as unknown as typeof fetch;
    expect(await breachedPassword("x", down)).toEqual({ checked: false, breached: false });
  });
});
