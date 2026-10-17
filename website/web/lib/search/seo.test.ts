import { describe, expect, it } from "vitest";
import { parseFinderParams } from "./params";
import { finderIndexability } from "./seo";

const f = (q: Record<string, string>) => finderIndexability(parseFinderParams(q));

describe("finder indexability", () => {
  it("indexes the finder home and single programme views", () => {
    expect(f({}).index).toBe(true);
    expect(f({ programme: "mba" })).toEqual({ index: true, canonicalQuery: "programme=mba" });
    expect(f({ programme: "mba", spec: "marketing" }).index).toBe(true);
    expect(f({ uni: "nmims" }).index).toBe(true);
  });
  it("does not index filter combinations; canonicalises to the programme", () => {
    expect(f({ programme: "mba", fee_max: "200000" })).toEqual({ index: false, canonicalQuery: "programme=mba" });
    expect(f({ programme: "mba,mca" }).index).toBe(false);
    expect(f({ q: "mba" }).index).toBe(false);
    expect(f({ programme: "mba", page: "2" }).index).toBe(false);
  });
});
