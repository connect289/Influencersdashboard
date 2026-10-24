import { describe, expect, it } from "vitest";
import config, { securityHeaders } from "./next.config.ts";

describe("security headers (security review m9)", () => {
  it("sets nosniff, the referrer policy and the permissions policy on every route", async () => {
    expect(await config.headers?.()).toEqual([{ source: "/(.*)", headers: securityHeaders }]);
    expect(Object.fromEntries(securityHeaders.map((h) => [h.key, h.value]))).toEqual({
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    });
    expect(config.poweredByHeader).toBe(false);
  });
});
