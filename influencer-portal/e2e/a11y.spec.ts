import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

// Accessibility pass (spec 19, Phase 10.4): axe checks for WCAG 2.1 A and AA on the key screens of every portal, in
// light mode. Serious and critical violations fail the test; the report names the rule and the elements.

const RIYA = "riya.creator@example.test";
const AGENCY = "agency.owner@example.test";

async function check(page: Page, path: string) {
  await page.goto(path);
  await page.waitForLoadState("networkidle");
  const result = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  const blocking = result.violations
    .filter((v) => v.impact === "serious" || v.impact === "critical")
    .flatMap((v) => v.nodes.map((n) => `${v.id}: ${n.target.join(" ")} ${n.failureSummary?.split("\n").at(-1) ?? ""}`));
  expect.soft(blocking, path).toEqual([]);
}

test.describe("accessibility", () => {
  test("public pages", async ({ page }) => {
    for (const path of ["/login", "/signup", "/legal/terms"]) await check(page, path);
  });

  test("creator portal", async ({ page }) => {
    await creatorLogin(page, RIYA);
    for (const path of [
      "/creator",
      "/creator/campaigns",
      "/creator/deals",
      "/creator/deliverables",
      "/creator/leads",
      "/creator/links",
      "/creator/earnings",
      "/creator/messages",
      "/creator/notifications/settings",
      "/creator/profile",
      "/creator/account/privacy",
      "/creator/help",
    ])
      await check(page, path);
  });

  test("staff console", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    for (const path of [
      "/admin",
      "/admin/analytics",
      "/admin/analytics/scorecards",
      "/admin/creators",
      "/admin/campaigns",
      "/admin/deals",
      "/admin/content",
      "/admin/leads",
      "/admin/finance",
      "/admin/finance/payouts",
      "/admin/communication/templates",
      "/admin/settings",
      "/admin/settings/tiers",
      "/admin/privacy",
      "/admin/audit",
      "/admin/system",
    ])
      await check(page, path);
  });

  test("agency portal", async ({ page }) => {
    await creatorLogin(page, AGENCY);
    for (const path of ["/agency", "/agency/messages", "/agency/team"]) await check(page, path);
  });
});
