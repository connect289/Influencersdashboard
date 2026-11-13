import { describe, expect, it } from "vitest";
import { privilegeListHash } from "./privileges.ts";

describe("privilegeListHash (D-137)", () => {
  it("is the hash the database computes for the same list (supabase/tests/local/99_privileges.sql)", () => {
    expect(privilegeListHash(["audit_probe_s.b(text)", "audit_probe_s.a()"])).toBe("72d071b226ab708adf5634bc36e65ec9");
  });

  it("does not depend on the order shown, and changes when one function is swapped for another", () => {
    const shown = ["ce_admin.b()", "ce_admin.a(text)", "ce_admin.C()"];
    expect(privilegeListHash(shown)).toBe(privilegeListHash([...shown].reverse()));
    expect(privilegeListHash(["ce_admin.b()", "ce_admin.x(text)", "ce_admin.C()"])).not.toBe(privilegeListHash(shown));
  });

  it("sorts bytewise, as collation C does: capitals before lower case", () => {
    expect(privilegeListHash(["s.b()", "s.A()"])).toBe(privilegeListHash(["s.A()", "s.b()"]));
    expect(privilegeListHash(["s.b()", "s.A()"])).toBe(
      // md5('s.A(),s.b()')
      privilegeListHash(["s.A(),s.b()"]),
    );
  });
});
