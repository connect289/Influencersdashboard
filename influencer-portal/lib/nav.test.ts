import { describe, expect, it } from "vitest";
import { permissionsFor } from "@/lib/auth/permissions";
import { isActive, visibleStaffNav } from "./nav";

describe("staff navigation", () => {
  it("shows Super Admin everything", () => {
    expect(
      visibleStaffNav(permissionsFor({ roles: ["super_admin"], isSignatory: false })).map(
        (i) => i.href,
      ),
    ).toEqual([
      "/admin",
      "/admin/creators",
      "/admin/campaigns",
      "/admin/applications",
      "/admin/deals",
      "/admin/contracts",
      "/admin/briefs",
      "/admin/content",
      "/admin/tasks",
      "/admin/agencies",
      "/admin/kyc",
      "/admin/staff",
      "/admin/settings",
      "/admin/audit",
      "/admin/system",
      "/admin/help",
    ]);
  });
  it("hides what a Viewer can't use", () => {
    expect(
      visibleStaffNav(permissionsFor({ roles: ["viewer"], isSignatory: false })).map((i) => i.href),
    ).toEqual(["/admin", "/admin/tasks", "/admin/help"]);
  });
  it("shows Finance the settings it can edit", () => {
    expect(
      visibleStaffNav(permissionsFor({ roles: ["finance"], isSignatory: false })).map(
        (i) => i.href,
      ),
    ).toContain("/admin/settings");
  });
  it("shows KYC review to Finance but not to Content Reviewers", () => {
    expect(
      visibleStaffNav(permissionsFor({ roles: ["finance"], isSignatory: false })).map(
        (i) => i.href,
      ),
    ).toContain("/admin/kyc");
    expect(
      visibleStaffNav(permissionsFor({ roles: ["content_reviewer"], isSignatory: false })).map(
        (i) => i.href,
      ),
    ).not.toContain("/admin/kyc");
  });
  it("matches active items", () => {
    expect(isActive("/admin", "/admin")).toBe(true);
    expect(isActive("/admin/staff", "/admin")).toBe(false);
    expect(isActive("/admin/settings/x", "/admin/settings")).toBe(true);
    expect(isActive("/admin/settingsx", "/admin/settings")).toBe(false);
  });
});
