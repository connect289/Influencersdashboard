// Settings registry (spec 2.9 and 21): every business-configurable value, typed and validated.
// - Each key has a zod schema, a default, a group, and the permission needed to change it.
// - `scripts/generate-sql.ts` writes the JSON Schema of each key into `inf.setting_definitions`, so the database
//   validates every write with `inf.json_schema_errors()` even when someone calls the RPC directly.
// - Tabular configuration lives in its own tables instead (TDS sections, stage mappings, notification templates,
//   deal presets, clause library, banned claims, tiers): those need per-row history and their own screens.
import { z } from "zod";
import type { Permission } from "@/lib/auth/permissions";

const hhmm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use 24-hour HH:MM");
const pct = z.number().min(0).max(100);
const days = (max: number) => z.number().int().min(0).max(max);
const msisdn = z.string().regex(/^[1-9]\d{9,14}$/, "Digits only, with country code, e.g. 919643977407");

/** Fields a creator may ever see (LEAD_FIELD_WHITELIST.md SHOW/BAND rows). Phone and email are always masked. */
export const CREATOR_VISIBLE_LEAD_FIELDS = [
  "display_name",
  "city",
  "state",
  "country",
  "preferred_language",
  "enquirer_relation",
  "interested_course",
  "interested_specialization",
  "field_of_interest",
  "interested_university",
  "university_preference",
  "program_level",
  "programme_segment",
  "study_mode_preference",
  "highest_qualification",
  "current_study",
  "enrollment_timeline",
  "eligibility_status",
  "admission_readiness",
  "lead_status",
  "experience_band",
  "first_touch_at",
  "applied_at",
  "enrolled_program",
  "enrolled_university",
  "enrollment_date",
] as const;

export const SETTING_GROUPS = {
  organisation: "Organisation",
  attribution: "Attribution",
  lead_visibility: "Lead visibility",
  compensation: "Compensation",
  contracts: "Contracts",
  content: "Content",
  finance: "Finance",
  creators: "Creators",
  scorecard: "Tiers and scorecard",
  notifications: "Notifications",
  security: "Security",
  retention: "Retention and privacy",
} as const;
export type SettingGroup = keyof typeof SETTING_GROUPS;

interface SettingDef<S extends z.ZodType> {
  group: SettingGroup;
  label: string;
  description: string;
  schema: S;
  default: z.output<S>;
  edit: Permission;
  /** Shown with a "confirm with CA / counsel" banner until a person confirms it. */
  needsConfirmation?: string;
}

function def<S extends z.ZodType>(d: SettingDef<S>): SettingDef<S> {
  return d;
}

export const SETTINGS = {
  "organisation.profile": def({
    group: "organisation",
    label: "Legal entity",
    description: "Name, address and tax identifiers printed on contracts, statements and payout advice.",
    schema: z.strictObject({
      legal_name: z.string().min(2).max(200),
      trade_name: z.string().max(120),
      address: z.string().max(500),
      state_code: z.string().regex(/^(\d{2})?$/, "Two-digit GST state code"),
      gstin: z.string().regex(/^(\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z])?$/, "15-character GSTIN"),
      pan: z.string().regex(/^([A-Z]{5}\d{4}[A-Z])?$/, "10-character PAN"),
      support_email: z.string().max(200),
    }),
    default: {
      legal_name: "Eduwit Learning Services",
      trade_name: "Eduwit",
      address: "Ghaziabad, Uttar Pradesh",
      state_code: "09",
      gstin: "",
      pan: "",
      support_email: "creators@eduwit.in",
    },
    edit: "settings.write",
  }),
  "attribution.rules": def({
    group: "attribution",
    label: "Attribution rules",
    description: "Window, model, duplicate and self-referral rules (spec 9.2).",
    schema: z.strictObject({
      window_days: z.number().int().min(1).max(365),
      model: z.enum(["first_touch", "last_touch", "first_touch_with_assisted"]),
      duplicate_grace_minutes: z.number().int().min(0).max(1440),
      reenquiry_credit_after_days: z.number().int().min(1).max(3650).nullable(),
      self_referral_match_phone: z.boolean(),
      self_referral_match_email: z.boolean(),
      self_referral_match_family: z.boolean(),
    }),
    default: {
      window_days: 90,
      model: "first_touch_with_assisted",
      duplicate_grace_minutes: 10,
      reenquiry_credit_after_days: null,
      self_referral_match_phone: true,
      self_referral_match_email: true,
      self_referral_match_family: true,
    },
    edit: "settings.write",
  }),
  "attribution.fraud": def({
    group: "attribution",
    label: "Fraud signals",
    description: "Thresholds that send leads to admin review. Signals never reject a lead automatically.",
    schema: z.strictObject({
      velocity_leads_per_hour: z.number().int().min(1).max(10000),
      same_device_max_leads: z.number().int().min(1).max(1000),
      no_witty_reply_hours: z.number().int().min(1).max(720),
      off_hours_start: hhmm,
      off_hours_end: hhmm,
      off_hours_burst: z.number().int().min(1).max(1000),
      junk_rate_pct: pct,
      min_sample: z.number().int().min(1).max(10000),
    }),
    default: {
      velocity_leads_per_hour: 30,
      same_device_max_leads: 3,
      no_witty_reply_hours: 48,
      off_hours_start: "00:30",
      off_hours_end: "06:00",
      off_hours_burst: 5,
      junk_rate_pct: 40,
      min_sample: 10,
    },
    edit: "settings.write",
  }),
  "attribution.links": def({
    group: "attribution",
    label: "Links and Witty",
    description: "Witty's WhatsApp number for deep links, the pre-filled message and UTM defaults.",
    schema: z.strictObject({
      witty_whatsapp_number: msisdn,
      deep_link_template: z.string().min(10).max(500),
      issue_witty_access_codes: z.boolean(),
      utm_source: z.string().min(1).max(60),
      short_link_base: z.string().max(200),
    }),
    default: {
      witty_whatsapp_number: "919643977407",
      deep_link_template: "Hi Eduwit! I saw {creator_name}'s post about {programme}. My access code is {access_code} (ref {code})",
      issue_witty_access_codes: true,
      utm_source: "influencer",
      short_link_base: "https://creators.eduwit.in/r/",
    },
    edit: "settings.write",
  }),
  "lead_visibility.creator": def({
    group: "lead_visibility",
    label: "What creators see",
    description:
      "Fields shown to creators on their leads. Phone and email are always masked and cannot be unmasked here.",
    schema: z.strictObject({
      fields: z.array(z.enum(CREATOR_VISIBLE_LEAD_FIELDS)).max(CREATOR_VISIBLE_LEAD_FIELDS.length),
      name_format: z.enum(["first_initial", "first_name", "full", "hidden"]),
      public_mail_domains: z.array(z.string().regex(/^[a-z0-9.-]+\.[a-z]{2,}$/)).max(50),
    }),
    default: {
      fields: [...CREATOR_VISIBLE_LEAD_FIELDS],
      name_format: "first_initial",
      public_mail_domains: [
        "gmail.com",
        "yahoo.com",
        "yahoo.co.in",
        "outlook.com",
        "hotmail.com",
        "live.com",
        "icloud.com",
        "rediffmail.com",
        "proton.me",
      ],
    },
    edit: "settings.write",
  }),
  "compensation.defaults": def({
    group: "compensation",
    label: "Compensation defaults",
    description: "Rounding, hold and refund windows, penalty caps and the default commission base.",
    schema: z.strictObject({
      rounding: z.literal("bankers"),
      hold_days: days(365),
      refund_window_days: days(365),
      penalty_cap_pct: pct,
      commission_base_default: z.enum(["gross_incl_gst", "net_of_gst"]),
      confirm_partial_receipts: z.boolean(),
      eduwit_commission_overdue_days: days(365),
    }),
    default: {
      rounding: "bankers",
      hold_days: 30,
      refund_window_days: 30,
      penalty_cap_pct: 20,
      commission_base_default: "net_of_gst",
      confirm_partial_receipts: false,
      eduwit_commission_overdue_days: 60,
    },
    edit: "settings.write",
  }),
  "contracts.signing": def({
    group: "contracts",
    label: "Signing and reminders",
    description: "OTP channels and limits, negotiation reminders, expiry reminders and the legal-review gate.",
    schema: z.strictObject({
      otp_channels: z.array(z.enum(["email", "whatsapp"])).min(1).max(2),
      otp_expiry_minutes: z.number().int().min(2).max(30),
      otp_max_attempts: z.number().int().min(1).max(10),
      otp_resend_cooldown_seconds: z.number().int().min(15).max(600),
      negotiation_deadline_days: z.number().int().min(1).max(60),
      negotiation_reminder_days: z.array(z.number().int().min(1).max(60)).max(5),
      expiry_reminder_days: z.array(z.number().int().min(1).max(120)).max(5),
      legal_review_gate: z.boolean(),
    }),
    default: {
      otp_channels: ["email"],
      otp_expiry_minutes: 10,
      otp_max_attempts: 5,
      otp_resend_cooldown_seconds: 60,
      negotiation_deadline_days: 7,
      negotiation_reminder_days: [2, 5],
      expiry_reminder_days: [30, 15, 7],
      legal_review_gate: true,
    },
    edit: "settings.write",
    needsConfirmation:
      "Stamp duty and enforceability depend on the state and contract type. Confirm with counsel before relying on OTP click-sign.",
  }),
  "content.review": def({
    group: "content",
    label: "Content review",
    description: "Revision limits, disclosure rules per platform and metric checkpoints.",
    schema: z.strictObject({
      default_revision_limit: z.number().int().min(0).max(20),
      metric_checkpoints_hours: z.array(z.number().int().min(1).max(24 * 90)).min(1).max(6),
      disclosure_terms: z.array(z.string().min(2).max(60)).min(1).max(20),
      disclosure_required_platforms: z.array(
        z.enum(["instagram", "youtube", "facebook", "linkedin", "x", "telegram", "moj_josh", "other"]),
      ),
    }),
    default: {
      default_revision_limit: 2,
      metric_checkpoints_hours: [24, 168, 720],
      disclosure_terms: ["#ad", "#collab", "#sponsored", "paid partnership"],
      disclosure_required_platforms: ["instagram", "youtube", "facebook", "linkedin", "x", "telegram", "moj_josh", "other"],
    },
    edit: "settings.write",
  }),
  "content.uploads": def({
    group: "content",
    label: "Upload limits",
    description: "Maximum sizes per file kind. Allowed types are fixed by the app.",
    schema: z.strictObject({
      max_video_mb: z.number().int().min(10).max(10240),
      max_image_mb: z.number().int().min(1).max(100),
      max_document_mb: z.number().int().min(1).max(100),
    }),
    default: { max_video_mb: 2048, max_image_mb: 20, max_document_mb: 25 },
    edit: "settings.write",
  }),
  "finance.payouts": def({
    group: "finance",
    label: "Payouts",
    description: "Payout cycle, approvals, KYC rule and the bank bulk-upload format.",
    schema: z.strictObject({
      cycle: z.enum(["weekly", "fortnightly", "monthly"]),
      payout_day_of_month: z.number().int().min(1).max(28),
      two_person_approval: z.boolean(),
      kyc_required_for_payout: z.boolean(),
      hold_until_tax_confirmed: z.boolean(),
      bank_export: z.strictObject({
        delimiter: z.enum([",", ";", "|", "\t"]),
        header: z.boolean(),
        columns: z
          .array(
            z.enum([
              "beneficiary_name",
              "account_number",
              "ifsc",
              "amount_inr",
              "narration",
              "payout_ref",
              "email",
              "creator_code",
            ]),
          )
          .min(3)
          .max(12),
      }),
    }),
    default: {
      cycle: "monthly",
      payout_day_of_month: 10,
      two_person_approval: true,
      kyc_required_for_payout: true,
      hold_until_tax_confirmed: false,
      bank_export: {
        delimiter: ",",
        header: true,
        columns: ["beneficiary_name", "account_number", "ifsc", "amount_inr", "narration", "payout_ref"],
      },
    },
    edit: "tax.manage",
  }),
  "finance.gst": def({
    group: "finance",
    label: "GST",
    description: "GST on creator payouts when the creator's GSTIN is verified.",
    schema: z.strictObject({
      rate_pct: pct,
      require_invoice_for_registered: z.boolean(),
      sac_code: z.string().regex(/^(\d{6})?$/, "Six-digit SAC"),
    }),
    default: { rate_pct: 18, require_invoice_for_registered: true, sac_code: "998361" },
    edit: "tax.manage",
    needsConfirmation: "GST rate and SAC code: confirm with your CA.",
  }),
  "creators.lifecycle": def({
    group: "creators",
    label: "Creator lifecycle",
    description: "Dormancy flag and self sign-up approval.",
    schema: z.strictObject({
      dormant_after_days: z.number().int().min(7).max(365),
      auto_approve_signups: z.boolean(),
      auto_approve_min_followers: z.number().int().min(0).max(100_000_000),
    }),
    default: { dormant_after_days: 45, auto_approve_signups: false, auto_approve_min_followers: 10000 },
    edit: "settings.write",
  }),
  "scorecard.weights": def({
    group: "scorecard",
    label: "Score weights",
    description: "Weights of the composite creator score (they need not sum to 1; they are normalised).",
    schema: z.strictObject({
      delivery: z.number().min(0).max(1),
      content: z.number().min(0).max(1),
      lead_quality: z.number().min(0).max(1),
      economics: z.number().min(0).max(1),
      compliance: z.number().min(0).max(1),
    }),
    default: { delivery: 0.25, content: 0.2, lead_quality: 0.25, economics: 0.2, compliance: 0.1 },
    edit: "tier.manage",
  }),
  "notifications.delivery": def({
    group: "notifications",
    label: "Delivery",
    description: "Quiet hours (IST) for WhatsApp and digests. Mandatory events still arrive in-app and by email.",
    schema: z.strictObject({
      quiet_hours_start: hhmm,
      quiet_hours_end: hhmm,
      creator_digest: z.enum(["off", "daily", "weekly"]),
      staff_digest: z.enum(["off", "daily", "weekly"]),
      digest_hour_ist: z.number().int().min(0).max(23),
    }),
    default: {
      quiet_hours_start: "21:00",
      quiet_hours_end: "09:00",
      creator_digest: "weekly",
      staff_digest: "daily",
      digest_hour_ist: 9,
    },
    edit: "settings.write",
  }),
  "security.sessions": def({
    group: "security",
    label: "Sessions",
    description: "Idle sign-out and trusted devices for staff.",
    schema: z.strictObject({
      idle_timeout_hours: z.number().int().min(1).max(72),
      trusted_device_days: z.number().int().min(0).max(90),
    }),
    default: { idle_timeout_hours: 12, trusted_device_days: 30 },
    edit: "settings.write",
  }),
  "retention.privacy": def({
    group: "retention",
    label: "Retention",
    description: "How long records are kept. Financial and contract records: at least 8 years.",
    schema: z.strictObject({
      financial_records_years: z.number().int().min(8).max(20),
      audit_log_years: z.number().int().min(1).max(20),
      click_anonymise_days: z.number().int().min(1).max(730),
      sign_in_log_days: z.number().int().min(30).max(3650),
    }),
    default: { financial_records_years: 8, audit_log_years: 8, click_anonymise_days: 90, sign_in_log_days: 365 },
    edit: "settings.write",
  }),
} as const;

export type SettingKey = keyof typeof SETTINGS;
export type SettingValue<K extends SettingKey> = z.output<(typeof SETTINGS)[K]["schema"]>;
export const SETTING_KEYS = Object.keys(SETTINGS) as SettingKey[];

export function isSettingKey(value: string): value is SettingKey {
  return Object.hasOwn(SETTINGS, value);
}

/** JSON Schema for the database validator. Throws if a schema uses something JSON Schema can't express. */
export function settingJsonSchema(key: SettingKey): Record<string, unknown> {
  const schema = z.toJSONSchema(SETTINGS[key].schema, {
    target: "draft-2020-12",
    io: "output",
    unrepresentable: "throw",
    reused: "inline",
  }) as Record<string, unknown>;
  delete schema.$schema;
  return schema;
}
