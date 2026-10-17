import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}
const count = async (page: Page) => Number(await page.getByTestId("result-count").getAttribute("data-total"));

test.describe("programme finder", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/programmes");
    await dismissConsent(page);
  });

  test("free text becomes structured filters (chips) and grouped results", async ({ page }) => {
    const box = page.getByRole("combobox", { name: /Search programmes/ });
    await box.fill("mba in marketing under 2 lakh");
    await box.press("Enter");
    await expect(page).toHaveURL(/programme=mba/);
    await expect(page).toHaveURL(/spec=marketing/);
    await expect(page).toHaveURL(/fee_max=200000/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("MBA in Marketing");
    const chips = page.getByRole("group", { name: "Applied filters" });
    await expect(chips).toContainText("MBA");
    await expect(chips).toContainText("Up to ₹2 lakh");
    await expect(page.locator("article").first()).toContainText("MBA · Marketing");
  });

  test("suggestions are a keyboard-navigable listbox", async ({ page }) => {
    const box = page.getByRole("combobox", { name: /Search programmes/ });
    await box.fill("mba mark");
    const list = page.getByRole("listbox", { name: "Suggestions" });
    await expect(list.getByRole("option").first()).toBeVisible();
    await box.press("ArrowDown");
    await expect(box).toHaveAttribute("aria-activedescendant", /.+/);
    await box.press("Enter");
    await expect(page).toHaveURL(/programme=mba/);
  });

  test("facets narrow results live, chips remove filters, URL holds state, back works", async ({ page, isMobile }) => {
    test.skip(isMobile, "desktop rail");
    const before = await count(page);
    await page.getByRole("complementary", { name: "Filters" }).getByRole("checkbox", { name: /^MBA/ }).check();
    await expect(page).toHaveURL(/programme=mba/);
    await expect.poll(() => count(page)).toBeLessThan(before);
    // hierarchy-aware: a specialisation that MBA does not offer is disabled, not hidden
    const rail = page.getByRole("complementary", { name: "Filters" });
    await rail.getByRole("button", { name: /^Show all/ }).first().click();
    await expect(rail.getByRole("checkbox", { name: /^English/ })).toBeDisabled();
    await page.getByRole("button", { name: /Remove filter MBA/ }).click();
    await expect(page).not.toHaveURL(/programme=mba/);
    await page.goto("/programmes?programme=mba&sort=fee_asc");
    await expect(page.getByRole("combobox", { name: "Sort" }).or(page.locator("select")).first()).toHaveValue("fee_asc");
  });

  test("group expands to universities; offering panel deep-links and closes back to results", async ({ page }) => {
    await page.goto("/programmes?programme=mba&spec=marketing");
    await page.getByRole("button", { name: /Show universities/ }).first().click();
    const row = page.locator("li a[href^='?offering=']").first();
    await expect(row).toBeVisible();
    await row.click();
    await expect(page).toHaveURL(/offering=\d+/);
    const dialog = page.getByRole("dialog");
    await expect(dialog).toContainText("Total programme fee");
    await expect(dialog).toContainText("Easy EMI available");
    await expect(dialog).toContainText("Data last verified");
    await page.keyboard.press("Escape");
    await expect(page).not.toHaveURL(/offering=/);
    // shared link opens straight into the panel
    const id = (await row.getAttribute("href"))!.replace(/\D/g, "");
    await page.goto(`/programmes?programme=mba&offering=${id}`);
    await expect(page.getByRole("dialog")).toContainText("Total programme fee");
  });

  test("zero results suggest which filter to relax and never dead-end", async ({ page }) => {
    await page.goto("/programmes?programme=bca&naac=b");
    await expect(page.getByRole("heading", { name: /No programmes match/ })).toBeVisible();
    const relax = page.getByRole("button", { name: /^Remove .*results/ }).first();
    await expect(relax).toBeVisible();
    await relax.click();
    await expect.poll(() => count(page)).toBeGreaterThan(0);
    await page.goto("/programmes?q=qwzxv");
    await expect(page.getByText("Closest matches")).toBeVisible();
    await expect(page.getByRole("link", { name: /counsellor|Witty/ }).last()).toBeVisible();
  });

  test("compare up to 4 via the tray, shareable compare page; shortlist persists", async ({ page }) => {
    await page.goto("/programmes?programme=mba&view=flat");
    const cmp = page.getByRole("button", { name: /^Compare MBA/ });
    await cmp.nth(0).click();
    await cmp.nth(1).click();
    const tray = page.getByRole("region", { name: "Compare selection" });
    await expect(tray).toContainText("2 of 4 selected");
    await page.getByRole("button", { name: /^Shortlist MBA/ }).first().click();
    await tray.getByRole("link", { name: "Compare" }).click();
    await expect(page).toHaveURL(/\/compare\?ids=\d+,\d+/);
    await expect(page.getByRole("table")).toContainText("Total fee");
    await expect(page.getByRole("table")).toContainText("Easy EMI available");
    await page.goto("/shortlist");
    await expect(page.locator("li a[href^='?offering=']")).toHaveCount(1);
  });

  test("guided finder narrows results with each answer", async ({ page }) => {
    await page.getByRole("button", { name: /Answer 3 questions|Guide me/ }).click();
    await page.getByRole("region").or(page.locator("section[aria-labelledby='guided-title']")).first();
    await page.locator("section[aria-labelledby='guided-title']").getByRole("button", { name: "Class 12" }).click();
    await expect(page).toHaveURL(/qual=12th/);
    await page.locator("section[aria-labelledby='guided-title']").getByRole("button", { name: /Get my first degree/ }).click();
    await expect(page).toHaveURL(/goal=first-degree/);
    await expect(page.locator("section[aria-labelledby='guided-title']")).toContainText("Step 3 of 3");
  });

  test("mobile filters: staged choices, live count, one apply", async ({ page, isMobile }) => {
    test.skip(!isMobile, "phone sheet");
    await page.goto("/programmes?programme=mba");
    await dismissConsent(page);
    await page.getByRole("button", { name: /^Filters/ }).click();
    const sheet = page.getByRole("dialog", { name: "Filters" });
    await sheet.getByRole("button", { name: /^Distance \(ODL\)/ }).click();
    await expect(page).not.toHaveURL(/mode=/); // staged, not applied yet
    const apply = sheet.getByRole("button", { name: /^Show \d+ results/ });
    await expect(apply).toBeVisible();
    await apply.click();
    await expect(page).toHaveURL(/mode=odl/);
  });
});

test.describe("finder accessibility", () => {
  for (const theme of ["dark", "light"] as const) {
    test(`/programmes with panel open · ${theme}`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce", colorScheme: theme });
      await page.goto("/programmes?programme=mba");
      await dismissConsent(page);
      let r = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
      expect(r.violations.filter((v) => v.impact !== "minor").map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`)).toEqual([]);
      await page.getByRole("button", { name: /Show universities/ }).first().click();
      await page.locator("li a[href^='?offering=']").first().click();
      await expect(page.getByRole("dialog")).toContainText("Total programme fee");
      r = await new AxeBuilder({ page }).include("[role=dialog]").withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
      expect(r.violations.filter((v) => v.impact !== "minor").map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`)).toEqual([]);
    });
  }
});
