import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { creatorSchema } = await import("./creators");

const base = { handle: "asha-rao", display_name: "Asha Rao", code: "asha" };

describe("creator payload", () => {
  it("accepts featured links to pages of this site", () => {
    const r = creatorSchema.safeParse({ ...base, featured: [{ title: "Online MBA", href: "/programmes/online-mba" }] });
    expect(r.success).toBe(true);
  });
  it("rejects featured links that browsers would open on another site", () => {
    for (const href of [
      "//evil.example/apply",
      "/\\evil.example",
      "/\t/evil.example",
      "https://evil.example",
      "javascript:alert(1)",
    ]) {
      expect(creatorSchema.safeParse({ ...base, featured: [{ title: "Apply", href }] }).success, href).toBe(false);
    }
  });
});
