import { describe, expect, it } from "vitest";
import { inQuietHours, sendAfterQuiet } from "./quiet";

// 21:00–09:00 IST is 15:30–03:30 UTC.
const at = (utc: string) => new Date(`2026-10-17T${utc}:00Z`);

describe("quiet hours", () => {
  it("windows that cross midnight", () => {
    expect(inQuietHours(at("15:29"), "21:00", "09:00")).toBe(false); // 20:59 IST
    expect(inQuietHours(at("15:30"), "21:00", "09:00")).toBe(true); // 21:00 IST
    expect(inQuietHours(at("20:00"), "21:00", "09:00")).toBe(true); // 01:30 IST
    expect(inQuietHours(at("03:29"), "21:00", "09:00")).toBe(true); // 08:59 IST
    expect(inQuietHours(at("03:30"), "21:00", "09:00")).toBe(false); // 09:00 IST
  });

  it("same-day windows and none", () => {
    expect(inQuietHours(at("08:30"), "13:00", "15:00")).toBe(true); // 14:00 IST
    expect(inQuietHours(at("10:30"), "13:00", "15:00")).toBe(false);
    expect(inQuietHours(at("08:30"), "09:00", "09:00")).toBe(false);
  });

  it("holds until the window ends", () => {
    expect(sendAfterQuiet(at("20:00"), "21:00", "09:00").toISOString()).toBe("2026-10-18T03:30:00.000Z");
    expect(sendAfterQuiet(at("16:00"), "21:00", "09:00").toISOString()).toBe("2026-10-18T03:30:00.000Z");
    const day = at("10:00");
    expect(sendAfterQuiet(day, "21:00", "09:00")).toBe(day);
  });
});
