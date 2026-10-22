import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { smtpPassword } = await import("./index");

describe("smtpPassword", () => {
  it("removes the display spaces from a Google app password", () => {
    expect(smtpPassword("abcd efgh ijkl mnop")).toBe("abcdefghijklmnop");
  });
  it("leaves any other password as typed", () => {
    expect(smtpPassword("my pass word")).toBe("my pass word");
    expect(smtpPassword("abcdefghijklmnop")).toBe("abcdefghijklmnop");
    expect(smtpPassword(undefined)).toBe("");
  });
});
