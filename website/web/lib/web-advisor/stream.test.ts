import { describe, expect, it } from "vitest";
import { parseReply, PlaceholderFilter, ReplyDecoder } from "./stream";

describe("ReplyDecoder", () => {
  it("decodes the reply string across arbitrary chunk boundaries", () => {
    const json = JSON.stringify({ reply: 'Hi "Rohit"!\nCost: {{P1.fee}} ₹ ok' });
    for (const size of [1, 2, 3, 5, 7, 50]) {
      const d = new ReplyDecoder();
      let out = "";
      for (let i = 0; i < json.length; i += size) out += d.feed(json.slice(i, i + size));
      expect(out).toBe('Hi "Rohit"!\nCost: {{P1.fee}} ₹ ok');
      expect(d.finished).toBe(true);
    }
  });
  it("parses whole outputs with fences", () => {
    expect(parseReply('```json\n{"reply":"x"}\n```')).toBe("x");
    expect(parseReply("nope")).toBeNull();
  });
});

describe("PlaceholderFilter", () => {
  it("fills placeholders split across chunks and never leaks raw ones", () => {
    const f = new PlaceholderFilter((p) => (p === "{{P1.fee}}" ? "₹21,000 per year" : "?"));
    const parts = ["Fee: {", "{P1.", "fee}", "} total {", "x"];
    const out = parts.map((p) => f.feed(p)).join("") + f.flush();
    expect(out).toBe("Fee: ₹21,000 per year total {x");
    expect(out).not.toContain("{{");
  });
});
