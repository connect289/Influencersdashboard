import { describe, expect, it } from "vitest";
import { leadIdFrom, parseLeadsQuery } from "./b2c-api";

const q = (s: string) => parseLeadsQuery(new URLSearchParams(s));

describe("b2c api queries", () => {
  it("reads the feed cursor", () => {
    expect(q("")).toEqual({ ok: true, kind: "feed", q: { after: 0, limit: 100 } });
    expect(q("after=42&limit=500")).toEqual({ ok: true, kind: "feed", q: { after: 42, limit: 500 } });
    expect(q("after=-1").ok).toBe(false);
    expect(q("limit=501").ok).toBe(false);
  });
  it("reads a lookup", () => {
    expect(q("phone=+91 98765 04701")).toEqual({ ok: true, kind: "lookup", q: { phone: "919876504701", email: null } });
    expect(q("email= A@B.co ")).toEqual({ ok: true, kind: "lookup", q: { phone: null, email: "a@b.co" } });
    expect(q("phone=123").ok).toBe(false);
    expect(q("email=nope").ok).toBe(false);
  });
  it("reads lead ids", () => {
    expect(leadIdFrom("949")).toBe(949);
    expect(leadIdFrom("9x")).toBeNull();
  });
});
