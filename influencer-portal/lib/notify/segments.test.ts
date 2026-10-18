import { describe, expect, it } from "vitest";
import { isEveryone, matchesSegment, segmentSchema } from "./segments";

const T1 = "00000000-0000-4000-8000-000000000001";
const C1 = "00000000-0000-4000-8000-0000000000c1";
const riya = { tier_id: T1, campaign_ids: [C1], platforms: ["instagram"], languages: ["English", "Hindi"] };

describe("announcement segments", () => {
  it("sends to everyone when nothing is set", () => {
    const s = segmentSchema.parse({});
    expect(isEveryone(s)).toBe(true);
    expect(matchesSegment({ tier_id: null, campaign_ids: [], platforms: [], languages: [] }, s)).toBe(true);
  });

  it("needs every set list to match, any value within a list", () => {
    expect(
      matchesSegment(riya, segmentSchema.parse({ platforms: ["youtube", "instagram"], languages: ["hindi"] })),
    ).toBe(true);
    expect(matchesSegment(riya, segmentSchema.parse({ platforms: ["youtube"] }))).toBe(false);
    expect(matchesSegment(riya, segmentSchema.parse({ tiers: [T1], campaigns: [C1] }))).toBe(true);
    expect(matchesSegment({ ...riya, tier_id: null }, segmentSchema.parse({ tiers: [T1] }))).toBe(false);
  });
});
