import { describe, expect, it } from "vitest";
import { portalNext } from "./link";

describe("portalNext", () => {
  it("sends agency members to their portal unless next is already there", () => {
    expect(portalNext("agency", "/creator")).toBe("/agency");
    expect(portalNext("agency", "/agency/team")).toBe("/agency/team");
  });
  it("keeps creators out of the agency portal", () => {
    expect(portalNext("creator", "/creator/kyc")).toBe("/creator/kyc");
    expect(portalNext("creator", "/agency")).toBe("/creator");
  });
});
