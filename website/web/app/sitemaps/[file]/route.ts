import { connection } from "next/server";
import { SITEMAP_TYPES, sitemapEntries, urlsetXml, type SitemapType } from "@/lib/server/sitemap";

/** /sitemaps/{pages|curated|universities|resources}.xml — one sitemap per type (spec 13.1). */
export async function GET(_req: Request, ctx: RouteContext<"/sitemaps/[file]">) {
  await connection(); // always current (new universities, views, guides); the data reads are cached
  const { file } = await ctx.params;
  const type = file.replace(/\.xml$/, "") as SitemapType;
  if (!file.endsWith(".xml") || !SITEMAP_TYPES.includes(type)) return new Response("Not found", { status: 404 });
  const xml = urlsetXml(await sitemapEntries(type));
  return new Response(xml, { headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "public, max-age=3600" } });
}
