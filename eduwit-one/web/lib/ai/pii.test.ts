import { describe, expect, it } from "vitest";
import { emailDomain, initials, lastFour, maskForAi, maskText, phoneDigits } from "./pii.ts";

// The mask is the promise that a model never sees a contact (spec §11). Each rule has a case, and the cases that
// must pass through untouched (dates, counts, ids, the database's own placeholders) have one too.

describe("pieces", () => {
  it("turns a name into initials", () => {
    expect(initials("Priya Sharma")).toBe("P.S.");
    expect(initials("  rahul  k. verma ")).toBe("R.K.V.");
    expect(initials("ज्योति")).toBe("ज.");
    expect(initials("")).toBe("?");
    expect(initials(42)).toBe("?");
  });

  it("keeps the last four digits of a phone", () => {
    expect(lastFour("+91 98765 43210")).toBe("…3210");
    expect(lastFour(9876543210)).toBe("…3210");
    expect(lastFour("12")).toBe("…");
  });

  it("keeps the domain of an email", () => {
    expect(emailDomain("Priya.S@Gmail.com")).toBe("@gmail.com");
    expect(emailDomain("not an email")).toBe("@?");
  });

  it("knows a phone from a date, a time or a short id", () => {
    expect(phoneDigits("9876543210")).toBe("9876543210");
    expect(phoneDigits("+91-98765-43210")).toBe("919876543210");
    expect(phoneDigits("098765 43210")).toBe("09876543210");
    expect(phoneDigits("+44 20 7946 0958")).toBe("442079460958");
    expect(phoneDigits("2026-10-24")).toBeNull();
    expect(phoneDigits("2026-10-24 02")).toBeNull();
    expect(phoneDigits("1729741234")).toBeNull();
    expect(phoneDigits("123456")).toBeNull();
  });
});

describe("free text", () => {
  it("masks emails and phones inside a sentence", () => {
    expect(maskText("Call 98765 43210 or mail priya@example.org today")).toBe("Call …3210 or mail @example.org today");
    expect(maskText("lead +919876543210 (whatsapp)")).toBe("lead …3210 (whatsapp)");
  });

  it("leaves timestamps, counts and the database's placeholders alone", () => {
    const s = "opened 2026-10-24T02:31:00Z, 17 runs, 4,512 rows, [phone] and [email] from one.redact";
    expect(maskText(s)).toBe(s);
  });
});

describe("maskForAi", () => {
  it("masks contact fields by key, at any depth", () => {
    const out = maskForAi({
      lead: {
        student_name: "Priya Sharma",
        guardian_name: "Anil Sharma",
        phone: "+91 98765 43210",
        guardian_phone: 919812345678,
        email: "priya@gmail.com",
        contact_email: "anil@yahoo.co.in",
      },
      leads: [{ name: "Rahul Verma", mobile: "9123456780" }],
    });
    expect(out).toEqual({
      lead: {
        student_name: "P.S.",
        guardian_name: "A.S.",
        phone: "…3210",
        guardian_phone: "…5678",
        email: "@gmail.com",
        contact_email: "@yahoo.co.in",
      },
      leads: [{ name: "R.V.", mobile: "…6780" }],
    });
  });

  it("masks contacts hiding in other fields: strings, numbers and map keys", () => {
    const out = maskForAi({
      error: "duplicate key for 9876543210 (priya@gmail.com)",
      wa: 919876543210,
      by_phone: { "9876543210": 3 },
    });
    expect(out).toEqual({
      error: "duplicate key for …3210 (@gmail.com)",
      wa: "…3210",
      by_phone: { "…3210": 3 },
    });
  });

  it("leaves message bodies out", () => {
    const out = maskForAi({
      messages: [
        { direction: "in", text: "Hi I am Priya, my number is 9876543210", at: "2026-10-24T02:31:00Z" },
        { direction: "out", body: "Hello Priya!", message: "Hello Priya!", content: "x", snippet: "y" },
      ],
      subject: "Admission for Priya",
    });
    expect(out).toEqual({
      messages: [{ direction: "in", at: "2026-10-24T02:31:00Z" }, { direction: "out" }],
    });
  });

  it("keeps short masked excerpts when the task may quote them", () => {
    const long = `My number is 9876543210 and mail priya@gmail.com. ${"word ".repeat(100)}`;
    const out = maskForAi({ messages: [{ text: long }] }, { excerpts: true }) as {
      messages: Array<{ text: string }>;
    };
    const text = out.messages[0]?.text ?? "";
    expect(text.startsWith("My number is …3210 and mail @gmail.com.")).toBe(true);
    expect(text.length).toBeLessThanOrEqual(281);
    expect(text).not.toContain("9876543210");
    expect(text).not.toContain("priya@");
  });

  it("drops secrets and identity documents, whatever the task", () => {
    const out = maskForAi(
      {
        api_key: "sk-123",
        authorization: "Bearer x",
        password: "p",
        pan: "ABCDE1234F",
        aadhaar: "1234 5678 9012",
        bank_account: "123",
        ifsc: "HDFC0001",
        address: "12 MG Road",
        dob: "2001-01-01",
        ip: "1.2.3.4",
        kept: true,
      },
      { excerpts: true },
    );
    expect(out).toEqual({ kept: true });
  });

  it("passes through what is not contact data", () => {
    const input = {
      check_id: "WITTY-02",
      severity: "P1",
      occurrences: 17,
      opened_at: "2026-10-24T02:31:00Z",
      subjects: ["b2c-outbox", "jobname:b2c-minute"],
      value: { stuck: 4, oldest_at: "2026-10-24T01:00:00Z", ids: [101, 102] },
      ok: false,
      ratio: 0.25,
      none: null,
      phone_verified: true,
      email_status: "sent",
    };
    expect(maskForAi(input)).toEqual(input);
  });

  it("bounds what it returns: long strings, long arrays and deep nesting", () => {
    const out = maskForAi({ s: "a".repeat(5000), a: Array.from({ length: 250 }, (_, i) => i) }) as {
      s: string;
      a: unknown[];
    };
    expect(out.s.length).toBe(2001);
    expect(out.a).toHaveLength(201);
    expect(out.a[200]).toBe("[50 more left out]");
    let deep: Record<string, unknown> = { leaf: 1 };
    for (let i = 0; i < 20; i++) deep = { d: deep };
    expect(JSON.stringify(maskForAi(deep))).toContain("[deeper data left out]");
  });

  it("does not change its input", () => {
    const input = { phone: "9876543210", nested: { email: "a@b.co" } };
    const copy = structuredClone(input);
    maskForAi(input);
    expect(input).toEqual(copy);
  });
});
