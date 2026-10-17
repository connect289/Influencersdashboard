import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { adminSignIn, dbSelect, dbUpsert, resetAdminCodes } from "./helpers";

/** Admin (spec 11, Phase 10): content editing with audit and instant publish, flags, taxonomy, dashboards, roles. */
test.describe("admin", () => {
  test.skip(({ isMobile }) => isMobile, "laptop only");
  test.describe.configure({ mode: "serial" });

  // One staff sign-in for the whole file (the second factor caps codes per hour).
  let page: Page;
  test.beforeAll(async ({ browser, isMobile }) => {
    if (isMobile) return;
    await resetAdminCodes();
    page = await (await browser.newContext()).newPage();
    await adminSignIn(page, "connect@eduwit.in", "local-test-password-1");
  });

  test("a curated view created in the admin is live at once, audited, and can be removed", async ({ request }) => {
    await page.goto("/admin");
    await expect(page.getByText("Verified leads today")).toBeVisible();

    const slug = `online-mba-hr-${Date.now().toString(36)}`;
    await page.getByRole("navigation", { name: "Admin" }).getByRole("link", { name: "Curated finder views" }).click();
    await page.getByRole("link", { name: "New curated view" }).click();
    await page.getByLabel("Slug").fill(slug);
    await page.getByLabel("Title (page title)").fill("Online MBA in HR");
    await page.getByLabel("H1").fill("Online MBA in Human Resource Management");
    await page.getByLabel("Filters").fill('{"programme":["mba"],"spec":["hr"]}');
    await page.getByLabel("Status").selectOption("published");
    await page.getByRole("button", { name: "Save and publish" }).click();
    await expect(page.getByText("Saved and published.")).toBeVisible();

    await expect.poll(async () => (await request.get(`/programmes/${slug}`)).status()).toBe(200);
    const live = await (await request.get(`/programmes/${slug}`)).text();
    expect(live).toContain("Online MBA in Human Resource Management");
    const audit = await dbSelect<{ action: string }>("web_audit_log", `entity=eq.curated_views&entity_id=eq.${slug}&select=action`);
    expect(audit.map((a) => a.action)).toContain("create");

    await page.getByRole("button", { name: "Delete this curated view" }).click();
    await expect(page.getByText("Deleted.")).toBeVisible();
  });

  test("content rules: testimonials need consent before publishing", async () => {
    await page.goto("/admin/content/testimonials/edit");
    await page.getByRole("textbox", { name: "Name *" }).fill("Test Student");
    await page.getByRole("textbox", { name: "Quote *" }).fill("The counsellor explained every fee clearly.");
    await page.getByLabel("Published").check();
    await page.getByRole("button", { name: "Save and publish" }).click();
    await expect(page.getByText(/only after the student agreed to be quoted/)).toBeVisible();
    await expect(page.getByRole("textbox", { name: "Quote *" })).toHaveValue("The counsellor explained every fee clearly."); // input kept
  });

  test("announcement bar from the settings page appears on the site", async ({ request }) => {
    await page.goto("/admin/settings");
    const text = `Admissions open ${Date.now().toString(36)}`;
    await page.getByLabel("Announcement bar").fill(JSON.stringify({ text, tone: "info" }));
    await page.getByLabel("Announcement bar").locator("xpath=ancestor::form").getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Saved announcement.")).toBeVisible();
    await expect.poll(async () => (await (await request.get("/about")).text()).includes(text)).toBe(true);
    await page.getByLabel("Announcement bar").fill("null");
    await page.getByLabel("Announcement bar").locator("xpath=ancestor::form").getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Saved announcement.")).toBeVisible();
  });

  test("dashboards load: insights, data quality, taxonomy, outbox, audit, privacy", async () => {
    for (const [path, heading] of [
      ["/admin/insights", "Funnels and Witty insights"],
      ["/admin/data-quality", "Data quality"],
      ["/admin/taxonomy", "Taxonomy mapping"],
      ["/admin/outbox", "Outbox and dead letters"],
      ["/admin/audit", "Audit log"],
      ["/admin/privacy", "Privacy requests"],
    ] as const) {
      await page.goto(path);
      await expect(page.getByRole("heading", { level: 1, name: heading })).toBeVisible();
    }
    await page.goto("/admin/insights");
    await expect(page.getByText("Witty gate funnel")).toBeVisible();
    await expect(page.getByText("Email verified").first()).toBeVisible();
  });

  test("admin screens pass axe (WCAG 2.1 AA)", async () => {
    for (const path of ["/admin", "/admin/content/curated_views", "/admin/content/faqs/edit", "/admin/settings", "/admin/insights", "/admin/outbox"]) {
      await page.goto(path);
      const r = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
      expect(r.violations.map((v) => `${path}: ${v.id} (${v.nodes.length})`)).toEqual([]);
    }
  });

  test("viewers can read but not change", async ({ page }) => {
    await dbUpsert("web_admin_users", { email: "viewer@eduwit.in", role: "viewer", display_name: "Viewer", active: true }, "email");
    await adminSignIn(page, "viewer@eduwit.in", "local-test-password-3");
    await page.goto("/admin/content/faqs");
    await expect(page.getByRole("link", { name: "New FAQ" })).toHaveCount(0);
    await page.getByRole("link", { name: "View", exact: true }).first().click();
    await expect(page.getByText("Read only for your role.")).toBeVisible();
    await page.goto("/admin/settings");
    await expect(page.getByLabel("Witty on the website")).toBeDisabled();
  });
});
