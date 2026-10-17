import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ cacheLife: vi.fn(), cacheTag: vi.fn(), revalidateTag: vi.fn() }));

const { indexXml, urlsetXml } = await import("./sitemap");

describe("sitemaps", () => {
  it("index lists one sitemap per type", () => {
    const x = indexXml();
    expect(x).toContain("<sitemapindex");
    for (const t of ["pages", "curated", "universities", "resources"]) expect(x).toContain(`/sitemaps/${t}.xml</loc>`);
  });
  it("urlset escapes and dates entries", () => {
    const x = urlsetXml([{ loc: "https://eduwit.in/programmes/online-mba?x=1&y=2", lastmod: "2026-10-17T10:00:00Z" }]);
    expect(x).toContain("<loc>https://eduwit.in/programmes/online-mba?x=1&amp;y=2</loc><lastmod>2026-10-17</lastmod>");
  });
});
