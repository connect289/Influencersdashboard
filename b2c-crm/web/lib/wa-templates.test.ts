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
});
