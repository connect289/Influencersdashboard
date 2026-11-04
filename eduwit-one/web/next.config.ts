import type { NextConfig } from "next";

// Security headers on every route (security review m9). The Content-Security-Policy is set per request in
// middleware.ts, where the nonce is.
export const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

// No build-time configuration: hosts, ids and thresholds are read from one.settings at runtime (spec standard 3).
const config: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  headers: async () => [{ source: "/(.*)", headers: securityHeaders }],
};

export default config;
