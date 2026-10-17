import { describe, expect, it } from "vitest";
import { agencyInput, memberInput } from "./schemas";

describe("agency schemas", () => {
  it("normalises GSTIN and accepts blanks", () => {
    expect(agencyInput.parse({ name: "Acme Talent", gstin: "27abcps1234k1z5" }).gstin).toBe(
      "27ABCPS1234K1Z5",
    );
    expect(agencyInput.safeParse({ name: "Acme" }).success).toBe(true);
  });
  it("rejects bad GSTIN, phone or a one-letter name", () => {
    expect(agencyInput.safeParse({ name: "Acme", gstin: "27ABCPS1234K1Y5" }).success).toBe(false);
    expect(agencyInput.safeParse({ name: "Acme", phone: "123" }).success).toBe(false);
    expect(agencyInput.safeParse({ name: "A" }).success).toBe(false);
  });
  it("lower-cases member emails", () => {
    const m = memberInput.parse({
      agencyId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      email: "Ola@Acme.Test",
      fullName: "Ola",
      role: "owner",
    });
    expect(m.email).toBe("ola@acme.test");
  });
});
