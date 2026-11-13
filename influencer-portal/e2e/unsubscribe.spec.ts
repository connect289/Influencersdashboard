import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";
import { signUnsubscribe } from "@/lib/notify/unsubscribe";
import { localEnv } from "./env";
import { creatorLogin } from "./helpers";

// Unsubscribe links (D-198): the link in an email works without signing in and without JavaScript, opening it changes
// nothing, the button and the mail provider's one-click POST turn email off for that kind of notification only, a
// link that is not ours gets the same answer, and the creator sees the choice in settings and in the consent history.

const env = localEnv();
const url = env.NEXT_PUBLIC_SUPABASE_URL ?? "";
if (!/^http:\/\/(127\.0\.0\.1|localhost)[:/]/.test(url))
  throw new Error("unsubscribe.spec runs against the local stack only");
const db = createClient<Database, "inf">(url, env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
  auth: { persistSession: false },
  db: { schema: "inf" },
});
const SECRET = env.UNSUBSCRIBE_SECRET ?? "";
const RIYA = "riya.creator@example.test";

async function riyaUserId(): Promise<string> {
  const creator = await db.from("creators").select("id").eq("handle", "riyalearns").single();
  const account = await db
    .from("creator_accounts")
    .select("user_id")
    .eq("creator_id", creator.data?.id ?? "")
    .single();
  return account.data?.user_id ?? "";
}

/** The campaign notifications a creator can turn off (group "campaigns" in the catalogue). */
const CAMPAIGN_EVENTS = [
  "application.accepted",
  "application.countered",
  "application.message",
  "application.rejected",
  "application.shortlisted",
  "campaign.invited",
];

/** Riya's switched-off choices, as "event:channel". */
async function switchedOff(userId: string): Promise<string[]> {
  const { data } = await db
    .from("notification_preferences")
    .select("event, channel")
    .eq("user_id", userId)
    .eq("enabled", false);
  return (data ?? []).map((r) => `${r.event}:${r.channel}`).sort();
}

test.describe("unsubscribe link", () => {
  test.describe.configure({ mode: "serial" });
  let userId = "";
  let campaigns = "";
  let digest = "";

  test.beforeAll(async () => {
    expect(SECRET.length).toBeGreaterThanOrEqual(32);
    userId = await riyaUserId();
    expect(userId).toMatch(/^[0-9a-f-]{36}$/);
    campaigns = signUnsubscribe(SECRET, { userId, category: "campaigns" });
    digest = signUnsubscribe(SECRET, { userId, category: "digest" });
    // Start from Riya's defaults for what this journey changes (a run may follow another on the same database).
    await db.from("notification_preferences").delete().eq("user_id", userId).like("event", "campaign.%");
    await db.from("notification_preferences").delete().eq("user_id", userId).like("event", "application.%");
  });

  test("opening the link changes nothing; the button stops that kind of email without JavaScript or signing in", async ({
    browser,
  }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    const res = await page.goto(`/unsubscribe/${campaigns}`);
    expect(res?.status()).toBe(200);
    expect(new URL(page.url()).pathname).toBe(`/unsubscribe/${campaigns}`);
    await expect(page.getByRole("heading", { name: "Stop these emails?" })).toBeVisible();
    await expect(page.getByText("Campaigns and applications")).toBeVisible();
    await expect(page.getByText(/Required notices about contracts, payments, KYC/)).toBeVisible();
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
    // Nothing about the person is on the page (the page source also carries the app's interface strings, so names
    // are looked for in what is shown, and the address and the account id in the whole source).
    const shown = (await page.locator("body").innerText()).toLowerCase();
    for (const personal of ["riya", "sharma", "riyalearns"]) expect(shown).not.toContain(personal);
    const html = await page.content();
    for (const personal of ["riya.creator@example.test", userId]) expect(html).not.toContain(personal);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    // Mail scanners open links: a GET (and a second one) must not unsubscribe.
    const before = await switchedOff(userId);
    await page.reload();
    expect(await switchedOff(userId)).toEqual(before);

    await page.getByRole("button", { name: "Stop these emails" }).click();
    await expect(page).toHaveURL(/\/unsubscribe\/[^/?]+\?r=done$/);
    await expect(page.getByRole("heading", { name: "You're all set" })).toBeVisible();
    // Only email, only this kind: WhatsApp and every other group are as they were.
    expect(await switchedOff(userId)).toEqual([...before, ...CAMPAIGN_EVENTS.map((e) => `${e}:email`)].sort());
    await context.close();
  });

  test("the page passes the accessibility check", async ({ page }) => {
    for (const path of [`/unsubscribe/${campaigns}`, `/unsubscribe/${campaigns}?r=done`, "/unsubscribe/not-a-link"]) {
      await page.goto(path);
      const result = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
      const blocking = result.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
      expect(
        blocking.map((v) => v.id),
        path,
      ).toEqual([]);
    }
  });

  test("a mail provider's one-click POST turns the digest off; a GET there changes nothing", async ({ request }) => {
    const before = await db.from("digest_preferences").select("frequency").eq("user_id", userId).maybeSingle();
    const get = await request.get(`/unsubscribe/${digest}/one-click`, { maxRedirects: 0 });
    expect(get.status()).toBe(303);
    const still = await db.from("digest_preferences").select("frequency").eq("user_id", userId).maybeSingle();
    expect(still.data?.frequency).toBe(before.data?.frequency);

    const wrongBody = await request.post(`/unsubscribe/${digest}/one-click`, { form: { hello: "world" } });
    expect(wrongBody.status()).toBe(400);
    const res = await request.post(`/unsubscribe/${digest}/one-click`, { form: { "List-Unsubscribe": "One-Click" } });
    expect(res.status()).toBe(200);
    expect(res.headers()["set-cookie"]).toBeUndefined();
    const after = await db.from("digest_preferences").select("frequency, channel").eq("user_id", userId).single();
    expect(after.data).toEqual({ frequency: "off", channel: "email" });
    // Pressing it again is harmless.
    const again = await request.post(`/unsubscribe/${digest}/one-click`, { form: { "List-Unsubscribe": "One-Click" } });
    expect(again.status()).toBe(200);
  });

  test("a link that is not ours gets the same answer and changes nothing", async ({ page, request }) => {
    const forged = signUnsubscribe("x".repeat(40), { userId, category: "deals" });
    for (const bad of [forged, `${campaigns}x`, "not-a-link"]) {
      const res = await page.goto(`/unsubscribe/${bad}`);
      expect(res?.status()).toBe(200);
      await expect(page.getByRole("heading", { name: "You're all set" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Stop these emails" })).toHaveCount(0);
      const post = await request.post(`/unsubscribe/${bad}/one-click`, { form: { "List-Unsubscribe": "One-Click" } });
      expect(post.status()).toBe(200);
    }
    const deals = await db
      .from("notification_preferences")
      .select("event")
      .eq("user_id", userId)
      .like("event", "deal.%")
      .eq("enabled", false);
    expect(deals.data ?? []).toEqual([]);
  });

  test("settings show the choice and can undo it; the consent history names the link", async ({ page }) => {
    await creatorLogin(page, RIYA);
    await page.goto("/creator/notifications/settings");
    const invited = page.getByRole("switch", { name: "Invited to a campaign: Email" });
    await expect(invited).not.toBeChecked();
    await expect(page.getByRole("switch", { name: "Invited to a campaign: WhatsApp" })).toBeChecked();
    await expect(page.getByRole("switch", { name: "Payout sent: Email" })).toBeChecked();
    await expect(page.getByLabel("How often")).toHaveValue("off");

    await page.goto("/creator/account/privacy");
    await expect(page.getByText(/Off \(by email link\)/).first()).toBeVisible();

    // The settings page still works on the same rows: switch one back on.
    await page.goto("/creator/notifications/settings");
    await page.getByRole("switch", { name: "Invited to a campaign: Email" }).click();
    await expect(page.getByRole("switch", { name: "Invited to a campaign: Email" })).toBeChecked();
    await page.reload();
    await expect(page.getByRole("switch", { name: "Invited to a campaign: Email" })).toBeChecked();
    const log = await db
      .from("communication_consents")
      .select("granted, source")
      .eq("user_id", userId)
      .eq("purpose", "campaign.invited")
      .order("id", { ascending: false })
      .limit(2);
    expect(log.data).toEqual([
      { granted: true, source: "settings" },
      { granted: false, source: "unsubscribe_link" },
    ]);
  });

  test("health and the signed-out proxy treat the route as public", async ({ request }) => {
    const page = await request.get(`/unsubscribe/${campaigns}`, { maxRedirects: 0 });
    expect(page.status()).toBe(200);
    expect(page.headers()["x-robots-tag"]).toContain("noindex");
    const health = (await (await request.get("/api/health")).json()) as { warnings?: string[] };
    expect(health.warnings).toBeUndefined();
  });
});
