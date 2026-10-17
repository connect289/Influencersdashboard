import "server-only";
// Preview details for a live post from the platform's public oEmbed endpoint (YouTube only; the others need app
// review). Fixed endpoint, short timeout, and only safe fields are kept (never HTML).
import type { Platform } from "@/lib/creators/schemas";
import { log } from "@/lib/log";
import { oembedEndpoint, pickOembed, type OembedInfo } from "./urls";

export async function fetchOembed(platform: Platform, url: string): Promise<OembedInfo | null> {
  const endpoint = oembedEndpoint(platform, url);
  if (!endpoint) return null;
  try {
    const r = await fetch(endpoint, { signal: AbortSignal.timeout(4000), redirect: "error", cache: "no-store" });
    if (!r.ok) return null;
    return pickOembed(await r.json());
  } catch (e) {
    log.info("oembed.failed", { platform, error: e instanceof Error ? e.message : String(e) });
    return null;
  }
}
