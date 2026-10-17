/**
 * Legacy URL map (docs/URL_REDIRECT_MAP.md). Completed from the crawl of the current site (S-01). /about and /legal/*
 * keep their paths. Admin-managed redirects (web_redirects) are applied at runtime after these.
 */
export interface LegacyRedirect {
  source: string;
  destination: string;
  permanent: true;
}

export const LEGACY_REDIRECTS: LegacyRedirect[] = [
  { source: "/privacy", destination: "/legal/privacy-policy", permanent: true },
  { source: "/privacy-policy", destination: "/legal/privacy-policy", permanent: true },
  { source: "/terms", destination: "/legal/terms-and-conditions", permanent: true },
  { source: "/terms-and-conditions", destination: "/legal/terms-and-conditions", permanent: true },
  { source: "/courses", destination: "/programmes", permanent: true },
  { source: "/programs", destination: "/programmes", permanent: true },
  { source: "/services", destination: "/how-it-works", permanent: true },
  { source: "/blog", destination: "/resources", permanent: true },
  { source: "/blog/:slug", destination: "/resources/:slug", permanent: true },
];
