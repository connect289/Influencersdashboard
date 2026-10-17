import { describe, expect, it } from "vitest";
import { siblingViews, universityLinks, viewsForProgrammes } from "./related";

const views = [
  { slug: "online-mba", title: "Online MBA", filters: { programme: ["mba"] } },
  { slug: "online-bca", title: "Online BCA", filters: { programme: ["bca"] } },
  { slug: "online-mba-finance", title: "Online MBA in Finance", filters: { programme: ["mba"], spec: ["finance"] } },
];

describe("related links", () => {
  it("links a university to the views for programmes it offers", () => {
    expect(viewsForProgrammes(views, ["mba", "bcom"]).map((l) => l.href)).toEqual(["/programmes/online-mba", "/programmes/online-mba-finance"]);
    expect(viewsForProgrammes(views, ["phd"])).toEqual([]);
  });
  it("lists sibling views, same programme first, never itself", () => {
    expect(siblingViews(views, views[0]!).map((l) => l.href)).toEqual(["/programmes/online-mba-finance", "/programmes/online-bca"]);
  });
  it("lists universities in the result by option count, skipping empty ones", () => {
    const f = [
      { value: "amity-university", label: "Amity University", count: 3 },
      { value: "nmims", label: "NMIMS", count: 9 },
      { value: "vit", label: "VIT", count: 0 },
    ];
    expect(universityLinks(f)).toEqual([
      { href: "/universities/nmims", label: "NMIMS" },
      { href: "/universities/amity-university", label: "Amity University" },
    ]);
  });
});
