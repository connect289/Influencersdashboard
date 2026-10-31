import { describe, expect, it } from "vitest";
import { shownArgs } from "./shown.ts";

describe("shownArgs (D-115)", () => {
  it("reads the arguments a card sends back", () => {
    expect(shownArgs('{"id": 3, "note": "x"}')).toEqual({ id: 3, note: "x" });
    expect(shownArgs("{}")).toEqual({});
  });

  it("refuses anything that is not one card's object", () => {
    for (const bad of [undefined, null, 3, "", "[1]", "null", '"x"', "{bad json", "x".repeat(20_001)]) {
      expect(shownArgs(bad)).toBeNull();
    }
  });
});
