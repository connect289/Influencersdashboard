import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { expect, type BrowserContext, type Page } from "@playwright/test";
import { SEED_PASSWORD } from "./env";
import { sixDigitCode, waitForEmail } from "./mail";

const AUTH_DIR = join(import.meta.dirname, ".auth");
const devicePath = (email: string) => join(AUTH_DIR, `${email.replace(/[^a-z0-9.@_-]/gi, "_")}.device.json`);
const sessionPath = (email: string) => join(AUTH_DIR, `${email.replace(/[^a-z0-9.@_-]/gi, "_")}.session.json`);
type Cookies = Parameters<BrowserContext["addCookies"]>[0];

/**
 * Signs a staff member in with password and the emailed code. The first sign-in of a run ticks "Trust this device"
 * and keeps the device cookie; later sign-ins of that person present it and skip the code (the product's trusted
 * device flow), because a full run signs some people in more often than the code limit (5 per 10 minutes) allows.
 * Later calls also reuse the person's session cookies while that session is live (D-98): the suite signs staff in
 * more often than the per-IP sign-in limit (30 per 5 minutes) allows. `fresh: true` always signs in with the code
 * (tests of the sign-in flow itself).
 */
export async function staffLogin(
  page: Page,
  email: string,
  opts: { trust?: boolean; fresh?: boolean } = {},
): Promise<void> {
  const file = devicePath(email);
  const session = sessionPath(email);
  if (!opts.fresh && existsSync(session)) {
    await page.context().addCookies(JSON.parse(readFileSync(session, "utf8")) as Cookies);
    await page.goto("/admin");
    await page.waitForLoadState("domcontentloaded");
    if (/^\/admin(\/|$)/.test(new URL(page.url()).pathname)) return;
    await page.context().clearCookies();
  }
  const known = !opts.fresh && existsSync(file);
  if (known) await page.context().addCookies(JSON.parse(readFileSync(file, "utf8")) as Cookies);
  await page.goto("/login/staff");
  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(SEED_PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(known ? /\/(admin|verify)/ : /\/verify/);
  if (new URL(page.url()).pathname.startsWith("/admin")) {
    if (!opts.fresh) writeFileSync(session, JSON.stringify(await page.context().cookies()));
    return;
  }
  const since = new Date();
  await page.getByRole("button", { name: "Email me a code" }).click();
  await expect(page.getByText(/A code is on its way/)).toBeVisible();
  const mail = await waitForEmail(email, since);
  expect(mail.subject).toMatch(/sign-in code/);
  await page.getByLabel("6-digit code").fill(sixDigitCode(mail.text));
  const remember = !opts.fresh || opts.trust === true;
  if (remember) await page.getByLabel("Trust this device for 30 days").check();
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page).toHaveURL(/\/admin/);
  if (!opts.fresh) {
    mkdirSync(AUTH_DIR, { recursive: true });
    const cookies = await page.context().cookies();
    writeFileSync(file, JSON.stringify(cookies.filter((c) => c.name === "inf_device")));
    writeFileSync(session, JSON.stringify(cookies));
  }
}

/**
 * Signs a creator or agency user in with the emailed one-time code. Later calls in the same run reuse that session's
 * cookies (and fall back to a new code if a test signed it out), because a full run signs some creators in more
 * often than the product's code limit (5 per email per 10 minutes) allows. `fresh: true` always uses the code.
 */
export async function creatorLogin(page: Page, email: string, opts: { fresh?: boolean } = {}): Promise<void> {
  const file = sessionPath(email);
  if (!opts.fresh && existsSync(file)) {
    await page.context().addCookies(JSON.parse(readFileSync(file, "utf8")) as Cookies);
    await page.goto("/creator");
    await page.waitForLoadState("domcontentloaded");
    if (/\/(creator|agency)(\/|$)/.test(new URL(page.url()).pathname)) return;
    await page.context().clearCookies();
  }
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  const since = new Date();
  await page.getByRole("button", { name: "Email me a code" }).click();
  await expect(page).toHaveURL(/\/login\/code/);
  const mail = await waitForEmail(email, since);
  await page.getByLabel("6-digit code").fill(sixDigitCode(mail.text));
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page).toHaveURL(/\/(creator|agency|no-access)/);
  if (!opts.fresh && /\/(creator|agency)(\/|$)/.test(new URL(page.url()).pathname)) {
    mkdirSync(AUTH_DIR, { recursive: true });
    writeFileSync(file, JSON.stringify(await page.context().cookies()));
  }
}
