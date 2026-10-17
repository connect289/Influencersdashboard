import { describe, expect, it } from "vitest";
import { buildCsp } from "./csp";

describe("CSP", () => {
  it("static policy is strict apart from inline scripts required by prerendered pages", () => {
    const p = buildCsp();
    expect(p).toContain("script-src 'self' 'unsafe-inline'");
    expect(p).not.toContain("unsafe-eval");
    expect(p).toContain("object-src 'none'");
    expect(p).toContain("frame-ancestors 'none'");
    expect(p).toContain("base-uri 'self'");
    expect(p).toContain("upgrade-insecure-requests");
  });
  it("nonce policy uses strict-dynamic and drops unsafe-inline for scripts", () => {
    const p = buildCsp({ nonce: "abc123" });
    const script = p.split("; ").find((d) => d.startsWith("script-src"))!;
    expect(script).toContain("'nonce-abc123'");
    expect(script).toContain("'strict-dynamic'");
    expect(script).not.toContain("unsafe-inline");
  });
  it("allows Turnstile and consented analytics hosts", () => {
    const p = buildCsp();
    expect(p).toContain("https://challenges.cloudflare.com");
    expect(p).toContain("https://www.googletagmanager.com");
  });
});
