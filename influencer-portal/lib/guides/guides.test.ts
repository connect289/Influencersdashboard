import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { STAFF_ROLES, type Permission } from "@/lib/auth/permissions";
import { findGuide, GUIDES, guidesFor, guideText, searchGuides, staffGuideOrder } from ".";
import { GUIDE_AUDIENCES } from "./types";

const appDir = join(import.meta.dirname, "..", "..", "app");

/** Every page route in app/, with route groups removed and dynamic segments as patterns. */
function routes(dir = appDir, prefix = ""): RegExp[] {
  const out: RegExp[] = [];
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (!statSync(p).isDirectory()) continue;
    const seg = /^\(.*\)$/.test(f) ? "" : f.startsWith("[") ? "/[^/]+" : `/${f}`;
    if (existsSync(join(p, "page.tsx"))) out.push(new RegExp(`^${prefix}${seg || ""}$`));
    out.push(...routes(p, prefix + seg));
  }
  return out;
}

describe("guides", () => {
  const pages = routes();

  it("has one guide per audience, with unique slugs", () => {
    expect(new Set(GUIDES.map((g) => g.audience))).toEqual(new Set(GUIDE_AUDIENCES));
    expect(new Set(GUIDES.map((g) => g.slug)).size).toBe(GUIDES.length);
  });

  it("every staff role has its own guide", () => {
    for (const role of STAFF_ROLES)
      expect(
        GUIDES.some((g) => g.audience === role),
        role,
      ).toBe(true);
  });

  it("section ids are unique within each guide and usable as anchors", () => {
    for (const g of GUIDES) {
      const ids = g.sections.map((s) => s.id);
      expect(new Set(ids).size, g.slug).toBe(ids.length);
      for (const id of ids) expect(id).toMatch(/^[a-z][a-z0-9-]*$/);
      expect(g.sections.length).toBeGreaterThan(0);
    }
  });

  it("every link in a guide points at a page that exists", () => {
    const raw = JSON.stringify(GUIDES);
    const links = [...raw.matchAll(/\]\((\/[^)\s#]*)/g)].map((m) => m[1] ?? "");
    expect(links.length).toBeGreaterThan(20);
    for (const href of links)
      expect(
        pages.some((r) => r.test(href)),
        href,
      ).toBe(true);
  });

  it("links never leave the app", () => {
    expect(JSON.stringify(GUIDES)).not.toMatch(/\]\((https?:)?\/\//);
  });

  it("each portal sees only its guides; the developer guide needs system access", () => {
    expect(guidesFor("creator").map((g) => g.audience)).toEqual(["creator"]);
    expect(guidesFor("agency").map((g) => g.audience)).toEqual(["agency"]);
    const staff = guidesFor("admin");
    expect(staff.some((g) => g.audience === "developer")).toBe(false);
    expect(staff.some((g) => g.audience === "creator" || g.audience === "agency")).toBe(false);
    const admin = guidesFor("admin", new Set<Permission>(["system.read"]));
    expect(admin.some((g) => g.audience === "developer")).toBe(true);
    expect(findGuide("creator", "super-admin")).toBeNull();
    expect(findGuide("admin", "developer")).toBeNull();
  });

  it("puts a staff member's own guides first", () => {
    const { mine, others } = staffGuideOrder(guidesFor("admin"), ["finance"]);
    expect(mine.map((g) => g.audience)).toEqual(["all_staff", "finance"]);
    expect(others.length).toBe(guidesFor("admin").length - 2);
  });

  it("search finds sections by every word and ignores markup", () => {
    const hits = searchGuides(guidesFor("admin"), "dry run");
    expect(hits.some((h) => h.section.id === "amendments")).toBe(true);
    expect(searchGuides(guidesFor("creator"), "media kit").map((h) => h.section.id)).toContain(
      "media-kit",
    );
    expect(searchGuides(guidesFor("creator"), "x")).toEqual([]);
    for (const g of GUIDES) expect(guideText(g)).not.toMatch(/\*\*|\]\(\//);
  });
});
