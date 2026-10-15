import { mkdirSync } from "node:fs";
import { test } from "@playwright/test";
import { people, service, stateFile, type Who } from "./helpers";

/**
 * Screenshots of chosen screens for a design review, at both sizes: SHOTS="asha:/s,asha:LEAD,admin:/w" npm run e2e -- shots
 * (LEAD = the person's first test lead). Files land in e2e/review/<laptop|phone>/.
 */
const spec = (process.env.SHOTS ?? "asha:/s,asha:LEAD,admin:/w").split(",").map((s) => s.trim()).filter(Boolean)
  .map((s) => { const [who, route] = s.split(":") as [Who, string]; return { who, route }; });

async function leadFor(who: Who): Promise<number> {
  if (who === "admin" || who === "marketing") return 990101;
  const { data } = await service().schema("b2c").from("leads_state").select("lead_id").eq("owner_id", people()[who].user_id)
    .gte("lead_id", 990101).lte("lead_id", 990130).order("lead_id").limit(1);
  return data?.[0]?.lead_id ?? 990101;
}

for (const who of [...new Set(spec.map((s) => s.who))]) {
  test.describe(who, () => {
    test.use({ storageState: stateFile(who) });
    test("review shots", async ({ page }, info) => {
      const dir = new URL(`./review/${info.project.name}/`, import.meta.url).pathname;
      mkdirSync(dir, { recursive: true });
      for (const s of spec.filter((x) => x.who === who)) {
        const route = s.route === "LEAD" ? `${who === "admin" || who === "marketing" ? "/w" : "/s"}/leads/${await leadFor(who)}` : s.route;
        await page.goto(route, { waitUntil: "networkidle" });
        await page.waitForTimeout(400);
        await page.screenshot({ path: `${dir}${who}-${route.replace(/^\//, "").replace(/[/?=&]+/g, "-") || "home"}.png`, fullPage: true });
      }
    });
  });
}
