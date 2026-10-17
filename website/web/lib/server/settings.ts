import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { DEFAULT_SETTINGS, parseSettings, type Settings } from "@/lib/settings";
import { dbConfigured, rpc } from "./db";
import { errorFields, log } from "./log";

/**
 * Site settings, cached (short TTL) and tagged so admin saves revalidate them instantly (spec 3A feature flags).
 * If the database is unreachable the site keeps working on defaults (graceful degradation).
 */
export async function getSettings(): Promise<Settings> {
  "use cache";
  cacheLife({ stale: 30, revalidate: 30, expire: 300 });
  cacheTag("settings");
  if (!dbConfigured()) return DEFAULT_SETTINGS;
  try {
    return parseSettings(await rpc<Record<string, unknown>>("web_settings_all"));
  } catch (err) {
    log("error", "settings.load_failed", errorFields(err));
    return DEFAULT_SETTINGS;
  }
}
