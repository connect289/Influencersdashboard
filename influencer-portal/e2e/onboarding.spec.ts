import { expect, test } from "@playwright/test";
import { staffLogin } from "./helpers";
import { sixDigitCode, waitForEmail } from "./mail";

test.describe.serial("self sign-up, onboarding and approval", () => {
  const email = `new.creator.${Date.now()}@example.test`;
  const handle = `newbie${String(Date.now()).slice(-6)}`;

  test("a creator signs up, completes every onboarding step and submits", async ({ page }) => {
    test.slow(); // the whole journey, from sign-up to submission
    await page.goto("/login");
    await page.getByRole("link", { name: "Sign up" }).click();
    await page.getByLabel("Your name").fill("Nina Newbie");
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Choose your Eduwit handle").fill(handle);
    await page.getByLabel("Profile link").fill(`https://instagram.com/${handle}`);
    await page.getByLabel("Followers (approximate)").fill("8,500");
    await page.getByRole("checkbox", { name: /I agree/ }).check();
    const since = new Date();
    await page.getByRole("button", { name: "Create my profile" }).click();
    await expect(page).toHaveURL(/\/login\/code/);
    const mail = await waitForEmail(email, since);
    await page.getByLabel("6-digit code").fill(sixDigitCode(mail.text));
    await page.getByRole("button", { name: "Continue" }).click();
    await expect(page).toHaveURL(/\/creator\/onboarding/);
    await expect(page.getByRole("heading", { name: "Get started" })).toBeVisible();

    // Profile.
    await page.getByLabel("Legal name").fill("Nina Newbie");
    await page.getByLabel("WhatsApp number").fill("98111 22334");
    await page.getByLabel("City").fill("Jaipur");
    await page.getByLabel("Topics you cover").fill("MBA");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByText("Profile saved.")).toBeVisible();

    // Platforms: added at sign-up.
    await page
      .getByRole("navigation", { name: "Onboarding steps" })
      .getByRole("link", { name: /Platforms/ })
      .click();
    await expect(page.getByText(`Instagram · @${handle}`)).toBeVisible();

    // KYC.
    await page.getByRole("navigation", { name: "Onboarding steps" }).getByRole("link", { name: /KYC/ }).click();
    await page.getByRole("textbox", { name: "PAN", exact: true }).fill("ABCPN1234K");
    await page.getByLabel("Name on PAN").fill("Nina Newbie");
    await page.getByLabel("Bank account number").fill("123456789000");
    await page.getByLabel("IFSC").fill("HDFC0000123");
    await page.getByLabel("Account holder name").fill("Nina Newbie");
    await page.getByRole("button", { name: "Submit for verification" }).click();
    await expect(page.getByText("Sent for verification.")).toBeVisible();

    // Terms.
    await page.getByRole("navigation", { name: "Onboarding steps" }).getByRole("link", { name: /Terms/ }).click();
    const boxes = page.getByRole("checkbox", { name: "I have read and agree to this" });
    await expect(boxes.first()).toBeVisible();
    for (let n = await boxes.count(); n > 0; n--) {
      await boxes.first().check();
      await page.getByRole("button", { name: "Accept" }).first().click();
      await expect(boxes).toHaveCount(n - 1);
    }

    // Course: two wrong answers first (75% < 80%), then all right (the seed's course has one correct option, always "B").
    await page
      .getByRole("navigation", { name: "Onboarding steps" })
      .getByRole("link", { name: /Compliance course/ })
      .click();
    const groups = page.getByRole("group");
    await expect(page.getByRole("heading", { name: "Quiz" })).toBeVisible();
    const count = await groups.count();
    expect(count).toBe(8);
    for (let i = 0; i < count; i++)
      await groups
        .nth(i)
        .getByRole("radio")
        .nth(i < 2 ? 0 : 1)
        .check();
    await page.getByRole("button", { name: "Check my answers" }).click();
    await expect(page.getByText(/You scored 75%/)).toBeVisible();
    await groups.nth(0).getByRole("radio").nth(1).check();
    await groups.nth(1).getByRole("radio").nth(1).check();
    await page.getByRole("button", { name: "Try again" }).click();
    await expect(page.getByText(/Passed with 100%/)).toBeVisible();

    await page
      .getByRole("navigation", { name: "Onboarding steps" })
      .getByRole("link", { name: /Submit/ })
      .click();
    await page.getByRole("button", { name: "Submit for approval" }).click();
    await expect(page.getByText("Submitted. We'll let you know when you're approved.")).toBeVisible();
  });

  test("a manager approves the creator from the approvals queue", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/creators/approvals");
    const row = page.getByRole("listitem").filter({ hasText: "Nina Newbie" });
    await expect(row.getByText("Signed up")).toBeVisible();
    await row.getByRole("button", { name: "Approve" }).click();
    await expect(page.getByText("Approved. The creator has been told.")).toBeVisible();
    await expect(page.getByText("Nobody is waiting")).toBeVisible();
  });

  test("staff invite a prospect, who receives the invitation email", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/creators?q=kabir");
    await page.getByRole("link", { name: /Kabir/ }).click();
    const since = new Date();
    await page.getByRole("button", { name: "Invite to portal" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Send invitation" }).click();
    await expect(page.getByText(/1 invitation sent/)).toBeVisible();
    const mail = await waitForEmail("kabir.creator@example.test", since);
    expect(mail.subject).toContain("invited");
  });
});
