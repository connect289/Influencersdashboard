import { expect, test, type APIRequestContext } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { localEnv } from "./env";
import { creatorLogin, staffLogin } from "./helpers";

// Phase 7 journeys: the creator's earnings (totals, the seeded paid payout, payment advice, monthly statement), a full
// payout run by Finance with two approvers (prepare, approve, second approval, bank file, mark paid), adjustments and
// holds, the TDS and receipts screens, and who may see a creator's earnings. The seed gives Riya verified KYC, a paid
// signing fee (₹60,000 less 10% TDS under 194J), a payable ₹10,000 milestone, a confirmed usage fee and a pending
// commission.

const env = localEnv();
const service = () =>
  createClient(env.NEXT_PUBLIC_SUPABASE_URL ?? "", env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
    auth: { persistSession: false },
    db: { schema: "inf" },
  });
const RIYA = "riya.creator@example.test";
const istMonth = () => new Date(Date.now() + 330 * 60_000).toISOString().slice(0, 7);

async function riyaId(): Promise<string> {
  const { data } = await service().from("creators").select("id").eq("handle", "riyalearns").single<{ id: string }>();
  return data?.id ?? "";
}

async function runJobs(request: APIRequestContext) {
  const r = await request.post("/api/internal/jobs", { headers: { "x-internal-key": env.INF_INTERNAL_API_KEY ?? "" } });
  expect(r.status()).toBe(200);
}

test.describe.serial("ledger and payouts", () => {
  test("the creator sees totals, the paid payout and every entry", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/earnings");
    await expect(page.getByRole("heading", { name: "Earnings", level: 1 })).toBeVisible();
    await expect(page.getByRole("group", { name: "Due to you", exact: true })).toContainText("₹10,000.00");
    await expect(page.getByRole("group", { name: "Confirmed", exact: true })).toContainText("₹5,000.00");
    await expect(page.getByRole("group", { name: "Pending", exact: true })).toContainText("₹4,000.00");
    await expect(page.getByRole("group", { name: "Paid", exact: true })).toContainText("₹60,000.00");
    const payout = page
      .getByRole("listitem")
      .filter({ hasText: /PO-\d{4}-\d{2}-\d{5}/ })
      .first();
    await expect(payout).toContainText("₹54,000.00");
    await expect(payout).toContainText("TDS ₹6,000.00");
    await expect(payout).toContainText("UTR HDFCN26101700001");
    await expect(page.getByText("Always-on MBA deal (demo)").filter({ visible: true }).first()).toBeVisible();
    await expect(page.getByText("Signing fee (demo)").filter({ visible: true }).first()).toBeVisible();
  });

  test("the payment advice is built after payment and downloads only for the creator", async ({ page, request }) => {
    await runJobs(request);
    await creatorLogin(page, RIYA);
    await page.goto("/creator/earnings");
    const advice = page.getByRole("link", { name: "Payment advice" }).first();
    await expect(advice).toBeVisible();
    const href = (await advice.getAttribute("href")) ?? "";
    expect(href).toMatch(/^\/api\/finance\/file\?path=advice%2F/);
    const redirect = await page.request.get(href, { maxRedirects: 0 });
    expect(redirect.status()).toBe(302);
    const pdf = await page.request.get(href);
    expect(pdf.status()).toBe(200);
    expect((await pdf.body()).subarray(0, 5).toString()).toBe("%PDF-");
    // Someone else's session gets nothing.
    await creatorLogin(page, "arjun.creator@example.test");
    expect((await page.request.get(href, { maxRedirects: 0 })).status()).toBe(404);
  });

  test("the monthly statement downloads as a PDF for the creator only", async ({ page, request }) => {
    const id = await riyaId();
    const url = `/api/earnings/${id}/statement?month=${istMonth()}`;
    // Signed out: the proxy sends the request to sign-in; no PDF.
    const anon = await request.get(url, { maxRedirects: 0 });
    expect([302, 307, 401]).toContain(anon.status());
    await creatorLogin(page, RIYA);
    const r = await page.request.get(url);
    expect(r.status()).toBe(200);
    expect(r.headers()["content-type"]).toBe("application/pdf");
    expect(r.headers()["content-disposition"]).toContain(`eduwit-statement-riyalearns-${istMonth()}.pdf`);
    expect((await page.request.get(`/api/earnings/${id}/statement?month=2026-13`)).status()).toBe(404);
    await creatorLogin(page, "arjun.creator@example.test");
    expect((await page.request.get(url)).status()).toBe(404);
  });

  test("an agency without the earnings grant cannot open the creator's earnings", async ({ page }) => {
    const id = await riyaId();
    await creatorLogin(page, "agency.owner@example.test");
    await page.goto(`/agency/creators/${id}`);
    await expect(page.getByRole("link", { name: "Open earnings" })).toHaveCount(0);
    await page.goto(`/agency/creators/${id}/earnings`);
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
  });

  test("finance prepares a batch, two people approve, the bank file exports and the payout is marked paid", async ({
    browser,
  }) => {
    const finance = await browser.newPage();
    await staffLogin(finance, "finance@example.test");
    await finance.goto("/admin/finance/payouts");
    await finance.getByLabel("Note").fill("E2E payout run");
    await finance.getByRole("button", { name: "Prepare batch" }).click();
    await expect(finance).toHaveURL(/\/admin\/finance\/payouts\/[0-9a-f-]{36}$/);
    const batchUrl = finance.url();
    const row = finance.getByRole("row").filter({ hasText: "Riya" });
    await expect(row).toContainText("₹10,000.00");
    await expect(row).toContainText("₹1,000.00");
    await expect(row).toContainText("₹9,000.00");
    await finance.getByRole("button", { name: "Approve" }).click();
    await expect(finance.getByText("Approved. A second person needs to approve too.")).toBeVisible();
    await expect(finance.getByRole("button", { name: /Approve|second approval/ })).toHaveCount(0);

    const admin = await browser.newPage();
    await staffLogin(admin, "admin@example.test");
    await admin.goto(batchUrl);
    await admin.getByRole("button", { name: "Give the second approval" }).click();
    await expect(admin.getByText("Batch approved. You can now export the bank file.")).toBeVisible();
    await admin.close();

    await finance.reload();
    const href = (await finance.getByRole("link", { name: "Bank file" }).getAttribute("href")) ?? "";
    const file = await finance.request.get(href);
    expect(file.status()).toBe(200);
    const csv = await file.text();
    expect(csv).toContain("50100123456789");
    expect(csv).toContain("9000.00");
    await finance.reload();
    await row.getByRole("button", { name: "Mark paid" }).click();
    await finance.getByRole("dialog").getByLabel("UTR").fill("HDFCN26101700002");
    await finance.getByRole("dialog").getByRole("button", { name: "Mark paid" }).click();
    await expect(finance.getByText(/1 payout marked paid/)).toBeVisible();
    await expect(row).toContainText("HDFCN26101700002");
    await finance.close();
  });

  test("the creator is notified and the new payout shows as paid", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/earnings");
    await expect(page.getByRole("group", { name: "Due to you", exact: true })).toContainText("₹0.00");
    await expect(page.getByRole("listitem").filter({ hasText: "HDFCN26101700002" })).toContainText("₹9,000.00");
    const { data } = await service()
      .from("notifications")
      .select("title")
      .eq("event", "payout.paid")
      .order("created_at", { ascending: false })
      .limit(1);
    expect(data?.[0]?.title).toMatch(/^Payment sent: PO-\d{4}-\d{2}-\d{5}$/);
  });

  test("finance posts an adjustment and holds it", async ({ page }) => {
    await staffLogin(page, "finance@example.test");
    const id = await riyaId();
    await page.goto(`/admin/finance?creator_id=${id}`);
    await page.getByRole("button", { name: "Adjustment" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Amount (₹)").fill("750");
    await dialog.getByLabel("Reason").fill("E2E travel reimbursement");
    await dialog.getByRole("button", { name: /Post/ }).click();
    await expect(page.getByText("Adjustment posted.")).toBeVisible();
    const line = page.getByRole("row").filter({ hasText: "E2E travel reimbursement" });
    await expect(line).toContainText("₹750.00");
    await line.getByRole("button", { name: "Hold" }).click();
    await page.getByRole("dialog").getByLabel("Reason").fill("Waiting for the receipt");
    await page.getByRole("dialog").getByRole("button", { name: "Hold" }).click();
    await expect(page.getByText("Entry put on hold.")).toBeVisible();
  });

  test("the TDS and receipts screens load for finance; managers only read payouts, viewers see nothing", async ({
    page,
  }) => {
    await staffLogin(page, "finance@example.test");
    await page.goto("/admin/finance/tds");
    await expect(page.getByText("194J").first()).toBeVisible();
    await page.goto("/admin/finance/receipts");
    await expect(page.getByRole("button", { name: "Record receipt" })).toBeVisible();
    // Managers read payouts but cannot prepare or approve them; viewers cannot open finance at all.
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/finance/payouts");
    await expect(page.getByRole("link", { name: /^PB-/ }).first()).toBeVisible();
    await expect(page.getByRole("button", { name: "Prepare batch" })).toHaveCount(0);
    await staffLogin(page, "viewer@example.test");
    await page.goto("/admin/finance/payouts");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
  });
});
