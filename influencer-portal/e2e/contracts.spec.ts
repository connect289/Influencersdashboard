import { expect, test, type Page } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

async function openDemoContract(page: Page, base: string) {
  await page.goto(base);
  await page
    .getByRole("link", { name: /Always-on MBA deal \(demo\)|CT-00001/ })
    .first()
    .click();
  await expect(page).toHaveURL(new RegExp(`${base}/[0-9a-f-]{36}`));
}

test.describe.serial("contracts: library, templates, negotiation, versions", () => {
  const key = `etiquette_${String(Date.now()).slice(-5)}`;

  test("a Super Admin adds a clause with a variable and marks it legally reviewed", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/contracts/clauses");
    await expect(page.getByRole("heading", { name: "Clause library" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Conduct and reputation" })).toBeVisible();
    await page.getByRole("link", { name: "New clause" }).click();
    await page.getByLabel("Title").fill("Social media etiquette");
    await page.getByLabel("Key").fill(key);
    await page.getByLabel("Category").selectOption("conduct");
    const editor = page.locator("#cl-body");
    await editor.click();
    await page.keyboard.type("The Creator keeps comments respectful when posting for ");
    await page.getByRole("button", { name: "Variable" }).click();
    await page.getByRole("menuitem", { name: /Eduwit's legal name/ }).click();
    await expect(editor).toContainText("{{eduwit.legal_name}}");
    await page.getByLabel("Negotiable").click();
    await page.getByRole("button", { name: "Create clause" }).click();
    await expect(page).toHaveURL(/\/admin\/contracts\/clauses\/[0-9a-f-]{36}$/);
    await expect(page.getByText("Not reviewed").first()).toBeVisible();
    await page.getByRole("button", { name: "Mark as legally reviewed" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Mark as legally reviewed" }).click();
    await expect(page.getByText("Marked as legally reviewed.")).toBeVisible();
    await expect(page.getByText("Reviewed").first()).toBeVisible();
  });

  test("the default template previews per deal type and takes the new clause", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/contracts/templates");
    await page.getByRole("link", { name: "Standard creator agreement" }).click();
    const preview = page.locator("article").last();
    await expect(preview.getByRole("heading", { name: /Exclusivity and non-compete/ })).toBeVisible();
    await page.getByLabel("Sample deal").selectOption("commission_only");
    await expect(preview.getByRole("heading", { name: /Exclusivity and non-compete/ })).toHaveCount(0);
    await page.getByLabel("Add a clause").selectOption({ label: "Social media etiquette (Conduct and morality)" });
    await page.getByRole("button", { name: "Add", exact: true }).click();
    await expect(preview.getByText(/keeps comments respectful when posting for Eduwit/)).toBeVisible();
    await page.getByRole("button", { name: "Save template" }).click();
    await expect(page.getByText("Template saved.")).toBeVisible();
  });

  test("the creator comments, suggests wording and sends a compensation counter-offer", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await openDemoContract(page, "/creator/contracts");
    await expect(page.getByText(/Read each clause/)).toBeVisible();

    const parties = page.locator("#clause-parties");
    await parties.getByRole("button", { name: "Comment" }).click();
    await parties.getByPlaceholder("Comment on this clause").fill("Please add my registered address.");
    await parties.getByRole("button", { name: "Post" }).click();
    await expect(page.getByText("Comment posted.")).toBeVisible();
    // Locked clauses take comments, not suggestions.
    await expect(parties.getByRole("button", { name: "Suggest wording" })).toHaveCount(0);

    const approval = page.locator("#clause-content_approval");
    await approval.getByRole("button", { name: "Suggest wording" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.locator("#sg-content_approval").click();
    await page.keyboard.press("ControlOrMeta+a");
    await page.keyboard.type(
      "Eduwit reviews each draft within two working days and asks for at most two rounds of changes.",
    );
    await dialog.getByLabel("Why (optional)").fill("Two rounds is the norm for me.");
    await dialog.getByRole("button", { name: "Send suggestion" }).click();
    await expect(page.getByText("Sent to Eduwit.")).toBeVisible();
    await expect(approval.getByText("Suggestion pending")).toBeVisible();

    await page.getByRole("link", { name: "Change requests" }).click();
    await page.getByRole("button", { name: "Propose different terms" }).click();
    await page.getByRole("dialog").getByLabel("Content fee").fill("20000");
    await page.getByRole("dialog").getByRole("button", { name: "Send counter-offer" }).click();
    await expect(page.getByText("Sent to Eduwit.")).toBeVisible();
    await expect(page.getByText("Compensation counter-offer").first()).toBeVisible();
  });

  test("the manager accepts the wording, counters the fee, compares versions and marks it ready", async ({ page }) => {
    test.slow();
    await staffLogin(page, "manager@example.test");
    await openDemoContract(page, "/admin/contracts");
    await expect(page.getByText("In negotiation").first()).toBeVisible();
    await page.getByRole("link", { name: /Change requests/ }).click();

    const wording = page.locator("article").filter({ hasText: "Wording: Content approval and revisions" });
    await expect(wording.locator("ins").first()).toBeVisible();
    await wording.getByRole("button", { name: "Accept" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Accept" }).click();
    await expect(page.getByText("Accepted. A new version has been generated.")).toBeVisible();

    const fee = page.locator("article").filter({ hasText: "Compensation counter-offer" });
    await expect(fee.getByText("₹15,000.00")).toBeVisible();
    await fee.getByRole("button", { name: "Counter" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Content fee").fill("18000");
    await dialog.getByLabel("Message to the creator").fill("We can meet you at 18,000.");
    await dialog.getByRole("button", { name: "Send counter" }).click();
    await expect(page.getByText("Countered. A new version has been generated.")).toBeVisible();

    await page.getByRole("link", { name: "Versions" }).click();
    await expect(page.getByText("Version 3").first()).toBeVisible();
    await page.getByLabel("From").selectOption({ label: "Version 1" });
    await page.getByRole("button", { name: "Show changes" }).click();
    await expect(
      page.locator("section").filter({ hasText: "Content approval and revisions" }).locator("ins").first(),
    ).toBeVisible();
    await expect(page.getByText("₹18,000").first()).toBeVisible();

    await page.getByRole("link", { name: "Document" }).click();
    await expect(page.locator("#clause-content_approval").getByText("Negotiated wording")).toBeVisible();
    await page.getByRole("button", { name: "Mark ready to sign" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Mark ready to sign" }).click();
    await expect(page.getByText("Marked ready to sign. The creator has been told.")).toBeVisible();
  });

  test("the creator sees the final version with the agreed wording and fee", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator/);
    await openDemoContract(page, "/creator/contracts");
    await expect(page.getByText("This version is final and ready for your signature.")).toBeVisible();
    await expect(page.getByText(/at most two rounds of changes/)).toBeVisible();
    await expect(page.getByText("₹18,000").first()).toBeVisible();
    await page.getByRole("link", { name: "Change requests" }).click();
    await expect(page.getByText("We can meet you at 18,000.")).toBeVisible();
  });
});
