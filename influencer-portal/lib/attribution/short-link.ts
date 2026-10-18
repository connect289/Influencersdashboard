import "server-only";
import { env } from "@/lib/env";
import { SETTINGS } from "@/lib/settings/registry";
import type { Db } from "@/lib/contracts/data";
import { shortLink } from "./links";

/** The short-link base from settings (the printed domain), or this app's own `/r/` when none is set. */
export async function shortLinkBase(db: Db): Promise<string> {
  const { data } = await db.rpc("setting", { p_key: "attribution.links" });
  const s = SETTINGS["attribution.links"].schema.catch(SETTINGS["attribution.links"].default).parse(data);
  return s.short_link_base.trim() || `${env().NEXT_PUBLIC_SITE_URL.replace(/\/$/, "")}/r/`;
}

export async function shortLinkFor(db: Db, code: string): Promise<string> {
  return shortLink(await shortLinkBase(db), code);
}
