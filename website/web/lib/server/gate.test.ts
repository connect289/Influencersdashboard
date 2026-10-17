import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: vi.fn(), headers: vi.fn() }));

const { codeHash, maskEmail, newCode, newReference } = await import("./gate");
const { readSessionId, signSessionId } = await import("./student-session");
const { capiPayload } = await import("./capi");

describe("verification codes", () => {
  it("are 6 digits and bound to the attempt", () => {
    for (let i = 0; i < 50; i++) expect(newCode()).toMatch(/^\d{6}$/);
    expect(codeHash("application:a", "123456")).not.toBe(codeHash("application:b", "123456"));
    expect(codeHash("application:a", "123456")).toBe(codeHash("application:a", "123456"));
  });
  it("masks emails", () => {
    expect(maskEmail("asha.rao@gmail.com")).toBe("a••••••@gmail.com");
    expect(maskEmail("ab@x.in")).toBe("a•@x.in");
  });
  it("references look like EDW-YY-XXXXX without ambiguous characters", () => {
    for (let i = 0; i < 50; i++) expect(newReference(new Date("2026-10-17"))).toMatch(/^EDW-26-[2-9A-HJKMNP-TV-Z]{5}$/);
  });
});

describe("student session cookie", () => {
  const sid = "6f1c2b9e-4d3a-4b8e-9f0a-1c2d3e4f5a6b";
  it("round-trips and rejects tampering", () => {
    const v = signSessionId(sid);
    expect(readSessionId(v)).toBe(sid);
    expect(readSessionId(v.slice(0, -2) + "xx")).toBeNull();
    expect(readSessionId(`7f1c2b9e-4d3a-4b8e-9f0a-1c2d3e4f5a6b.${v.split(".")[1]}`)).toBeNull();
    expect(readSessionId("not-a-uuid.sig")).toBeNull();
    expect(readSessionId(undefined)).toBeNull();
  });
});

describe("Conversions API payload", () => {
  it("hashes personal data and keeps the event id", () => {
    const p = capiPayload({ name: "Lead", eventId: "e1", email: " Asha@Example.com ", phone: "+91 98450 12345", at: new Date(1_800_000_000_000) }, "TEST1");
    const d = p.data[0]!;
    expect(d.event_id).toBe("e1");
    expect(d.event_time).toBe(1_800_000_000);
    expect(d.user_data.em?.[0]).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(p)).not.toContain("asha");
    expect(JSON.stringify(p)).not.toContain("98450");
    expect(p.test_event_code).toBe("TEST1");
  });
});
