import { indexXml } from "@/lib/server/sitemap";

/** /sitemap.xml — sitemap index (spec 13.1). */
export async function GET() {
  return new Response(indexXml(), { headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "public, max-age=3600" } });
}
