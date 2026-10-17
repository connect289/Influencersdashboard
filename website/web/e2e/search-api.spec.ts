import { expect, test } from "@playwright/test";

test.describe("catalogue API", () => {
  test.skip(({ isMobile }) => isMobile, "API checks run once");

  test("search parses natural language into filters and returns grouped results with facets", async ({ request }) => {
    const res = await request.get("/api/search?q=MBA%20in%20marketing%20under%202%20lakh");
    expect(res.status()).toBe(200);
    expect(res.headers()["cache-control"]).toContain("s-maxage");
    const j = await res.json();
    expect(j.canonical).toBe("q=mba+in+marketing&fee_max=200000");
    expect(j.total).toBeGreaterThan(0);
    expect(j.items[0]).toMatchObject({ programme_id: "mba", spec_ids: ["marketing"] });
    for (const g of j.items) expect(g.fee_max ?? 0).toBeLessThanOrEqual(200000);
    expect(j.facets.level.length).toBeGreaterThan(0);
    expect(JSON.stringify(j)).not.toMatch(/commission|partner_|accreditation_text|source_file/);
  });

  test("zero results never dead-end", async ({ request }) => {
    const j = await (await request.get("/api/search?q=qwzxv")).json();
    expect(j.total).toBe(0);
    expect(j.closest.length).toBeGreaterThan(0);
    expect(j.without_query).toBeGreaterThan(0);
  });

  test("suggestions are grouped", async ({ request }) => {
    const j = await (await request.get("/api/suggest?q=mba%20mark")).json();
    expect(j.groups[0].label).toContain("MBA");
  });

  test("offering details: only catalogue facts; unknown id is a 404", async ({ request }) => {
    const search = await (await request.get("/api/search?programme=mba&view=flat")).json();
    const id = search.items[0].id;
    const d = await (await request.get(`/api/offerings/${id}`)).json();
    expect(d.id).toBe(id);
    expect(d.university.slug).toBeTruthy();
    expect((await request.get("/api/offerings/999999999")).status()).toBe(404);
    expect((await request.get("/api/offerings/abc")).status()).toBe(404);
  });

  test("internal endpoints require the bearer key", async ({ request }) => {
    expect((await request.post("/api/internal/outbox")).status()).toBe(401);
    expect((await request.post("/api/internal/revalidate", { data: { tags: ["catalog"] } })).status()).toBe(401);
  });
});
