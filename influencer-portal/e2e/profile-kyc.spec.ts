import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

// One creator (Arjun, onboarding) fills in the profile and KYC; Finance then reveals and verifies it.
test.describe.serial("creator profile and KYC", () => {
  test("creator adds a platform, a rate and submits KYC (stored values come back masked)", async ({ page }) => {
    await creatorLogin(page, "arjun.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);

    await page.goto("/creator/profile");
    await page.getByLabel("Topics you cover").fill("MBA, Finance");
    await page.getByRole("button", { name: "Save", exact: true }).first().click();
    await expect(page.getByText("Profile saved.")).toBeVisible();

    await page.getByRole("button", { name: "Add platform" }).click();
    const pd = page.getByRole("dialog");
    await pd.getByLabel("Handle").fill("@arjun_mba");
    await pd.getByLabel("Profile link").fill("https://instagram.com/arjun_mba");
    await pd.getByLabel("Followers").fill("85000");
    await pd.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Platform saved.")).toBeVisible();
    await expect(page.getByText("Instagram · @arjun_mba")).toBeVisible();
    await expect(page.getByText("85K followers")).toBeVisible();

    await page.getByRole("button", { name: "Add rate" }).click();
    const rd = page.getByRole("dialog");
    await rd.getByLabel("Price (₹)").fill("15000");
    await rd.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("₹15,000")).toBeVisible();

    await page.goto("/creator/kyc");
    await page.getByRole("textbox", { name: "PAN", exact: true }).fill("ABCPA1234K");
    await page.getByLabel("Name on PAN").fill("Arjun Mehta");
    await page.getByLabel("Bank account number").fill("123456789012");
    await page.getByLabel("IFSC").fill("sbin0001234");
    await page.getByLabel("Account holder name").fill("Arjun Mehta");
    await page.locator("input[type=file]").setInputFiles({
      name: "pan card.png",
      mimeType: "image/png",
      buffer: Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
        "base64",
      ),
    });
    await expect(page.getByRole("button", { name: "pan card.png" })).toBeVisible();
    await page.getByRole("button", { name: "Submit for verification" }).click();
    await expect(page.getByText("Sent for verification.")).toBeVisible();
    await page.reload();
    await expect(page.getByText("Waiting for review")).toBeVisible();
    await expect(page.getByText("On file: XXXXXX234K. Leave blank to keep it.")).toBeVisible();
    await expect(page.getByText("On file: XXXXXXXX9012. Leave blank to keep it.")).toBeVisible();
    // The full numbers are never in the page.
    expect(await page.content()).not.toContain("ABCPA1234K");
    expect(await page.content()).not.toContain("123456789012");
  });

  test("manager sees KYC masked and cannot reveal", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/kyc");
    await page.getByRole("link", { name: "Arjun" }).click();
    await expect(page.getByText("XXXXXX234K")).toBeVisible();
    await expect(page.getByRole("button", { name: "Show full details" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Mark verified" })).toHaveCount(0);
  });

  test("finance reveals with a reason (audited) and verifies", async ({ page }) => {
    await staffLogin(page, "finance@example.test");
    await page.goto("/admin/kyc");
    await page.getByRole("link", { name: "Arjun" }).click();
    await page.getByRole("button", { name: "Show full details" }).click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByRole("button", { name: "Show" })).toBeDisabled();
    await dialog.getByLabel("Reason").fill("Checking before the first payout");
    await dialog.getByRole("button", { name: "Show" }).click();
    await expect(page.getByText("ABCPA1234K")).toBeVisible();
    await expect(page.getByText("123456789012")).toBeVisible();
    await expect(page.getByRole("link", { name: /Open uploaded proof/ })).toBeVisible();
    await page.getByRole("button", { name: "Mark verified" }).click();
    await expect(page.getByText("KYC verified. The creator has been told.")).toBeVisible();
    await page.goto("/admin/kyc");
    await expect(page.getByText("Nothing to review")).toBeVisible();
  });
});
