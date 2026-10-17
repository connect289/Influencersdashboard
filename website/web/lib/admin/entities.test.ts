import { describe, expect, it } from "vitest";
import { ENTITIES, entityConfig, parseEntityForm } from "./entities";

const fd = (o: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(o)) f.set(k, v);
  return f;
};

describe("admin entity forms", () => {
  it("every entity has a key and fields", () => {
    for (const e of ENTITIES) {
      expect(e.key.length).toBeGreaterThan(0);
      expect(e.fields.length).toBeGreaterThan(0);
    }
  });
  it("parses types and reports errors", () => {
    const cfg = entityConfig("curated_views")!;
    const ok = parseEntityForm(cfg, fd({ slug: "online-mba-hr", title: "Online MBA in HR", filters: '{"programme":["mba"]}', status: "draft", sort: "5" }), true);
    expect(ok.errors).toEqual({});
    expect(ok.row).toMatchObject({ slug: "online-mba-hr", filters: { programme: ["mba"] }, sort: 5, status: "draft" });
    const bad = parseEntityForm(cfg, fd({ slug: "", title: "x", filters: "{oops", status: "live" }), true);
    expect(Object.keys(bad.errors).sort()).toEqual(["filters", "slug", "status"]);
  });
  it("booleans from checkboxes, tags from commas, redirect codes as numbers", () => {
    expect(parseEntityForm(entityConfig("testimonials")!, fd({ name: "A", quote: "Q", published: "on" }), true).row).toMatchObject({ published: true, consent_confirmed: false });
    expect(parseEntityForm(entityConfig("consent_texts")!, fd({ version: "v2", channel: "form", body: "x", purposes: "sales, partner_share" }), true).row.purposes).toEqual(["sales", "partner_share"]);
    expect(parseEntityForm(entityConfig("redirects")!, fd({ from_path: "/old", to_path: "/new", code: "301" }), true).row.code).toBe(301);
  });
  it("keys cannot change on edit", () => {
    const r = parseEntityForm(entityConfig("pages")!, fd({ path: "/about", title: "About Eduwit" }), false);
    expect(r.row.path).toBe("/about");
  });
  it("empty optional fields use database defaults on create and clear on edit", () => {
    const cfg = entityConfig("curated_views")!;
    const created = parseEntityForm(cfg, fd({ slug: "x", title: "X", filters: "{}", status: "draft", faqs: "", h1: "" }), true).row;
    expect("faqs" in created || "h1" in created).toBe(false);
    const edited = parseEntityForm(cfg, fd({ slug: "x", title: "X", filters: "{}", status: "draft", faqs: "", h1: "" }), false).row;
    expect(edited.h1).toBeNull();
    expect("faqs" in edited).toBe(false);
  });
});
