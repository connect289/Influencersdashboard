import { expect, test, type Page } from "@playwright/test";
import { dbSelect, freshIp, latestCode, setSetting, typeCode, uniqueEmail, uniquePhone } from "./helpers";

/**
 * Witty on the website (spec 16 e2e 3, 4, 8) with the scripted model provider (no API key in CI, S-14): the gate, the
 * lead only after the email code, streamed replies with programme cards, storage, returning users, and the flag-off
 * fallback. Runs on the laptop project only (the flag is global state).
 */
const BASE = process.env.E2E_BASE_URL ?? "http://localhost:3100";

async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}
async function ask(page: Page, text: string) {
  const box = page.getByLabel("Message Witty");
  await box.fill(text);
  // wait for the previous reply to finish streaming (Send is disabled meanwhile)
  await expect(page.getByRole("button", { name: "Send" })).toBeEnabled();
  await box.press("Enter");
}
const chat = (page: Page) => page.getByRole("region", { name: "Chat with Witty" });
/** The visible conversation (the screen-reader live region repeats the last reply). */
const log = (page: Page) => page.getByRole("log", { name: "Conversation" });

test.describe.configure({ mode: "serial" });
test.describe("Witty on the website", () => {
  test.skip(({ isMobile }) => isMobile, "global flag; covered once on the laptop project");
  test.beforeAll(async () => setSetting(BASE, "web_advisor_enabled", true));
  test.afterAll(async () => setSetting(BASE, "web_advisor_enabled", false));
  test.beforeEach(async ({ page }) => freshIp(page));

  const email = uniqueEmail("witty");
  const phone = uniquePhone();

  test("gate first, lead only after the code, then streamed replies with programme cards", async ({ page }) => {
    await expect.poll(async () => (await page.request.get("/witty")).status()).toBe(200);
    await page.goto("/");
    await dismissConsent(page);
    await page.locator("#hero-ask").fill("I want to do an MBA");
    await page.locator("#hero-ask").press("Enter");
    await expect(page).toHaveURL(/\/witty\?q=/);

    // The gate opens on the first interaction; the question waits.
    await expect(page.getByRole("heading", { name: "Before we chat" })).toBeVisible();
    await page.getByLabel("Full name", { exact: true }).fill("Kavya Menon");
    await page.getByLabel("Mobile number", { exact: true }).fill(phone);
    await page.getByLabel("Email", { exact: true }).fill(email);
    await page.getByRole("checkbox", { name: /Witty, Eduwit's AI admissions assistant, is stored/ }).check();
    const sent = new Date();
    await page.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(page.getByText("Check your email")).toBeVisible();
    const [pending] = await dbSelect<{ lead_id: number | null; surface: string }>("web_gate_attempts", `email_norm=eq.${encodeURIComponent(email)}&select=lead_id,surface`);
    expect(pending).toMatchObject({ surface: "gate", lead_id: null }); // no lead before verification

    await typeCode(page, chat(page), await latestCode(email, sent));
    // The waiting question is sent: ask-before-suggest (how many options, no names or fees yet).
    await expect(log(page).getByText(/options that could suit you/)).toBeVisible();
    await expect(log(page).getByText(/specialization in mind/)).toBeVisible();

    await ask(page, "Finance");
    await expect(log(page).getByText(/highest qualification/).last()).toBeVisible();
    await ask(page, "B.Com, 65%");
    const cards = log(page).getByRole("list", { name: "Programmes Witty found" }).last();
    await expect(cards).toBeVisible();
    expect(await cards.getByRole("listitem").count()).toBeGreaterThan(0);
    await expect(log(page).getByText(/Here are options you qualify for/)).toBeVisible();
    await expect(log(page)).toContainText("₹");
    await expect(log(page)).not.toContainText("{{");
    await expect(chat(page).getByRole("button", { name: "This session" })).toBeVisible();

    // Feedback and a callback.
    await log(page).getByRole("button", { name: "Helpful" }).last().click();
    await chat(page).getByRole("button", { name: "Book a callback" }).click();
    await chat(page).getByLabel("Day", { exact: true }).selectOption({ index: 1 });
    await chat(page).getByText("evening", { exact: true }).click();
    await chat(page).getByRole("button", { name: "Book", exact: true }).click();
    await expect(chat(page).getByText(/^Booked:/)).toBeVisible();

    // Stored: lead via lead_intake with Witty's fields, transcript in the w2_messages shape, feedback, callback.
    const [attempt] = await dbSelect<{ lead_id: number }>("web_gate_attempts", `email_norm=eq.${encodeURIComponent(email)}&select=lead_id`);
    expect(attempt!.lead_id).toBeTruthy();
    const [lead] = await dbSelect<Record<string, unknown>>("student_leads", `id=eq.${attempt!.lead_id}&select=*`);
    expect(lead).toMatchObject({ lead_source: "website_agent", channel: "web", first_agent_channel: "web", interested_course: "MBA", interested_specialization: "Finance", highest_qualification: "B.Com" });
    expect(String(lead!.preferred_counseling_time)).toMatch(/^Callback .*evening/);
    const [session] = await dbSelect<{ id: string; turns: number; agent_core_version: string }>("web_advisor_sessions", `lead_id=eq.${attempt!.lead_id}&select=id,turns,agent_core_version&order=created_at.desc&limit=1`);
    expect(session!.turns).toBe(3);
    expect(session!.agent_core_version).toMatch(/^extractor:6:b53fe530d440d4be2e5e99013e033ec0\|counselor:6:/);
    const msgs = await dbSelect<{ direction: string; channel: string }>("web_advisor_messages", `session_id=eq.${session!.id}&select=direction,channel`);
    expect(msgs).toHaveLength(6);
    expect(msgs.every((m) => m.channel === "web")).toBe(true);
    expect(await dbSelect("web_advisor_feedback", `session_id=eq.${session!.id}&select=rating`)).toHaveLength(1);
  });

  test("returning user signs in and resumes the conversation; the same phone keeps one lead", async ({ page }) => {
    await page.goto("/account/sign-in?next=/witty");
    await dismissConsent(page);
    await page.getByLabel("Email", { exact: true }).fill(email);
    const sent = new Date();
    await page.getByRole("button", { name: "Email me a code" }).click();
    await expect(page.getByText(/We sent a 6-digit code/)).toBeVisible();
    await typeCode(page, page.locator("main"), await latestCode(email, sent));
    await expect(page).toHaveURL(/\/witty$/);
    await expect(log(page).getByText("B.Com, 65%")).toBeVisible(); // history restored
    await expect(log(page).getByText(/^Hi Kavya!/)).toBeVisible();

    // Account shows the chat.
    await page.goto("/account");
    await expect(page.getByRole("heading", { name: "Chats with Witty" })).toBeVisible();
    await expect(page.getByText(/ongoing/)).toBeVisible();

    // Same phone, new email, new browser → lead_intake merges into the same lead.
    await page.context().clearCookies();
    const other = uniqueEmail("witty.k");
    await page.goto("/witty");
    await ask(page, "BCA options");
    await page.getByLabel("Full name", { exact: true }).fill("Kavya Menon");
    await page.getByLabel("Mobile number", { exact: true }).fill(phone);
    await page.getByLabel("Email", { exact: true }).fill(other);
    await page.getByRole("checkbox", { name: /Witty, Eduwit's AI admissions assistant, is stored/ }).check();
    const sent2 = new Date();
    await page.getByRole("button", { name: "Verify email and continue" }).click();
    await typeCode(page, chat(page), await latestCode(other, sent2));
    await expect(log(page).getByText("BCA options")).toBeVisible();
    const a1 = await dbSelect<{ lead_id: number }>("web_gate_attempts", `email_norm=eq.${encodeURIComponent(email)}&surface=eq.gate&select=lead_id`);
    const a2 = await dbSelect<{ lead_id: number }>("web_gate_attempts", `email_norm=eq.${encodeURIComponent(other)}&surface=eq.gate&select=lead_id`);
    expect(a1[0]!.lead_id).toBeTruthy();
    expect(a2[0]!.lead_id).toBe(a1[0]!.lead_id);
  });

  test("an erasure request routes to the opt-out flow", async ({ page }) => {
    await page.goto("/account/sign-in?next=/witty");
    await page.getByLabel("Email", { exact: true }).fill(email);
    const sent = new Date();
    await page.getByRole("button", { name: "Email me a code" }).click();
    await typeCode(page, page.locator("main"), await latestCode(email, sent));
    await expect(page).toHaveURL(/\/witty$/);
    await ask(page, "please delete my data");
    await expect(log(page).getByRole("link", { name: "Manage my data" })).toBeVisible();
  });

  test("flag off: hero falls back to search + guided finder; /witty and the API fall back", async ({ page, request }) => {
    await setSetting(BASE, "web_advisor_enabled", false);
    await expect.poll(async () => (await request.post("/api/witty", { data: { message: "hi", message_id: "abcdefgh12" } })).status()).toBe(404);
    await page.goto("/");
    await expect(page.getByRole("link", { name: "Answer 3 quick questions" })).toBeVisible();
    await page.goto("/witty");
    await expect(page.getByRole("heading", { name: "Witty is taking a short break" })).toBeVisible();
    await setSetting(BASE, "web_advisor_enabled", true);
  });
});
