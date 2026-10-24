import { z } from "zod";

// The shape of one.app_tick_state() (migration 0008). Validated at the boundary (spec standard 4): a settings row a
// person edited into a bad shape fails where it is read, with an error that names the key, instead of breaking a probe
// half-way or the whole tick (F6).

const url = z.url();
const iso = z.string().nullable();

// Each key of one.settings has its own schema, and each reader parses only the keys it reads (F6): a person's bad edit
// to witty.expect_nurture stops the n8n probe's WITTY-08 with an error that names the key, never the whole tick.
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
export const healthPathsSchema = z.record(z.string(), z.string().startsWith("/"));
export const vendorsSchema = z.looseObject({ vercel_api: url, graph_api: url, resend_api: url });
export const alertsSchema = z.looseObject({ email_from: z.string().min(3) });
export const vercelSchema = z.object({ team: z.string(), projects: z.record(z.string(), z.string()) });
export const chatwootSchema = z.object({ account_id: z.string() });
export const n8nSchema = z.object({
  witty_workflow_id: z.string(),
  nurture_workflow_id: z.string().optional(),
  learning_workflow_id: z.string().optional(),
  // Only the synthetic tests read these; a bad value leaves T-WITTY-QUALIFY unconfigured, never the tick (D-072).
  test_harness_workflow_id: z.string().optional().catch(undefined),
  test_harness_webhook_path: z.string().startsWith("/").optional().catch(undefined),
  test_harness_scenario: z.string().optional().catch(undefined),
});
export const whatsappSchema = z.object({
  waba_ids: z.array(z.string()),
  alert_phone_id: z.string().nullable(),
  phone_ids: z.record(z.string(), z.string()).optional(),
});
export const wittySchema = z.object({
  expect_nurture: z.boolean(),
  expect_learning: z.boolean(),
  gemini_daily_cap: z.number().optional(),
});
export const thresholdsSchema = z.record(z.string(), z.number());
// Sign-in settings (0009); absent before that migration.
export const accessSchema = z
  .object({
    trusted_days: z.number().int().min(0).max(90).default(30),
    idle_hours: z.number().int().min(1).max(72).default(12),
    code_minutes: z.number().int().min(2).max(30).default(10),
  })
  .optional();

/** Everything: the synthetic tests and the Setup validators read across the keys. */
export const settingsSchema = z.object({
  hosts: hostsSchema,
  health_paths: healthPathsSchema,
  vendors: vendorsSchema,
  alerts: alertsSchema,
  vercel: vercelSchema,
  chatwoot: chatwootSchema,
  n8n: n8nSchema,
  whatsapp: whatsappSchema,
  witty: wittySchema,
  thresholds: thresholdsSchema,
  access: accessSchema,
});

/** What lib/clients needs to build the vendor clients. */
export const clientSettingsSchema = z.object({
  hosts: hostsSchema.pick({ chatwoot: true, n8n: true }),
  vendors: vendorsSchema,
});
export type ClientSettings = z.infer<typeof clientSettingsSchema>;

/** What the alert sender needs: the sender address and the host its links point to. */
export const alertSettingsSchema = z.object({ alerts: alertsSchema, hosts: hostsSchema.pick({ one: true }) });

/** What the sign-in code email needs. */
export const signInSettingsSchema = z.object({
  access: accessSchema,
  alerts: alertsSchema,
  hosts: hostsSchema.pick({ one: true }),
  vendors: vendorsSchema.pick({ resend_api: true }),
});

/** The first problems zod found, each as "key: message", so an error names the setting to fix. */
export function settingsIssue(error: z.ZodError): string {
  const issues = error.issues
    .slice(0, 3)
    .map((i) => `${i.path.map(String).join(".") || "settings"}: ${i.message}`)
    .join("; ");
  return `settings ${issues}`;
}

/** Parses the part of one.settings a reader needs; a failure names the key (F6). */
export function readSettings<S extends z.ZodType>(
  schema: S,
  raw: unknown,
): { ok: true; value: z.infer<S> } | { ok: false; error: string } {
  const parsed = schema.safeParse(raw);
  return parsed.success ? { ok: true, value: parsed.data } : { ok: false, error: settingsIssue(parsed.error) };
}

export const tickStateSchema = z.object({
  now: z.string(),
  // The raw one.settings rows: each probe and the tick's other steps parse what they read (F6).
  settings: z.record(z.string(), z.unknown()),
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
