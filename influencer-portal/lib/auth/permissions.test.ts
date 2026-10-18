import { describe, expect, it } from "vitest";
import { ALL_PERMISSIONS, can, isPermission, permissionsFor, ROLE_GRANTS, STAFF_ROLES } from "./permissions";

describe("permission matrix", () => {
  it("grants only known permissions", () => {
    for (const role of STAFF_ROLES) for (const p of ROLE_GRANTS[role]) expect(isPermission(p)).toBe(true);
  });

  it("gives Super Admin everything except countersigning, which needs the signatory flag", () => {
    const admin = permissionsFor({ roles: ["super_admin"], isSignatory: false });
    expect(admin.size).toBe(ALL_PERMISSIONS.length - 1);
    expect(admin.has("contract.countersign")).toBe(false);
    expect(can({ roles: ["super_admin"], isSignatory: true }, "contract.countersign")).toBe(true);
  });

  it("lets the signatory flag combine with any role", () => {
    expect(can({ roles: ["viewer"], isSignatory: true }, "contract.countersign")).toBe(true);
  });

  it("keeps student contacts to Super Admin only by default", () => {
    for (const role of STAFF_ROLES) {
      expect(can({ roles: [role], isSignatory: true }, "lead.contacts")).toBe(role === "super_admin");
    }
  });

  it("keeps Content Reviewers away from money", () => {
    const reviewer = permissionsFor({ roles: ["content_reviewer"], isSignatory: false });
    for (const p of reviewer)
      expect(p.startsWith("ledger") || p.startsWith("payout") || p.startsWith("tax") || p.startsWith("deal")).toBe(
        false,
      );
  });

  it("restricts unmasked KYC to Finance and Super Admin", () => {
    const allowed = STAFF_ROLES.filter((r) => can({ roles: [r], isSignatory: false }, "kyc.reveal"));
    expect(allowed.sort()).toEqual(["finance", "super_admin"]);
  });

  it("gives Viewers dashboards only", () => {
    expect([...permissionsFor({ roles: ["viewer"], isSignatory: false })].sort()).toEqual([
      "analytics.read",
      "scorecard.read",
    ]);
  });

  it("denies a missing access object", () => {
    expect(can(null, "creator.read")).toBe(false);
  });
});
