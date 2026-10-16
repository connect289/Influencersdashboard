import { existsSync, statSync } from "node:fs";
import { expect, test as setup } from "@playwright/test";
import { people, service, sessionOf, stateFile, type Who } from "./helpers";

/**
 * Signs each test person in once through the real screens: password, then the emailed code. The code is not read from
 * an inbox: the test asks the database for a fresh code for this browser's session (b2c.mfa_issue, service role only),
 * which is exactly what the app does before emailing it. "Trust this device" keeps later runs from needing a code.
 */
const WHO: Who[] = ["admin", "manager", "asha", "ravi", "marketing"];

for (const who of WHO) {
  setup(`sign in: ${who}`, async ({ page, context }) => {
    const file = stateFile(who);
    if (existsSync(file) && Date.now() - statSync(file).mtimeMs < 30 * 60_000) return; // signed in recently
    const p = people()[who];
    await page.goto("/login");
    await page.locator('input[name="email"]').fill(p.email);
    await page.locator('input[name="password"]').fill(p.password);
    await page.getByRole("button", { name: "Sign in", exact: true }).click();
    await page.waitForURL(/\/(verify|s|w)(\?|\/|$)/, { timeout: 30_000 });
    if (page.url().includes("/verify")) {
      const s = await sessionOf(context);
      const { data: code, error } = await service().schema("b2c").rpc("mfa_issue", { p_user: s.sub, p_session: s.session_id });
      if (error) throw new Error(`mfa_issue: ${error.message}`);
      await page.locator('input[name="code"]').fill(String(code));
      await page.locator('input[name="trust"]').check();
      await page.getByRole("button", { name: "Continue", exact: true }).click();
    }
    await page.waitForURL(new RegExp(`${p.home}(\\?|/|$)`), { timeout: 30_000 });
    await expect(page.locator("h1").first()).toBeVisible();
    await context.storageState({ path: file });
  });
}
