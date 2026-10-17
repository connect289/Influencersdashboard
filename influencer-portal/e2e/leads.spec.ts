import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { localEnv } from "./env";
import { creatorLogin, staffLogin } from "./helpers";

// Phase 6 journeys: links and QR codes, the /r redirect, the lead sweep, the masked creator pipeline, staff overrides,
// fraud review, stage rules and the agency view. The seed gives Riya links RIYA-MBA1 and RIYA-WEB1 and four test
// leads; this file adds one more lead through the local copy of public.lead_intake(), as Witty would.

const env = localEnv();
const service = () =>
  createClient(env.NEXT_PUBLIC_SUPABASE_URL ?? "", env.SUPABASE_SERVICE_ROLE_KEY ?? "", {
    auth: { persistSession: false },
  });
const BROWSER_UA =
  "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36";
const NEW_PHONE = "910000000201";

test.describe.serial("links and leads", () => {
  test("a creator makes a link and downloads its QR code", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/links");
    await expect(page.getByText("RIYA-MBA1", { exact: true })).toBeVisible();
    await page.getByLabel("Label").fill("Second reel");
    await page.getByRole("button", { name: "Create link" }).click();
    await expect(page.getByText(/^Link [A-Z0-9-]+ created\.$/)).toBeVisible();
    const item = page.getByRole("listitem").filter({ hasText: "Second reel" });
    await expect(item).toBeVisible();
    const png = await page.request.get((await item.getByRole("link", { name: "PNG" }).getAttribute("href")) ?? "");
    expect(png.status()).toBe(200);
    expect(png.headers()["content-type"]).toBe("image/png");
    const svg = await page.request.get((await item.getByRole("link", { name: "SVG" }).getAttribute("href")) ?? "");
    expect(await svg.text()).toContain("<svg");
  });

  test("every post has its own link, shown on the deliverable and in the brief", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/deliverables");
    await page
      .getByRole("link", { name: /Launch reel/ })
      .first()
      .click();
    await expect(page.getByText("Your link for this post")).toBeVisible();
    await expect(page.getByText(/^RIYALEARNS-IG-[A-Z0-9]{3}$/)).toBeVisible();
    await page.goto("/creator/briefs");
    await page
      .getByRole("link", { name: /Always-on MBA deal/ })
      .first()
      .click();
    await expect(page.getByText(/Each post below has its own tracking link/)).toBeVisible();
    await expect(page.getByText(/^RIYALEARNS-IG-[A-Z0-9]{3}$/)).toHaveCount(2);
  });

  test("the short link redirects to WhatsApp, counts people and ignores crawlers", async ({ page, request }) => {
    const bot = await request.get("/r/RIYA-MBA1", {
      maxRedirects: 0,
      headers: { "user-agent": "facebookexternalhit/1.1" },
    });
    expect(bot.status()).toBe(302);
    const r = await request.get("/r/riya-mba1", {
      maxRedirects: 0,
      headers: { "user-agent": BROWSER_UA },
    });
    expect(r.status()).toBe(302);
    const location = r.headers()["location"] ?? "";
    expect(location).toMatch(/^https:\/\/wa\.me\/919643977407\?text=/);
    expect(decodeURIComponent(location)).toContain("RIYA-MBA1");
    expect(r.headers()["cache-control"]).toBe("no-store");
    const missing = await request.get("/r/NOPE-NOPE", { maxRedirects: 0 });
    expect(missing.headers()["location"]).toMatch(/\/link-inactive$/);

    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/links");
    await expect(page.getByRole("listitem").filter({ hasText: "RIYA-MBA1" })).toContainText("Clicks: 1");
  });

  test("a switched-off link shows the inactive page", async ({ page, request }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/links");
    const web = page.getByRole("listitem").filter({ hasText: "RIYA-WEB1" });
    await web.getByRole("switch", { name: "Active" }).click();
    await expect(page.getByText(/Link switched off/)).toBeVisible();
    const r = await request.get("/r/RIYA-WEB1", {
      maxRedirects: 0,
      headers: { "user-agent": BROWSER_UA },
    });
    expect(r.headers()["location"]).toMatch(/\/link-inactive$/);
    await page.goto("/link-inactive");
    await expect(page.getByRole("heading", { name: "This link is no longer active" })).toBeVisible();
    await page.goto("/creator/links");
    await page.getByRole("listitem").filter({ hasText: "RIYA-WEB1" }).getByRole("switch", { name: "Active" }).click();
    await expect(page.getByText("Link switched on.")).toBeVisible();
  });

  test("the sweep attributes a new lead (internal key required)", async ({ request }) => {
    const made = await service()
      .schema("public")
      .rpc("lead_intake", {
        p: {
          phone: NEW_PHONE,
          source_system: "witty",
          is_test: true,
          attribution: { creator_code: "RIYA-MBA1" },
          lead: {
            student_name: "Rohan Gupta",
            city: "Indore",
            state: "Madhya Pradesh",
            interested_course: "Online MBA",
            referral_code: "RIYA-MBA1",
            email_id: "rohan.gupta@example.test",
          },
        },
      });
    expect(made.error).toBeNull();
    expect((await request.post("/api/internal/lead-sync")).status()).toBe(401);
    const r = await request.post("/api/internal/lead-sync", {
      headers: { "x-internal-key": env.INF_INTERNAL_API_KEY ?? "" },
    });
    expect(r.status()).toBe(200);
    const body = (await r.json()) as { scanned: number; decisions: number };
    expect(body.scanned).toBeGreaterThan(0);
    expect(body.decisions).toBeGreaterThan(0);
  });

  test("the creator sees the lead with phone and email masked", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/leads");
    await expect(page.getByRole("region", { name: "Qualifying" })).toContainText("Rohan G.");
    await expect(page.getByRole("region", { name: "Applied" })).toContainText("Kabir N.");
    await expect(page.getByRole("region", { name: "Closed" })).toContainText("Meera I.");
    const html = await page.content();
    expect(html).not.toContain(NEW_PHONE);
    expect(html).not.toContain("rohan.gupta@example.test");
    expect(html).not.toContain("Gupta");

    await page.getByRole("link", { name: /Rohan G\./ }).click();
    const drawer = page.getByRole("dialog");
    await expect(drawer).toContainText("00XXXXXX01");
    await expect(drawer).toContainText("r****@****.test");
    await expect(drawer).toContainText("RIYA-MBA1");
    await expect(drawer).toContainText("Indore");
    expect(await page.content()).not.toContain(NEW_PHONE);
    await drawer.getByRole("button", { name: "Close" }).click();

    await page.getByRole("button", { name: "Table" }).click();
    await expect(page.getByRole("columnheader", { name: "Programme" })).toBeVisible();
    await page.getByText("Filters and saved views").click();
    await page.getByLabel("Stage", { exact: true }).selectOption("applied");
    await expect(page.getByRole("row").filter({ hasText: "Kabir N." })).toBeVisible();
    await expect(page.getByRole("row").filter({ hasText: "Rohan G." })).toHaveCount(0);

    const csv = await page.request.get(
      (await page.getByRole("link", { name: "Export CSV" }).getAttribute("href")) ?? "",
    );
    expect(csv.status()).toBe(200);
    const text = await csv.text();
    expect(text).toContain("Kabir N.");
    expect(text).not.toMatch(/9100000001\d\d/);
  });

  test("a manager rejects an attribution with a reason; only a Super Admin sees contacts", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/leads?test=1");
    await page.getByRole("link", { name: /Rohan G\./ }).click();
    const drawer = page.getByRole("dialog");
    await expect(drawer).toContainText("00XXXXXX01");
    expect(await page.content()).not.toContain(NEW_PHONE);
    await drawer.getByLabel("Reason").fill("Student says a friend shared the link, not the creator");
    await drawer.getByRole("button", { name: "Reject this attribution" }).click();
    await expect(page.getByText("Attribution rejected. The lead is re-checked shortly.")).toBeVisible();

    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/leads?test=1");
    await page.getByRole("link", { name: /Isha V\./ }).click();
    await expect(page.getByRole("dialog")).toContainText("910000000102");
  });

  test("staff see the pipeline as a board", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/leads?test=1");
    await page.getByRole("link", { name: "Board", exact: true }).click();
    await expect(page.getByRole("region", { name: "Applied" })).toContainText("Kabir N.");
    await expect(page.getByRole("region", { name: "Applied" })).toContainText("Riya Sharma");
  });

  test("a campaign can set its own model and WhatsApp message", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/campaigns");
    await page.getByRole("link", { name: "Online MBA winter push (demo)" }).click();
    await page.getByRole("link", { name: "Edit", exact: true }).click();
    await page.getByLabel("Attribution model").selectOption("last_touch");
    const message = page.getByLabel("WhatsApp message");
    await message.fill("Hi Eduwit, tell me about the MBA");
    await expect(page.getByText("Include {code} so the creator's code reaches Witty.")).toBeVisible();
    await message.fill("Hi Eduwit! {creator_name} sent me. Code {code}");
    await page.getByRole("button", { name: "Save", exact: true }).last().click();
    await expect(page.getByText("Tracking settings saved. New clicks and the next sync use them.")).toBeVisible();
  });

  test("a manager clears a fraud flag with a reason", async ({ page }) => {
    const db = service().schema("inf" as never) as unknown as ReturnType<typeof service>;
    const att = await db
      .from("lead_attributions")
      .select("id, creator_id")
      .eq("code", "RIYA-MBA1")
      .eq("creator_stage", "applied")
      .single();
    expect(att.error).toBeNull();
    const flag = await db.from("fraud_flags").insert({
      creator_id: (att.data as { creator_id: string }).creator_id,
      attribution_id: (att.data as { id: string }).id,
      signal: "same_device",
      detail: { leads: 4, max: 3 },
    });
    expect(flag.error).toBeNull();

    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/leads/fraud");
    const row = page.getByRole("row").filter({ hasText: "Same device" });
    await expect(row).toContainText("4 leads from one device (limit 3)");
    await row.getByRole("button", { name: "Clear" }).click();
    const d = page.getByRole("dialog");
    await d.getByLabel("Reason").fill("Family members enquiring from one phone");
    await d.getByRole("button", { name: "Clear" }).click();
    await expect(page.getByText("Flag cleared.")).toBeVisible();
    await expect(page.getByRole("row").filter({ hasText: "Same device" })).toHaveCount(0);
  });

  test("a Super Admin adds a stage rule; a manager can only read them", async ({ page }) => {
    await staffLogin(page, "admin@example.test");
    await page.goto("/admin/leads/stages");
    await page.getByRole("button", { name: "Add rule" }).click();
    const d = page.getByRole("dialog");
    await d.getByLabel("Priority").fill("65");
    await d.getByRole("combobox", { name: "Field" }).selectOption("stage");
    await d.getByRole("combobox", { name: "Test" }).selectOption("in");
    await d.getByRole("textbox", { name: "Values" }).fill("on_hold");
    await d.getByLabel("Creator stage").selectOption("allocated");
    await d.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Stage rule saved. Leads update on the next sync.")).toBeVisible();
    await expect(page.getByText("{on_hold}")).toBeVisible();

    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/leads/stages");
    await expect(page.getByText("{on_hold}")).toBeVisible();
    await expect(page.getByRole("button", { name: "Add rule" })).toHaveCount(0);
  });

  test("an agency sees its creator's leads masked, without making links", async ({ page }) => {
    await creatorLogin(page, "agency.owner@example.test");
    await page
      .getByRole("link", { name: /Riya Sharma/ })
      .first()
      .click();
    await expect(page.getByText("RIYA-MBA1", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Create link" })).toHaveCount(0);
    await page.getByRole("link", { name: "Open leads" }).click();
    await expect(page.getByText("Riya Sharma's leads, masked exactly as the creator sees them.")).toBeVisible();
    await expect(page.getByText("Kabir N.")).toBeVisible();
    expect(await page.content()).not.toMatch(/9100000001\d\d/);
  });
});
