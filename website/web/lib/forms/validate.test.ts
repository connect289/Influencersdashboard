import { describe, expect, it } from "vitest";
import { canonicalEmail, cleanName, isMinor, normaliseEmail, normaliseIndianMobile, parseAge, validateAcademic, validateContact, validatePreferences } from "./validate";

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
    expect(validateContact({ name: "Asha Rao", phone: "9123456789", email: "a@b.in", age: "24", consent: false, guardian: false })).toEqual({ consent: expect.any(String) });
  });
  it("age is required and in range", () => {
    expect(parseAge("17")).toBe(17);
    expect(parseAge(" 24 ")).toBe(24);
    expect(parseAge("9")).toBeNull();
    expect(parseAge("100")).toBeNull();
    expect(parseAge("17.5")).toBeNull();
    expect(parseAge("")).toBeNull();
    const c = { name: "Asha Rao", phone: "9123456789", email: "a@b.in", consent: true, guardian: false };
    expect(validateContact({ ...c, age: "" }).age).toBeDefined();
    expect(validateContact({ ...c, age: "abc" }).age).toBeDefined();
    expect(validateContact({ ...c, age: "18" })).toEqual({});
  });
  it("under 18 needs the parent or guardian checkbox; 18 and over does not", () => {
    expect(isMinor(17)).toBe(true);
    expect(isMinor(18)).toBe(false);
    expect(isMinor(null)).toBe(false);
    const c = { name: "Asha Rao", phone: "9123456789", email: "a@b.in", consent: true };
    expect(validateContact({ ...c, age: "16", guardian: false })).toEqual({ guardian: expect.any(String) });
    expect(validateContact({ ...c, age: "16", guardian: true })).toEqual({});
    expect(validateContact({ ...c, age: "19", guardian: false })).toEqual({});
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
  it("canonical inbox for counting codes (D-095, same rule as web_email_canonical)", () => {
    expect(canonicalEmail(" J.Doe+news@GoogleMail.com ")).toBe("jdoe@gmail.com");
    expect(canonicalEmail("j.d.o.e@gmail.com")).toBe("jdoe@gmail.com");
    expect(canonicalEmail("a.b+x@yahoo.com")).toBe("a.b@yahoo.com");
    expect(canonicalEmail("asha@example.com")).toBe("asha@example.com");
    expect(canonicalEmail("+x@yahoo.com")).toBe("+x@yahoo.com");
    expect(canonicalEmail("..+x@gmail.com")).toBe("..+x@gmail.com");
    expect(canonicalEmail("no-at-sign")).toBe("no-at-sign");
    // the stored address keeps its tag
    expect(normaliseEmail("Asha+Fees@Example.com")).toBe("asha+fees@example.com");
  });
});
