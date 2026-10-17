#!/usr/bin/env node
// axe-core WCAG 2.1 AA scan of pages in both themes. Usage: node scripts/axe.mjs <baseUrl> <path,path,...>
import { chromium } from "@playwright/test";
import { AxeBuilder } from "@axe-core/playwright";

const [base = "http://localhost:3100", list = "/"] = process.argv.slice(2);
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || "/opt/pw-browsers/chromium" });
let failures = 0;
for (const theme of ["dark", "light"]) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: "reduce" });
  const page = await ctx.newPage();
  for (const p of list.split(",")) {
    await page.goto(base + p, { waitUntil: "networkidle" });
    await page.evaluate((t) => document.querySelectorAll("[data-theme]").forEach((el) => el.setAttribute("data-theme", t)), theme);
    await page.waitForTimeout(300);
    const r = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
    const v = r.violations.filter((x) => x.impact === "serious" || x.impact === "critical" || x.impact === "moderate");
    failures += v.length;
    console.info(`${theme} ${p}: ${v.length ? v.map((x) => `${x.id} (${x.nodes.length}) e.g. ${x.nodes[0]?.target}`).join("; ") : "no violations"}`);
  }
  await ctx.close();
}
await browser.close();
process.exit(failures ? 1 : 0);
