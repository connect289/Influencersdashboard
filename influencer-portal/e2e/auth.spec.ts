import { expect, test } from "@playwright/test";
import { creatorLogin, staffLogin } from "./helpers";
import { SEED_PASSWORD } from "./env";
import { waitForEmail } from "./mail";

test.describe("signed out", () => {
  test("protected pages send people to the right sign-in", async ({ page }) => {
    await page.goto("/admin/settings");
    await expect(page).toHaveURL(/\/login\/staff\?next=%2Fadmin%2Fsettings/);
    await page.goto("/creator");
    await expect(page).toHaveURL(/\/login\?next=%2Fcreator/);
  });

  test("health endpoint reports ok without details", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.status()).toBe(200);
    const body = (await res.json()) as { status: string; checks: Record<string, boolean> };
    expect(body.status).toBe("ok");
    expect(Object.keys(body.checks).sort()).toEqual(["db", "queue", "storage"]);
  });

  test("internal endpoints refuse callers without the key", async ({ request }) => {
    expect((await request.post("/api/internal/jobs")).status()).toBe(401);
    expect((await request.get("/api/metrics/summary")).status()).toBe(401);
  });

  test("every response carries a nonce CSP and anti-framing headers", async ({ request }) => {
    const res = await request.get("/login");
    const csp = res.headers()["content-security-policy"] ?? "";
    expect(csp).toMatch(/script-src 'self' 'nonce-[^']+' 'strict-dynamic'/);
    expect(csp).toContain("frame-ancestors 'none'");
    expect(res.headers()["x-frame-options"]).toBe("DENY");
  });
});

test.describe("staff", () => {
  test("wrong password is refused with a generic message", async ({ page }) => {
    await page.goto("/login/staff");
    await page.getByLabel("Work email").fill("admin@example.test");
    await page.getByLabel("Password").fill("not-the-password");
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByText("Email or password is incorrect.")).toBeVisible();
  });

  test("password plus emailed code reaches the console", async ({ page }) => {
    await staffLogin(page, "admin@example.test", { fresh: true });
    await expect(page.getByRole("heading", { name: /Hello, Asha/ })).toBeVisible();
    await expect(
      page.getByRole("navigation", { name: "Main navigation" }).getByRole("link", { name: "Staff and roles" }),
    ).toBeVisible();
  });

  test("a signed-in staff member without the code can't open the console", async ({ page }) => {
    await page.goto("/login/staff");
    await page.getByLabel("Work email").fill("manager@example.test");
    await page.getByLabel("Password").fill(SEED_PASSWORD);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page).toHaveURL(/\/verify/);
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/verify/);
    await page.getByRole("button", { name: "Email me a code" }).click();
    await page.getByLabel("6-digit code").fill("000000");
    await page.getByRole("button", { name: "Continue" }).click();
    await expect(page.getByText(/That code isn't right|expired/)).toBeVisible();
  });

  test("a Viewer doesn't see or reach admin screens", async ({ page }) => {
    await staffLogin(page, "viewer@example.test", { fresh: true });
    const nav = page.getByRole("navigation", { name: "Main navigation" });
    await expect(nav.getByRole("link", { name: "Overview" })).toBeVisible();
    await expect(nav.getByRole("link", { name: "Staff and roles" })).toHaveCount(0);
    await expect(nav.getByRole("link", { name: "Settings" })).toHaveCount(0);
    // Hidden, not disabled: the screen renders the not-found page (streamed responses keep HTTP 200).
    await page.goto("/admin/staff");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
    await expect(page.getByText("admin@example.test")).toHaveCount(0);
  });

  test("a creator account can't use the staff sign-in", async ({ page }) => {
    await page.goto("/login/staff");
    await page.getByLabel("Work email").fill("riya.creator@example.test");
    await page.getByLabel("Password").fill(SEED_PASSWORD);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByText(/incorrect|can't sign in/)).toBeVisible();
  });
});

test.describe("creators", () => {
  test("email code sign-in, then terms acceptance clears it from the action centre", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await expect(page).toHaveURL(/\/creator$/);
    await expect(page.getByRole("heading", { name: /Hi Riya/ })).toBeVisible();
    await page.getByRole("link", { name: /Accept the platform terms/ }).click();
    for (let i = 0; i < 2; i++) {
      const card = page
        .locator("section")
        .filter({ has: page.getByRole("button", { name: "Accept" }) })
        .first();
      await card.getByLabel("I have read and agree to this").check();
      await card.getByRole("button", { name: "Accept" }).click();
      await expect(page.getByText("Your acceptance is recorded.").first()).toBeVisible();
    }
    await expect(page.getByText("Nothing to accept")).toBeVisible();
    await page.getByRole("link", { name: "Home" }).first().click();
    // The terms item is gone; the seeded contract and brief still need Riya.
    await expect(page.getByRole("link", { name: /A contract needs you/ })).toBeVisible();
    await expect(page.getByRole("link", { name: /Accept the platform terms/ })).toHaveCount(0);
  });

  test("an invited creator is linked on first sign-in", async ({ page }) => {
    await creatorLogin(page, "neha.creator@example.test");
    await expect(page).toHaveURL(/\/creator$/);
    await expect(page.getByRole("heading", { name: /Hi Neha/ })).toBeVisible();
  });

  test("an unknown email gets the same answer and no email", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Email").fill("nobody@example.test");
    await page.getByRole("button", { name: "Email me a code" }).click();
    await expect(page).toHaveURL(/\/login\/code/);
    await expect(waitForEmail("nobody@example.test", new Date(Date.now() - 5000), 3000)).rejects.toThrow();
  });

  test("a blocked creator is refused", async ({ page }) => {
    await creatorLogin(page, "blocked.creator@example.test");
    await expect(page).toHaveURL(/\/no-access\?portal=creator/);
  });

  test("signing out another device ends that session", async ({ browser }) => {
    // Two staff sessions for one person (creator OTPs to one address are throttled by Supabase Auth).
    const a = await (await browser.newContext()).newPage();
    const b = await (await browser.newContext()).newPage();
    await staffLogin(a, "reviewer@example.test", { fresh: true });
    await staffLogin(b, "reviewer@example.test", { fresh: true });
    await b.goto("/admin/account");
    await b.getByRole("button", { name: "Sign out", exact: true }).first().click();
    await expect(b.getByText("That device has been signed out.")).toBeVisible();
    await a.goto("/admin/account");
    await expect(a).toHaveURL(/\/login\/staff/);
  });
});
