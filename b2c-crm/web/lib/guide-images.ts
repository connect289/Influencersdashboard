import "server-only";
import { adminClient } from "@/lib/supabase/admin";
import type { MdImage } from "@/lib/markdown";

/**
 * Screenshots for guide articles the person may already read (the ids come from b2c.guides, which checks the role):
 * each as a 10-minute signed link to the private b2c-guides bucket. A missing file shows as its caption.
 */
export async function guideImages(articleIds: number[]): Promise<Record<number, (MdImage & { path: string })[]>> {
  const ids = [...new Set(articleIds)].filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) return {};
  const db = adminClient();
  const { data, error } = await db.from("user_guides").select("id, images").in("id", ids);
  if (error || !data) return {};
  const rows = data as { id: number; images: { path: string; caption?: string }[] | null }[];
  const paths = rows.flatMap((r) => (r.images ?? []).map((i) => i.path)).filter((p) => /^guides\/[A-Za-z0-9/_.-]+$/.test(p));
  const signed = new Map<string, string>();
  if (paths.length) {
    const { data: urls } = await db.storage.from("b2c-guides").createSignedUrls(paths, 600);
    for (const u of urls ?? []) if (u.path && u.signedUrl) signed.set(u.path, u.signedUrl);
  }
  return Object.fromEntries(rows.filter((r) => (r.images ?? []).length).map((r) => [r.id, (r.images ?? []).map((i) => ({ path: i.path, caption: i.caption ?? null, url: signed.get(i.path) ?? null }))]));
}
