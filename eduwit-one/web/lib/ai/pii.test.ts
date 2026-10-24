import { describe, expect, it } from "vitest";
import { emailDomain, initials, lastFour, maskForAi, maskText, normaliseDigits } from "./pii.ts";

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

  it("reads other scripts' digits and unusual spaces as plain ones", () => {
    expect(normaliseDigits("९८७६५४३२१०")).toBe("9876543210");
    expect(normaliseDigits("９８７６５")).toBe("98765");
    expect(normaliseDigits("98765\u00a043210")).toBe("98765 43210");
    expect(normaliseDigits("৯৮৭")).toBe("987");
  });
});

describe("free text", () => {
  it("masks emails and phones inside a sentence", () => {
    expect(maskText("Call 98765 43210 or mail priya@example.org today")).toBe("Call …3210 or mail @example.org today");
    expect(maskText("lead +919876543210 (whatsapp)")).toBe("lead …3210 (whatsapp)");
  });

  it("finds a phone inside a longer run of digits and in every separator people use (review M2)", () => {
    for (const [input, out] of [
      ["lead 12 9876543210", "lead 12 …3210"],
      ["count 3 (9876543210)", "count 3 (…3210)"],
      ["9876543210 9123456780", "…3210 …6780"],
      ["at 10:00 9876543210", "at 10:00 …3210"],
      ["98765/43210", "…3210"],
      ["98765_43210", "…3210"],
      ["98765\u00a043210", "…3210"],
      ["９８７６５４３２１０", "…3210"],
      ["फ़ोन ९८७६५४३२१० है", "फ़ोन …3210 है"],
      ["0091 98765 43210", "…3210"],
      ["+44 (20) 7946-0958", "…0958"],
      ["id 123456789012", "id …9012"],
    ]) {
      expect(maskText(input as string), input).toBe(out);
    }
  });

  it("leaves dates, times, UUIDs and short numbers alone", () => {
    const s = "2026-10-24T02:31:00Z 2026-10-24 06:31 24/10/2026 10:30 0c3e4a1b-1f2d-4c5e-9a7b-112233445566 12345678";
    expect(maskText(s)).toBe(s);
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

  it("masks every string under a name key, nested or listed, and keys of a map of people (review M2)", () => {
    expect(
      maskForAi({
        name: { first: "Priya", last: "Sharma" },
        names: ["Rahul Verma", "Anil Rao"],
        by_counsellor: { "Meena Iyer": 4 },
      }),
    ).toEqual({ name: { first: "P.", last: "S." }, names: ["R.V.", "A.R."], by_counsellor: { "M.I.": 4 } });
  });

  it("keeps apart two keys that mask alike (review m3)", () => {
    expect(maskForAi({ "9876543210": 1, "+91 98765 43210": 2 })).toEqual({ "…3210": 1, "…3210#2": 2 });
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
