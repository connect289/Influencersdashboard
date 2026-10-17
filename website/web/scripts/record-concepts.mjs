#!/usr/bin/env node
// Records short walkthrough videos of both design concepts (Phase 1 deliverable) on a phone and a desktop.
// Usage: node scripts/record-concepts.mjs <baseUrl> <outDir>
import { chromium, devices } from "@playwright/test";
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";

const [base = "http://localhost:3100", outArg = "../docs/design/recordings"] = process.argv.slice(2);
const out = path.resolve(outArg);
const tmp = path.join(out, ".raw");
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || "/opt/pw-browsers/chromium", args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const pause = (p, ms) => p.waitForTimeout(ms);

async function walk(page, c, mobile) {
  await page.goto(`${base}/concepts/${c}`, { waitUntil: "networkidle" });
  await page.evaluate(() => document.documentElement.setAttribute("data-tier", "high"));
  await pause(page, 2500);
  await page.mouse.wheel(0, 900);
  await pause(page, 1500);
  await page.mouse.wheel(0, 900);
  await pause(page, 1200);
  // Witty chat: ask-before-suggest flow with generative UI
  await page.goto(`${base}/concepts/${c}/chat`, { waitUntil: "networkidle" });
  await pause(page, 1200);
  for (const chip of ["Find an online MBA under ₹2L", "Marketing", "B.Com, 68%", "Compare these"]) {
    await page.getByRole("button", { name: chip, exact: true }).first().click();
    await pause(page, chip === "B.Com, 68%" ? 4200 : 3200);
  }
  // Finder: filter, expand a group, open the detail panel
  await page.goto(`${base}/concepts/${c}/finder`, { waitUntil: "networkidle" });
  await pause(page, 1000);
  await page.getByPlaceholder(/mba marketing/).fill("mba");
  await pause(page, 1200);
  if (!mobile && c === "a") {
    await page.getByRole("button", { name: /Postgraduate/ }).first().click();
    await pause(page, 1000);
  }
  await page.locator('button[aria-controls^="group-"]').first().click();
  await pause(page, 1200);
  await page.locator('[id^="group-"][id$="-list"] li button').first().click();
  await pause(page, 2200);
  await page.getByRole("dialog").getByText("Approvals and accreditation").scrollIntoViewIfNeeded();
  await pause(page, 1800);
  await page.keyboard.press("Escape");
  await pause(page, 800);
}

for (const c of ["a", "b"]) {
  for (const [name, opts] of [["phone", { ...devices["Pixel 7"] }], ["desktop", { viewport: { width: 1440, height: 900 } }]]) {
    const ctx = await browser.newContext({ ...opts, recordVideo: { dir: tmp, size: name === "phone" ? { width: 412, height: 839 } : { width: 1440, height: 900 } } });
    const page = await ctx.newPage();
    try {
      await walk(page, c, name === "phone");
    } catch (e) {
      console.error(`concept ${c} ${name}:`, e.message);
    }
    const v = page.video();
    await ctx.close();
    if (v) await v.saveAs(path.join(out, `concept-${c}-${name}.webm`));
    console.info(`recorded concept-${c}-${name}.webm`);
  }
}
await browser.close();
rmSync(tmp, { recursive: true, force: true });
