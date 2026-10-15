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

/** Google OAuth client (Web application) for "Connect my Gmail" (D6). Redirect URI: <site>/auth/google/gmail/callback. */
export function googleOAuthClient(): { clientId: string; clientSecret: string } | null {
  const clientId = process.env.GOOGLE_OAUTH_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_OAUTH_CLIENT_SECRET;
  if (!clientId || !clientSecret) return null;
  return { clientId, clientSecret };
}

/**
 * The AES-256-GCM key that seals each person's Gmail refresh token before it is stored (b2c.user_connections). 32 bytes,
 * as 64 hex characters or base64 (openssl rand -base64 32). Null when unset; throws when set but not 32 bytes. Changing
 * it makes every stored connection unreadable: everyone reconnects.
 */
export function gmailTokenKey(value = process.env.GMAIL_TOKEN_KEY): Buffer | null {
  if (!value) return null;
  const v = value.trim();
  const key = /^[0-9a-f]{64}$/i.test(v) ? Buffer.from(v, "hex") : Buffer.from(v.replace(/-/g, "+").replace(/_/g, "/"), "base64");
  if (key.length !== 32) throw new Error("GMAIL_TOKEN_KEY must be 32 bytes: 64 hex characters or base64 (openssl rand -base64 32).");
  return key;
}
