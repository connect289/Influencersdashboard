// Deliverable rows for a deal from its agreed pieces: one row per piece ("Instagram reel 1", "Instagram reel 2"…)
// with format specs, the template's stages and due dates from its offsets. Pure.
import { z } from "zod";
import type { DeliverableItem } from "@/lib/campaigns/schemas";
import { CONTENT_FORMATS, PLATFORMS, type ContentFormat, type Platform } from "@/lib/creators/schemas";
import { deliverableSpecs, dueDatesFrom, type briefTemplateContent } from "./brief";

const PLATFORM_LABEL: Record<Platform, string> = {
  instagram: "Instagram",
  youtube: "YouTube",
  facebook: "Facebook",
  linkedin: "LinkedIn",
  x: "X",
  telegram: "Telegram",
  moj_josh: "Moj/Josh",
  other: "Other",
};
const FORMAT_LABEL: Record<ContentFormat, string> = {
  reel: "reel",
  story: "story",
  post: "post",
  youtube_video: "video",
  short: "short",
  live: "live session",
  carousel: "carousel",
  blog: "blog post",
  other: "piece",
};

export type DeliverablePlan = {
  title: string;
  platform: Platform;
  format: ContentFormat;
  specs: { duration_s: number | null; aspect_ratio: string | null; notes: string };
  stages: Record<string, boolean>;
  due_dates: Record<string, string>;
};

/** One row per piece, with format specs and due dates counted from `start`. */
export function planDeliverables(
  items: readonly DeliverableItem[],
  start: string,
  template: z.output<typeof briefTemplateContent>,
): DeliverablePlan[] {
  const specs = deliverableSpecs(items);
  const due = dueDatesFrom(start, template.due_offsets, template.stages);
  return items.flatMap((d, i) =>
    Array.from({ length: d.count }, (_, n) => ({
      title: `${PLATFORM_LABEL[d.platform]} ${FORMAT_LABEL[d.format]}${d.count > 1 ? ` ${String(n + 1)}` : ""}`,
      platform: z.enum(PLATFORMS).parse(d.platform),
      format: z.enum(CONTENT_FORMATS).parse(d.format),
      specs: { duration_s: specs[i]?.duration_s ?? null, aspect_ratio: specs[i]?.aspect_ratio ?? null, notes: "" },
      stages: { ...template.stages },
      due_dates: due,
    })),
  );
}
