import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

test.describe("in-app guides", () => {
  test("staff see their role's guide first, can search, and open guides from screens", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/deals");
    await page.getByRole("link", { name: "How this works" }).click();
    await expect(page).toHaveURL(/\/admin\/help\/influencer-manager#deals$/);
    await expect(page.getByRole("heading", { name: "Deals: building compensation" })).toBeVisible();
    await expect(page.getByRole("navigation", { name: "On this page" })).toBeVisible();

    await page.goto("/admin/help");
    await expect(page.getByText("For your role")).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Influencer Manager: creators, campaigns, deals and contracts/ }),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: /Finance: KYC, tax settings and payouts/ })).toBeVisible();
    // The developer guide needs system access.
    await expect(page.getByRole("link", { name: /Developer guide/ })).toHaveCount(0);
    await page.goto("/admin/help/developer");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();

    await page.goto("/admin/help");
    await page.getByLabel("Search the guides").fill("dry run");
    await page.getByLabel("Search the guides").press("Enter");
    await page.getByRole("link", { name: "Amendments and the dry run" }).click();
    await expect(page).toHaveURL(/#amendments$/);
  });

  test("a Super Admin also gets the developer guide", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/help");
    await page.getByRole("link", { name: /Developer guide/ }).click();
    await expect(page.getByRole("heading", { name: "Local set-up" })).toBeVisible();
  });

  test("creators get the creator guide only", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/help");
    await page.getByRole("link", { name: /Creator guide/ }).click();
    await expect(page.getByRole("heading", { name: "Your deals and how you earn" })).toBeVisible();
    await page.goto("/creator/help/super-admin");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
  });

  test("agencies get the agency guide", async ({ page }) => {
    await creatorLogin(page, "agency.owner@example.test");
    await expect(page).toHaveURL(/\/agency/);
    await page.goto("/agency/help");
    await page.getByRole("link", { name: /Agency guide/ }).click();
    await expect(page.getByRole("heading", { name: "Linking with your creators" })).toBeVisible();
  });
});
