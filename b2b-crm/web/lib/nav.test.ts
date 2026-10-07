import { describe, expect, it } from "vitest";
import { isActive, NAV_ITEMS, SECTION_BY_SLUG } from "./nav";

describe("navigation", () => {
  it("has unique paths and unique g-shortcuts", () => {
    const hrefs = NAV_ITEMS.map((i) => i.href);
    expect(new Set(hrefs).size).toBe(hrefs.length);
    const keys = NAV_ITEMS.flatMap((i) => (i.key ? [i.key] : []));
    expect(new Set(keys).size).toBe(keys.length);
  });
  it("gives every unbuilt top-level section a placeholder", () => {
    expect(Object.keys(SECTION_BY_SLUG)).toEqual(expect.arrayContaining(["money", "dashboards"]));
    expect(SECTION_BY_SLUG["settings"]).toBeUndefined();
    expect(SECTION_BY_SLUG["leads"]).toBeUndefined(); // built: app/(app)/leads
    expect(SECTION_BY_SLUG["partners"]).toBeUndefined(); // built: app/(app)/partners
    expect(SECTION_BY_SLUG["programmes"]).toBeUndefined(); // built: app/(app)/programmes
    expect(SECTION_BY_SLUG["routing"]).toBeUndefined(); // built: app/(app)/routing
    expect(SECTION_BY_SLUG["notifications"]).toBeUndefined(); // built: app/(app)/notifications
    expect(SECTION_BY_SLUG["pool"]).toBeUndefined(); // built: app/(app)/pool
    expect(SECTION_BY_SLUG["system"]).toBeUndefined(); // built: app/(app)/system
    expect(SECTION_BY_SLUG["mapping"]).toBeUndefined(); // built: app/(app)/mapping
    expect(SECTION_BY_SLUG["intake"]).toBeUndefined(); // built: app/(app)/intake
    expect(SECTION_BY_SLUG["capi"]).toBeUndefined(); // built: app/(app)/capi
  });
  it("marks the right item active", () => {
    expect(isActive("/", "/")).toBe(true);
    expect(isActive("/leads", "/")).toBe(false);
    expect(isActive("/leads/42", "/leads")).toBe(true);
    expect(isActive("/settings/sessions", "/settings/security")).toBe(true);
    expect(isActive("/leadsx", "/leads")).toBe(false);
  });
});
