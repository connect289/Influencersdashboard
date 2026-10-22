import { expect, test, type Page } from "@playwright/test";
import { LEGACY_REDIRECTS } from "../content/redirects";

async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}

test.describe("content pages", () => {
  test("homepage with Witty off: search, guided finder and free counselling; live trust line; data sections", async ({ page }) => {
    await page.goto("/");
    await dismissConsent(page);
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Find the right degree");
    await expect(page.getByRole("combobox", { name: /Search programmes/ })).toBeVisible();
    await expect(page.getByRole("link", { name: /Answer 3 quick questions/ })).toHaveAttribute("href", "/programmes?guided=1");
    await expect(page.getByRole("link", { name: /Get free counselling/ }).first()).toBeVisible();
    await expect(page.getByText(/partner universities/).first()).toBeVisible();
    await expect(page.getByRole("region", { name: "Popular programmes" }).getByRole("link").first()).toHaveAttribute("href", /\/programmes\?programme=/);
    await expect(page.getByRole("heading", { name: "Partner universities" })).toBeVisible();
    const ld = await page.locator("script[type='application/ld+json']").allInnerTexts();
    expect(ld.some((t) => t.includes('"FAQPage"'))).toBe(true);
    expect(ld.some((t) => t.includes('"EducationalOrganization"'))).toBe(true);
    // no testimonials yet → no empty "stories" section; no guides → Resources hidden from navigation
    await expect(page.getByRole("heading", { name: "In their words" })).toHaveCount(0);
    await expect(page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Resources" })).toHaveCount(0);
  });

  test("guided finder opens from the homepage link", async ({ page }) => {
    await page.goto("/programmes?guided=1");
    await expect(page.getByRole("heading", { name: "Find programmes that fit you" })).toBeVisible();
  });

  test("about, how it works and contact pages", async ({ page }) => {
    await page.goto("/about");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Choose your education wisely");
    await expect(page.getByText("GST 09BXLPJ7928K1ZP").first()).toBeVisible();
    await page.goto("/how-it-works");
    await expect(page.getByRole("heading", { name: "What we never do" })).toBeVisible();
    await page.goto("/contact");
    await dismissConsent(page);
    await expect(page.getByRole("heading", { name: "Send an enquiry" })).toBeVisible();
  });

  // The enquiry form flow (real email codes, lead assertions) lives in leads.spec.ts.
  test("legal pages keep their URLs; unmigrated text is not indexed and offers a contact", async ({ page }) => {
    for (const slug of ["terms-and-conditions", "privacy-policy", "disclaimer", "refund-policy", "cookie-policy", "data-privacy-opt-out"]) {
      const res = await page.goto(`/legal/${slug}`);
      expect(res?.status()).toBe(200);
    }
    await page.goto("/legal/privacy-policy");
    await expect(page.getByText("This page is being moved from our previous website.")).toBeVisible();
    expect(await page.locator("meta[name='robots']").first().getAttribute("content")).toContain("noindex");
  });

  test("guides page has a helpful empty state until guides are published", async ({ page }) => {
    await page.goto("/resources");
    await expect(page.getByText("Our first guides are being written and reviewed.")).toBeVisible();
  });

  test("redirects: legacy map and admin-managed redirects", async ({ request }) => {
    const legacy = await request.get("/courses", { maxRedirects: 0 });
    expect(legacy.status()).toBe(301);
    expect(legacy.headers().location).toBe("/programmes");
    const admin = await request.get("/old-mba-page", { maxRedirects: 0 });
    expect(admin.status()).toBe(301);
    expect(admin.headers().location).toContain("/programmes/online-mba");
  });

  test("pages keep working after cache tags expire (settings, content, catalogue)", async ({ request }) => {
    const key = process.env.WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001";
    const r = await request.post("/api/internal/revalidate", {
      headers: { authorization: `Bearer ${key}` },
      data: { tags: ["settings", "content", "catalog"], expire_now: true },
    });
    expect(r.ok()).toBe(true);
    for (const path of ["/universities/nmims", "/programmes/online-mba", "/legal/privacy-policy", "/c/demo-creator", "/c/unknown-handle", "/about", "/"]) {
      expect((await request.get(path)).status(), path).toBe(200);
    }
  });

  test("every legacy URL 301s to its new URL, and the destination works", async ({ request }) => {
    for (const r of LEGACY_REDIRECTS) {
      const from = r.source.replace(/:(\w+)/g, "sample-$1");
      const to = r.destination.replace(/:(\w+)/g, "sample-$1");
      const res = await request.get(from, { maxRedirects: 0 });
      expect(res.status(), from).toBe(301);
      expect(res.headers().location, from).toBe(to);
      if (!to.includes("sample-")) expect((await request.get(to)).status(), to).toBe(200);
    }
  });
});
