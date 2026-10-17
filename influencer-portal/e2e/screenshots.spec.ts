// Screenshots of the main screens for reviews and guides. Runs only with SHOTS_DIR set.
import { devices, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";

const dir = process.env.SHOTS_DIR;
test.skip(!dir, "set SHOTS_DIR to capture screenshots");

test("laptop screens", async ({ browser }) => {
  const page = await (
    await browser.newContext({ viewport: { width: 1366, height: 860 }, baseURL: "http://localhost:3200" })
  ).newPage();
  await page.goto("/login/staff");
  await page.screenshot({ path: `${dir}/01-staff-login.png` });
  await staffLogin(page, "admin@example.test");
  await page.screenshot({ path: `${dir}/02-overview.png`, fullPage: true });
  await page.goto("/admin/settings");
  await page.screenshot({ path: `${dir}/03-settings.png` });
  await page.goto("/admin/staff");
  await page.screenshot({ path: `${dir}/04-staff.png` });
  await page.goto("/admin/analytics?test=1");
  await page.getByRole("heading", { name: "Leaderboards" }).waitFor();
  await page.screenshot({ path: `${dir}/07-analytics.png`, fullPage: true });
  await page.goto("/admin/analytics/finance?range=this_fy");
  await page.getByRole("heading", { name: "Reconciliation status" }).waitFor();
  await page.screenshot({ path: `${dir}/08-analytics-finance.png`, fullPage: true });
  await creatorLogin(page, "riya.creator@example.test");
  await page.goto("/creator");
  await page.getByRole("heading", { name: "Lead funnel" }).waitFor();
  await page.screenshot({ path: `${dir}/09-creator-home.png`, fullPage: true });
});

test("phone screens", async ({ browser }) => {
  const page = await (await browser.newContext({ ...devices["Pixel 7"], baseURL: "http://localhost:3200" })).newPage();
  await creatorLogin(page, "riya.creator@example.test");
  await page.getByRole("heading", { name: "Lead funnel" }).waitFor();
  await page.screenshot({ path: `${dir}/05-creator-home-phone.png`, fullPage: true });
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto("/creator/terms");
  await page.screenshot({ path: `${dir}/06-terms-phone-dark.png` });
});
