import { readFileSync } from "node:fs";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { localEnv } from "./env";
import { creatorLogin, staffLogin } from "./helpers";

// Phase 10 journeys: tiers in Settings, the creator 360 Scorecard and Compliance tabs (run now, manual tier), the
// programme scorecard list, the creator's tier card, tier payout cycles for Finance, and the DPDP flows (data export
// download, a deletion request blocked by an open deal and rejected by staff). Uses the seed's Bronze, Silver and Gold
// tiers and Riya's monthly scorecard.

const env = localEnv();
const service = () =>
  createClient(env.NEXT_PUBLIC_SUPABASE_URL ?? "", env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
    auth: { persistSession: false },
  });
const RIYA = "riya.creator@example.test";
const riyaId = async () => {
  const { data } = await service()
    .schema("inf")
    .from("creators")
    .select("id")
    .eq("handle", "riyalearns")
    .single<{ id: string }>();
  return data?.id ?? "";
};

test.describe.serial("tiers, scorecards and privacy", () => {
  test("the Super Admin edits tiers; a duplicate rank is refused", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/settings");
    await page.getByRole("link", { name: /Tiers/ }).first().click();
    await expect(page).toHaveURL(/\/admin\/settings\/tiers/);
    await expect(page.getByText("Score 80+ · 10+ enrolments in 90 days · Compliance 80+")).toBeVisible();
    await page.getByRole("button", { name: "Add tier" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Name").fill("Platinum");
    await dialog.getByRole("spinbutton", { name: "Rank", exact: true }).fill("3");
    await dialog.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Another active tier already has this rank.")).toBeVisible();
    await dialog.getByRole("spinbutton", { name: "Rank", exact: true }).fill("4");
    await dialog.getByLabel("Minimum composite score").fill("92");
    await dialog.getByLabel("Early access to open campaigns (days)").fill("10");
    await dialog.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Tier saved")).toBeVisible();
    await expect(page.getByText("Score 92+")).toBeVisible();
    await expect(page.getByText("10-day early access")).toBeVisible();
  });

  test("the creator 360 shows the scorecard, runs one now and sets a tier by hand", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto(`/admin/creators/${await riyaId()}?tab=scorecard`);
    await expect(page.getByRole("heading", { name: "Scorecard", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Monthly scorecards" })).toBeVisible();
    await page.getByRole("button", { name: "Run scorecard now" }).click();
    await expect(page.getByText("Scorecard calculated")).toBeVisible();
    await expect(page.getByText("Composite").first()).toBeVisible();

    await page.getByRole("button", { name: "Set tier by hand" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Tier").selectOption({ label: "Silver" });
    const until = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
    await dialog.getByLabel("Holds until").fill(until);
    await dialog.getByLabel("Reason").fill("Launch partner for the MBA campaign");
    await dialog.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Manual tier set")).toBeVisible();
    await expect(page.getByText(/Set by hand until .*: Launch partner for the MBA campaign/)).toBeVisible();
    await expect(page.getByText("Set by hand from Bronze to Silver")).toBeVisible();
  });

  test("the compliance tab lists obligations per deliverable", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto(`/admin/creators/${await riyaId()}?tab=compliance`);
    await expect(page.getByRole("heading", { name: "Compliance", exact: true })).toBeVisible();
    await expect(page.getByText("Live on time").first()).toBeVisible();
    await expect(page.getByText("Brief acknowledged").first()).toBeVisible();
  });

  test("the programme scorecard list shows last month's cards", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/analytics/scorecards");
    await expect(page.getByRole("heading", { name: "Scorecards", exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "Riya Sharma" })).toBeVisible();
  });

  test("the creator sees their tier and what the next one needs", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator");
    await expect(page.getByText("You're in the Silver tier")).toBeVisible();
    await expect(page.getByText("+5% commission")).toBeVisible();
    await expect(page.getByText("To reach Gold")).toBeVisible();
  });

  test("Finance sees the tier payout cycles when preparing a batch", async ({ page }) => {
    await staffLogin(page, "finance@example.test");
    await page.goto("/admin/finance/payouts");
    await expect(page.getByText(/Tier payout cycles: Gold: Weekly · Silver: Fortnightly/)).toBeVisible();
  });

  test("the creator downloads their data", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/account");
    await page.getByRole("link", { name: "Manage my data" }).click();
    await expect(page.getByRole("heading", { name: "Privacy and data" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Communication consents" })).toBeVisible();
    await page.getByRole("button", { name: "Prepare my data" }).click();
    await expect(page.getByText("Your data is ready to download.")).toBeVisible();
    const download = page.waitForEvent("download");
    await page.getByRole("link", { name: "Download" }).click();
    const file = await download;
    expect(file.suggestedFilename()).toMatch(/\.json$/);
    const body: unknown = JSON.parse(readFileSync(await file.path(), "utf8"));
    expect(body).toHaveProperty("profile");
    expect(body).toHaveProperty("earnings");
  });

  test("a deletion request with an open deal is blocked for staff, who reject it", async ({ page, browser }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/account/privacy");
    await page.getByLabel("Why are you leaving? (optional)").fill("Taking a break from content");
    await page.getByRole("button", { name: "Request deletion" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Request deletion" }).click();
    await expect(page.getByText(/Deletion requested on/)).toBeVisible();

    const staff = await browser.newPage();
    await staffLogin(staff, "admin@example.test");
    await staff.goto("/admin/privacy");
    await expect(staff.getByRole("heading", { name: "Privacy requests" })).toBeVisible();
    await staff.getByRole("button", { name: "Review" }).click();
    const dialog = staff.getByRole("dialog");
    await expect(dialog.getByText("Taking a break from content")).toBeVisible();
    await expect(dialog.getByText(/still open\. End them before approving/)).toBeVisible();
    await dialog.getByLabel("Note to the creator").fill("Your MBA deal is still running; ask again once it ends.");
    await expect(dialog.getByRole("button", { name: "Approve and erase" })).toBeDisabled();
    await dialog.getByRole("button", { name: "Reject" }).click();
    await expect(staff.getByText("Request rejected")).toBeVisible();
    await staff.close();

    await page.reload();
    await expect(page.getByRole("button", { name: "Request deletion" })).toBeVisible();
  });
});
