import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/admin", () => ({ adminClient: () => ({}) }));
import { templateBody } from "./wa-templates";

describe("Meta template body", () => {
  it("adds example values and quick replies", () => {
    expect(templateBody({ id: 1, name: "nurture_x", language: "en", category: "marketing", body: "Hi {{1}}, {{2}}?", variables: ["first_name", "programme"],
      buttons: [{ type: "quick_reply", text: "Yes, call me" }] })).toEqual({
      name: "nurture_x", language: "en", category: "MARKETING",
      components: [{ type: "BODY", text: "Hi {{1}}, {{2}}?", example: { body_text: [["Asha", "Online MBA"]] } },
                   { type: "BUTTONS", buttons: [{ type: "QUICK_REPLY", text: "Yes, call me" }] }],
    });
  });
  it("puts a text or media header first", () => {
    const base = { id: 1, name: "t", language: "en", category: "utility", body: "Hi", variables: [], buttons: [] };
    expect(templateBody({ ...base, header: { type: "text", text: "Fees" } }).components).toEqual([{ type: "HEADER", format: "TEXT", text: "Fees" }, { type: "BODY", text: "Hi" }]);
    expect((templateBody({ ...base, header: { type: "image", example_url: "https://x.in/a.png" } }, "4::h") as { components: unknown[] }).components[0])
      .toEqual({ type: "HEADER", format: "IMAGE", example: { header_handle: ["4::h"] } });
  });
});
