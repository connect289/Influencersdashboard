import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const KEY_PAGES = ["/", "/thank-you", "/styleguide", "/about", "/how-it-works", "/contact", "/legal/privacy-policy", "/universities", "/programmes/online-mba", "/compare", "/shortlist", "/account/sign-in", "/c/demo-creator", "/witty"];

test.describe("site shell", () => {
  test("home renders real text as LCP, header and footer facts", async ({ page, isMobile }) => {
    const errors: string[] = [];
    page.on("console", (m) => m.type() === "error" && /Content Security Policy|Refused/.test(m.text()) && errors.push(m.text()));
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("contentinfo")).not.toContainText("09BXLPJ7928K1ZP");
    await expect(page.getByRole("contentinfo")).toContainText("All contact details");
    if (isMobile) {
      await expect(page.getByRole("navigation", { name: "Quick actions" })).toBeVisible();
      await page.getByRole("button", { name: "Open menu" }).click();
      await expect(page.getByRole("navigation", { name: "Menu" }).getByRole("link", { name: "Programmes" })).toBeVisible();
    } else {
      await expect(page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Programmes" })).toBeVisible();
    }
    expect(errors, "no CSP violations").toEqual([]);
  });

  test("consent banner: nothing optional loads before a choice; choice is remembered", async ({ page, context }) => {
    await context.clearCookies();
    await page.goto("/");
    const banner = page.getByRole("region", { name: "Cookie preferences" });
    await expect(banner).toBeVisible();
    expect(await page.evaluate(() => [...document.scripts].some((s) => /googletagmanager|fbevents|clarity/.test(s.src)))).toBe(false);
    await banner.getByRole("button", { name: "Only necessary" }).click();
    await expect(banner).toBeHidden();
    await page.reload();
    await expect(page.getByRole("region", { name: "Cookie preferences" })).toBeHidden();
    const consent = (await context.cookies()).find((c) => c.name === "ew_consent");
    expect(decodeURIComponent(consent?.value ?? "")).toContain('"analytics":false');
  });

  test("404 is never a dead end", async ({ page }) => {
    const res = await page.goto("/this-page-does-not-exist");
    expect(res?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1 })).toContainText("moved or doesn");
    await expect(page.getByRole("searchbox").or(page.getByPlaceholder(/Search/))).toBeVisible();
  });

  test("health endpoint: { ok } in public, detail with the internal key", async ({ request }) => {
    const pub = await request.get("/api/health");
    expect(pub.status()).toBe(200);
    expect(await pub.json()).toEqual({ ok: true });
    const res = await request.get("/api/health", { headers: { authorization: `Bearer ${process.env.WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001"}` } });
    const j = await res.json();
    expect(j.checks.db.ok).toBe(true);
    expect(JSON.stringify(j)).not.toMatch(/sb_secret|eyJhbGci/);
  });

  test("security headers are present", async ({ request }) => {
    const res = await request.get("/");
    const h = res.headers();
    expect(h["content-security-policy"]).toContain("frame-ancestors 'none'");
    expect(h["x-content-type-options"]).toBe("nosniff");
    expect(h["strict-transport-security"]).toContain("max-age=");
    expect(h["x-request-id"]).toBeTruthy();
  });

  test("attribution cookies hold no personal data", async ({ page, context }) => {
    await page.goto("/?utm_source=google&utm_medium=cpc&gclid=TEST123&email=someone@example.com");
    const ft = (await context.cookies()).find((c) => c.name === "ew_ft");
    expect(ft?.httpOnly).toBe(true);
    const decoded = Buffer.from(ft!.value, "base64url").toString();
    expect(decoded).toContain("TEST123");
    expect(decoded).not.toContain("someone@example.com");
  });
});

test.describe("accessibility (WCAG 2.1 AA, both themes)", () => {
  for (const path of KEY_PAGES) {
    for (const theme of ["dark", "light"] as const) {
      test(`${path} · ${theme}`, async ({ page }) => {
        await page.emulateMedia({ reducedMotion: "reduce", colorScheme: theme });
        await page.goto(path);
        await page.evaluate((t) => document.querySelectorAll("[data-theme]").forEach((el) => el.setAttribute("data-theme", t)), theme);
        const r = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).exclude("[aria-label='Cookie preferences']").analyze();
        const serious = r.violations.filter((v) => ["serious", "critical", "moderate"].includes(v.impact ?? ""));
        expect(serious.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`)).toEqual([]);
      });
    }
  }
});
