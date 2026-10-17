import "server-only";
import type { Metadata } from "next";
import { cacheLife, cacheTag } from "next/cache";
import { dbConfigured, rpc } from "./db";

/**
 * Admin overrides for page titles, descriptions, OG images and noindex (spec 13.1 "templates with admin overrides";
 * table web_pages, edited in the admin SEO toolkit). Templates stay in code; an override replaces only what it sets.
 */
interface PageMeta {
  path: string;
  title: string | null;
  description: string | null;
  og_image: string | null;
  noindex: boolean;
}

async function pageMeta(path: string): Promise<PageMeta | null> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("pages", `page:${path}`);
  if (!dbConfigured()) return null;
  return rpc<PageMeta | null>("web_page_meta", { p_path: path }).catch(() => null);
}

export async function withOverrides(path: string, base: Metadata): Promise<Metadata> {
  const o = await pageMeta(path);
  if (!o) return base;
  return {
    ...base,
    ...(o.title ? { title: { absolute: o.title } } : {}),
    ...(o.description ? { description: o.description } : {}),
    ...(o.og_image ? { openGraph: { ...(base.openGraph ?? {}), images: [o.og_image] }, twitter: { ...(base.twitter ?? {}), images: [o.og_image] } } : {}),
    ...(o.noindex ? { robots: { index: false, follow: true } } : {}),
  };
}
