import { readFileSync, writeFileSync } from "node:fs";
import { expect, test } from "@playwright/test";
import { people, service, stateFile, watch } from "./helpers";

/**
 * The main things people do, on test leads only (staging). Laptop size: on a phone the Call button hands over to the
 * phone's dialler, which a test browser cannot follow. Support tickets are opened but never sent (they would email the
 * developer).
 */
test.skip(({ isMobile }) => isMobile, "laptop flows");

async function leadOf(who: "asha" | "ravi"): Promise<number> {
  const { data } = await service().schema("b2c").from("leads_state").select("lead_id").eq("owner_id", people()[who].user_id)
    .gte("lead_id", 990101).lte("lead_id", 990130).eq("status", "active").order("lead_id").limit(1);
  if (!data?.[0]) throw new Error(`${who} has no test lead: run npm run e2e:seed`);
  return data[0].lead_id as number;
}

test.describe("counsellor", () => {
  test.use({ storageState: stateFile("asha") });

  test("sees her own leads in Leads and Pipeline", async ({ page }) => {
    const problems = watch(page);
    await page.goto("/s/leads");
    await page.getByRole("link", { name: "All mine" }).click();
    await expect(page.locator("a[href^='/s/leads/99']").first()).toBeVisible();
    await page.goto("/s/pipeline");
    await expect(page.getByText(/^[1-9]\d* active leads?$/)).toBeVisible();
    expect(problems).toEqual([]);
  });

  test("logs a call with an outcome and the next follow-up", async ({ page }) => {
    const lead = await leadOf("asha");
    const problems = watch(page);
    await page.goto(`/s/leads/${lead}`);
    await page.getByRole("button", { name: /^Call / }).first().click();
    await expect(page.getByText("Dial on your work phone")).toBeVisible();
    await page.getByRole("button", { name: "No answer", exact: true }).click();
    await page.getByRole("button", { name: "Tomorrow 10:00", exact: true }).click();
    await page.getByRole("button", { name: "Save call log" }).click();
    await expect(page.getByText(/Call logged/)).toBeVisible();
    await expect(page.locator(".tl-item").filter({ hasText: /No answer/i }).first()).toBeVisible();
    expect(problems).toEqual([]);
  });

  test("adds a note to the timeline", async ({ page }) => {
    const lead = await leadOf("asha");
    const note = `E2E note ${Date.now()}`;
    await page.goto(`/s/leads/${lead}`);
    await page.getByPlaceholder("Add a note").fill(note);
    await page.getByRole("button", { name: "Add note" }).click();
    await expect(page.locator(".tl-item").filter({ hasText: note })).toBeVisible();
  });

  test("cannot open another counsellor's lead", async ({ page }) => {
    const other = await leadOf("ravi");
    await page.goto(`/s/leads/${other}`);
    await expect(page.getByRole("heading", { name: /Not found|not yours|Something went wrong/i }).or(page.getByText(/not your lead|not found/i)).first()).toBeVisible();
    await expect(page.getByRole("button", { name: /^Call / })).toHaveCount(0);
  });

  test("opens a support ticket form (not sent)", async ({ page }) => {
    await page.goto("/s/support");
    await page.getByRole("button", { name: "New ticket" }).click();
    await expect(page.locator("input[name='subject']")).toBeVisible();
    await expect(page.locator("textarea[name='body']")).toBeVisible();
    await expect(page.getByRole("button", { name: "Raise ticket" })).toBeVisible();
  });
});

test.describe("admin", () => {
  test.use({ storageState: stateFile("admin") });

  test("changes a counsellor's work mobile, with a reason", async ({ page }) => {
    const number = `+91 90000 9${String(Date.now()).slice(-4)}`;
    await page.goto("/w/teams");
    const row = page.locator("tr", { hasText: "Asha Counsellor" }).filter({ has: page.getByRole("button", { name: "Change" }) });
    await row.getByRole("button", { name: "Change" }).first().click();
    await page.getByPlaceholder("+91 90000 00000").fill(number);
    await page.getByPlaceholder("e.g. new company SIM").fill("E2E test SIM");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(row.getByText(number.replace(/\s/g, ""))).toBeVisible();
  });
});

test.describe("marketing", () => {
  test.use({ storageState: stateFile("marketing") });

  test("sees a lead but cannot call it", async ({ page }) => {
    await page.goto("/w/leads/990101");
    await expect(page.getByRole("heading", { level: 1 }).or(page.locator("h2").first())).toBeVisible();
    await expect(page.getByRole("button", { name: /^Call / })).toHaveCount(0);
  });
});

test.describe("password", () => {
  test("the link form answers the same for an unknown address", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("link", { name: "First time, or forgot your password?" }).click();
    await expect(page.getByRole("heading", { name: "Set your password" })).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.locator("input[name='email']").fill("e2e.nobody@eduwit.in");
    await expect(page.locator("input[name='email']")).toHaveValue("e2e.nobody@eduwit.in");
    await page.getByRole("button", { name: "Email me a link" }).click();
    await expect(page.getByText(/If e2e\.nobody@eduwit\.in has an Eduwit Spark account/)).toBeVisible();
  });

  test("sets a new password through the emailed link, then the code step follows", async ({ page }) => {
    const p = people();
    // the link the email would carry (b2c sends it with the app's own mail; here no email leaves the test)
    const { data, error } = await service().auth.admin.generateLink({ type: "recovery", email: p.ravi.email });
    if (error) throw error;
    await page.goto(`/auth/confirm?token_hash=${encodeURIComponent(data.properties.hashed_token)}&type=recovery`);
    await expect(page.getByRole("heading", { name: "New password" })).toBeVisible();
    const fresh = `E2e-${Date.now()}-new-pass`;
    await page.locator("input[name='password']").fill(fresh);
    await page.locator("input[name='again']").fill(fresh);
    await page.getByRole("button", { name: "Save password" }).click();
    await expect(page.getByRole("heading", { name: "Check your email" })).toBeVisible();
    const file = new URL("./.auth/passwords.json", import.meta.url);
    const all = JSON.parse(readFileSync(file, "utf8"));
    all.ravi.password = fresh;
    writeFileSync(file, JSON.stringify(all, null, 2), { mode: 0o600 });
    // a used link does not work twice
    await page.context().clearCookies();
    await page.goto(`/auth/confirm?token_hash=${encodeURIComponent(data.properties.hashed_token)}&type=recovery`);
    await expect(page.getByText(/expired or was already used/)).toBeVisible();
  });
});

