import { chromium, devices } from "@playwright/test";
const out = process.argv[2]; const base = "http://localhost:3000";
const pages = (process.argv[3] ?? "/concepts/a,/concepts/b").split(",");
const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium", args: ["--enable-unsafe-swiftshader", "--use-gl=angle", "--use-angle=swiftshader"] });
for (const [name, opts] of [["desktop", { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 }], ["mobile", { ...devices["Pixel 7"] }]]) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  for (const p of pages) {
    await page.goto(base + p, { waitUntil: "networkidle" });
    await page.evaluate(() => document.documentElement.setAttribute("data-tier", "high"));
    await page.waitForTimeout(2500);
    const f = `${out}/${name}${p.replaceAll("/", "_")}.png`;
    await page.screenshot({ path: f, fullPage: process.argv[4] === "full" });
    console.log(f, errors.length ? "ERRORS: " + errors.join(" | ").slice(0, 400) : "");
    errors.length = 0;
  }
  await ctx.close();
}
await browser.close();
