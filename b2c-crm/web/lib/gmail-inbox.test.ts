import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/admin", () => ({ adminClient: () => ({}) }));
import { bounceEmailId, plainText, replyOnly } from "./gmail-inbox";

describe("marketing inbox", () => {
  it("keeps only the new part of a reply", () => {
    expect(replyOnly("Yes please call me\n\nOn Tue, 14 Oct, Eduwit wrote:\n> Hi Asha")).toBe("Yes please call me");
    expect(replyOnly("Interested\n> quoted")).toBe("Interested");
  });
  it("finds the plain text in a multipart message", () => {
    const data = Buffer.from("hello there").toString("base64url");
    expect(plainText({ mimeType: "multipart/alternative", parts: [{ mimeType: "text/html", body: { data: "x" } }, { mimeType: "text/plain", body: { data } }] })).toBe("hello there");
  });
  it("finds our email id in a bounce", () => {
    expect(bounceEmailId("Original headers:\nX-B2C-Email-Id: 4521\nSubject: x")).toBe(4521);
    expect(bounceEmailId("nothing")).toBeNull();
  });
});
