import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

test.describe.serial("campaigns, applications and negotiation", () => {
  const name = `Spring BBA drive ${String(Date.now()).slice(-5)}`;

  test("a manager builds a campaign with a catalogue programme and opens it", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/campaigns");
    await page.getByRole("link", { name: "New campaign" }).click();
    await page.getByLabel("Campaign name").fill(name);
    await page.getByLabel("Search programmes or universities").fill("BBA");
    await page.getByRole("option", { name: /Online BBA/ }).click();
    await expect(page.getByText("Online BBA · Demo State University")).toBeVisible();
    const ends = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
    await page.getByLabel("Ends").fill(ends);
    await page.getByLabel("Budget (₹)").fill("200000");
    await page.getByLabel("Compensation summary").fill("Fixed fee for one reel");
    await page.getByRole("button", { name: "Create campaign" }).click();
    await expect(page).toHaveURL(/\/admin\/campaigns\/[0-9a-f-]{36}$/);
    await page.getByRole("button", { name: "Open", exact: true }).click();
    await expect(page.getByText("Campaign is now Open.")).toBeVisible();
  });

  test("an approved creator finds it in the marketplace and applies", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/campaigns");
    await page.getByRole("link", { name: new RegExp(name) }).click();
    await expect(page.getByText("Online BBA")).toBeVisible();
    // Budget and internal notes never reach creators.
    expect(await page.content()).not.toContain("200000");
    await page.getByLabel("Your pitch").fill("My audience is first-year commerce students.");
    await page.getByLabel("Fixed fee (₹)").fill("15000");
    await page.getByRole("button", { name: "Send application" }).click();
    await expect(page).toHaveURL(/\/creator\/applications\//);
    await expect(page.getByText("Creator's proposal")).toBeVisible();
    await expect(page.getByText("₹15,000")).toBeVisible();
  });

  test("the manager counters with a message", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/applications");
    await page.getByRole("row").filter({ hasText: name }).getByRole("link", { name: "Riya" }).click();
    await page.getByRole("button", { name: "Make a counter-offer" }).click();
    const d = page.getByRole("dialog");
    await d.getByLabel("Fixed fee (₹)").fill("12000");
    await d.getByLabel("Message (optional)").fill("We can do 12k for one reel.");
    await d.getByRole("button", { name: "Send offer" }).click();
    await expect(page.getByText("Offer sent.")).toBeVisible();
    await page.getByLabel("Write a message").fill("Happy to talk timing.");
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect(page.getByText("Happy to talk timing.")).toBeVisible();
  });

  test("the creator accepts the counter-offer", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await page.goto("/creator/campaigns?tab=applications");
    await page.getByRole("link", { name: new RegExp(name) }).click();
    await expect(page.getByText("Happy to talk timing.")).toBeVisible();
    await page.getByRole("button", { name: "Accept this offer" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Accept this offer" }).click();
    await expect(page.getByText("Offer accepted.")).toBeVisible();
    await expect(page.getByText(/Accepted\. The agreed terms are final/)).toBeVisible();
    await expect(page.getByText("₹12,000").first()).toBeVisible();
  });
});
