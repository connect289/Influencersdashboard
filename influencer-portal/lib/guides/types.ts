// In-app guides (requested 17 Oct 2026; D-77). Typed long-form content, one guide per audience, rendered in each
// portal's Help area. Text may use **bold**, `code` and [label](/path) links; links to app routes are checked by
// guides.test.ts so a guide never points at a screen that does not exist.

export const GUIDE_AUDIENCES = [
  "all_staff",
  "super_admin",
  "influencer_manager",
  "content_reviewer",
  "finance",
  "viewer",
  "creator",
  "agency",
  "developer",
] as const;
export type GuideAudience = (typeof GUIDE_AUDIENCES)[number];

export type Block =
  | { p: string }
  | { h: string }
  | { steps: string[] }
  | { list: string[] }
  | { tip: string }
  | { warning: string }
  | { table: { head: string[]; rows: string[][] } };

export interface GuideSection {
  /** Anchor id, unique within the guide. */
  id: string;
  title: string;
  blocks: Block[];
}

export interface Guide {
  slug: string;
  audience: GuideAudience;
  title: string;
  summary: string;
  sections: GuideSection[];
}
