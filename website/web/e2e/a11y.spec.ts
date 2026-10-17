import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { freshIp, latestCode, setSetting, typeCode, uniqueEmail, uniquePhone } from "./helpers";

/**
 * Phase 12 accessibility audit (spec 10.5, WCAG 2.1 AA): the screens the smoke and finder sweeps do not reach —
 * university and guide pages, legal pages, the 404 page, the cookie banner itself, the gate and application dialogs
 * (including error and code states), the signed-in account, and Witty with a conversation — in both themes, plus
 * keyboard-only checks (skip link, dialog focus and Escape). Results: docs/ACCESSIBILITY.md.
 */
const BASE = process.env.E2E_BASE_URL ?? "http://localhost:3100";
const TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];

async function axe(page: Page, include?: string) {
  let b = new AxeBuilder({ page }).withTags(TAGS);
  if (include) b = b.include(include);
  const r = await b.analyze();
  return r.violations.filter((v) => v.impact !== "minor").map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`);
}
/** Switches the theme on a loaded page and waits for colour transitions to finish (axe must not measure mid-fade). */
async function theme(page: Page, t: "dark" | "light") {
  await page.evaluate((x) => document.querySelectorAll("[data-theme]").forEach((el) => el.setAttribute("data-theme", x)), t);
  await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== "running"));
}
async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}

test.describe("accessibility audit: remaining pages", () => {
  for (const t of ["dark", "light"] as const) {
    for (const path of ["/universities/nmims", "/resources", "/legal/terms-and-conditions", "/legal/cookie-policy", "/no-such-page-a11y"]) {
      test(`${path} · ${t}`, async ({ page }) => {
        await page.emulateMedia({ reducedMotion: "reduce", colorScheme: t });
        await page.goto(path);
        await dismissConsent(page);
        await theme(page, t);
        expect(await axe(page)).toEqual([]);
      });
    }
    test(`cookie banner · ${t}`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce", colorScheme: t });
      await page.goto("/about");
      await theme(page, t);
      const banner = page.getByRole("region", { name: "Cookie preferences" });
      await expect(banner).toBeVisible();
      expect(await axe(page, "[aria-label='Cookie preferences']")).toEqual([]);
      await banner.getByRole("button", { name: "Choose", exact: true }).click();
      expect(await axe(page, "[aria-label='Cookie preferences']"), "category choices").toEqual([]);
    });
  }
});

test.describe("accessibility audit: dialogs and forms", () => {
  test.beforeEach(async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await freshIp(page);
  });

  test("application form: step 1 with errors, code entry, step 2 (both themes)", async ({ page }) => {
    await page.goto("/programmes?programme=mba&view=flat");
    await dismissConsent(page);
    await page.locator("li a[href^='?offering=']").first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Apply now" }).click();
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Enter your full name (letters only).")).toBeVisible();
    // errors are tied to their fields
    await expect(dialog.getByLabel("Full name", { exact: true })).toHaveAttribute("aria-invalid", "true");
    for (const t of ["dark", "light"] as const) {
      await theme(page, t);
      expect(await axe(page, "[role=dialog]"), `step 1 errors · ${t}`).toEqual([]);
    }
    const email = uniqueEmail("a11y");
    await dialog.getByLabel("Full name", { exact: true }).fill("Asha Rao");
    await dialog.getByLabel("Mobile number", { exact: true }).fill(uniquePhone());
    await dialog.getByLabel("Email", { exact: true }).fill(email);
    await dialog.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
    const sent = new Date();
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Check your email")).toBeVisible();
    expect(await axe(page, "[role=dialog]"), "code entry").toEqual([]);
    await typeCode(page, dialog, await latestCode(email, sent));
    await expect(dialog.getByText("Step 2 of 5: Academic")).toBeVisible();
    expect(await axe(page, "[role=dialog]"), "step 2").toEqual([]);

    // signed in now: the account pages
    for (const path of ["/account", "/legal/data-privacy-opt-out"]) {
      await page.goto(path);
      for (const t of ["dark", "light"] as const) {
        await theme(page, t);
        expect(await axe(page), `${path} · ${t}`).toEqual([]);
      }
    }
  });
});

test.describe("accessibility audit: keyboard", () => {
  test.skip(({ isMobile }) => isMobile, "keyboard checks on the laptop project");

  test("skip link is the first stop and moves focus to the content", async ({ page }) => {
    await page.goto("/about");
    await page.keyboard.press("Tab");
    await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/#main$/);
  });

  test("choosing in the cookie banner keeps keyboard focus on the page", async ({ page }) => {
    await page.goto("/about");
    const banner = page.getByRole("region", { name: "Cookie preferences" });
    await banner.getByRole("button", { name: "Only necessary" }).focus();
    await page.keyboard.press("Enter");
    await expect(banner).toBeHidden();
    await expect(page.locator("#main")).toBeFocused();
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => document.getElementById("main")!.contains(document.activeElement))).toBe(true);
  });

  test("detail panel: opens from the keyboard, traps focus, Escape closes and returns focus", async ({ page }) => {
    await page.goto("/programmes?programme=mba&view=flat");
    await dismissConsent(page);
    const trigger = page.locator("li a[href^='?offering=']").first();
    await trigger.focus();
    await page.keyboard.press("Enter");
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    for (let i = 0; i < 25; i++) {
      await page.keyboard.press("Tab");
      expect(await dialog.evaluate((d) => d.contains(document.activeElement))).toBe(true);
    }
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(trigger).toBeFocused();
  });
});

test.describe("accessibility audit: Witty", () => {
  test.describe.configure({ mode: "serial" });
  test.skip(({ isMobile }) => isMobile, "global flag; laptop project only");
  test.beforeAll(async () => setSetting(BASE, "web_advisor_enabled", true));
  test.afterAll(async () => setSetting(BASE, "web_advisor_enabled", false));
  test.beforeEach(async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await freshIp(page);
  });

  test("gate and a conversation (both themes)", async ({ page }) => {
    await expect.poll(async () => (await page.request.get("/witty")).status()).toBe(200);
    await page.goto("/witty?q=MBA%20for%20working%20professionals");
    await dismissConsent(page);
    await expect(page.getByRole("heading", { name: "Before we chat" })).toBeVisible();
    expect(await axe(page), "gate").toEqual([]);
    const email = uniqueEmail("a11yw");
    await page.getByLabel("Full name", { exact: true }).fill("Kavya Menon");
    await page.getByLabel("Mobile number", { exact: true }).fill(uniquePhone());
    await page.getByLabel("Email", { exact: true }).fill(email);
    await page.getByRole("checkbox", { name: /Witty, Eduwit's AI admissions assistant, is stored/ }).check();
    const sent = new Date();
    await page.getByRole("button", { name: "Verify email and continue" }).click();
    const region = page.getByRole("region", { name: "Chat with Witty" });
    await typeCode(page, region, await latestCode(email, sent));
    const log = page.getByRole("log", { name: "Conversation" });
    await expect(log.getByText(/options that could suit you/)).toBeVisible();
    // Send is enabled once the reply has finished streaming and there is text to send
    await page.getByLabel("Message Witty").fill("Marketing");
    await expect(page.getByRole("button", { name: "Send" })).toBeEnabled();
    for (const t of ["dark", "light"] as const) {
      await theme(page, t);
      expect(await axe(page), `conversation · ${t}`).toEqual([]);
    }
  });
});
