import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { DEFAULT_SETTINGS, parseSettings, type Settings } from "@/lib/settings";
import { dbConfigured, rpc } from "./db";
import { errorFields, log } from "./log";

/**
 * Site settings, cached and tagged so admin saves revalidate them instantly (spec 3A feature flags).
 * If the database is unreachable the site keeps working on defaults (graceful degradation).
 *
 * The lifetime is the catalogue's (D-094). The root layout reads the settings, so their lifetime is every page's: at
 * 30 s to revalidate and 300 s to expire, each prerendered page regenerated every 30 s and, after five quiet minutes,
 * was rendered again while the visitor waited. A setting saved in the admin still applies at once (revalidateTag);
 * one changed by SQL takes up to five minutes, or /api/internal/revalidate.
 */
export async function getSettings(): Promise<Settings> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("settings");
  if (!dbConfigured()) return DEFAULT_SETTINGS;
  try {
    return parseSettings(await rpc<Record<string, unknown>>("web_settings_all"));
  } catch (err) {
    log("error", "settings.load_failed", errorFields(err));
    return DEFAULT_SETTINGS;
  }
}
