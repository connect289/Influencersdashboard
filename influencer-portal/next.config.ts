import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

// Static security headers for every response. The Content-Security-Policy carries a per-request nonce and is set in
// proxy.ts.
const securityHeaders = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
  },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "X-Robots-Tag", value: "noindex, nofollow" },
];

const config: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  typedRoutes: false,
  experimental: { serverActions: { bodySizeLimit: "2mb" } },
  headers() {
    return Promise.resolve([{ source: "/:path*", headers: securityHeaders }]);
  },
};

export default createNextIntlPlugin("./i18n/request.ts")(config);
