import "server-only";
// Each deliverable's tracking link (the first active one, normally created with the deliverable), with its short URL.
import { shortLink } from "@/lib/attribution/links";
import { shortLinkBase } from "@/lib/attribution/short-link";
import type { Db } from "@/lib/contracts/data";
import { loadLinks } from "./data";

export interface DeliverableLink {
  id: string;
  code: string;
  url: string;
}

/** Fallback when links cannot be loaded: the page still renders, without links. */
export const noLinks = (): Record<string, DeliverableLink> => ({});

export async function loadDeliverableLinks(
  db: Db,
  creatorId: string,
): Promise<Record<string, DeliverableLink>> {
  const [links, base] = await Promise.all([loadLinks(db, creatorId), shortLinkBase(db)]);
  const out: Record<string, DeliverableLink> = {};
  for (const l of [...links].sort((a, b) => a.created_at.localeCompare(b.created_at)))
    if (l.deliverable_id && l.active && !out[l.deliverable_id])
      out[l.deliverable_id] = { id: l.id, code: l.code, url: shortLink(base, l.code) };
  return out;
}
