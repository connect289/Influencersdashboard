/**
 * Legacy URL map (docs/URL_REDIRECT_MAP.md). Completed from the crawl of the current site (S-01). /about and /legal/*
 * keep their paths. Admin-managed redirects (web_redirects) are applied at runtime after these.
 */
/** 301 exactly as the spec asks (Next's `permanent` would send 308). */
export interface LegacyRedirect {
  source: string;
  destination: string;
  statusCode: 301;
}

export const LEGACY_REDIRECTS: LegacyRedirect[] = [
  { source: "/privacy", destination: "/legal/privacy-policy", statusCode: 301 },
  { source: "/privacy-policy", destination: "/legal/privacy-policy", statusCode: 301 },
  { source: "/terms", destination: "/legal/terms-and-conditions", statusCode: 301 },
  { source: "/terms-and-conditions", destination: "/legal/terms-and-conditions", statusCode: 301 },
  { source: "/courses", destination: "/programmes", statusCode: 301 },
  { source: "/programs", destination: "/programmes", statusCode: 301 },
  { source: "/services", destination: "/how-it-works", statusCode: 301 },
  { source: "/blog", destination: "/resources", statusCode: 301 },
  { source: "/blog/:slug", destination: "/resources/:slug", statusCode: 301 },
];
