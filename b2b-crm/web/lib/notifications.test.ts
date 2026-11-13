import { describe, expect, it } from "vitest";
import { SettingsSchema, TemplateSchema, channelBlockers, mayHaveBeenSent, renderTemplate, settingsPayload, siteUrlDefault, unknownVariables, type NotificationsOverview } from "./notifications";

const settings = {
  quiet_start: "08:00", quiet_end: "21:00", support_contact: "support@eduwit.in", unsubscribe_url: "", site_url: "", wa_phone_number_id: "123456789012",
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
  it("takes the CRM web address (M34j) as an https address without a query, and sends it without a trailing slash", () => {
    expect(settingsPayload(SettingsSchema.parse({ ...settings, site_url: " https://b2b.eduwit.in/ " })).site_url).toBe("https://b2b.eduwit.in");
    expect(settingsPayload(SettingsSchema.parse({ ...settings, site_url: "https://crm.example.in:8443/b2b" })).site_url).toBe("https://crm.example.in:8443/b2b");
    expect(settingsPayload(SettingsSchema.parse(settings)).site_url).toBe(""); // empty clears it: emails fall back to the old footer
    for (const bad of ["http://b2b.eduwit.in", "b2b.eduwit.in", "https://b2b.eduwit.in/?next=x", "https://b2b.eduwit.in/#a", "https://user:pw@b2b.eduwit.in", "javascript:alert(1)"]) {
      const r = SettingsSchema.safeParse({ ...settings, site_url: bad });
      expect(r.success ? [] : r.error.issues.map((i) => i.path[0])).toEqual(["site_url"]);
    }
  });
  it("offers the saved address, else this deployment's own when it is https", () => {
    expect(siteUrlDefault("https://b2b.eduwit.in", "https://other.example")).toBe("https://b2b.eduwit.in");
    expect(siteUrlDefault(null, "https://b2b.eduwit.in/")).toBe("https://b2b.eduwit.in");
    expect(siteUrlDefault(undefined, "http://localhost:3000")).toBe("");
    expect(siteUrlDefault(null, null)).toBe("");
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

describe("mayHaveBeenSent (M34i)", () => {
  it("flags the error notify_tick writes when an unclear answer is not sent again", () => {
    expect(mayHaveBeenSent("may have been sent (no answer from the provider), so it is not sent again automatically: check with the student before Send again")).toBe(true);
    expect(mayHaveBeenSent("may have been sent (HTTP 502: Bad Gateway), so it is not sent again automatically: check with the student before Send again")).toBe(true);
  });
  it("leaves clear failures and empty errors alone", () => {
    for (const e of ["HTTP 400: invalid recipient", "email provider is not configured", "", null, undefined]) expect(mayHaveBeenSent(e)).toBe(false);
  });
});
