import type { OneDb } from "../db.ts";
import { secretEnv } from "../env.ts";

// Where each vendor credential comes from (spec standard 3, D-059): the Vercel env when set there, else the Vault
// secret the Setup page saved (one.app_secrets), read at most once a minute. A secret saved on the Setup page takes
// effect within a minute, without a deploy. Values are never logged.

export type Credentials = {
  vercel?: string;
  chatwoot?: string;
  n8n?: string;
  whatsapp?: string;
  email?: string;
  uptimerobot?: string;
  meta?: string;
};

export function credentialsFrom(vault: Record<string, string>): Credentials {
  return {
    vercel: secretEnv("ONE_VERCEL_TOKEN", "VERCEL_TOKEN") ?? vault.one_vercel_token,
    chatwoot: secretEnv("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN") ?? vault.one_chatwoot_token,
    n8n: secretEnv("ONE_N8N_API_KEY") ?? vault.one_n8n_key,
    whatsapp: secretEnv("ONE_WHATSAPP_TOKEN") ?? vault.one_whatsapp_token,
    email: secretEnv("ONE_EMAIL_KEY", "RESEND_API_KEY") ?? vault.one_email_key,
    uptimerobot: secretEnv("ONE_UPTIMEROBOT_KEY", "UPTIMEROBOT_API_KEY") ?? vault.one_uptimerobot_key,
    meta: secretEnv("ONE_META_TOKEN") ?? vault.one_meta_token,
  };
}

let cached: { at: number; value: Record<string, string> } | undefined;

/** Vault's one_* secrets through the service role, cached 60 s. A failed read keeps the last good copy, or none. */
export async function vaultSecrets(db: Pick<OneDb, "appSecrets">, now = Date.now()): Promise<Record<string, string>> {
  if (cached && now - cached.at < 60_000) return cached.value;
  try {
    cached = { at: now, value: await db.appSecrets() };
  } catch {
    return cached?.value ?? {};
  }
  return cached.value;
}

export function resetVaultCache(): void {
  cached = undefined;
}
