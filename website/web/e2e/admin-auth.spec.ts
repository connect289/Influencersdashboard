import { expect, test } from "@playwright/test";
import { ensureStaffUser, fillCode, latestCode } from "./helpers";

// Staff sign-in with the email-code second factor (spec 11). Runs once (laptop) — the flow is not layout-dependent.
test.describe("admin sign-in", () => {
  test.skip(({ isMobile }) => isMobile, "laptop only");

  test("allow-listed staff must pass the email code; others are refused", async ({ page }) => {
    await ensureStaffUser("connect@eduwit.in", "local-test-password-1");
    await ensureStaffUser("intruder@example.com", "local-test-password-2");

    // not on the allow-list
    await page.goto("/admin/login");
    await page.getByLabel("Work email").fill("intruder@example.com");
    await page.getByLabel("Password").fill("local-test-password-2");
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.locator("main [role=alert]")).toContainText("does not have access");

    // dashboard is gated before sign-in
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/admin\/login/);

    // allow-listed owner
    await page.getByLabel("Work email").fill("connect@eduwit.in");
    await page.getByLabel("Password").fill("local-test-password-1");
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page).toHaveURL(/\/admin\/verify/);

    // second factor still required
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/admin\/verify/);

    const sentAt = new Date();
    await page.getByRole("button", { name: "Send code" }).click();
    await expect(page.getByText(/We sent a 6-digit code/)).toBeVisible();
    const code = await latestCode("connect@eduwit.in", sentAt);

    // wrong code first
    await fillCode(page, code === "000000" ? "111111" : "000000");
    await page.getByRole("button", { name: "Verify" }).click();
    await expect(page.locator("main [role=alert]")).toContainText("not right");

    await page.locator('input[name="code"]').evaluate((el) => ((el as HTMLInputElement).value = ""));
    await page.reload();
    await fillCode(page, code);
    await page.getByRole("button", { name: "Verify" }).click();
    await expect(page.getByRole("heading", { name: "Website admin" })).toBeVisible();
    await expect(page.getByText("super admin")).toBeVisible();

    // sign out
    await page.getByRole("button", { name: "Sign out" }).click();
    await expect(page).toHaveURL(/\/admin\/login/);
  });
});
