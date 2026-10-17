import "server-only";
import { z } from "zod";

/**
 * Server environment, validated once on first use (not at import, so builds and tests run without secrets).
 * Missing optional credentials switch the matching adapter to its mock (docs/SETUP_CHECKLIST.md).
 */
const schema = z.object({
  APP_ENV: z.enum(["local", "test", "preview", "production"]).default("local"),
  NEXT_PUBLIC_SITE_URL: z.url().default("http://localhost:3000"),
  NEXT_PUBLIC_SUPABASE_URL: z.url().default("http://127.0.0.1:54321"),
  SUPABASE_SECRET_KEY: z.string().min(20).optional(), // sb_secret_… (or a legacy service-role JWT); deliberately not SUPABASE_SERVICE_ROLE_KEY (D-027)
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(10).optional(),
  WEB_SESSION_SECRET: z.string().min(32).optional(),
  WEB_INTERNAL_KEY: z.string().min(24).optional(),
  CRON_SECRET: z.string().min(16).optional(), // set by Vercel Cron; accepted on /api/internal/* like WEB_INTERNAL_KEY
  EMAIL_PROVIDER: z.enum(["console", "smtp", "resend"]).default("console"),
  EMAIL_FROM: z.string().default("Eduwit <no-reply@eduwit.in>"),
  EMAIL_SMTP_HOST: z.string().optional(),
  EMAIL_SMTP_PORT: z.coerce.number().int().default(587),
  EMAIL_SMTP_USER: z.string().optional(),
  EMAIL_SMTP_PASSWORD: z.string().optional(),
  RESEND_API_KEY: z.string().optional(),
  NEXT_PUBLIC_TURNSTILE_SITE_KEY: z.string().optional(),
  TURNSTILE_SECRET_KEY: z.string().optional(),
  ANTHROPIC_API_KEY: z.string().optional(),
  WEB_ANTHROPIC_BASE_URL: z.url().optional(), // never the environment's ANTHROPIC_BASE_URL (D-027)
  WEB_ADVISOR_PROVIDER: z.enum(["auto", "claude", "mock"]).default("auto"),
  UPSTASH_REDIS_REST_URL: z.url().optional(),
  UPSTASH_REDIS_REST_TOKEN: z.string().optional(),
  NEXT_PUBLIC_GA4_ID: z.string().optional(),
  NEXT_PUBLIC_META_PIXEL_ID: z.string().optional(),
  META_CAPI_TOKEN: z.string().optional(),
  META_CAPI_TEST_CODE: z.string().optional(),
  NEXT_PUBLIC_CLARITY_ID: z.string().optional(),
  SENTRY_DSN: z.string().optional(),
  NEXT_PUBLIC_SENTRY_DSN: z.string().optional(),
  GSC_SA_EMAIL: z.string().optional(),
  GSC_SA_PRIVATE_KEY: z.string().optional(),
  GSC_SITE_URL: z.string().optional(),
  CREATOR_API_URL: z.url().optional(),
});

export type Env = z.infer<typeof schema>;

let cached: Env | null = null;

export function env(): Env {
  if (cached) return cached;
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    throw new Error(
      `Invalid environment: ${parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")}`,
    );
  }
  const e = parsed.data;
  // Deployed environments (production and preview) never run on the dev fallback secrets, which are public in the repo.
  if (e.APP_ENV === "production" || e.APP_ENV === "preview") {
    const missing = (["SUPABASE_SECRET_KEY", "WEB_SESSION_SECRET", "WEB_INTERNAL_KEY"] as const).filter((k) => !e[k]);
    if (missing.length) throw new Error(`Missing required ${e.APP_ENV} secrets: ${missing.join(", ")}`);
  }
  cached = e;
  return e;
}

/** Canonical site origin for absolute URLs (never derived from request headers). */
export function siteUrl(path = "/"): string {
  return new URL(path, env().NEXT_PUBLIC_SITE_URL).toString();
}

export function isProduction(): boolean {
  return env().APP_ENV === "production";
}

/** Production or preview (a Vercel deployment, possibly several server instances). */
export function isDeployed(): boolean {
  const a = env().APP_ENV;
  return a === "production" || a === "preview";
}

/** Dev-only fallback secret; refused in production and preview by env(). */
export function sessionSecret(): string {
  return env().WEB_SESSION_SECRET ?? "dev-only-session-secret-not-for-production-use-0001";
}
export function internalKey(): string {
  return env().WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001";
}
export function cronSecret(): string | undefined {
  return env().CRON_SECRET;
}

/** For tests. */
export function resetEnvCache() {
  cached = null;
}
