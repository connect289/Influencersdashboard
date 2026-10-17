import { describe, expect, it } from "vitest";
import { auditFilterSchema, auditQueryString, istDayEnd, istDayStart } from "./audit";

describe("audit filters", () => {
  it("drops invalid values instead of failing", () => {
    expect(
      auditFilterSchema.parse({
        entity: "creator; drop",
        actor: "x",
        before: "-1",
        from: "2026-10-01",
      }),
    ).toEqual({
      from: "2026-10-01",
    });
  });
  it("converts IST days to UTC ranges", () => {
    expect(istDayStart("2026-10-17")).toBe("2026-10-16T18:30:00.000Z");
    expect(istDayEnd("2026-10-17")).toBe("2026-10-17T18:30:00.000Z");
  });
  it("builds query strings", () => {
    expect(auditQueryString({ entity: "setting" }, { before: 10 })).toBe("?entity=setting&before=10");
    expect(auditQueryString({})).toBe("");
  });
});
