import { describe, expect, it } from "vitest";
import { refreshReasons } from "./refresh";

const now = Date.parse("2026-10-17T00:00:00Z");
const g = (slug: string, published_at: string | null, refresh_due_at: string | null = null, status = "published") => ({ slug, status, published_at, refresh_due_at });

describe("refresh due", () => {
  it("flags past refresh date, losing clicks and old guides; ignores drafts and small drops", () => {
    const r = refreshReasons(
      [
        g("dated", "2026-09-01", "2026-10-01"),
        g("falling", "2026-09-01"),
        g("small-drop", "2026-09-01"),
        g("old", "2025-12-01"),
        g("fresh", "2026-09-01"),
        g("draft", "2024-01-01", null, "draft"),
      ],
      [
        { page: "/resources/falling", clicks: 6, prev: 20 },
        { page: "/resources/small-drop", clicks: 3, prev: 4 },
      ],
      now,
    );
    expect(Object.fromEntries(r)).toEqual({ dated: "past its refresh date", falling: "losing clicks (20 → 6)", old: "older than 9 months" });
  });
});
