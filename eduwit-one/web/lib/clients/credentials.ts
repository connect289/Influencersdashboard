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
  /** The synthetic tests' own (D-070): B2B intake-only key, test partner secret, test runner login, test sender. */
  b2bIntake?: string;
  testPartnerSecret?: string;
  testRunnerPassword?: string;
  testRunnerTotp?: string;
  testWhatsapp?: string;
  /** The AI layer's model keys (D-004, D-075): one per provider; the tier's provider decides which is used. */
  anthropic?: string;
  gemini?: string;
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
    b2bIntake: secretEnv("ONE_B2B_INTAKE_KEY", "B2B_INTAKE_TEST_KEY") ?? vault.one_b2b_intake_key,
    testPartnerSecret: secretEnv("ONE_TEST_PARTNER_SECRET") ?? vault.one_test_partner_secret,
    testRunnerPassword: secretEnv("ONE_TEST_RUNNER_PASSWORD") ?? vault.one_test_runner_password,
    testRunnerTotp: secretEnv("ONE_TEST_RUNNER_TOTP") ?? vault.one_test_runner_totp,
    testWhatsapp: secretEnv("ONE_TEST_WA_TOKEN") ?? vault.one_test_wa_token,
    anthropic: secretEnv("ONE_ANTHROPIC_API_KEY") ?? vault.one_anthropic_key,
    gemini: secretEnv("ONE_GEMINI_API_KEY") ?? vault.one_gemini_key,
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
