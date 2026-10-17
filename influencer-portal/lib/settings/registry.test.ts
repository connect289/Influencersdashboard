import { describe, expect, it } from "vitest";
import { CREATOR_VISIBLE_LEAD_FIELDS, SETTINGS, SETTING_KEYS, settingJsonSchema } from "./registry";

describe("settings registry", () => {
  it.each(SETTING_KEYS)("%s: default matches its schema and converts to JSON Schema", (key) => {
    const d = SETTINGS[key];
    expect(d.schema.safeParse(d.default).success).toBe(true);
    const js = settingJsonSchema(key);
    expect(js.type).toBe("object");
    expect(js.additionalProperties).toBe(false);
    expect(JSON.stringify(js)).not.toContain("$ref");
  });

  it("never allows phone or email in the creator-visible lead fields", () => {
    const fields: readonly string[] = CREATOR_VISIBLE_LEAD_FIELDS;
    for (const f of [
      "whatsapp_number",
      "email_id",
      "alternate_phone",
      "guardian_phone",
      "ip_address",
      "fingerprint",
    ]) {
      expect(fields).not.toContain(f);
    }
    const schema = SETTINGS["lead_visibility.creator"].schema;
    expect(
      schema.safeParse({
        fields: ["whatsapp_number"],
        name_format: "full",
        public_mail_domains: [],
      }).success,
    ).toBe(false);
  });

  it("defaults to first name and initial for student names", () => {
    expect(SETTINGS["lead_visibility.creator"].default.name_format).toBe("first_initial");
  });

  it("keeps financial records at least 8 years", () => {
    const schema = SETTINGS["retention.privacy"].schema;
    expect(
      schema.safeParse({ ...SETTINGS["retention.privacy"].default, financial_records_years: 7 })
        .success,
    ).toBe(false);
  });

  it("uses the approved attribution defaults", () => {
    expect(SETTINGS["attribution.rules"].default).toMatchObject({
      window_days: 90,
      model: "first_touch_with_assisted",
      reenquiry_credit_after_days: null,
    });
    expect(SETTINGS["compensation.defaults"].default.confirm_partial_receipts).toBe(false);
  });
});
