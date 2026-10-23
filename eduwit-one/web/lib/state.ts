import { z } from "zod";

// The shape of one.app_tick_state() (migration 0008). Validated at the boundary (spec standard 4): a settings row a
// person edited into a bad shape fails here with a typed error instead of breaking a probe half-way.

const url = z.url();
const iso = z.string().nullable();

export const hostsSchema = z.object({
  website: url,
  website_internal: url.optional(),
  spark: url,
  b2b_app: url,
  influencer: url,
  chatwoot: url,
  n8n: url,
  one: url,
});

export const settingsSchema = z.object({
  hosts: hostsSchema,
  health_paths: z.record(z.string(), z.string().startsWith("/")),
  vendors: z.looseObject({ vercel_api: url, graph_api: url, resend_api: url }),
  alerts: z.looseObject({ email_from: z.string().min(3) }),
  vercel: z.object({ team: z.string(), projects: z.record(z.string(), z.string()) }),
  chatwoot: z.object({ account_id: z.string() }),
  n8n: z.object({
    witty_workflow_id: z.string(),
    nurture_workflow_id: z.string().optional(),
    learning_workflow_id: z.string().optional(),
  }),
  whatsapp: z.object({
    waba_ids: z.array(z.string()),
    alert_phone_id: z.string().nullable(),
    phone_ids: z.record(z.string(), z.string()).optional(),
  }),
  witty: z.object({
    expect_nurture: z.boolean(),
    expect_learning: z.boolean(),
    gemini_daily_cap: z.number().optional(),
  }),
  thresholds: z.record(z.string(), z.number()),
  // Sign-in settings (0009); absent before that migration.
  access: z
    .object({
      allowed_domain: z.string().default("eduwit.in"),
      trusted_days: z.number().int().min(0).max(90).default(30),
      idle_hours: z.number().int().min(1).max(72).default(12),
      code_minutes: z.number().int().min(2).max(30).default(10),
    })
    .optional(),
});

export const tickStateSchema = z.object({
  now: z.string(),
  settings: settingsSchema,
  setup: z.record(z.string(), z.object({ status: z.string().nullable(), validated: z.boolean() })),
  checks: z.array(
    z.object({
      id: z.string(),
      enabled: z.boolean(),
      disabled_reason: z.string().nullable(),
      cadence_s: z.number(),
      last_ran_at: iso,
    }),
  ),
  heartbeats: z.array(
    z.object({
      component: z.string(),
      last_ok_at: iso,
      last_error_at: iso,
      expected_interval_s: z.number(),
    }),
  ),
});

export type Settings = z.infer<typeof settingsSchema>;
export type TickState = z.infer<typeof tickStateSchema>;

/** A heartbeat to write: the component's reading this tick. */
export type HeartbeatReport = {
  component: string;
  ok: boolean;
  detail: Record<string, unknown>;
  error?: string;
  expected_interval_s: number;
};

/** An app-run check result. "skipped" means the probe could not form a verdict (for example a vendor timeout). */
export type ResultReport = {
  check_id: string;
  status: "ok" | "fail" | "error" | "skipped";
  value: Record<string, unknown>;
  error?: string;
  duration_ms?: number;
};

export type Report = { heartbeats: HeartbeatReport[]; results: ResultReport[] };
