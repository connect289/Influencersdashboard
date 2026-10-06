import { describe, expect, it } from "vitest";
import { SettingsSchema, TemplateSchema, channelBlockers, renderTemplate, settingsPayload, unknownVariables, type NotificationsOverview } from "./notifications";

const settings = {
  quiet_start: "08:00", quiet_end: "21:00", support_contact: "support@eduwit.in", unsubscribe_url: "", wa_phone_number_id: "123456789012",
  wa_api_version: "v21.0", wa_token: "", email_provider: "resend", email_from: "Hello@Eduwit.in", email_from_name: "Team Eduwit", email_reply_to: "",
  email_api_key: "", reason: "first setup",
};

describe("notification settings", () => {
  it("accepts a valid form and keeps stored secrets when left empty", () => {
    const p = SettingsSchema.parse(settings);
    const out = settingsPayload(p);
    expect(out.email.from_email).toBe("hello@eduwit.in");
    expect(out.whatsapp.token).toBe("");
    expect(out.email.api_key).toBe("");
  });
  it("refuses quiet hours that end before they start, bad ids and http links", () => {
    const r = SettingsSchema.safeParse({ ...settings, quiet_start: "21:00", quiet_end: "08:00", wa_phone_number_id: "abc", unsubscribe_url: "http://x.in" });
    expect(r.success).toBe(false);
    const paths = r.success ? [] : r.error.issues.map((i) => i.path[0]);
    expect(paths).toEqual(expect.arrayContaining(["quiet_end", "wa_phone_number_id", "unsubscribe_url"]));
  });
  it("needs a reason and a support contact", () => {
    const r = SettingsSchema.safeParse({ ...settings, reason: "", support_contact: "x" });
    expect(r.success ? [] : r.error.issues.map((i) => i.path[0])).toEqual(expect.arrayContaining(["reason", "support_contact"]));
  });
});

describe("templates", () => {
  const base = { channel: "email", subject: "Your counsellor", body: "Hi {{student_first_name}}, {{partner_display_name}} will call you.", wa_template: "", wa_language: "", status: "active" };
  it("flags unknown variables", () => {
    expect(unknownVariables("Hi {{student_first_name}} {{fee}} {{ fee }}")).toEqual(["fee"]);
    expect(TemplateSchema.safeParse({ ...base, body: "Hi {{student_first_name}}, pay {{fee}} today please." }).success).toBe(false);
  });
  it("needs an email subject and a WhatsApp template name before activating", () => {
    expect(TemplateSchema.safeParse({ ...base, subject: "" }).success).toBe(false);
    expect(TemplateSchema.safeParse({ ...base, channel: "whatsapp", subject: "" }).success).toBe(false);
    expect(TemplateSchema.safeParse({ ...base, channel: "whatsapp", subject: "", status: "draft" }).success).toBe(true);
    expect(TemplateSchema.safeParse({ ...base, channel: "whatsapp", subject: "", wa_template: "eduwit_partner_assigned" }).success).toBe(true);
  });
  it("renders known variables and leaves the rest", () => {
    expect(renderTemplate("Hi {{student_first_name}}, {{x}}", { student_first_name: "Ravi" })).toBe("Hi Ravi, {{x}}");
  });
});

describe("channel readiness", () => {
  const o = {
    settings: { quiet_start: "08:00", quiet_end: "21:00", support_contact: null, unsubscribe_url: null,
      whatsapp: { phone_number_id: null, has_token: false }, email: { from_email: "hello@eduwit.in", has_key: true } },
    version: 1, switches: { whatsapp: false, email: false },
    templates: [{ id: 3, kind: "accepted", channel: "email", language: "en", subject: "s", body: "b", wa_template: null, wa_language: null, status: "active", version: 1, updated_at: "" }],
    partners: [], counts: {}, log: [],
  } as unknown as NotificationsOverview;
  it("lists what blocks each channel", () => {
    expect(channelBlockers(o, "email")).toEqual(["Add Eduwit's support contact in Providers."]);
    expect(channelBlockers(o, "whatsapp")).toHaveLength(4);
  });
});
