// Server-side environment, validated once with zod. Import only from server code (route handlers, server actions,
// server components, scripts). Public values that the browser needs live in lib/env-public.ts.
import "server-only";
import { z } from "zod";

const onOff = z.enum(["on", "off"]).default("off");
const optionalSecret = z.string().min(1).optional();

const schema = z
  .object({
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    NEXT_PUBLIC_SUPABASE_URL: z.url(),
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(20),
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),
    NEXT_PUBLIC_SITE_URL: z.url(),
    INF_INTERNAL_API_KEY: z.string().min(32, "INF_INTERNAL_API_KEY must be at least 32 characters"),
    STAFF_GOOGLE_HD: z.string().regex(/^[a-z0-9.-]+\.[a-z]{2,}$/i).optional(),
    LIVE_MODE: onOff,
    EMAIL_PROVIDER: z.enum(["mock", "smtp", "resend", "brevo"]).default("mock"),
    EMAIL_FROM: z.string().min(3).default("Eduwit Creators <creators@eduwit.in>"),
    SMTP_HOST: z.string().optional(),
    SMTP_PORT: z.coerce.number().int().min(1).max(65535).default(587),
    SMTP_SECURE: onOff,
    SMTP_USER: z.string().optional(),
    SMTP_PASSWORD: optionalSecret,
    RESEND_API_KEY: optionalSecret,
    BREVO_API_KEY: optionalSecret,
    WHATSAPP_PROVIDER: z.enum(["mock", "meta"]).default("mock"),
    WHATSAPP_PHONE_NUMBER_ID: z.string().regex(/^\d+$/).optional(),
    WHATSAPP_TOKEN: optionalSecret,
    WHATSAPP_API_VERSION: z.string().regex(/^v\d+\.\d+$/).default("v21.0"),
    LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
  })
  .superRefine((env, ctx) => {
    const need = (cond: boolean, key: string, why: string) => {
      if (cond) ctx.addIssue({ code: "custom", path: [key], message: why });
    };
    need(env.EMAIL_PROVIDER === "smtp" && !env.SMTP_HOST, "SMTP_HOST", "required when EMAIL_PROVIDER=smtp");
    need(env.EMAIL_PROVIDER === "resend" && !env.RESEND_API_KEY, "RESEND_API_KEY", "required when EMAIL_PROVIDER=resend");
    need(env.EMAIL_PROVIDER === "brevo" && !env.BREVO_API_KEY, "BREVO_API_KEY", "required when EMAIL_PROVIDER=brevo");
    need(
      env.WHATSAPP_PROVIDER === "meta" && (!env.WHATSAPP_PHONE_NUMBER_ID || !env.WHATSAPP_TOKEN),
      "WHATSAPP_TOKEN",
      "WHATSAPP_PHONE_NUMBER_ID and WHATSAPP_TOKEN are required when WHATSAPP_PROVIDER=meta",
    );
    need(env.NODE_ENV === "production" && env.EMAIL_PROVIDER === "mock", "EMAIL_PROVIDER", "the mock provider is not allowed in production");
  });

export type ServerEnv = z.infer<typeof schema>;

/** Parses an environment object. Exported for tests; the app uses `env()`. Error messages name variables, never values. */
export function parseEnv(source: Record<string, string | undefined>): ServerEnv {
  const result = schema.safeParse(source);
  if (!result.success) {
    const problems = result.error.issues.map((i) => `${i.path.join(".") || "(env)"}: ${i.message}`).join("; ");
    throw new Error(`Invalid environment: ${problems}`);
  }
  return result.data;
}

let cached: ServerEnv | undefined;
export function env(): ServerEnv {
  cached ??= parseEnv(process.env);
  return cached;
}
