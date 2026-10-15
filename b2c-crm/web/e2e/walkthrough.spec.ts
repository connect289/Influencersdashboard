import { mkdirSync } from "node:fs";
import { expect, test } from "@playwright/test";
import { people, service, stateFile, watch, type Who } from "./helpers";

/**
 * Opens every screen as each role and checks it renders: no error page, no exception, no failed server call.
 * Screenshots go to e2e/screens/<laptop|phone>/ for review.
 */
const SALES = ["/s", "/s/leads", "LEAD", "/s/pipeline", "/s/followups", "/s/inbox", "/s/programmes", "/s/programmes?university=Jain&mode=Online", "/s/money", "/s/analytics",
  "/s/team", "/s/alerts", "/s/me", "/s/me?tab=availability", "/s/me?tab=templates", "/s/me?tab=enrolments", "/s/me?tab=snippets", "/s/me?tab=guide", "/s/support"];
const WORKSPACE = ["/w", "/w/leads", "LEAD", "/w/pipeline",
  "/w/allocation", "/w/allocation?tab=rules", "/w/allocation?tab=pools", "/w/allocation?tab=calendar", "/w/allocation?tab=queues", "/w/allocation?tab=simulation", "/w/allocation?tab=audit",
  "/w/enrollments",
  "/w/nurture", "/w/nurture?tab=pool", "/w/nurture?tab=journeys", "/w/nurture?tab=campaigns", "/w/nurture?tab=segments", "/w/nurture?tab=replies", "/w/nurture?tab=scoring",
  "/w/templates", "/w/templates?tab=wa_sales", "/w/templates?tab=wa_marketing", "/w/templates?tab=email_marketing",
  "/w/money", "/w/money?tab=universities", "/w/money?tab=enrolments", "/w/money?tab=receivables", "/w/money?tab=statements", "/w/money?tab=commission", "/w/money?tab=ads",
  "/w/analytics", "/w/team", "/w/teams", "/w/connectors", "/w/settings", "/w/settings?tab=health", "/w/settings?tab=audit", "/w/settings?tab=signins", "/w/leads/duplicates", "/w/guide", "/w/support",
  "/w/programmes", "/w/programmes?course=MBA&level=PG", "/w/qualify", "/w/leads/flagged", "/w/leads?layout=kanban", "/w/allocation?tab=capacity"];

const ROUTES: Record<Who, string[]> = { asha: SALES, ravi: ["/s", "/s/leads", "LEAD"], manager: SALES, admin: WORKSPACE, marketing: WORKSPACE };

async function leadFor(who: Who): Promise<number> {
  if (who === "admin" || who === "marketing") return 990101;
  const { data } = await service().schema("b2c").from("leads_state").select("lead_id").eq("owner_id", people()[who].user_id)
    .gte("lead_id", 990101).lte("lead_id", 990130).order("lead_id").limit(1);
  return data?.[0]?.lead_id ?? 990101;
}

const slug = (r: string) => r.replace(/^\//, "").replace(/[/?=&]+/g, "-") || "home";

for (const who of Object.keys(ROUTES) as Who[]) {
  test.describe(`${who}`, () => {
    test.use({ storageState: stateFile(who) });
    test(`every screen opens`, async ({ page }, info) => {
      test.setTimeout(ROUTES[who].length * 45_000);
      const dir = new URL(`./screens/${info.project.name}/`, import.meta.url).pathname;
      mkdirSync(dir, { recursive: true });
      const lead = await leadFor(who);
      for (const r of ROUTES[who]) {
        const route = r === "LEAD" ? `${ROUTES[who][0] ?? "/s"}/leads/${lead}` : r;
        await test.step(route, async () => {
          const problems = watch(page);
          const res = await page.goto(route, { waitUntil: "networkidle" });
          expect.soft(res?.status(), `${route} status`).toBeLessThan(400);
          expect.soft(await page.getByRole("heading", { name: /Something went wrong|Not found/ }).count(), `${route} error page`).toBe(0);
          await expect.soft(page.locator("main, [role=main], body").first()).toBeVisible();
          await page.screenshot({ path: `${dir}${who}-${slug(r === "LEAD" ? "lead" : r)}.png`, fullPage: true });
          expect.soft(problems, `${route} problems`).toEqual([]);
          page.removeAllListeners("console"); page.removeAllListeners("pageerror"); page.removeAllListeners("response");
        });
      }
    });
  });
}
