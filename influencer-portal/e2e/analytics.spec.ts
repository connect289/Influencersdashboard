import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { localEnv } from "./env";
import { creatorLogin, staffLogin } from "./helpers";

// Phase 8 journeys: the creator home dashboard (action centre, earnings, live funnel, range presets), the staff
// analytics overview (KPIs with definitions, spend, breakdowns, CSV export, refresh), the campaign and finance
// dashboards, the creator 360 analytics tab and who may open what. The seed's leads are test leads, which dashboards
// leave out unless asked; this file adds one real-looking lead (a local-only number) through the local lead_intake().

const env = localEnv();
const service = () =>
  createClient(env.NEXT_PUBLIC_SUPABASE_URL ?? "", env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
    auth: { persistSession: false },
  });
const RIYA = "riya.creator@example.test";

test.describe.serial("dashboards and analytics", () => {
  test("a new lead is attributed and the summary views refresh", async ({ request }) => {
    const made = await service()
      .schema("public")
      .rpc("lead_intake", {
        p: {
          phone: "919000000301",
          source_system: "witty",
          is_test: false,
          attribution: { creator_code: "RIYA-MBA1" },
          lead: { student_name: "Tara Menon", city: "Bengaluru", state: "Karnataka", referral_code: "RIYA-MBA1" },
        },
      });
    expect(made.error).toBeNull();
    const sweep = await request.post("/api/internal/lead-sync", {
      headers: { "x-internal-key": env.INF_INTERNAL_API_KEY ?? "" },
    });
    expect(sweep.status()).toBe(200);
    const refreshed = await service().schema("inf").rpc("analytics_refresh");
    expect(refreshed.error).toBeNull();
  });

  test("the creator home shows the action centre, earnings and the live funnel", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator");
    await expect(page.getByRole("heading", { name: "Needs your attention" })).toBeVisible();
    await expect(page.getByRole("link", { name: /A contract needs you/ })).toBeVisible();
    await expect(page.getByRole("link", { name: /A brief to acknowledge/ })).toBeVisible();
    await expect(page.getByRole("group", { name: "Due to you", exact: true })).toContainText("₹10,000");
    await expect(page.getByRole("group", { name: "Leads", exact: true })).toContainText("1");
    await expect(page.getByRole("heading", { name: "Lead funnel" })).toBeVisible();
    // Every number explains itself.
    await page.getByRole("button", { name: "About Leads" }).click();
    await expect(page.getByText("Students who enquired through a creator's link or code")).toBeVisible();
    await page.keyboard.press("Escape");
    // Date range presets live in the URL.
    await page.getByLabel("Period", { exact: true }).selectOption("7d");
    await expect(page).toHaveURL(/range=7d/);
    await expect(page.getByRole("group", { name: "Leads", exact: true })).toContainText("1");
    // The creator's own export: counts only.
    const href = (await page.getByRole("link", { name: "Export CSV" }).getAttribute("href")) ?? "";
    const csv = await page.request.get(href);
    expect(csv.status()).toBe(200);
    const text = await csv.text();
    expect(text).toContain("Section,Name,Leads,Enrolled");
    expect(text).not.toContain("919000000301");
    await creatorLogin(page, "arjun.creator@example.test");
    expect((await page.request.get(href)).status()).toBe(404);
  });

  test("staff see programme analytics with definitions, breakdowns and a CSV export", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/analytics");
    await expect(page.getByRole("heading", { name: "Analytics", level: 1 })).toBeVisible();
    await expect(page.getByRole("group", { name: "Committed", exact: true })).toContainText("₹15,000");
    await expect(page.getByRole("group", { name: "Leads", exact: true })).toContainText("1");
    await expect(page.getByRole("row").filter({ hasText: "Riya Sharma" }).first()).toBeVisible();
    await page.getByRole("link", { name: "Platform", exact: true }).click();
    await expect(page).toHaveURL(/dim=platform/);
    await expect(page.getByRole("heading", { name: "By Platform" })).toBeVisible();
    const href = (await page.getByRole("link", { name: "Export CSV" }).getAttribute("href")) ?? "";
    const csv = await page.request.get(href);
    expect(csv.status()).toBe(200);
    expect(await csv.text()).toMatch(/^\uFEFFPlatform,Clicks,Leads/);
    await page.getByRole("button", { name: "Refresh" }).click();
    await expect(page.getByText(/Dashboards refreshed\.|refreshed in the last two minutes/)).toBeVisible();
    // Test leads only on request.
    await page.getByLabel("Include test leads").check();
    await expect(page).toHaveURL(/test=1/);
    await expect(page.getByRole("group", { name: "Leads", exact: true })).not.toContainText(/^Leads1$/);
  });

  test("the creator 360 has an analytics tab", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    const { data } = await service()
      .schema("inf")
      .from("creators")
      .select("id")
      .eq("handle", "riyalearns")
      .single<{ id: string }>();
    await page.goto(`/admin/creators/${data?.id ?? ""}?tab=analytics`);
    await expect(page.getByRole("heading", { name: "Lead quality over time" })).toBeVisible();
    await expect(page.getByRole("group", { name: "Leads", exact: true })).toContainText("1");
  });

  test("finance sees the finance dashboard; a viewer gets analytics but not finance", async ({ page }) => {
    await staffLogin(page, "finance@example.test");
    await page.goto("/admin/analytics/finance");
    await expect(page.getByRole("group", { name: "Owed to creators", exact: true })).toBeVisible();
    await expect(page.getByRole("cell", { name: "194J" }).first()).toBeVisible();
    await staffLogin(page, "viewer@example.test");
    await page.goto("/admin/analytics");
    await expect(page.getByRole("group", { name: "Leads", exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: "Finance", exact: true })).toHaveCount(0);
    await page.goto("/admin/analytics/finance");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
    await page.goto("/admin/analytics/campaigns");
    await expect(page.getByRole("heading", { name: "Analytics", level: 1 })).toBeVisible();
  });

  test("creators cannot open staff analytics or its export", async ({ page }) => {
    await creatorLogin(page, RIYA);
    const r = await page.request.get("/api/analytics/export?dim=creator", { maxRedirects: 0 });
    expect([302, 307, 404]).toContain(r.status());
    await page.goto("/admin/analytics");
    await expect(page).not.toHaveURL(/\/admin\/analytics/);
  });
});
