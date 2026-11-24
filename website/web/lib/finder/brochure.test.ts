import { describe, expect, it } from "vitest";
import { brochureHref } from "./brochure";

describe("brochureHref", () => {
  it("passes an https brochure address through", () => {
    expect(brochureHref(" https://example.edu/mba.pdf ")).toBe("https://example.edu/mba.pdf");
    expect(brochureHref("https://drive.google.com/file/d/abc/view?usp=drive_link")).toContain("drive.google.com");
  });
  it("shows no button for a missing or unsafe address", () => {
    for (const v of [
      null,
      undefined,
      "",
      "  ",
      "mba.pdf",
      "http://example.edu/mba.pdf",
      "javascript:alert(1)",
      "https://user:pw@example.edu/x.pdf",
    ])
      expect(brochureHref(v)).toBeNull();
  });
});
