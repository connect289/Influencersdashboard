// Media kit data (inf.media_kit / inf.media_kit_public) and helpers shared by the web page and the PDF.
import { z } from "zod";
import { CONTENT_FORMATS, PLATFORMS } from "@/lib/creators/schemas";

export const mediaKitSchema = z.object({
  creator_id: z.uuid(),
  display_name: z.string(),
  handle: z.string(),
  bio: z.string().nullable(),
  city: z.string().nullable(),
  state: z.string().nullable(),
  languages: z.array(z.string()),
  niches: z.array(z.string()),
  avatar_path: z.string().nullable(),
  public_page_enabled: z.boolean(),
  show_rates: z.boolean(),
  total_followers: z.number(),
  platforms: z.array(
    z.object({
      platform: z.enum(PLATFORMS),
      handle: z.string(),
      url: z.string(),
      followers: z.number().nullable(),
      avg_views: z.number().nullable(),
      engagement_rate: z.number().nullable(),
      stats_updated_at: z.string().nullable(),
    }),
  ),
  rates: z.array(
    z.object({
      platform: z.enum(PLATFORMS),
      format: z.enum(CONTENT_FORMATS),
      suggested_paise: z.number(),
    }),
  ),
  portfolio: z.array(z.object({ url: z.string(), title: z.string().nullable() })),
  generated_at: z.string(),
});
export type MediaKit = z.infer<typeof mediaKitSchema>;

export const AVATAR_BUCKET = "inf-public-avatars";
export const AVATAR_TYPES = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
} as const;
export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;

export function avatarUrl(supabaseUrl: string, path: string | null): string | null {
  if (!path || !/^[0-9a-f-]{36}\/\d{10,16}\.(jpg|png|webp)$/.test(path)) return null;
  return `${supabaseUrl.replace(/\/$/, "")}/storage/v1/object/public/${AVATAR_BUCKET}/${path}`;
}

/** Weighted average engagement across platforms that report it (by followers). */
export function averageEngagement(kit: Pick<MediaKit, "platforms">): number | null {
  const rows = kit.platforms.filter((p) => p.engagement_rate !== null && (p.followers ?? 0) > 0);
  const total = rows.reduce((s, p) => s + (p.followers ?? 0), 0);
  if (!total) return null;
  return (
    Math.round(
      (rows.reduce((s, p) => s + (p.engagement_rate ?? 0) * (p.followers ?? 0), 0) / total) * 100,
    ) / 100
  );
}

/** File name for the PDF download. */
export function mediaKitFileName(handle: string): string {
  return `${handle.replace(/[^a-z0-9._-]/gi, "").replace(/^\.+/, "") || "creator"}-media-kit.pdf`;
}
