import { expect, test, type Page } from "@playwright/test";
import { adminSignIn, dbSelect, resetAdminCodes } from "./helpers";

/** SEO toolkit (spec 13.4, Phase 11) with sample Search Console data (no credentials in CI, S-20). */
test.describe("SEO toolkit", () => {
  test.skip(({ isMobile }) => isMobile, "laptop only");
  test.describe.configure({ mode: "serial" });

  let page: Page;
  test.beforeAll(async ({ browser, isMobile }) => {
    if (isMobile) return;
    await resetAdminCodes();
    page = await (await browser.newContext()).newPage();
    await adminSignIn(page, "connect@eduwit.in", "local-test-password-1");
  });

  test("Search Console sync fills the dashboard (labelled sample data)", async () => {
    await page.goto("/admin/seo");
    await page.getByRole("button", { name: "Sync now" }).click();
    await expect(page.getByRole("status")).toContainText(/Imported \d+ rows \(sample data/);
    await expect(page.getByText(/sample data \(Search Console not connected/)).toBeVisible();
    await expect(page.getByRole("heading", { name: "Top queries" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "online mba fees" }).first()).toBeVisible();
  });

  test("opportunity → draft curated view; question → guide idea → brief → first draft", async () => {
    await page.goto("/admin/seo/opportunities");
    const row = page.getByRole("listitem").filter({ hasText: "online mba for working professionals" });
    await row.getByRole("button", { name: "Create draft view" }).click();
    await expect(page).toHaveURL(/\/admin\/content\/curated_views\/edit/);
    await expect(page.getByLabel("Filters")).toHaveValue(/"mba"/);
    await expect(page.getByLabel("Status")).toHaveValue("draft");
    await page.getByRole("button", { name: /Delete this curated view/ }).click();

    await page.goto("/admin/seo/opportunities");
    await page.getByRole("listitem").filter({ hasText: "is online degree valid for government jobs" }).getByRole("button", { name: "Add guide idea" }).click();
    await expect(page.getByRole("status")).toContainText("to the planner");
    const idea = page.getByRole("listitem").filter({ hasText: "Is Online Degree Valid For Government Jobs?" });
    await idea.getByRole("button", { name: "Generate brief" }).click();
    await expect(page.getByRole("status")).toContainText("Brief ready");
    await page.getByRole("listitem").filter({ hasText: "Is Online Degree Valid For Government Jobs?" }).getByRole("button", { name: "First draft" }).click();
    await expect(page.getByRole("status")).toContainText(/Draft skeleton created|First draft written/);
    const [r] = await dbSelect<{ status: string; brief: { facts: string[]; rules: string[] }; author_id: number | null }>(
      "web_resources",
      "slug=eq.is-online-degree-valid-for-government-jobs&select=status,brief,author_id",
    );
    expect(r!.status).toBe("draft");
    expect(r!.brief.rules.join(" ")).toContain("named author");
    expect(r!.author_id).toBeNull(); // never published without a named author and reviewer
  });

  test("on-page checker scores the content pages", async () => {
    await page.goto("/admin/seo/checks");
    await page.getByRole("button", { name: "Run checks now" }).click();
    await expect(page.getByRole("status")).toContainText(/Checked \d+ pages; average score \d+/);
    await expect(page.getByText("/programmes/online-mba").first()).toBeVisible();
  });

  test("404 monitor: a miss is logged and becomes a 301 in one click", async ({ request }) => {
    const path = `/old-page-${Date.now().toString(36)}`;
    const visitor = await page.context().browser()!.newPage();
    await visitor.goto(path);
    await expect(visitor.getByText("This page has moved or doesn't exist.")).toBeVisible();
    await expect.poll(async () => (await dbSelect("web_404_log", `path=eq.${path}&select=hits`)).length).toBe(1);
    await page.goto("/admin/seo/404");
    await page.getByLabel(`Redirect ${path} to`).fill("/programmes");
    await page.getByLabel(`Redirect ${path} to`).locator("xpath=ancestor::form").getByRole("button", { name: "Redirect (301)" }).click();
    await expect(page.getByRole("status")).toContainText("Redirect created");
    // the proxy re-reads admin redirects within a minute (D-045)
    await expect.poll(async () => (await request.get(path, { maxRedirects: 0 })).status(), { timeout: 80_000, intervals: [5000] }).toBe(301);
  });

  test("keywords, internal links and local SEO pages", async () => {
    await page.goto("/admin/seo/keywords");
    await expect(page.getByRole("heading", { level: 1, name: "Keyword list" })).toBeVisible();
    await page.goto("/admin/seo/links");
    await page.getByRole("button", { name: "Find new suggestions" }).click();
    await expect(page.getByRole("status")).toContainText("new suggestion");
    await page.goto("/admin/seo/local");
    await expect(page.getByText("Claim and verify the Google Business Profile")).toBeVisible();
  });
});
