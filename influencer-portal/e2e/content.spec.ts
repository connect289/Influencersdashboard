import { expect, test, type Page } from "@playwright/test";
import { crc32, deflateSync } from "node:zlib";
import { creatorLogin, staffLogin } from "./helpers";

/** A solid-colour PNG (w × h) to upload as a draft image. */
function png(w: number, h: number): Buffer {
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr.set([8, 2, 0, 0, 0], 8);
  const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(w * 3, 0x5b)]);
  const raw = Buffer.concat(Array.from({ length: h }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const DEAL = "Always-on MBA deal (demo)";

async function openReel(page: Page, base: string) {
  await page.goto(base);
  await page
    .getByRole("link", { name: /Launch reel/ })
    .first()
    .click();
  await expect(page).toHaveURL(new RegExp(`${base}/[0-9a-f-]{36}`));
}

test.describe.serial("content: brief → concept → draft → live → metrics", () => {
  test("a manager edits the brief and publishes a new version", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/briefs");
    await expect(page.getByRole("heading", { name: "Briefs" })).toBeVisible();
    await page.getByRole("link", { name: DEAL }).click();
    await expect(page.getByRole("link", { name: "Launch reel" })).toBeVisible();
    await page.getByLabel("Tone").fill("Friendly, honest and practical.");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByText("Brief saved.")).toBeVisible();
    await page.getByRole("button", { name: "Publish new version" }).click();
    await page.getByLabel("What changed").fill("Tone updated");
    await page.getByRole("button", { name: "Publish", exact: true }).click();
    await expect(page.getByText("Brief published. The creator has been told.")).toBeVisible();
    await page.getByRole("link", { name: "Versions" }).click();
    await expect(page.getByText("v2")).toBeVisible();
  });

  test("the creator reads, acknowledges and asks a question", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await page.goto("/creator/briefs");
    await page.getByRole("link", { name: new RegExp(DEAL.replace(/[()]/g, "\\$&")) }).click();
    await expect(page.getByText("What changed: Tone updated")).toBeVisible();
    await expect(page.getByText("Friendly, honest and practical.")).toBeVisible();
    await page.getByText(/I have read this brief/).click();
    await page.getByRole("button", { name: "Acknowledge brief" }).click();
    await expect(page.getByText("You acknowledged this version of the brief.")).toBeVisible();
    await page.getByPlaceholder("Your question").fill("Can I film in Hindi?");
    await page.getByRole("button", { name: "Ask", exact: true }).click();
    await expect(page.getByText("Question sent.")).toBeVisible();
  });

  test("the manager answers the question", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/briefs");
    await expect(page.getByText("1 question")).toBeVisible();
    await page.getByRole("link", { name: DEAL }).click();
    await page.getByRole("button", { name: "Reply" }).first().click();
    await page.getByPlaceholder("Your reply").fill("Yes, Hindi is perfect.");
    await page.getByRole("button", { name: "Reply" }).last().click();
    await expect(page.getByText("Reply sent.")).toBeVisible();
  });

  test("the creator submits a concept the scan flags", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await openReel(page, "/creator/deliverables");
    await expect(page.getByRole("heading", { name: "Your next step" })).toBeVisible();
    await page
      .getByLabel("Your concept")
      .fill("A day in my life studying online. Guaranteed placement after this MBA!");
    await page.getByRole("button", { name: "Submit concept" }).click();
    await expect(page.getByText(/The automatic check flagged something/)).toBeVisible();
    await expect(page.getByText("Eduwit is reviewing your submission.")).toBeVisible();
  });

  test("a reviewer overrides the flag with a reason and approves the concept", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/content?view=review");
    await page.getByRole("link", { name: "Launch reel" }).click();
    await expect(page.getByText(/Banned claims: failed/)).toBeVisible();
    await expect(page.getByText(/“Guaranteed placement”/)).toBeVisible();
    await page.getByRole("button", { name: "Approve" }).click();
    await expect(page.getByText(/A check failed/)).toBeVisible();
    await page.getByRole("button", { name: "Override" }).click();
    await page.getByLabel("Reason").fill("Will be rephrased in the draft; idea approved");
    await page.getByRole("dialog").getByRole("button", { name: "Override" }).click();
    await expect(page.getByText("Check overridden.")).toBeVisible();
    await page.getByLabel("Note to the creator").fill("Lovely idea. Drop the placement line.");
    await page.getByRole("button", { name: "Approve" }).click();
    await expect(page.getByText("Approved. The creator has been told.")).toBeVisible();
  });

  test("the creator uploads a draft image with a disclosed caption", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await openReel(page, "/creator/deliverables");
    await expect(page.getByText("Eduwit: Lovely idea. Drop the placement line.")).toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.getByLabel("Caption or script").fill("#ad My honest online MBA story, from fees to exams.");
    await page.locator("#sub-files").setInputFiles({ name: "cover.png", mimeType: "image/png", buffer: png(320, 200) });
    await expect(page.getByText("cover.png")).toBeVisible();
    await page.getByRole("button", { name: "Submit draft" }).click();
    await expect(page.getByText("Submitted for review.")).toBeVisible();
  });

  test("the reviewer marks an area, completes the ASCI checklist and approves", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/content?view=review");
    await page.getByRole("link", { name: "Launch reel" }).click();
    await expect(page.getByText(/Disclosure: passed/)).toBeVisible();
    const img = page.getByRole("img", { name: "cover.png" });
    await expect(img).toBeVisible();
    const box = await img.boundingBox();
    if (!box) throw new Error("image not laid out");
    await page.mouse.move(box.x + box.width * 0.2, box.y + box.height * 0.2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width * 0.6, box.y + box.height * 0.5, { steps: 5 });
    await page.mouse.up();
    await expect(page.getByText("Area marked")).toBeVisible();
    await page.getByPlaceholder("Add a comment").first().fill("Make the logo bigger here.");
    await page.getByRole("button", { name: "Comment", exact: true }).click();
    await expect(page.getByText("Comment added.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Area 1" })).toBeVisible();
    const approve = page.getByRole("button", { name: "Approve" });
    await expect(approve).toBeDisabled();
    for (const box of await page.getByRole("group", { name: "ASCI checklist" }).getByRole("checkbox").all())
      await box.check();
    await approve.click();
    await expect(page.getByText("Approved. The creator has been told.")).toBeVisible();
  });

  test("the creator goes live; a wrong link is refused", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await openReel(page, "/creator/deliverables");
    await page.getByLabel("Live link").fill("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    await page.getByRole("button", { name: "Submit live link" }).click();
    await expect(page.getByText("That link is for a different platform.")).toBeVisible();
    await page.getByLabel("Live link").fill("https://www.instagram.com/reel/C1aBcD2eF3g/?igsh=abc");
    await page.getByRole("button", { name: "Submit live link" }).click();
    await expect(page.getByText("Live link submitted. Eduwit will verify it.")).toBeVisible();
    await expect(page.getByText("Eduwit is checking your live post.")).toBeVisible();
  });

  test("the reviewer verifies the live post", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/content?view=review");
    await page.getByRole("link", { name: "Launch reel" }).click();
    await expect(page.getByRole("link", { name: /instagram\.com\/reel\/C1aBcD2eF3g\/$/ })).toBeVisible();
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(page.getByText("Live post verified.")).toBeVisible();
  });

  test("the creator reports 24-hour metrics", async ({ page }) => {
    await creatorLogin(page, "riya.creator@example.test");
    await openReel(page, "/creator/deliverables");
    await page.getByLabel("Views").fill("12,500");
    await page.getByLabel("Reach").fill("9800");
    await page.getByRole("button", { name: "Save metrics" }).click();
    await expect(page.getByText("Metrics saved.")).toBeVisible();
    await expect(page.getByRole("cell", { name: "12,500" })).toBeVisible();
  });

  test("the reviewer completes the deliverable and sees its history", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/content");
    await page.getByRole("link", { name: "Launch reel" }).click();
    await page.getByRole("link", { name: "Settings" }).click();
    await page.getByRole("button", { name: "Mark completed" }).click();
    await expect(page.getByText("Deliverable completed.")).toBeVisible();
    await page.getByRole("link", { name: "History" }).click();
    await expect(page.getByText("Live post verified")).toBeVisible();
    await expect(page.getByText("Completed").first()).toBeVisible();
  });
});

test.describe("content administration", () => {
  test("a reviewer adds a banned claim and tries a sentence", async ({ page }) => {
    await staffLogin(page, "reviewer@example.test");
    await page.goto("/admin/content/claims");
    await page.getByLabel("Phrase or pattern").fill("easy money");
    await page.getByLabel("Why (shown to the reviewer)").fill("Misleading earnings claim");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.getByText("Banned claims saved.")).toBeVisible();
    await page.getByLabel("Try a sentence").fill("This course is EASY   money for everyone");
    await expect(page.getByText("“EASY   money”")).toBeVisible();
  });

  test("a manager creates a brief template with scheduling on", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/briefs/templates");
    await expect(page.getByText("Standard creator brief")).toBeVisible();
    await page.getByRole("link", { name: "New template" }).click();
    await page.getByLabel("Name").fill(`Short-form brief ${String(Date.now()).slice(-4)}`);
    await page.getByLabel("Scheduling").click();
    await page.getByLabel("Objective").fill("Quick explainer reels.");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page).toHaveURL(/\/admin\/briefs\/templates\/[0-9a-f-]{36}$/);
    await expect(page.getByText("Template saved.")).toBeVisible();
  });

  test("the deal's content tab lists the deliverables and penalties stay empty", async ({ page }) => {
    await staffLogin(page, "manager@example.test");
    await page.goto("/admin/deals");
    await page.getByRole("link", { name: DEAL }).click();
    await page.locator('a[href$="?tab=content"]').click();
    await expect(page.getByRole("link", { name: "Story set" })).toBeVisible();
    await page.goto("/admin/content/penalties");
    await expect(page.getByText("No proposals here")).toBeVisible();
  });

  test("a viewer cannot open content", async ({ page }) => {
    await staffLogin(page, "viewer@example.test");
    await page.goto("/admin/content");
    await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
  });
});
