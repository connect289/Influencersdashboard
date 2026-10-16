import { expect, type Page } from "@playwright/test";
import { SEED_PASSWORD } from "./env";
import { sixDigitCode, waitForEmail } from "./mail";

export async function staffLogin(page: Page, email: string, opts: { trust?: boolean } = {}): Promise<void> {
  await page.goto("/login/staff");
  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(SEED_PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/verify/);
  const since = new Date();
  await page.getByRole("button", { name: "Email me a code" }).click();
  await expect(page.getByText(/A code is on its way/)).toBeVisible();
  const mail = await waitForEmail(email, since);
  expect(mail.subject).toMatch(/sign-in code/);
  await page.getByLabel("6-digit code").fill(sixDigitCode(mail.text));
  if (opts.trust) await page.getByLabel("Trust this device for 30 days").check();
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page).toHaveURL(/\/admin/);
}

export async function creatorLogin(page: Page, email: string): Promise<void> {
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  const since = new Date();
  await page.getByRole("button", { name: "Email me a code" }).click();
  await expect(page).toHaveURL(/\/login\/code/);
  const mail = await waitForEmail(email, since);
  await page.getByLabel("6-digit code").fill(sixDigitCode(mail.text));
  await page.getByRole("button", { name: "Continue" }).click();
}
