import { describe, expect, it } from "vitest";
import { parseFinderParams } from "./params";
import { finderIndexability } from "./seo";

const curated = [
  { slug: "online-mba", filters: { programme: ["mba"] } },
  { slug: "online-mba-marketing", filters: { programme: ["mba"], spec: ["marketing"] } },
];
const f = (q: Record<string, string>) => finderIndexability(parseFinderParams(q), curated);

describe("finder indexability (spec 13.1: only curated views are indexable)", () => {
  it("indexes only the finder home", () => {
    expect(f({})).toEqual({ index: true, canonical: "/programmes" });
    expect(f({ programme: "mba" }).index).toBe(false);
    expect(f({ uni: "nmims" })).toEqual({ index: false, canonical: "/programmes" });
  });
  it("canonicalises filtered URLs to the matching curated view", () => {
    expect(f({ programme: "mba" }).canonical).toBe("/programmes/online-mba");
    expect(f({ programme: "mba", spec: "marketing" }).canonical).toBe("/programmes/online-mba-marketing");
    expect(f({ programme: "mba", spec: "marketing", sort: "fee_asc", page: "2" }).canonical).toBe("/programmes/online-mba-marketing");
    expect(f({ programme: "mba", fee_max: "200000", spec: "finance" }).canonical).toBe("/programmes/online-mba");
    expect(f({ programme: "mca", q: "cheap" }).canonical).toBe("/programmes");
  });
});
