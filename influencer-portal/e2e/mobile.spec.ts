import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

test("creator portal on a phone uses the bottom navigation", async ({ page }) => {
  await creatorLogin(page, "riya.creator@example.test");
  const bottom = page.getByRole("navigation", { name: "Main navigation" }).last();
  await expect(bottom).toBeVisible();
  // Campaigns is a tab; Account sits in the "More" sheet once there are more than five items.
  await expect(bottom.getByRole("link", { name: "Campaigns" })).toBeVisible();
  await bottom.getByRole("button", { name: "More" }).click();
  await page.getByRole("dialog").getByRole("link", { name: "Account" }).click();
  await expect(page).toHaveURL(/\/creator\/account/);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

test("admin console on a phone opens the menu", async ({ page }) => {
  await staffLogin(page, "manager@example.test");
  await page.getByRole("button", { name: "Open menu" }).click();
  await expect(page.getByRole("dialog").getByRole("link", { name: "Overview" })).toBeVisible();
});
