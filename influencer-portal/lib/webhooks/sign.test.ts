import { describe, expect, it } from "vitest";
import { assertSafePayload, MAX_ATTEMPTS, nextAttemptAt, outcome, sign, signatureHeader, verify } from "./sign";

describe("webhook signatures", () => {
  it("is a stable hex HMAC-SHA256 of the timestamp and body", () => {
    // Reference value from `printf '1700000000.{"a":1}' | openssl dgst -sha256 -hmac secret`.
    expect(sign("secret", 1700000000, '{"a":1}')).toBe(
      "49f24e537407743fa4a0242bb63b94b9a47ee99cbbe071ccd8a22550ae411686",
    );
    expect(sign("secret", 1700000000, '{"a":1}')).toMatch(/^[0-9a-f]{64}$/);
    expect(sign("secret", 1700000000, '{"a":1}')).not.toBe(sign("secret", 1700000001, '{"a":1}'));
  });

  it("verifies its own header and rejects tampering, other secrets and old timestamps", () => {
    const body = '{"id":"evt_1"}';
    const h = signatureHeader("s3cret", 1700000000, body);
    expect(verify("s3cret", h, body, 1700000100)).toBe(true);
    expect(verify("s3cret", h, '{"id":"evt_2"}', 1700000100)).toBe(false);
    expect(verify("other", h, body, 1700000100)).toBe(false);
    expect(verify("s3cret", h, body, 1700000000 + 301)).toBe(false);
    expect(verify("s3cret", "garbage", body, 1700000000)).toBe(false);
  });
});

describe("retries", () => {
  it("backs off 1, 5, 30, 120, 360 and 1440 minutes, then stops", () => {
    const t = new Date("2026-10-17T00:00:00Z");
    expect(nextAttemptAt(1, t)?.toISOString()).toBe("2026-10-17T00:01:00.000Z");
    expect(nextAttemptAt(6, t)?.toISOString()).toBe("2026-10-18T00:00:00.000Z");
    expect(nextAttemptAt(7, t)).toBeNull();
    expect(MAX_ATTEMPTS).toBe(7);
  });

  it("classifies responses", () => {
    expect([outcome(200), outcome(204), outcome(429), outcome(503), outcome(null), outcome(400), outcome(410)]).toEqual(
      ["delivered", "delivered", "retry", "retry", "retry", "failed", "failed"],
    );
  });
});

describe("payload safety", () => {
  it("refuses contact details and secrets anywhere in the payload", () => {
    expect(() => assertSafePayload({ lead_ref: "L-1", creator: { handle: "riya" } })).not.toThrow();
    expect(() => assertSafePayload({ lead: { student_phone: "9198" } })).toThrow(/student_phone/);
    expect(() => assertSafePayload({ items: [{ email: "a@b" }] })).toThrow(/items\[0\]\.email/);
  });
});
