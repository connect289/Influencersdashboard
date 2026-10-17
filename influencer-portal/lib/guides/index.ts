// Guide registry: which guides each portal shows, and lookup by slug.
import type { Permission } from "@/lib/auth/permissions";
import { DEVELOPER } from "./content/developer";
import { AGENCY, CREATOR } from "./content/external";
import {
  ALL_STAFF,
  CONTENT_REVIEWER,
  FINANCE,
  INFLUENCER_MANAGER,
  SUPER_ADMIN,
  VIEWER,
} from "./content/staff";
import type { Guide, GuideAudience } from "./types";

export const GUIDES: readonly Guide[] = [
  ALL_STAFF,
  SUPER_ADMIN,
  INFLUENCER_MANAGER,
  CONTENT_REVIEWER,
  FINANCE,
  VIEWER,
  DEVELOPER,
  CREATOR,
  AGENCY,
];

export type Portal = "admin" | "creator" | "agency";

const STAFF_AUDIENCES: readonly GuideAudience[] = [
  "all_staff",
  "super_admin",
  "influencer_manager",
  "content_reviewer",
  "finance",
  "viewer",
];

/** Guides a portal user may read. Staff read every staff guide; the developer guide needs system access. */
export function guidesFor(
  portal: Portal,
  permissions: ReadonlySet<Permission> = new Set(),
): Guide[] {
  return GUIDES.filter((g) => {
    if (portal === "creator") return g.audience === "creator";
    if (portal === "agency") return g.audience === "agency";
    if (g.audience === "developer") return permissions.has("system.read");
    return STAFF_AUDIENCES.includes(g.audience);
  });
}

/** The guides written for a staff member's own roles come first ("for you"). */
export function staffGuideOrder(
  guides: readonly Guide[],
  roles: readonly string[],
): { mine: Guide[]; others: Guide[] } {
  const mine = guides.filter(
    (g) =>
      g.audience === "all_staff" ||
      roles.includes(g.audience) ||
      (g.audience === "developer" && roles.includes("super_admin")),
  );
  return { mine, others: guides.filter((g) => !mine.includes(g)) };
}

export function findGuide(
  portal: Portal,
  slug: string,
  permissions?: ReadonlySet<Permission>,
): Guide | null {
  return guidesFor(portal, permissions).find((g) => g.slug === slug) ?? null;
}

/** Plain text of a guide, for search. */
export function guideText(g: Guide): string {
  const parts: string[] = [g.title, g.summary];
  for (const s of g.sections) {
    parts.push(s.title);
    for (const b of s.blocks) {
      if ("p" in b) parts.push(b.p);
      else if ("h" in b) parts.push(b.h);
      else if ("steps" in b) parts.push(...b.steps);
      else if ("list" in b) parts.push(...b.list);
      else if ("tip" in b) parts.push(b.tip);
      else if ("warning" in b) parts.push(b.warning);
      else parts.push(...b.table.head, ...b.table.rows.flat());
    }
  }
  return parts.join(" ").replace(/\*\*|`|\[([^\]]+)\]\([^)]+\)/g, "$1");
}

/** Sections matching a search, across the given guides. */
export function searchGuides(
  guides: readonly Guide[],
  q: string,
): { guide: Guide; section: Guide["sections"][number] }[] {
  const terms = q
    .toLowerCase()
    .split(/\s+/)
    .filter((x) => x.length >= 2);
  if (!terms.length) return [];
  const out: { guide: Guide; section: Guide["sections"][number] }[] = [];
  for (const guide of guides)
    for (const section of guide.sections) {
      const text = guideText({
        ...guide,
        title: "",
        summary: "",
        sections: [section],
      }).toLowerCase();
      if (terms.every((t) => text.includes(t))) out.push({ guide, section });
    }
  return out.slice(0, 30);
}
