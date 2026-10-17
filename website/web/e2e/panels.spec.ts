import { expect, test, type Page } from "@playwright/test";

async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}

test.describe("detail panels, application form, university pages, curated views", () => {
  test("application form inside the offering panel: steps, inline email code, review, reference", async ({ page }) => {
    await page.goto("/programmes?programme=mba&view=flat");
    await dismissConsent(page);
    await page.locator("li a[href^='?offering=']").first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Apply now" }).click();
    await expect(dialog.getByText("Step 1 of 5: Contact")).toBeVisible();
    // validation: nothing filled
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Enter your full name (letters only).")).toBeVisible();
    await dialog.getByLabel("Full name", { exact: true }).fill("Asha Rao");
    await dialog.getByLabel("Mobile number", { exact: true }).fill("91234 56789");
    await dialog.getByLabel("Email", { exact: true }).fill("asha@example.com");
    await dialog.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Check your email")).toBeVisible();
    // wrong code path (mock rejects 000000), then a right one
    await dialog.getByRole("textbox").first().click();
    await page.keyboard.type("000000");
    await expect(dialog.getByText(/didn't match/)).toBeVisible();
    await dialog.getByRole("textbox").first().click();
    await page.keyboard.type("123456");
    await expect(dialog.getByText("Step 2 of 5: Academic")).toBeVisible();
    await expect(dialog.getByText("Email verified")).toBeVisible();
    await dialog.getByLabel("Highest qualification").selectOption("graduation");
    await expect(dialog.getByText("You meet the eligibility for this programme.")).toBeVisible();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await expect(dialog.getByText("Step 3 of 5: Work and goals")).toBeVisible();
    await dialog.getByText("Yes", { exact: true }).first().click();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await dialog.getByText("WhatsApp", { exact: true }).click();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await expect(dialog.getByText("Step 5 of 5: Review")).toBeVisible();
    await expect(dialog).toContainText("Asha Rao");
    await dialog.getByRole("button", { name: "Submit application request" }).click();
    await expect(dialog.getByText("Application request received")).toBeVisible();
    await expect(dialog).toContainText(/EDW-26-[A-Z0-9]{5}/);
  });

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
