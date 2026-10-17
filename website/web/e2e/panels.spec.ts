import { expect, test, type Page } from "@playwright/test";

async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}

test.describe("detail panels, application form, university pages, curated views", () => {
  // The application form flow (real email codes, lead assertions) lives in leads.spec.ts.
  test("programme group panel deep link lists universities and offers a picker form", async ({ page }) => {
    await page.goto("/programmes?programme=mba&group=mba:marketing");
    await dismissConsent(page);
    const dialog = page.getByRole("dialog");
    await expect(dialog).toContainText("MBA · Marketing");
    await expect(dialog.getByText("Universities offering it")).toBeVisible();
    await dialog.locator("li button").first().click(); // switches to the offering panel
    await expect(page).toHaveURL(/offering=\d+/);
    await expect(page.getByRole("dialog")).toContainText("Total programme fee");
  });

  test("university page: facts with explanations, programmes, structured data, apply section", async ({ page }) => {
    await page.goto("/universities/nmims");
    await dismissConsent(page);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("NMIMS");
    await expect(page.getByText("What the NAAC grade means")).toBeVisible();
    await expect(page.getByRole("heading", { name: /Programmes at NMIMS/ })).toBeVisible();
    const ld = await page.locator("script[type='application/ld+json']").allInnerTexts();
    expect(ld.some((t) => t.includes('"CollegeOrUniversity"'))).toBe(true);
    expect(ld.some((t) => t.includes('"Course"') && t.includes('"priceCurrency":"INR"'))).toBe(true);
    await expect(page.getByRole("heading", { name: "Apply to NMIMS" })).toBeVisible();
    await page.goto("/universities");
    await expect(page.getByRole("link", { name: /NMIMS/ }).first()).toBeVisible();
    // Unknown slugs render the not-found page with noindex (a streamed soft 404 — D-040).
    await page.goto("/universities/no-such-university");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("moved or doesn");
    expect(await page.locator("meta[name='robots']").first().getAttribute("content")).toContain("noindex");
  });

  test("curated finder view: intro, FAQs with FAQ structured data, results; filters lead into the full finder", async ({ page, isMobile }) => {
    await page.goto("/programmes/online-mba");
    await dismissConsent(page);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Online MBA");
    await expect(page.getByRole("heading", { name: "Frequently asked questions" })).toBeVisible();
    const ld = await page.locator("script[type='application/ld+json']").allInnerTexts();
    expect(ld.some((t) => t.includes('"FAQPage"'))).toBe(true);
    await expect(page.locator("article").first()).toContainText("MBA");
    if (!isMobile) {
      await page.getByRole("complementary", { name: "Filters" }).getByRole("button", { name: /^Distance \(ODL\)/ }).click();
      await expect(page).toHaveURL(/\/programmes\?programme=mba&mode=odl/);
    }
  });
});
