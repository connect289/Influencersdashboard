import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

test.describe.serial("deals: build, simulate, propose, negotiate, amend", () => {
  const title = `Diwali MBA deal ${String(Date.now()).slice(-5)}`;
  let dealUrl = "";

  test("a manager builds a deal from a preset with the live simulator and proposes it", async ({ page }) => {
    test.slow();
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/deals");
    await page.getByRole("link", { name: "New deal" }).click();
    // Retry until the page has hydrated and the search answers.
    await expect(async () => {
      await page.getByLabel("Creator").fill("");
      await page.getByLabel("Creator").fill("Riya");
      await expect(page.getByRole("option", { name: /Riya Sharma/ })).toBeVisible({ timeout: 2_000 });
    }).toPass();
    await page.getByRole("option", { name: /Riya Sharma/ }).click();
    await page.getByLabel("Title").fill(title);
    await page.getByLabel("Start from preset").selectOption({ label: "Fixed + commission" });
    await page.getByRole("button", { name: "Create and open builder" }).click();
    await expect(page).toHaveURL(/\/admin\/deals\/[0-9a-f-]{36}\?tab=terms$/);
    dealUrl = page.url().replace(/\?.*$/, "");

    // The simulator runs on the unsaved builder state.
    await expect(page.getByText("Earnings simulator")).toBeVisible();
    await expect(page.getByText("Projected margin")).toBeVisible();
    await page.locator("#fx-fee-amount").fill("20000");
    await expect(page.getByRole("definition").filter({ hasText: "₹20,000.00" }).first()).toBeVisible();

    // Validation: milestone shares must add up to 100%.
    await page.locator("#fx-fee-signing-share").fill("40");
    await expect(page.getByText("Milestone shares must add up to 100%.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Save terms" })).toBeDisabled();
    await page.locator("#fx-fee-signing-share").fill("50");
    await page.getByRole("button", { name: "Save terms" }).click();
    await expect(page.getByText("Saved.")).toBeVisible();

    await page.getByRole("button", { name: "Send terms to creator" }).click();
    await page.getByRole("dialog").getByLabel("Note to the creator").fill("Fee as discussed on the call.");
    await page.getByRole("dialog").getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Terms sent to the creator.")).toBeVisible();
    await expect(page.getByText(/Version 1 is waiting for the creator's answer/)).toBeVisible();
  });

  test("the creator reviews the terms with their own simulator and declines with a reason", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/deals");
    await page.getByRole("link", { name: new RegExp(title) }).click();
    await expect(page.getByText("Terms to review")).toBeVisible();
    await expect(page.getByText("Content fee").first()).toBeVisible();
    await expect(page.getByText("Earnings simulator")).toBeVisible();
    await expect(page.getByText("Net payout")).toBeVisible();
    // Never Eduwit's economics.
    await expect(page.getByText("Projected margin")).toHaveCount(0);
    await expect(page.getByText("Eduwit view (staff only)")).toHaveCount(0);
    await page.getByRole("button", { name: "Decline" }).click();
    await page
      .getByRole("dialog")
      .getByLabel("What would you like changed?")
      .fill("Please make it 60/40 with more on signing.");
    await page.getByRole("dialog").getByRole("button", { name: "Decline" }).click();
    await expect(page.getByText("Terms declined. Eduwit will revise them.")).toBeVisible();
  });

  test("the manager revises and re-proposes; the creator accepts", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto(`${dealUrl}?tab=versions`);
    await expect(page.getByText("Please make it 60/40 with more on signing.")).toBeVisible();
    await page.goto(`${dealUrl}?tab=terms`);
    await page.locator("#fx-fee-signing-share").fill("60");
    await page.locator("#fx-fee-live-share").fill("40");
    await page.getByRole("button", { name: "Save terms" }).click();
    await expect(page.getByText("Saved.")).toBeVisible();
    await page.getByRole("button", { name: "Send terms to creator" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Terms sent to the creator.")).toBeVisible();

    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/deals");
    await page.getByRole("link", { name: new RegExp(title) }).click();
    await page.getByRole("button", { name: "Accept terms" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Accept terms" }).click();
    await expect(page.getByText("Terms accepted.")).toBeVisible();
    await expect(page.getByText("Terms in force (version 2)")).toBeVisible();
  });

  test("the manager activates, amends with a dry run, and the creator accepts the amendment", async ({ page }) => {
    test.slow();
    await staffLogin(page, "manager@example.test");
    await page.goto(dealUrl);
    await page.getByRole("button", { name: "Activate" }).click();
    await page.getByRole("dialog").getByLabel("Reason").fill("Signed on paper at the office");
    await page.getByRole("dialog").getByRole("button", { name: "Activate" }).click();
    await expect(page.getByText("Deal status updated.")).toBeVisible();

    await page.getByRole("button", { name: "Amend terms" }).click();
    await expect(page.getByText(/You are preparing an amendment/)).toBeVisible();
    await page.locator("#fx-fee-amount").fill("25000");
    await page.getByRole("button", { name: "Save terms" }).click();
    await expect(page.getByText("Saved.")).toBeVisible();

    await page.getByRole("link", { name: "Dry run" }).click();
    await page.getByRole("button", { name: "Run dry run" }).click();
    await expect(page.getByText("Change for the creator")).toBeVisible();
    await expect(page.getByText("Recent dry runs")).toBeVisible();

    await page.getByRole("button", { name: "Propose amendment" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Terms sent to the creator.")).toBeVisible();

    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/deals");
    await page.getByRole("link", { name: new RegExp(title) }).click();
    await expect(page.getByText(/Updated terms to review \(version 3\)/)).toBeVisible();
    await page.getByRole("button", { name: "Accept terms" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Accept terms" }).click();
    await expect(page.getByText("Terms in force (version 3)")).toBeVisible();
  });

  test("presets: system presets are read-only, staff save their own", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/deals/presets");
    await page.getByRole("link", { name: "Commission only" }).click();
    await page.getByRole("link", { name: "Copy to a new preset" }).click();
    const name = `Reel pack ${String(Date.now()).slice(-5)}`;
    await page.getByLabel("Name").first().fill(name);
    await page.getByRole("button", { name: "Save preset" }).click();
    await expect(page.getByText("Preset saved.")).toBeVisible();
    await page.goto("/admin/deals/presets");
    await expect(page.getByRole("link", { name })).toBeVisible();
  });
});
