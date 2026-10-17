import { expect, test, type Page } from "@playwright/test";
import { dbSelect, freshIp, latestCode, typeCode, uniqueEmail, uniquePhone, wrongCode } from "./helpers";

/**
 * Phase 7: email verification, leads through lead_intake (local stack only), application and enquiry forms, accounts,
 * creator attribution (spec 16 e2e 4, 5, 6). Codes are read from Mailpit; lead rows are asserted in the local database.
 */
async function dismissConsent(page: Page) {
  const banner = page.getByRole("region", { name: "Cookie preferences" });
  if (await banner.isVisible().catch(() => false)) await banner.getByRole("button", { name: "Only necessary" }).click();
}

type Attempt = { id: string; lead_id: number | null; verified_at: string | null; surface: string; junk_score: number };
type Lead = Record<string, unknown> & { id: number };

async function attemptFor(email: string): Promise<Attempt[]> {
  return dbSelect<Attempt>("web_gate_attempts", `email_norm=eq.${encodeURIComponent(email)}&select=id,lead_id,verified_at,surface,junk_score&order=submitted_at.desc`);
}
async function lead(id: number): Promise<Lead> {
  const [l] = await dbSelect<Lead>("student_leads", `id=eq.${id}&select=*`);
  return l!;
}

async function enquiry(page: Page, o: { name: string; phone: string; email: string; path?: string; programme?: string }) {
  await page.goto("about:blank");
  await page.goto(o.path ?? "/contact#enquiry");
  await dismissConsent(page);
  const form = page.locator("form").filter({ has: page.getByRole("button", { name: "Verify email and send" }) });
  await form.getByLabel("Full name", { exact: true }).fill(o.name);
  await form.getByLabel("Mobile number", { exact: true }).fill(o.phone);
  await form.getByLabel("Email", { exact: true }).fill(o.email);
  if (o.programme) await form.getByLabel(/Programme you're interested in/).fill(o.programme);
  await form.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
  const sent = new Date();
  await form.getByRole("button", { name: "Verify email and send" }).click();
  const box = page.getByText("Check your email").locator("..");
  await expect(page.getByText("Check your email")).toBeVisible();
  return { sent, box };
}

test.describe("leads, verification and accounts", () => {
  test.beforeEach(async ({ page }) => freshIp(page));

  test("application form: lead only after the email code; steps enrich the same lead; submit marks an application request", async ({ page }) => {
    const email = uniqueEmail("asha");
    const phone = uniquePhone();
    await page.goto("/programmes?programme=mba&view=flat");
    await dismissConsent(page);
    await page.locator("li a[href^='?offering=']").first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Apply now" }).click();
    await expect(dialog.getByText("Step 1 of 5: Contact")).toBeVisible();
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Enter your full name (letters only).")).toBeVisible();
    await dialog.getByLabel("Full name", { exact: true }).fill("Asha Rao");
    await dialog.getByLabel("Mobile number", { exact: true }).fill(phone);
    await dialog.getByLabel("Email", { exact: true }).fill(email);
    await dialog.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
    const sent = new Date();
    await dialog.getByRole("button", { name: "Verify email and continue" }).click();
    await expect(dialog.getByText("Check your email")).toBeVisible();
    await expect(dialog).toContainText("spam");

    // Submitted but not verified: the attempt is recorded, no lead exists.
    const [pending] = await attemptFor(email);
    expect(pending?.verified_at).toBeNull();
    expect(pending?.lead_id).toBeNull();

    const code = await latestCode(email, sent);
    await typeCode(page, dialog, wrongCode(code));
    await expect(dialog.getByText(/didn't match\. 4 tries left/)).toBeVisible();
    await typeCode(page, dialog, code);
    await expect(dialog.getByText("Step 2 of 5: Academic")).toBeVisible();
    await expect(dialog.getByText("Email verified")).toBeVisible();

    const [verified] = await attemptFor(email);
    expect(verified?.lead_id).toBeTruthy();
    const created = await lead(verified!.lead_id!);
    expect(created).toMatchObject({ student_name: "Asha Rao", email_id: email, lead_source: "website_form", channel: "web_form", is_test: true });
    expect(created.interested_course).toBeTruthy();
    expect(created.interested_university).toBeTruthy();
    expect(created.consent_text_version).toBe("web-form-2026-10-v1");

    await dialog.getByLabel("Highest qualification").selectOption("graduation");
    await expect(dialog.getByText("You meet the eligibility for this programme.")).toBeVisible();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await expect(dialog.getByText("Step 3 of 5: Work and goals")).toBeVisible();
    // Drop-off after step 2 would keep this: it is already on the lead.
    await expect.poll(async () => (await lead(verified!.lead_id!)).highest_qualification).toBe("Graduation");

    await dialog.getByText("Yes", { exact: true }).first().click();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await dialog.getByText("WhatsApp", { exact: true }).click();
    await dialog.getByRole("button", { name: "Save and continue" }).click();
    await expect(dialog.getByText("Step 5 of 5: Review")).toBeVisible();
    await expect(dialog).toContainText("Asha Rao");
    await dialog.getByRole("button", { name: "Submit application request" }).click();
    await expect(dialog.getByText("Application request received")).toBeVisible();
    const ref = (await dialog.textContent())?.match(/EDW-26-[2-9A-Z]{5}/)?.[0];
    expect(ref).toBeTruthy();

    const done = await lead(verified!.lead_id!);
    expect(done.intent_type).toBe("wants_to_apply");
    expect(done.work_experience_years).toBe("Working");
    expect(String(done.preferred_counseling_time)).toContain("WhatsApp");
    const [app] = await dbSelect<{ status: string; lead_id: number }>("web_applications", `reference=eq.${ref}&select=status,lead_id`);
    expect(app).toMatchObject({ status: "submitted", lead_id: verified!.lead_id });
    // Exactly one lead write for the verification, and the confirmation email is queued.
    expect(await dbSelect("web_lead_submissions", `idempotency_key=eq.web:verify:${verified!.id}&select=idempotency_key`)).toHaveLength(1);
    expect(await dbSelect("web_outbox", `kind=eq.email_confirmation&payload->>reference=eq.${ref}&select=id`)).toHaveLength(1);
  });

  test("enquiry form, then a duplicate phone with a new email does not create a second lead", async ({ page }) => {
    const phone = uniquePhone();
    const first = uniqueEmail("ravi");
    const { sent, box } = await enquiry(page, { name: "Ravi Kumar", phone, email: first, programme: "Online MBA" });
    await typeCode(page, box, await latestCode(first, sent));
    await expect(page.getByText("Thanks, we've got your enquiry")).toBeVisible();
    await expect(page.getByRole("status")).toContainText(/EDW-26-/);
    const [a1] = await attemptFor(first);
    expect(a1?.lead_id).toBeTruthy();
    expect((await lead(a1!.lead_id!)).intent_type).toBe("enquiry");

    // New browser state, same phone, different email → lead_intake merges into the same lead.
    await page.context().clearCookies();
    const second = uniqueEmail("ravi.k");
    const r2 = await enquiry(page, { name: "Ravi Kumar", phone, email: second });
    await typeCode(page, r2.box, await latestCode(second, r2.sent));
    await expect(page.getByText("Thanks, we've got your enquiry")).toBeVisible();
    const [a2] = await attemptFor(second);
    expect(a2?.lead_id).toBe(a1!.lead_id);
  });

  test("an unverified attempt creates no lead; the honeypot silently drops bots", async ({ page }) => {
    const email = uniqueEmail("drop");
    await enquiry(page, { name: "Meera Iyer", phone: uniquePhone(), email });
    const [a] = await attemptFor(email);
    expect(a).toBeTruthy();
    expect(a!.lead_id).toBeNull();

    await page.context().clearCookies();
    const bot = uniqueEmail("bot");
    await page.goto("about:blank");
    await page.goto("/contact#enquiry");
    await dismissConsent(page);
    const form = page.locator("form").filter({ has: page.getByRole("button", { name: "Verify email and send" }) });
    await form.getByLabel("Full name", { exact: true }).fill("Bot Person");
    await form.getByLabel("Mobile number", { exact: true }).fill(uniquePhone());
    await form.getByLabel("Email", { exact: true }).fill(bot);
    await form.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
    await form.locator('input[name="website"]').fill("http://spam.example", { force: true });
    await form.getByRole("button", { name: "Verify email and send" }).click();
    await expect(page.getByText("Check your email")).toBeVisible();
    expect(await attemptFor(bot)).toHaveLength(0);
  });

  test("creator landing page: the code is attached to the lead and never gates anything", async ({ page }) => {
    await page.goto("/c/demo-creator?code=ANJALI10");
    await dismissConsent(page);
    await expect(page.getByText("Recommended by Demo Creator")).toBeVisible();
    await expect(page.getByRole("main").getByRole("link", { name: /Online MBA/ })).toBeVisible();
    const email = uniqueEmail("creator");
    const { sent, box } = await enquiry(page, { name: "Kiran Shah", phone: uniquePhone(), email, path: "/c/demo-creator?code=ANJALI10" });
    await typeCode(page, box, await latestCode(email, sent));
    await expect(page.getByText("Thanks, we've got your enquiry")).toBeVisible();
    const [a] = await attemptFor(email);
    const l = await lead(a!.lead_id!);
    expect(l.referred_by_code).toBe("anjali10");
    // Unknown handles never claim an endorsement.
    await page.goto("/c/someone-else");
    await expect(page.getByText(/Recommended by/)).toHaveCount(0);
  });

  test("account: sign in with an email code, see the application, signed-in forms skip the code, sign out", async ({ page }) => {
    const email = uniqueEmail("neha");
    const phone = uniquePhone();
    // Create the identity through an enquiry.
    const r = await enquiry(page, { name: "Neha Gupta", phone, email });
    await typeCode(page, r.box, await latestCode(email, r.sent));
    await expect(page.getByText("Thanks, we've got your enquiry")).toBeVisible();

    // Fresh device: sign in.
    await page.context().clearCookies();
    await page.goto("/account");
    await expect(page).toHaveURL(/\/account\/sign-in\?next=%2Faccount/);
    await page.getByLabel("Email", { exact: true }).fill(email);
    const sent = new Date();
    await page.getByRole("button", { name: "Email me a code" }).click();
    await expect(page.getByText(/We sent a 6-digit code/)).toBeVisible();
    await typeCode(page, page.locator("main"), await latestCode(email, sent));
    await expect(page).toHaveURL(/\/account$/);
    await expect(page.getByRole("heading", { name: "Your account" })).toBeVisible();
    await expect(page.getByText(email)).toBeVisible();
    await expect(page.getByText(/EDW-26-[2-9A-Z]{5}/).first()).toBeVisible();
    await expect(page.getByText("Contact about my enquiry")).toBeVisible();

    // Signed in: the enquiry form is pre-filled and skips the code.
    await page.goto("/contact#enquiry");
    const form = page.locator("form").filter({ has: page.getByRole("button", { name: "Verify email and send" }) });
    await expect(form.getByLabel("Email", { exact: true })).toHaveValue(email);
    await form.getByRole("checkbox", { name: /I agree that Eduwit/ }).check();
    await form.getByRole("button", { name: "Verify email and send" }).click();
    await expect(page.getByText("Thanks, we've got your enquiry")).toBeVisible();

    // Privacy request and sign out.
    await page.goto("/account");
    await page.getByRole("button", { name: "Email me a copy of my data" }).click();
    await expect(page.getByText(/Request received/)).toBeVisible();
    await page.getByRole("button", { name: "Sign out" }).click();
    await expect(page).toHaveURL(/signed_out=1/);
    await page.goto("/account");
    await expect(page).toHaveURL(/\/account\/sign-in/);
  });
});
