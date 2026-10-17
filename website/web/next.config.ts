import type { NextConfig } from "next";
import { LEGACY_REDIRECTS } from "./content/redirects";
import { SECURITY_HEADERS, buildCsp } from "./lib/security/csp";

const dev = process.env.NODE_ENV === "development";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  cacheComponents: true,
  partialPrefetching: true,
  images: { formats: ["image/avif", "image/webp"] },
  experimental: {
    optimizePackageImports: ["lucide-react", "motion"],
  },
  async headers() {
    const security = Object.entries(SECURITY_HEADERS).map(([key, value]) => ({ key, value }));
    return [
      {
        // Static public pages: strict CSP without nonces (D-025). /account and /admin get a nonce CSP from proxy.ts.
        source: "/((?!account|admin).*)",
        headers: [
          ...security,
          {
            key: "Content-Security-Policy",
            value: buildCsp({ dev, supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL }),
          },
        ],
      },
      { source: "/(account|admin)(.*)", headers: security },
      { source: "/(concepts|styleguide)(.*)", headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }] },
      { source: "/fonts/(.*)", headers: [{ key: "Cache-Control", value: "public, max-age=31536000, immutable" }] },
      {
        source: "/brand/(.*)",
        headers: [{ key: "Cache-Control", value: "public, max-age=86400, stale-while-revalidate=604800" }],
      },
    ];
  },
  async redirects() {
    return LEGACY_REDIRECTS;
  },
};

export default nextConfig;
