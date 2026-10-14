// Environment access. NEXT_PUBLIC_* names must stay literal so Next.js can inline them into browser code.

function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing environment variable ${name}. See b2c-crm/web/.env.example.`);
  return value;
}

export function supabaseUrl(): string {
  return required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL);
}

export function supabasePublishableKey(): string {
  return required("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
}

/** Base URL used in emailed links. Taken from configuration, never from request headers (host-header injection). */
export function siteUrl(): string {
  return required("NEXT_PUBLIC_SITE_URL", process.env.NEXT_PUBLIC_SITE_URL).replace(/\/+$/, "");
}

/** Only these Google Workspace accounts may sign in (spec B2). */
export const ALLOWED_DOMAIN = "eduwit.in";

/** Real messages go out only when LIVE_MODE=on. Anything else is a dry run, logged but not sent (spec A3). */
export function liveMode(): boolean {
  return process.env.LIVE_MODE === "on";
}

/** Shared key the database's pg_cron jobs send in x-internal-key (Vault secret b2c_internal_key). */
export function internalKey(): string {
  return required("B2C_INTERNAL_KEY", process.env.B2C_INTERNAL_KEY);
}

/** The B2B CRM link (contract v3): base URL, API key (scopes b2c, events, intake) and the webhook signing secret. */
export function b2bConfig(): { url: string; key: string; secret: string } | null {
  const url = process.env.B2B_API_URL;
  const key = process.env.B2B_API_KEY;
  const secret = process.env.B2B_SIGNING_SECRET;
  if (!url || !key || !secret) return null;
  return { url: url.replace(/\/+$/, ""), key, secret };
}

export function signingSecret(): string | null {
  return process.env.B2B_SIGNING_SECRET || null;
}
