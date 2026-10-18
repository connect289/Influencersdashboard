import { describe, expect, it } from "vitest";
import { addDays, addMonths, istDate, istMidnight, istMonth, nextMonth } from "./events";

describe("IST helpers", () => {
  it("maps instants to IST dates and months", () => {
    expect(istDate("2026-10-31T18:29:59Z")).toBe("2026-10-31");
    expect(istDate("2026-10-31T18:30:00Z")).toBe("2026-11-01");
    expect(istMonth("2026-12-31T19:00:00Z")).toBe("2027-01");
  });
  it("gives midnight IST as an instant", () => {
    expect(istMidnight("2026-11-01")).toBe("2026-10-31T18:30:00.000Z");
  });
  it("adds days and months (clamping month ends)", () => {
    expect(addDays("2026-12-30", 3)).toBe("2027-01-02");
    expect(addMonths("2026-01-31", 1)).toBe("2026-02-28");
    expect(addMonths("2028-01-31", 1)).toBe("2028-02-29");
    expect(nextMonth("2026-12")).toBe("2027-01");
  });
});
