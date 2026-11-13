import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ cacheLife: () => undefined, cacheTag: () => undefined }));
const rpcRead = vi.fn(async (_fn: string, args: { p_ids: number[] }) =>
  args.p_ids.filter((id) => id !== 3).map((id) => ({ id })),
);
vi.mock("./db", () => ({ rpc: rpcRead, rpcRead, dbConfigured: () => true }));

const { MAX_OFFERING_CARDS, offeringCards, offeringIdSet } = await import("./search");

describe("offering cards (D-095)", () => {
  it("de-duplicates, drops invalid ids, caps the count and sorts the cache key", () => {
    expect(offeringIdSet([5, 2, 5, -1, 0, 2.5, Number.NaN, 9, 2])).toEqual({ ordered: [5, 2, 9], key: [2, 5, 9] });
    const many = Array.from({ length: 500 }, (_, i) => 500 - i);
    const { ordered, key } = offeringIdSet(many);
    expect(ordered).toHaveLength(MAX_OFFERING_CARDS);
    expect(ordered[0]).toBe(500);
    expect(key[0]).toBe(401);
  });
  it("asks the database for the sorted set and answers in the caller's order, hidden ones skipped", async () => {
    rpcRead.mockClear();
    const cards = await offeringCards([9, 3, 1, 9, 4]);
    expect(rpcRead).toHaveBeenCalledWith("web_offering_cards", { p_ids: [1, 3, 4, 9], p_qual: null });
    expect(cards.map((c) => c.id)).toEqual([9, 1, 4]);
    expect(await offeringCards([0, -2])).toEqual([]);
  });
});
