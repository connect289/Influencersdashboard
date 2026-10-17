import { expect, test } from "@playwright/test";

/** Technical SEO (spec 13.1, Phase 9): robots, sitemap index by type, indexing and canonical rules, structured data, OG images. */
test.describe("technical SEO", () => {
  test.skip(({ isMobile }) => isMobile, "server responses; one project is enough");

  test("robots.txt points to the sitemap index and keeps private areas out", async ({ request }) => {
    const r = await (await request.get("/robots.txt")).text();
    expect(r).toMatch(/Sitemap: .*\/sitemap\.xml/);
    for (const p of ["/admin", "/account", "/api/"]) expect(r).toContain(`Disallow: ${p}`);
  });

  test("sitemap index split by type, only indexable URLs", async ({ request }) => {
    const index = await (await request.get("/sitemap.xml")).text();
    const files = [...index.matchAll(/<loc>[^<]*(\/sitemaps\/\w+\.xml)<\/loc>/g)].map((m) => m[1]!);
    expect(files).toEqual(["/sitemaps/pages.xml", "/sitemaps/curated.xml", "/sitemaps/universities.xml", "/sitemaps/resources.xml"]);
    const all: string[] = [];
    for (const f of files) {
      const res = await request.get(f);
      expect(res.status(), f).toBe(200);
      expect(res.headers()["content-type"]).toContain("application/xml");
      all.push(...[...(await res.text()).matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]!));
    }
    expect(all.some((u) => u.endsWith("/universities/nmims"))).toBe(true);
    expect(all.some((u) => u.endsWith("/programmes/online-mba"))).toBe(true);
    expect(all.filter((u) => u.includes("?") || u.includes("/admin") || u.includes("/account"))).toEqual([]);
    expect(all.some((u) => u.includes("/legal/"))).toBe(false); // legal pages still awaiting the verbatim migration are noindex
    expect((await request.get("/sitemaps/nope.xml")).status()).toBe(404);
  });

  test("only the finder home and curated views are indexable; panels are noindex", async ({ page }) => {
    const meta = async (path: string) => {
      await page.goto(path);
      const { robots, canonical } = await page.evaluate(() => ({
        robots: document.querySelector('meta[name="robots"]')?.getAttribute("content") ?? null,
        canonical: document.querySelector('link[rel="canonical"]')?.getAttribute("href") ?? null,
      }));
      return { robots, canonical: canonical?.replace(/^https?:\/\/[^/]+/, "") };
    };
    expect(await meta("/programmes")).toMatchObject({ canonical: "/programmes" });
    expect((await meta("/programmes")).robots ?? "").not.toContain("noindex");
    expect(await meta("/programmes?programme=mba")).toEqual({ robots: "noindex, follow", canonical: "/programmes/online-mba" });
    expect(await meta("/programmes?programme=mba&mode=online&fee_max=200000")).toMatchObject({ robots: "noindex, follow", canonical: "/programmes/online-mba" });
    expect((await meta("/programmes?offering=1")).robots).toContain("noindex");
    expect((await meta("/programmes/online-mba")).canonical).toBe("/programmes/online-mba");
  });

  test("structured data and OG images", async ({ page, request }) => {
    await page.goto("/");
    const ld = (await page.locator('script[type="application/ld+json"]').allTextContents()).map((t) => JSON.parse(t) as { "@type": string });
    const types = ld.map((x) => x["@type"]);
    expect(types).toEqual(expect.arrayContaining(["EducationalOrganization", "WebSite"]));
    const site = ld.find((x) => x["@type"] === "WebSite") as unknown as { potentialAction: { target: { urlTemplate: string } } };
    expect(site.potentialAction.target.urlTemplate).toContain("/programmes?q={search_term_string}");
    const og = await page.locator('meta[property="og:image"]').first().getAttribute("content");
    expect(og).toContain("/opengraph-image");
    expect(await page.locator('meta[name="twitter:image"]').count()).toBeGreaterThan(0);
    for (const path of ["/", "/universities/nmims", "/programmes/online-mba"]) {
      await page.goto(path);
      const img = await page.locator('meta[property="og:image"]').first().getAttribute("content");
      expect(img, path).toContain("opengraph-image");
      const res = await request.get(img!.replace(/^https?:\/\/[^/]+/, ""));
      expect(res.status(), img!).toBe(200);
      expect(res.headers()["content-type"]).toBe("image/png");
    }
  });
});
