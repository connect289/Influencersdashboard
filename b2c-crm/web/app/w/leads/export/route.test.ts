import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { rpc, assertUser } = vi.hoisted(() => ({ rpc: vi.fn(), assertUser: vi.fn() }));
vi.mock("@/lib/auth", () => ({ assertUser }));
vi.mock("@/lib/data", () => ({ rpc }));
import * as route from "./route";

const SITE = "https://spark.eduwit.in";
const form = (fields: Record<string, string>) => new URLSearchParams(fields).toString();
const post = (origin: string | null, fields: Record<string, string>, extra: Record<string, string> = {}) =>
  new NextRequest(`${SITE}/w/leads/export`, {
    method: "POST", body: form(fields),
    headers: { "content-type": "application/x-www-form-urlencoded", host: "spark.eduwit.in", ...(origin ? { origin } : {}), ...extra },
  });

describe("the leads export", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", SITE);
    assertUser.mockResolvedValue({ user_id: "a", role: "admin" });
    rpc.mockImplementation(async (fn: string) => {
      if (fn === "export_request") return { inline: true, rows: 1 };
      if (fn === "lead_list") return { total: 1, rows: [{ lead_id: 7, name: "Asha Test" }] };
      return null;
    });
  });
  afterEach(() => { vi.unstubAllEnvs(); rpc.mockReset(); assertUser.mockReset(); });

  it("never starts from a GET link: back to the Leads page with the same view", async () => {
    const res = await route.GET(new NextRequest(`${SITE}/w/leads/export?view=3&q=asha&format=csv&ids=1,2`));
    expect(res.status).toBe(303);
    expect(res.headers.get("location")).toBe(`${SITE}/w/leads?view=3&q=asha`);
    expect(assertUser).not.toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
  });

  it("refuses a POST that does not come from this site", async () => {
    for (const req of [post("https://evil.example", { format: "csv" }), post(null, { format: "csv" }), post("null", { format: "csv" }),
      post(SITE, { format: "csv" }, { "sec-fetch-site": "cross-site" })]) {
      expect((await route.POST(req)).status).toBe(403);
    }
    expect(rpc).not.toHaveBeenCalled();
  });

  it("exports on a POST from the Leads page", async () => {
    const res = await route.POST(post(SITE, { q: "asha", format: "csv" }, { "sec-fetch-site": "same-origin" }));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-disposition")).toMatch(/^attachment; filename="b2c-leads-\d+\.csv"$/);
    expect(await res.text()).toContain("Asha Test");
    expect(rpc.mock.calls.map((c) => c[0])).toEqual(["export_request", "lead_list", "audit"]);
  });
});
