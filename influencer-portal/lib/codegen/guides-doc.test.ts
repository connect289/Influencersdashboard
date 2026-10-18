import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { GUIDES } from "@/lib/guides";
import { GUIDE_DOCS, guideMarkdown, type GuideDoc } from "./guides-doc";

describe("docs/ADMIN_GUIDE.md and docs/CREATOR_GUIDE.md", () => {
  it.each(Object.keys(GUIDE_DOCS) as GuideDoc[])(
    "%s matches the in-app guides (run npm run gen:sql if this fails)",
    (doc) => {
      const file = join(import.meta.dirname, "..", "..", "docs", doc);
      expect(readFileSync(file, "utf8")).toBe(guideMarkdown(doc));
    },
  );

  it("covers every staff, creator and agency guide (the developer guide stays in the app)", () => {
    const covered = new Set<string>(Object.values(GUIDE_DOCS).flatMap((d) => d.audiences));
    expect(GUIDES.filter((g) => !covered.has(g.audience)).map((g) => g.audience)).toEqual(["developer"]);
  });

  it("keeps app paths and drops in-guide anchors", () => {
    const md = guideMarkdown("CREATOR_GUIDE.md");
    expect(md).toContain("(`/creator/account/privacy`)");
    expect(md).not.toMatch(/\]\(#/);
  });
});
