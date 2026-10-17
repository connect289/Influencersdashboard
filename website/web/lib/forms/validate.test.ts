import { describe, expect, it } from "vitest";
import { cleanName, normaliseEmail, normaliseIndianMobile, validateAcademic, validateContact, validatePreferences } from "./validate";

describe("form validation", () => {
  it("normalises Indian mobiles", () => {
    expect(normaliseIndianMobile("98765 43211")).toBe("+919876543211");
    expect(normaliseIndianMobile("+91-91234-56789")).toBe("+919123456789");
    expect(normaliseIndianMobile("09123456789")).toBe("+919123456789");
    expect(normaliseIndianMobile("5123456789")).toBeNull();
    expect(normaliseIndianMobile("9999999999")).toBeNull();
    expect(normaliseIndianMobile("12345")).toBeNull();
  });
  it("emails and names", () => {
    expect(normaliseEmail(" Asha@Example.COM ")).toBe("asha@example.com");
    expect(normaliseEmail("asha@example")).toBeNull();
    expect(cleanName("  Asha   Rao ")).toBe("Asha Rao");
    expect(cleanName("A")).toBeNull();
    expect(cleanName("<script>")).toBeNull();
    expect(cleanName("राहुल शर्मा")).toBe("राहुल शर्मा");
  });
  it("contact step requires consent", () => {
    expect(validateContact({ name: "Asha Rao", phone: "9123456789", email: "a@b.in", consent: false })).toEqual({ consent: expect.any(String) });
  });
  it("academic score range depends on the scale", () => {
    const base = { qualification: "graduation", stream: "", currentlyStudying: false, yearOfPassing: "", board: "" };
    expect(validateAcademic({ ...base, scoreType: "cgpa", score: "11" }).score).toBeDefined();
    expect(validateAcademic({ ...base, scoreType: "percent", score: "78" })).toEqual({});
  });
  it("university choice is required only when not pre-selected", () => {
    const p = { intake: "", budget: "", emi: "" as const, universities: [], city: "", state: "", contactMode: "call" as const, bestTime: "", questions: "" };
    expect(validatePreferences(p, true).universities).toBeDefined();
    expect(validatePreferences(p, false)).toEqual({});
  });
});
