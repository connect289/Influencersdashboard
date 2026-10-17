import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";
import { waitForEmail } from "./mail";

test.describe.serial("agencies", () => {
  const ownerEmail = `owner.${Date.now()}@agency.example.test`;

  test("staff create an agency and invite its owner", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/agencies");
    await page.getByRole("button", { name: "Add agency" }).click();
    await page.getByRole("dialog").getByRole("textbox", { name: "Name", exact: true }).fill("Northstar Creators");
    await page.getByRole("dialog").getByRole("button", { name: "Save" }).click();
    await expect(page).toHaveURL(/\/admin\/agencies\/[0-9a-f-]{36}/);
    await page.getByRole("button", { name: "Invite member" }).click();
    const d = page.getByRole("dialog");
    await d.getByRole("textbox", { name: "Name", exact: true }).fill("Nina North");
    await d.getByLabel("Email").fill(ownerEmail);
    await d.getByLabel("Role").selectOption("owner");
    const since = new Date();
    await d.getByRole("button", { name: "Send invitation" }).click();
    await expect(page.getByText(`Invitation sent to ${ownerEmail}.`)).toBeVisible();
    const mail = await waitForEmail(ownerEmail, since);
    expect(mail.subject).toContain("Northstar Creators");
  });

  test("the owner signs in to the agency portal and asks a creator to link", async ({ page }) => {
    await creatorLogin(page, ownerEmail);
    await expect(page).toHaveURL(/\/agency$/);
    await expect(page.getByRole("heading", { name: "Your creators" })).toBeVisible();
    await expect(page.getByText("No creators yet")).toBeVisible();
    await page.getByLabel("Creator handle").fill("@arjun_mba");
    await page.getByRole("button", { name: "Send request" }).click();
    await expect(page.getByText("Request sent.", { exact: false })).toBeVisible();
    await expect(page.getByText("Waiting for the creator")).toBeVisible();
    // The creator portal is not reachable for an agency account.
    await page.goto("/creator");
    await expect(page).toHaveURL(/\/agency$/);
  });

  test("the creator accepts with chosen permissions; the agency then sees the profile", async ({ page }) => {
    await creatorLogin(page, "arjun.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/agency");
    const card = page.locator("section").filter({ hasText: "Northstar Creators" });
    await card.getByRole("switch", { name: "Negotiate and sign" }).click();
    await card.getByRole("button", { name: "Accept" }).click();
    await expect(page.getByText("Permissions saved.")).toBeVisible();

    await page.context().clearCookies();
    await creatorLogin(page, ownerEmail);
    await expect(page).toHaveURL(/\/agency$/);
    await page.getByRole("link", { name: /Arjun/ }).click();
    await expect(page.getByText("Negotiate and sign", { exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Platforms" })).toBeVisible();
    // Read-only: no edit controls, and no KYC or contact details anywhere.
    await expect(page.getByRole("button", { name: "Add platform" })).toHaveCount(0);
    expect(await page.content()).not.toContain("arjun.creator@example.test");
  });
});
