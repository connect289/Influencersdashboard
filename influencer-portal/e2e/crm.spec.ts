import { expect, test } from "@playwright/test";
import { staffLogin } from "./helpers";

test.describe.serial("creator CRM", () => {
  test.beforeEach(async ({ page }) => {
    await staffLogin(page, "manager@example.test");
  });

  test("add a prospect, log outreach with a follow-up, and assign a task", async ({ page }) => {
    await page.goto("/admin/creators");
    await page.getByRole("button", { name: "Add prospect" }).first().click();
    const d = page.getByRole("dialog");
    await d.getByLabel("Display name").fill("Meera Maths");
    await d.getByLabel("Handle").fill("meera.maths");
    await d.getByLabel("Topics you cover").fill("Maths, JEE");
    await d.getByRole("button", { name: "Add prospect" }).click();
    await expect(page).toHaveURL(/\/admin\/creators\/[0-9a-f-]{36}$/);
    await expect(page.getByRole("heading", { name: "Meera Maths" })).toBeVisible();

    await page.getByRole("link", { name: "Outreach" }).click();
    await page.getByLabel("Channel").selectOption("instagram_dm");
    await page.getByLabel("Notes").fill("Sent the programme deck");
    const tomorrow = new Date(Date.now() + 86_400_000 + 5.5 * 3_600_000).toISOString().slice(0, 10);
    await page.getByLabel("Follow up on").fill(tomorrow);
    await page.getByRole("button", { name: "Log it" }).click();
    await expect(page.getByText("Outreach logged.")).toBeVisible();
    await expect(page.getByText("Sent the programme deck")).toBeVisible();
    // Logging outreach moves a prospect to Contacted.
    await expect(page.getByLabel("Stage", { exact: true })).toHaveValue("contacted");

    await page.getByRole("link", { name: "Tasks" }).last().click();
    await page.getByRole("button", { name: "New task" }).click();
    const td = page.getByRole("dialog");
    await td.getByLabel("Task").fill("Share the MBA brief with Meera");
    await td.getByLabel("Assign to").selectOption({ label: "Rekha Reviewer" });
    await td.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Task created.")).toBeVisible();
    await expect(page.getByText("Share the MBA brief with Meera")).toBeVisible();
  });

  test("search, filter, save a view and move a creator on the board", async ({ page }) => {
    await page.goto("/admin/creators");
    await page.getByRole("searchbox", { name: "Search creators" }).fill("meera");
    await expect(page).toHaveURL(/q=meera/);
    await expect(page.getByRole("link", { name: "Meera Maths" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Riya" })).toHaveCount(0);

    await page.getByRole("button", { name: "Views" }).click();
    await page.getByRole("menuitem", { name: "Save current view" }).click();
    await page.getByRole("dialog").getByLabel("View name").fill("Meera search");
    await page.getByRole("dialog").getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("View saved.")).toBeVisible();

    await page.getByRole("button", { name: "Pipeline board" }).click();
    await expect(page).toHaveURL(/view=kanban/);
    // Drag the card (not its link) with real pointer moves, as dnd-kit needs.
    const card = page.getByRole("button", { name: /Meera Maths/ });
    const from = await card.boundingBox();
    const to = await page.getByRole("region", { name: "Negotiating" }).boundingBox();
    if (!from || !to) throw new Error("board not rendered");
    await page.mouse.move(from.x + 20, from.y + from.height - 8);
    await page.mouse.down();
    await page.mouse.move(from.x + 40, from.y + from.height, { steps: 5 });
    await page.mouse.move(to.x + to.width / 2, to.y + 80, { steps: 15 });
    await page.mouse.up();
    await expect(page.getByText("Moved to Negotiating.")).toBeVisible();
    await page.reload();
    await expect(
      page.getByRole("region", { name: "Negotiating" }).getByRole("link", { name: "Meera Maths" }),
    ).toBeVisible();
  });

  test("import prospects from CSV: check first, then import; duplicates are skipped", async ({ page }) => {
    await page.goto("/admin/creators/import");
    // The file input only reacts once the page has hydrated.
    await page.waitForLoadState("networkidle");
    const csv = [
      "name,handle,email,platform,profile url,followers",
      "Om Physics,om.physics,om@example.test,youtube,https://youtube.com/@om,52000",
      "Meera again,meera_2,,,,",
      "Bad Row,bad handle,,,,",
      "Riya twin,riyalearns,,,,",
    ].join("\n");
    await page
      .getByLabel("Choose file")
      .setInputFiles({ name: "prospects.csv", mimeType: "text/csv", buffer: Buffer.from(csv) });
    await expect(page.getByText("Check of prospects.csv")).toBeVisible();
    await expect(page.getByText("2 new")).toBeVisible();
    await expect(page.getByText("1 duplicates")).toBeVisible();
    await expect(page.getByText("1 with errors")).toBeVisible();
    await expect(page.getByText("Handle already in the CRM")).toBeVisible();
    await page.getByRole("button", { name: "Import 2 prospects" }).click();
    await expect(page.getByText("Import complete")).toBeVisible();
    await page.goto("/admin/creators?q=om.physics");
    await expect(page.getByRole("link", { name: "Om Physics" })).toBeVisible();
  });

  test("the overview shows my follow-ups and tasks", async ({ page }) => {
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Follow-ups due" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "My tasks" })).toBeVisible();
  });
});
