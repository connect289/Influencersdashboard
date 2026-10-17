import { describe, expect, it } from "vitest";
import { isLocalPath, safeLocalPath } from "./paths";

describe("local paths", () => {
  it("accepts site paths", () => {
    for (const p of ["/", "/account", "/compare?ids=1,2", "/programmes/online-mba#faq"]) expect(isLocalPath(p), p).toBe(true);
  });
  it("rejects anything a browser could send off-site", () => {
    for (const p of ["//evil.com", "/\\evil.com", "/\tevil.com", "/\t/evil.com", "/ /evil.com", "https://evil.com", "evil.com", "", null, undefined, "/%0a/x\n"])
      expect(isLocalPath(p as string), JSON.stringify(p)).toBe(false);
  });
  it("falls back", () => expect(safeLocalPath("/\\evil.com", "/account")).toBe("/account"));
});
