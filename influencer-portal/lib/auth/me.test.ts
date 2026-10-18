import { describe, expect, it } from "vitest";
import { homeFor, meSchema, toAgencyMe, toCreatorMe, toStaffMe } from "./me";

const uid = "6b0f7b5e-6a3c-4b1e-9b9d-6f2f1d1a2b3c";
const cid = "0e4a1f2b-3c4d-4e5f-8a9b-0c1d2e3f4a5b";

describe("me", () => {
  it("parses a staff member and derives permissions", () => {
    const me = meSchema.parse({
      signed_in: true,
      user_id: uid,
      email: "a@eduwit.in",
      kind: "staff",
      session: { registered: true, verified: true, revoked: false, verified_via: "email_code" },
      staff: {
        full_name: "A",
        status: "active",
        is_signatory: true,
        roles: ["finance", "unknown_role"],
      },
      creator: null,
    });
    const staff = toStaffMe(me);
    expect(staff?.roles).toEqual(["finance"]);
    expect(staff?.permissions.has("payout.approve")).toBe(true);
    expect(staff?.permissions.has("contract.countersign")).toBe(true);
    expect(homeFor(me)).toBe("/admin");
  });

  it("refuses suspended staff", () => {
    const me = meSchema.parse({
      signed_in: true,
      user_id: uid,
      kind: "staff",
      staff: { full_name: "A", status: "suspended", is_signatory: false, roles: ["super_admin"] },
    });
    expect(toStaffMe(me)).toBeNull();
  });

  it("parses a creator and refuses blocked or archived ones", () => {
    const base = {
      signed_in: true,
      user_id: uid,
      kind: "creator" as const,
      creator: {
        id: cid,
        display_name: "R",
        handle: "r",
        status: "active",
        is_blocked: false,
        is_test: false,
      },
    };
    expect(toCreatorMe(meSchema.parse(base))?.creatorId).toBe(cid);
    expect(toCreatorMe(meSchema.parse({ ...base, creator: { ...base.creator, status: "archived" } }))).toBeNull();
    expect(toCreatorMe(meSchema.parse({ ...base, creator: { ...base.creator, is_blocked: true } }))).toBeNull();
    expect(homeFor(meSchema.parse(base))).toBe("/creator");
  });

  it("parses an agency member and refuses suspended agencies or removed members", () => {
    const base = {
      signed_in: true,
      user_id: uid,
      email: "ola@acme.test",
      kind: "agency",
      agency: {
        id: cid,
        name: "Acme",
        status: "active",
        member_name: "Ola",
        role: "owner",
        member_status: "active",
      },
    };
    const me = meSchema.parse(base);
    expect(toAgencyMe(me)).toMatchObject({ agencyId: cid, agencyName: "Acme", isOwner: true });
    expect(toCreatorMe(me)).toBeNull();
    expect(toStaffMe(me)).toBeNull();
    expect(homeFor(me)).toBe("/agency");
    expect(toAgencyMe(meSchema.parse({ ...base, agency: { ...base.agency, status: "suspended" } }))).toBeNull();
    expect(toAgencyMe(meSchema.parse({ ...base, agency: { ...base.agency, member_status: "removed" } }))).toBeNull();
  });

  it("sends anyone else to no-access", () => {
    expect(homeFor(meSchema.parse({ signed_in: true, user_id: uid, kind: "none" }))).toBe("/no-access");
  });
});
