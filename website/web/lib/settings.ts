import { z } from "zod";

/** Site settings and feature flags (mirror of web_settings defaults in web1_foundation). */
export const settingsSchema = z.object({
  web_advisor_enabled: z.boolean().default(false),
  require_phone_otp: z.boolean().default(false),
  push_unverified_gate_leads: z.boolean().default(false),
  push_unverified_after_minutes: z.number().int().default(60),
  document_upload_enabled: z.boolean().default(false),
  design_concept: z.enum(["a", "b"]).default("a"),
  default_theme: z.enum(["system", "dark", "light"]).default("system"),
  finder_include_regular_mode: z.boolean().default(false),
  lead_writer: z.enum(["lead_intake", "intake_api"]).default("lead_intake"),
  transcript_target: z.string().default("web_advisor_messages"),
  counsellor_whatsapp: z.string().default("+919643977407"),
  counsellor_phone: z.string().default("+919650683269"),
  announcement: z
    .object({ text: z.string(), href: z.string().optional(), tone: z.enum(["info", "amber"]).default("info") })
    .nullable()
    .default(null),
  web_advisor_models: z
    .object({ extractor: z.string(), counselor: z.string() })
    .default({ extractor: "claude-haiku-5-5", counselor: "claude-sonnet-5-5" }),
  web_advisor_budget: z
    .object({ max_tokens_per_session: z.number(), turn_timeout_ms: z.number(), max_turns_per_session: z.number() })
    .default({ max_tokens_per_session: 60000, turn_timeout_ms: 20000, max_turns_per_session: 40 }),
  /** Site-wide ceilings (web14; enforced in the database, super-admin only). */
  code_send_hourly_cap: z.number().int().min(0).default(200),
  web_advisor_daily_cap: z.object({ turns: z.number().min(0), cost_usd: z.number().min(0) }).default({ turns: 2000, cost_usd: 25 }),
  sections: z.record(z.string(), z.boolean()).default({}),
  /** Opening hours for LocalBusiness structured data, e.g. ["Mo-Sa 10:00-19:00"] (S-51); none shown until set. */
  business_hours: z.array(z.string().regex(/^(Mo|Tu|We|Th|Fr|Sa|Su)(-(Mo|Tu|We|Th|Fr|Sa|Su))? \d{2}:\d{2}-\d{2}:\d{2}$/)).nullable().default(null),
  /** Application form: non-core fields to hide or make optional (spec 9.1A; contact and consent are locked). */
  application_form: z
    .object({ hidden: z.array(z.string()).default([]), optional: z.array(z.string()).default([]) })
    .default({ hidden: [], optional: [] }),
});

export type Settings = z.infer<typeof settingsSchema>;

export const DEFAULT_SETTINGS: Settings = settingsSchema.parse({});

/** Unknown keys are ignored; invalid values fall back to defaults key by key, so one bad setting never breaks the site. */
export function parseSettings(raw: Record<string, unknown>): Settings {
  const out: Record<string, unknown> = {};
  const shape = settingsSchema.shape;
  for (const key of Object.keys(shape) as (keyof typeof shape)[]) {
    const r = shape[key].safeParse(raw[key]);
    out[key] = r.success ? r.data : DEFAULT_SETTINGS[key];
  }
  return out as Settings;
}
