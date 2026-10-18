import { describe, expect, it } from "vitest";
import { BOARD_COLUMNS, boardColumn } from "./board";
import { DELIVERABLE_STATUSES } from "./workflow";

describe("board columns", () => {
  it("places every status except cancelled", () => {
    for (const s of DELIVERABLE_STATUSES) {
      const c = boardColumn(s);
      if (s === "cancelled") expect(c).toBeNull();
      else expect(BOARD_COLUMNS).toContain(c);
    }
  });
  it("submitted work and live posts awaiting verification are in review", () => {
    expect(boardColumn("concept_submitted")).toBe("in_review");
    expect(boardColumn("draft_submitted")).toBe("in_review");
    expect(boardColumn("live", true)).toBe("in_review");
    expect(boardColumn("live")).toBe("live");
  });
});
