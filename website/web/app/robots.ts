import type { MetadataRoute } from "next";
import { env, siteUrl } from "@/lib/server/env";

/**
 * robots.txt (spec 13.1). Preview deployments are never crawlable. Staff, account, API, campaign and utility routes are
 * excluded; noindex pages that should still pass link signals (compare, shortlist, filtered finder URLs) stay crawlable.
 */
export default function robots(): MetadataRoute.Robots {
  if (env().APP_ENV === "preview") return { rules: { userAgent: "*", disallow: "/" } };
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/admin", "/account", "/api/", "/c/", "/thank-you", "/concepts", "/styleguide"] },
    sitemap: siteUrl("/sitemap.xml"),
    host: siteUrl("/"),
  };
}
