import { expect, test } from "@playwright/test";
import { staffLogin } from "./helpers";
import { waitForEmail } from "./mail";

test.describe("admin console", () => {
  test.beforeEach(async ({ page }) => {
    await staffLogin(page, "admin@example.test");
  });

  test("a setting change needs a reason, is versioned and lands in the audit log", async ({ page }) => {
    await page.goto("/admin/settings#attribution.rules");
    const card = page.locator("[id='attribution.rules']");
    const windowField = card.getByLabel("Attribution window (days)");
    const next = (await windowField.inputValue()) === "60" ? "61" : "60";
    await windowField.fill(next);
    await expect(card.getByRole("button", { name: "Save change" })).toBeDisabled();
    await card.getByLabel("Reason for the change").fill("Shorter window for the October campaign");
    await card.getByRole("button", { name: "Save change" }).click();
    await expect(page.getByText("Saved.")).toBeVisible();
    await page.reload();
    await expect(page.locator("[id='attribution.rules']").getByText(/Version \d+/)).toBeVisible();
    await page.goto("/admin/audit?entity=setting");
    await expect(page.getByRole("cell", { name: /setting/ }).first()).toBeVisible();
  });

  test("inviting a staff member emails a password link", async ({ page }) => {
    const email = `new.staff.${Date.now()}@example.test`;
    await page.goto("/admin/staff");
    await page.getByRole("button", { name: "Invite staff" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Name").fill("Nisha New");
    await dialog.getByLabel("Email").fill(email);
    await dialog.getByLabel(/Content Reviewer/).check();
    const since = new Date();
    await dialog.getByRole("button", { name: "Send invitation" }).click();
    await expect(page.getByText(`Invitation sent to ${email}.`)).toBeVisible();
    await expect(page.getByRole("cell", { name: new RegExp(email.replace(/[.]/g, "\\.")) })).toBeVisible();
    const mail = await waitForEmail(email, since);
    expect(mail.text).toContain("/auth/confirm?token_hash=");
  });

  test("system status and account pages load", async ({ page }) => {
    await page.goto("/admin/system");
    await expect(page.getByRole("heading", { name: "Job queue" })).toBeVisible();
    await expect(page.getByText("inf-jobs")).toBeVisible();
    await page.goto("/admin/account");
    await expect(page.getByText("This device")).toBeVisible();
  });
});
