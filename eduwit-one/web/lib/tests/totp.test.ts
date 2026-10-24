import { describe, expect, it } from "vitest";
import { base32Decode, totp } from "./totp.ts";

// RFC 6238 appendix B (SHA1): secret "12345678901234567890", 8 digits. The 6-digit codes are the same values' last six.
const SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

describe("totp", () => {
  it("decodes base32", () => {
    expect(base32Decode(SECRET).toString("ascii")).toBe("12345678901234567890");
    expect(base32Decode("gezd gnbv gy3t qojq gezd gnbv gy3t qojq").toString("ascii")).toBe("12345678901234567890");
    expect(() => base32Decode("not base32!")).toThrow(/base32/);
  });

  it.each([
    [59, "94287082"],
    [1111111109, "07081804"],
    [1111111111, "14050471"],
    [1234567890, "89005924"],
    [2000000000, "69279037"],
    [20000000000, "65353130"],
  ])("matches the RFC vector at %i s", (t, code) => {
    expect(totp(SECRET, t * 1000, 8)).toBe(code);
    expect(totp(SECRET, t * 1000)).toBe(code.slice(2));
  });
});
