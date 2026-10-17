import { describe, expect, it } from "vitest";
import { junkScore } from "./junk";

describe("junkScore", () => {
  it("scores a genuine attempt at zero", () => {
    expect(junkScore({ name: "Asha Rao", phone: "+919845012345", email: "asha.rao@gmail.com" })).toEqual({ score: 0, reasons: [] });
    expect(junkScore({ name: "राहुल शर्मा", phone: "+917011223344", email: "rahul.sharma92@yahoo.in" }).score).toBeLessThan(20);
  });

  it("flags repeated and sequential phone digits", () => {
    expect(junkScore({ name: "Asha Rao", phone: "+919999990000", email: "asha@gmail.com" }).reasons).toContain("phone_repeated_digits");
    expect(junkScore({ name: "Asha Rao", phone: "+919123456780", email: "asha@gmail.com" }).reasons).toContain("phone_sequential");
  });

  it("flags test names, keyboard mashing and test emails", () => {
    const r = junkScore({ name: "Test User", phone: "+919845012345", email: "asdf@example.com" });
    expect(r.reasons).toEqual(expect.arrayContaining(["name_test_word", "email_keyboard_pattern", "email_test_domain"]));
    expect(r.score).toBeGreaterThanOrEqual(50);
    expect(junkScore({ name: "Qwerty", phone: "+919845012345", email: "a@gmail.com" }).reasons).toContain("name_test_word");
  });

  it("flags vowel-less random email locals and caps at 100", () => {
    expect(junkScore({ name: "Asha Rao", phone: "+919845012345", email: "xkcdfghtrw@gmail.com" }).reasons).toContain("email_no_vowels");
    expect(junkScore({ name: "test aaa asdf", phone: "+919999999876", email: "test1234@example.com" }).score).toBe(100);
  });
});
