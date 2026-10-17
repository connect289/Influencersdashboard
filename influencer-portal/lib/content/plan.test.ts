import { describe, expect, it } from "vitest";
import { briefTemplateContent } from "./brief";
import { planDeliverables } from "./plan";

const template = briefTemplateContent.parse({});

describe("planDeliverables", () => {
  it("makes one numbered row per piece with format specs", () => {
    const rows = planDeliverables(
      [
        { platform: "instagram", format: "reel", count: 2 },
        { platform: "youtube", format: "youtube_video", count: 1 },
      ],
      "2026-11-01T00:00:00.000Z",
      template,
    );
    expect(rows.map((r) => r.title)).toEqual([
      "Instagram reel 1",
      "Instagram reel 2",
      "YouTube video",
    ]);
    expect(rows[0]?.specs).toEqual({ duration_s: 60, aspect_ratio: "9:16", notes: "" });
    expect(rows[2]?.specs).toEqual({ duration_s: 480, aspect_ratio: "16:9", notes: "" });
  });

  it("uses the template's stages and due offsets (end of the IST day)", () => {
    const [r] = planDeliverables(
      [{ platform: "instagram", format: "story", count: 1 }],
      "2026-11-01T00:00:00.000Z",
      {
        ...template,
        stages: { ...template.stages, concept: false },
      },
    );
    expect(r?.stages.concept).toBe(false);
    expect(r?.due_dates.concept).toBeUndefined();
    // 1 Nov 05:30 IST + 10 days → 11 Nov 23:59:59 IST.
    expect(r?.due_dates.draft).toBe("2026-11-11T18:29:59.000Z");
    expect(r?.due_dates.live).toBe("2026-11-16T18:29:59.000Z");
  });

  it("returns nothing for no pieces", () => {
    expect(planDeliverables([], "2026-11-01T00:00:00.000Z", template)).toEqual([]);
  });
});
