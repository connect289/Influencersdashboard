import { describe, expect, it } from "vitest";
import {
  contactInput,
  GSTIN_RE,
  IFSC_RE,
  kycInput,
  normalisePhone,
  PAN_RE,
  platformInput,
  profileInput,
  rateCardInput,
  rupeesToPaise,
  safeFileName,
} from "./schemas";

const kyc = {
  pan: "abcps 1234k",
  nameOnPan: "Riya Sharma",
  gstStatus: "unregistered" as const,
  gstin: "",
  bankAccount: "0012 3456 7890",
  ifsc: "sbin0001234",
  accountHolder: "Riya Sharma",
};

describe("identifiers", () => {
  it.each([
    ["ABCPS1234K", true],
    ["ABCXS1234K", false], // 4th letter must be a holder type
    ["ABCP1234K", false],
    ["abcps1234k", false],
  ])("PAN %s → %s", (v, ok) => expect(PAN_RE.test(v)).toBe(ok));

  it.each([
    ["SBIN0001234", true],
    ["HDFC0ABC123", true],
    ["SBIN1001234", false],
    ["SBI00001234", false],
  ])("IFSC %s → %s", (v, ok) => expect(IFSC_RE.test(v)).toBe(ok));

  it.each([
    ["27ABCPS1234K1Z5", true],
    ["97ABCPS1234K1Z5", true],
    ["39ABCPS1234K1Z5", false],
    ["27ABCPS1234K1Y5", false],
    ["27ABCPS1234K0Z5", false],
  ])("GSTIN %s → %s", (v, ok) => expect(GSTIN_RE.test(v)).toBe(ok));
});

describe("normalisePhone", () => {
  it.each([
    ["98765 43210", "+919876543210"],
    ["098765-43210", "+919876543210"],
    ["919876543210", "+919876543210"],
    ["+91 98765 43210", "+919876543210"],
    ["+14155550123", "+14155550123"],
    ["12345", null],
    ["5876543210", null],
    ["", null],
  ])("%s → %s", (v, out) => expect(normalisePhone(v)).toBe(out));
});

describe("kycInput", () => {
  it("normalises PAN, IFSC and account number", () => {
    const r = kycInput.parse(kyc);
    expect(r.pan).toBe("ABCPS1234K");
    expect(r.ifsc).toBe("SBIN0001234");
    expect(r.bankAccount).toBe("001234567890");
  });

  it("allows blank PAN and account on edit (keeps stored values)", () => {
    expect(kycInput.safeParse({ ...kyc, pan: "", bankAccount: "" }).success).toBe(true);
  });

  it("needs a GSTIN when registered, and the GSTIN must embed the PAN", () => {
    expect(kycInput.safeParse({ ...kyc, gstStatus: "registered" }).success).toBe(false);
    expect(
      kycInput.safeParse({ ...kyc, gstStatus: "registered", gstin: "27ABCPX1234K1Z5" }).success,
    ).toBe(false);
    expect(
      kycInput.safeParse({ ...kyc, gstStatus: "registered", gstin: "27abcps1234k1z5" }).success,
    ).toBe(true);
  });

  it.each([
    [{ pan: "ABCDE1234" }, "pan"],
    [{ bankAccount: "1234" }, "bankAccount"],
    [{ ifsc: "SBIN1001234" }, "ifsc"],
  ])("rejects %o", (patch, path) => {
    const r = kycInput.safeParse({ ...kyc, ...patch });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.path[0]).toBe(path);
  });
});

describe("profile, platform, rate card, contact", () => {
  it("profile accepts blanks and validates phone", () => {
    expect(profileInput.safeParse({ displayName: "Riya" }).success).toBe(true);
    expect(profileInput.safeParse({ displayName: "Riya", phone: "123" }).success).toBe(false);
    expect(profileInput.safeParse({ displayName: "R" }).success).toBe(false);
  });

  it("platform needs https and strips @ from handles; NaN counts become null", () => {
    const r = platformInput.parse({
      platform: "instagram",
      url: "https://instagram.com/riya",
      handle: "@riya",
      followers: Number.NaN,
      avgViews: 1200,
      engagementRate: 4.56789,
    });
    expect(r.handle).toBe("riya");
    expect(r.followers).toBeNull();
    expect(r.engagementRate).toBe(4.568);
    expect(platformInput.safeParse({ ...r, url: "http://instagram.com/riya" }).success).toBe(false);
  });

  it("rate card converts rupees to integer paise", () => {
    const r = rateCardInput.parse({
      platform: "youtube",
      format: "youtube_video",
      rupees: 15000.5,
    });
    expect(rupeesToPaise(r.rupees)).toBe(1500050);
    expect(rupeesToPaise(0.1 + 0.2)).toBe(30);
  });

  it("contact needs a phone or an email", () => {
    expect(contactInput.safeParse({ kind: "family" }).success).toBe(false);
    expect(contactInput.safeParse({ kind: "family", phone: "9876543210" }).success).toBe(true);
    expect(contactInput.safeParse({ kind: "team", email: "a@b.in" }).success).toBe(true);
    expect(contactInput.safeParse({ kind: "team", phone: "12" }).success).toBe(false);
  });
});

describe("safeFileName", () => {
  it.each([
    ["PAN card (front).jpg", "PAN-card-front-.jpg"],
    ["../../etc/passwd", "etc-passwd"],
    ["résumé.pdf", "re-sume-.pdf"],
    [".hidden", "hidden"],
    ["", "file"],
  ])("%s → %s", (input, out) => {
    const r = safeFileName(input);
    expect(r).toMatch(/^[A-Za-z0-9._-]{1,120}$/);
    expect(r).toBe(out);
  });
});
