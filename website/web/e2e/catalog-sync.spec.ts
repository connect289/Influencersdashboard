import { expect, test } from "@playwright/test";
import { dbPatch, dbRpc, dbSelect } from "./helpers";

/**
 * The programme list follows the shared catalogue (the rows Witty and the CRMs read), whoever edits it (D-081): a fee
 * changed directly in the catalogue table — no loader, no updated_at, no catalog_version — reaches the website through
 * the same path as production: catalogue poll (pg_cron) → read-model rebuild → outbox revalidation → fresh pages and API.
 */
const internalKey = () => process.env.WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001";

test.describe("catalogue sync", () => {
  test.skip(({ isMobile }) => isMobile, "server-side flow; laptop project only");

  test("a direct catalogue edit reaches the finder API and the university page", async ({ request }) => {
    const [o] = await dbSelect<{ id: number; uni_slug: string; fee_total: number }>(
      "web_offering_search",
      "visible=eq.true&fee_total=not.is.null&select=id,uni_slug,fee_total&order=id&limit=1",
    );
    const [c] = await dbSelect<{ fee_total: number }>("catalog_programs", `id=eq.${o!.id}&select=fee_total`);
    const original = c!.fee_total;
    const changed = original + 1111;
    const syncNow = async () => {
      await dbRpc("web_catalog_poll");
      const r = await request.post("/api/internal/outbox", { headers: { authorization: `Bearer ${internalKey()}` } });
      expect(r.ok()).toBe(true);
    };
    const apiFee = async () => {
      const r = await request.get(`/api/search?uni=${o!.uni_slug}&view=flat&page_size=100&sync=${Date.now()}`);
      const j = (await r.json()) as { items: { id: number; fee: { total?: number } }[] };
      return j.items.find((i) => i.id === o!.id)?.fee.total;
    };
    try {
      await dbPatch("catalog_programs", `id=eq.${o!.id}`, { fee_total: changed });
      await syncNow();
      await expect.poll(apiFee, { timeout: 20_000, intervals: [500, 1000, 2000] }).toBe(changed);
      const shown = changed.toLocaleString("en-IN");
      await expect
        .poll(async () => (await (await request.get(`/universities/${o!.uni_slug}`)).text()).includes(shown), { timeout: 20_000, intervals: [500, 1000, 2000] })
        .toBe(true);
    } finally {
      await dbPatch("catalog_programs", `id=eq.${o!.id}`, { fee_total: original });
      await syncNow();
    }
  });
});
