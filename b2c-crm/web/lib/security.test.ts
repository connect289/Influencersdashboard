import { describe, expect, it } from "vitest";
import { breachedPassword, buildCsp, clientIp, isIdleExpired, passwordProblem, pwnedCount, pwnedParts, rateIp, rateKey, retryAfter, safeNext, sameOrigin } from "./security";

describe("same-origin POSTs", () => {
  const h = (o: Record<string, string>) => new Headers(o);
  it("accepts this deployment by host, forwarded host or site URL", () => {
    expect(sameOrigin(h({ origin: "https://spark.eduwit.in", host: "spark.eduwit.in" }))).toBe(true);
    expect(sameOrigin(h({ origin: "https://spark.eduwit.in", host: "internal:3000", "x-forwarded-host": "spark.eduwit.in" }))).toBe(true);
    expect(sameOrigin(h({ origin: "https://spark.eduwit.in", host: "internal:3000" }), "https://spark.eduwit.in")).toBe(true);
    expect(sameOrigin(h({ origin: "http://localhost:3000", host: "localhost:3000", "sec-fetch-site": "same-origin" }))).toBe(true);
  });
  it("refuses another site, a missing or opaque origin, and a cross-site fetch", () => {
    expect(sameOrigin(h({ origin: "https://evil.example", host: "spark.eduwit.in" }), "https://spark.eduwit.in")).toBe(false);
    expect(sameOrigin(h({ host: "spark.eduwit.in" }), "https://spark.eduwit.in")).toBe(false);
    expect(sameOrigin(h({ origin: "null", host: "spark.eduwit.in" }))).toBe(false);
    expect(sameOrigin(h({ origin: "https://spark.eduwit.in", host: "spark.eduwit.in", "sec-fetch-site": "same-site" }))).toBe(false);
    expect(sameOrigin(h({ origin: "https://spark.eduwit.in.evil.example", host: "spark.eduwit.in" }))).toBe(false);
  });
});

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

describe("rate limit keys", () => {
  it("prefers the platform's address headers and takes the first hop", () => {
    expect(rateIp(new Headers({ "x-vercel-forwarded-for": "198.51.100.4", "x-forwarded-for": "203.0.113.7" }))).toBe("198.51.100.4");
    expect(rateIp(new Headers({ "x-real-ip": "198.51.100.5", "x-forwarded-for": "203.0.113.7" }))).toBe("198.51.100.5");
    expect(rateIp(new Headers({ "x-forwarded-for": "203.0.113.7, 10.0.0.1" }))).toBe("203.0.113.7");
  });
  it("cuts IPv6 to its /64 and unwraps IPv4-mapped addresses", () => {
    expect(rateIp(new Headers({ "x-forwarded-for": "2001:db8:abcd:12:1:2:3:4" }))).toBe("2001:db8:abcd:12::/64");
    expect(rateIp(new Headers({ "x-forwarded-for": "2001:db8::1" }))).toBe("2001:db8:0:0::/64");
    expect(rateIp(new Headers({ "x-forwarded-for": "2001:DB8:0000:0012:ffff::9" }))).toBe("2001:db8:0:12::/64");
    expect(rateIp(new Headers({ "x-forwarded-for": "::ffff:203.0.113.9" }))).toBe("203.0.113.9");
  });
  it("never lets junk become a key of its own", () => {
    for (const bad of ["<script>", "999.1.1.1", "1.2.3", "2001:db8::1::2", "abc"]) expect(rateIp(new Headers({ "x-forwarded-for": bad }))).toBe("unknown");
    expect(rateIp(new Headers())).toBe("unknown");
  });
  it("builds a bounded key per scope and address", () => {
    expect(rateKey("v1:handoffs", "203.0.113.7")).toBe("v1:handoffs:203.0.113.7");
    expect(rateKey("q submit/../x", "1.2.3.4")).toBe("q_submit____x:1.2.3.4");
    expect(rateKey("x".repeat(300), "1.2.3.4")).toHaveLength(200);
  });
  it("answers Retry-After until the fixed window ends", () => {
    expect(retryAfter(60, 1_800_000_000_000)).toBe(60 - (1_800_000_000 % 60));
    expect(retryAfter(60, 59_000)).toBe(1);
    expect(retryAfter(60, 60_000)).toBe(60);
  });
});

describe("breached passwords (k-anonymity)", () => {
  // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
  it("sends only the first five characters of the SHA-1", () => {
    expect(pwnedParts("password")).toEqual({ prefix: "5BAA6", suffix: "1E4C9B93F3F0682250B6CF8331B7EE68FD8" });
  });
  it("finds the suffix in a range answer, ignoring case and padding", () => {
    const body = "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n1e4c9b93f3f0682250b6cf8331b7ee68fd8:9545824\r\n00D4F6E8FA6EECAD2A3AA415EEC418D38EC:0";
    expect(pwnedCount(body, "1E4C9B93F3F0682250B6CF8331B7EE68FD8")).toBe(9545824);
    expect(pwnedCount(body, "00D4F6E8FA6EECAD2A3AA415EEC418D38EC")).toBe(0);
    expect(pwnedCount(body, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")).toBe(0);
  });
  it("asks the range API with padding and refuses a known password", async () => {
    let asked = "", padding: string | null = null;
    const fake = (async (url: string, init?: RequestInit) => {
      asked = url; padding = new Headers(init?.headers).get("add-padding");
      return new Response("1E4C9B93F3F0682250B6CF8331B7EE68FD8:3\r\nAAAA:0");
    }) as unknown as typeof fetch;
    expect(await breachedPassword("password", fake)).toEqual({ checked: true, breached: true, count: 3 });
    expect(asked).toBe("https://api.pwnedpasswords.com/range/5BAA6");
    expect(padding).toBe("true");
  });
  it("fails open when the service cannot be reached", async () => {
    const down = (async () => { throw new Error("offline"); }) as unknown as typeof fetch;
    expect(await breachedPassword("correct horse battery staple", down)).toEqual({ checked: false, breached: false, count: 0 });
  });
});
