import { describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

vi.mock("server-only", () => ({}));
const limit = { ok: true };
const rateLimit = vi.fn(async () => ({ ok: limit.ok, remaining: 0 }));
vi.mock("@/lib/server/rate-limit", () => ({
  rateLimit,
  LIMITS: { searchPerIp: { name: "search_ip", limit: 600, windowSeconds: 600 } },
}));
const offeringCards = vi.fn(async (ids: number[]) => ids.map((id) => ({ id })));
const offeringDetails = vi.fn(async (id: number) => ({ id }));
vi.mock("@/lib/server/search", async () => {
  const real = await vi.importActual<{ offeringIdSet: unknown; MAX_OFFERING_CARDS: number }>("@/lib/server/search");
  return {
    offeringIdSet: real.offeringIdSet,
    MAX_OFFERING_CARDS: real.MAX_OFFERING_CARDS,
    offeringCards,
    offeringDetails,
  };
});
vi.mock("next/cache", () => ({ cacheLife: () => undefined, cacheTag: () => undefined }));
vi.mock("@/lib/server/db", () => ({ rpc: vi.fn(), rpcRead: vi.fn(), dbConfigured: () => true }));

const batch = await import("./route");
const single = await import("./[id]/route");

describe("/api/offerings (D-095)", () => {
  it("is rate-limited per IP like /api/search", async () => {
    limit.ok = false;
    const r = await batch.GET(
      new NextRequest("http://localhost/api/offerings?ids=1,2", { headers: { "x-forwarded-for": "203.0.113.9" } }),
    );
    expect(r.status).toBe(429);
    const s = await single.GET(new NextRequest("http://localhost/api/offerings/7"), {
      params: Promise.resolve({ id: "7" }),
    });
    expect(s.status).toBe(429);
    expect(offeringCards).not.toHaveBeenCalled();
    expect(offeringDetails).not.toHaveBeenCalled();
    limit.ok = true;
  });
  it("passes distinct valid ids, in order, at most 100", async () => {
    const ids = [3, 1, 3, "x", 2, ...Array.from({ length: 300 }, (_, i) => i + 10)].join(",");
    const r = await batch.GET(new NextRequest(`http://localhost/api/offerings?ids=${ids}`));
    expect(r.status).toBe(200);
    const asked = offeringCards.mock.calls[0]![0];
    expect(asked.slice(0, 3)).toEqual([3, 1, 2]);
    expect(asked).toHaveLength(100);
    expect(new Set(asked).size).toBe(100);
  });
});
