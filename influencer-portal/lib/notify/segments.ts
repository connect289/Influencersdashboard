// Announcement audiences (spec 14 "to all creators or a segment (tier, campaign, platform, language)"): empty lists
// mean "any"; a creator must match every list that is set (and any one value within a list). Pure.
import { z } from "zod";

export const segmentSchema = z.object({
  tiers: z.array(z.uuid()).max(50).default([]),
  campaigns: z.array(z.uuid()).max(50).default([]),
  platforms: z
    .array(z.string().regex(/^[a-z_]{1,20}$/))
    .max(20)
    .default([]),
  languages: z.array(z.string().trim().min(2).max(40)).max(30).default([]),
});
export type Segment = z.infer<typeof segmentSchema>;

export interface SegmentFacts {
  tier_id: string | null;
  campaign_ids: readonly string[];
  platforms: readonly string[];
  languages: readonly string[];
}

const anyOf = <T>(wanted: readonly T[], have: readonly T[]) =>
  wanted.length === 0 || wanted.some((w) => have.includes(w));

export function matchesSegment(c: SegmentFacts, s: Segment): boolean {
  const langs = c.languages.map((l) => l.toLowerCase());
  return (
    (s.tiers.length === 0 || (c.tier_id !== null && s.tiers.includes(c.tier_id))) &&
    anyOf(s.campaigns, c.campaign_ids) &&
    anyOf(s.platforms, c.platforms) &&
    anyOf(
      s.languages.map((l) => l.toLowerCase()),
      langs,
    )
  );
}

export function isEveryone(s: Segment): boolean {
  return !s.tiers.length && !s.campaigns.length && !s.platforms.length && !s.languages.length;
}
