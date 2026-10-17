import "server-only";
import { LEGAL_PAGES } from "@/content/site";
import { legalPage, resourcesList } from "./content";
import { siteUrl } from "./env";
import { curatedViews, universities } from "./search";

/**
 * Sitemap index split by type (spec 13.1): pages, curated finder views, universities, resources. Only indexable URLs:
 * no filtered finder URLs, no panels, no account/admin, no legal page still awaiting migration (noindex, D-044).
 */
export const SITEMAP_TYPES = ["pages", "curated", "universities", "resources"] as const;
export type SitemapType = (typeof SITEMAP_TYPES)[number];
export interface SitemapEntry {
  loc: string;
  lastmod?: string;
}

const STATIC_PAGES = ["/", "/programmes", "/universities", "/about", "/how-it-works", "/contact", "/resources"];

export async function sitemapEntries(type: SitemapType): Promise<SitemapEntry[]> {
  switch (type) {
    case "pages": {
      const legal = await Promise.all(LEGAL_PAGES.map((l) => legalPage(l.slug).catch(() => null)));
      return [
        ...STATIC_PAGES.map((p) => ({ loc: siteUrl(p) })),
        ...legal.filter((l) => l && l.status !== "pending_migration").map((l) => ({ loc: siteUrl(`/legal/${l!.slug}`), lastmod: l!.updated_at })),
      ];
    }
    case "curated":
      return (await curatedViews()).map((v) => ({ loc: siteUrl(`/programmes/${v.slug}`), lastmod: v.updated_at }));
    case "universities":
      return (await universities()).map((u) => ({ loc: siteUrl(`/universities/${u.slug}`) }));
    case "resources":
      return (await resourcesList()).map((r) => ({ loc: siteUrl(`/resources/${r.slug}`), lastmod: r.published_at }));
  }
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const day = (s?: string) => (s ? new Date(s).toISOString().slice(0, 10) : undefined);

export function urlsetXml(entries: SitemapEntry[]): string {
  const rows = entries.map((e) => `  <url><loc>${esc(e.loc)}</loc>${e.lastmod ? `<lastmod>${day(e.lastmod)}</lastmod>` : ""}</url>`).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows}\n</urlset>\n`;
}

export function indexXml(): string {
  const rows = SITEMAP_TYPES.map((t) => `  <sitemap><loc>${esc(siteUrl(`/sitemaps/${t}.xml`))}</loc></sitemap>`).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${rows}\n</sitemapindex>\n`;
}
