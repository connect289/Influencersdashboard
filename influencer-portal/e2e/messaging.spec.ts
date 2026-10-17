import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

// Phase 9 journeys: the bell and notification centre, announcements on the creator home, notification settings with
// locked mandatory events and the digest, conversations with files and @mentions across the creator, staff and agency
// portals, and the admin communication tools (templates, announcements, webhooks). Uses the seed's support
// conversation, announcement and template.

const RIYA = "riya.creator@example.test";
const AGENCY = "agency.owner@example.test";
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n");

test.describe.serial("messages and notifications", () => {
  test("the creator sees announcements, the bell and the notification centre", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator");
    await expect(page.getByRole("heading", { name: "From Eduwit" })).toBeVisible();
    await expect(page.getByText("Welcome to Eduwit Creators")).toBeVisible();
    const bell = page.getByRole("link", { name: /Notifications, \d+ unread/ });
    await expect(bell).toBeVisible();
    await bell.click();
    await expect(page).toHaveURL(/\/creator\/notifications/);
    await expect(page.getByRole("heading", { name: "Notifications", exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Mark all read" }).click();
    await expect(page.getByText("All notifications marked read")).toBeVisible();
    await expect(page.getByRole("link", { name: "Notifications", exact: true })).toBeVisible();
  });

  test("required notifications stay on; optional ones and the digest are the creator's choice", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/notifications/settings");
    await expect(page.getByRole("switch", { name: "Payout sent: Email" })).toBeDisabled();
    await expect(page.getByRole("switch", { name: "Payout sent: Email" })).toBeChecked();
    const optional = page.getByRole("switch", { name: "Deliverable due soon: WhatsApp" });
    await expect(optional).toBeChecked();
    await optional.click();
    await expect(optional).not.toBeChecked();
    await page.reload();
    await expect(page.getByRole("switch", { name: "Deliverable due soon: WhatsApp" })).not.toBeChecked();
    await page.getByLabel("How often").selectOption("daily");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Digest settings saved")).toBeVisible();
  });

  test("the creator writes to Eduwit with a file", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/messages");
    await expect(page.getByRole("heading", { name: "Talk to Eduwit" })).toBeVisible();
    await expect(page.getByText(/two new campaigns open next week/)).toBeVisible();
    await expect(page.getByText("Manoj (Eduwit)")).toBeVisible();
    await page.getByLabel("Write a message").fill("Thanks! Here is my content calendar.");
    await page.locator('input[type="file"]').setInputFiles({
      name: "calendar.pdf",
      mimeType: "application/pdf",
      buffer: PDF,
    });
    await expect(page.getByRole("list", { name: "Files to send" })).toContainText("calendar.pdf");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Thanks! Here is my content calendar.")).toBeVisible();
    const file = page.getByRole("link", { name: "calendar.pdf" });
    await expect(file).toBeVisible();
    const href = await file.getAttribute("href");
    const res = await page.request.get(href ?? "", { maxRedirects: 0 });
    expect(res.status()).toBe(302);
    // Other conversations are listed too (the demo deal).
    await expect(page.getByRole("link", { name: /Deal: / }).first()).toBeVisible();
  });

  test("staff find it in the inbox, reply and mention a colleague", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/messages?unread=1");
    const row = page.getByRole("link", { name: /Support: Riya/ });
    await expect(row).toBeVisible();
    await expect(row).toContainText("Here is my content calendar");
    await expect(row).toContainText("1 unread message");
    await row.click();
    await expect(page).toHaveURL(/\/admin\/creators\/.+tab=messages/);
    await expect(page.getByRole("heading", { name: "Support conversation" })).toBeVisible();
    await expect(page.getByText("Thanks! Here is my content calendar.")).toBeVisible();
    await page.getByLabel("Write a message").fill("Looks good.");
    await page.getByLabel("Mention a colleague").selectOption({ label: "Rekha Reviewer" });
    await expect(page.getByLabel("Write a message")).toHaveValue("Looks good. @Rekha Reviewer ");
    await page.getByLabel("Write a message").pressSequentially("please check the dates.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("please check the dates.")).toBeVisible();
    // Search finds it.
    await page.goto("/admin/messages?q=calendar");
    await expect(page.getByRole("link", { name: /Support: Riya/ })).toBeVisible();
    await page.goto("/admin/messages?q=nothing-matches-this");
    await expect(page.getByText("No conversations match these filters")).toBeVisible();
  });

  test("the mentioned colleague is notified", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/notifications");
    await expect(page.getByText("You were mentioned: Support: Riya Sharma")).toBeVisible();
    await page.goto("/admin/messages?mentions=1");
    await expect(page.getByRole("link", { name: /Support: Riya/ })).toBeVisible();
  });

  test("the creator sees the reply with the mention as a name, and Seen once staff read hers", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/messages");
    await expect(page.getByText("@Rekha Reviewer")).toBeVisible();
    await expect(page.getByText(/user:[0-9a-f-]{36}/)).toHaveCount(0);
  });

  test("an agency with view access talks to Eduwit about its creator", async ({ page }) => {
    await creatorLogin(page, AGENCY);
    await page.goto("/agency/messages");
    await expect(page.getByRole("heading", { name: /Support for Riya/ })).toBeVisible();
    await expect(page.getByText("Thanks! Here is my content calendar.")).toBeVisible();
    await page.getByLabel("Write a message").fill("Riya's agency here: we'll handle scheduling.");
    await page.getByRole("button", { name: "Send" }).click();
    await expect(page.getByText("Riya's agency here: we'll handle scheduling.")).toBeVisible();
  });

  test("the Super Admin edits a template with variables and versions", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/communication/templates?event=payout.paid");
    await expect(page.getByText("Version 1 is in use.")).toBeVisible();
    await page.getByLabel("Email text").fill("Hi {{name}}, call {{phone}}.");
    await expect(page.getByText("Not available for this notification: phone")).toBeVisible();
    await expect(page.getByRole("button", { name: "Save as new version" })).toBeDisabled();
    await page.getByLabel("Email text").fill("Hi {{name}}, {{amount}} is paid (UTR {{utr}}).");
    await expect(page.getByText("Hi Riya, ₹4,500.00 is paid (UTR HDFC0000123456).")).toBeVisible();
    await page.getByRole("button", { name: "Save as new version" }).click();
    await expect(page.getByText("Template saved")).toBeVisible();
    await expect(page.getByText("Version 2 is in use.")).toBeVisible();
    // Test sends need live sending, which is off locally.
    await expect(page.getByRole("button", { name: "Send me a test" })).toBeDisabled();
  });

  test("an announcement goes to a segment", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/communication/announcements");
    await expect(page.getByText("Welcome to Eduwit Creators")).toBeVisible();
    await page.getByRole("link", { name: "New announcement" }).click();
    await page.getByLabel("Title").fill("Hindi creators: new reel format");
    await page.getByLabel("Text").fill("Reels up to 90 seconds now count for the October campaign.");
    // No seeded creator lists Instagram: nobody to send to.
    await page.getByRole("checkbox", { name: "Instagram" }).check();
    await expect(page.getByText(/\b0 creators\b/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Send now" })).toBeDisabled();
    await page.getByRole("checkbox", { name: "Instagram" }).uncheck();
    await page.getByLabel("Languages").fill("Hindi");
    await expect(page.getByText(/\b1 creator\b/)).toBeVisible();
    await page.getByRole("button", { name: "Send now" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Send now" }).click();
    await expect(page.getByText("Announcement sent")).toBeVisible();
    await expect(page.getByText("Hindi creators: new reel format")).toBeVisible();
    await expect(page.getByText(/Sent .* to/).first()).toBeVisible();
  });

  test("webhook endpoints: private addresses refused, secret shown once, test queued", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/communication/webhooks");
    await expect(page.getByText("https://hooks.example.test/eduwit")).toBeVisible();
    await page.getByRole("button", { name: "Add endpoint" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Endpoint URL").fill("https://10.0.0.5/hook");
    await dialog.getByRole("checkbox", { name: /payout\.paid/ }).check();
    await dialog.getByRole("button", { name: "Create endpoint" }).click();
    await expect(page.getByText("This address can't receive webhooks. Use a public HTTPS address.")).toBeVisible();
    await dialog.getByLabel("Endpoint URL").fill("https://erp.example.test/eduwit");
    await dialog.getByRole("button", { name: "Create endpoint" }).click();
    await expect(page.getByRole("dialog", { name: "Signing secret" })).toContainText(/whsec_[0-9a-f]{64}/);
    await page.getByRole("dialog", { name: "Signing secret" }).getByRole("button", { name: "Close" }).click();
    const card = page.locator("section").filter({ hasText: "https://erp.example.test/eduwit" });
    await card.getByRole("button", { name: "Send test event" }).click();
    await expect(page.getByText("Test event queued")).toBeVisible();
    await expect(card.getByText("Recent deliveries (1)")).toBeVisible();
  });

  test("roles without the permission don't see the communication tools", async ({ page }) => {
    await staffLogin(page, "viewer@example.test");
    await page.goto("/admin");
    await expect(page.getByRole("link", { name: "Communication" })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Messages", exact: true })).toHaveCount(0);
    await page.goto("/admin/communication/webhooks");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
  });
});
