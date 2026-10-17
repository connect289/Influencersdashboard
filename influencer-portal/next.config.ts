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
  // CSV imports send up to 2 MB of text to a server action.
  experimental: { serverActions: { bodySizeLimit: "3mb" } },
  // The media-kit PDF renders on the server with bundled Geist fonts (SIL OFL).
  serverExternalPackages: ["@react-pdf/renderer"],
  outputFileTracingIncludes: {
    "/m/[handle]/pdf": ["./lib/media-kit/fonts/*.ttf"],
    "/api/media-kit/[creatorId]": ["./lib/media-kit/fonts/*.ttf"],
  },
  headers() {
    return Promise.resolve([{ source: "/:path*", headers: securityHeaders }]);
  },
};

export default createNextIntlPlugin("./i18n/request.ts")(config);
