import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { sampleRows } = await import("./gsc");

describe("Search Console sample rows", () => {
  it("are deterministic and only for pages that exist", () => {
    const a = sampleRows(7, ["/programmes/online-mba"], new Date("2026-10-17"));
    expect(a).toEqual(sampleRows(7, ["/programmes/online-mba"], new Date("2026-10-17")));
    expect(a.every((r) => ["/", "/programmes", "/programmes/online-mba"].includes(r.page))).toBe(true);
    expect(a.every((r) => r.clicks <= r.impressions && r.position >= 1)).toBe(true);
  });
});
