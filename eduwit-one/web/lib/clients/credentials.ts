import type { OneDb } from "../db.ts";
import { secretEnv } from "../env.ts";
import { log } from "../log.ts";

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
  /** The AI layer's Claude key (Claude only, owner 24 Oct; D-004, D-075). */
  anthropic?: string;
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
  };
}

/** The Vault name each credential is read from in credentialsFrom (a unit test keeps the two in step). */
export const VAULT_CREDENTIALS: Readonly<Record<string, keyof Credentials>> = {
  one_vercel_token: "vercel",
  one_chatwoot_token: "chatwoot",
  one_n8n_key: "n8n",
  one_whatsapp_token: "whatsapp",
  one_email_key: "email",
  one_uptimerobot_key: "uptimerobot",
  one_meta_token: "meta",
  one_b2b_intake_key: "b2bIntake",
  one_test_partner_secret: "testPartnerSecret",
  one_test_runner_password: "testRunnerPassword",
  one_test_runner_totp: "testRunnerTotp",
  one_test_wa_token: "testWhatsapp",
  one_anthropic_key: "anthropic",
};

/**
 * Whether this deployment holds the credential stored under a Vault name (D-108): the name is in Vault, or one of the
 * environment variables credentialsFrom prefers is set. Null for a name no client or validator reads. Values are never
 * read here: Vault's side is the name's presence, the environment's only whether a variable is set.
 */
export function credentialAvailable(vaultName: string, inVault: boolean): boolean | null {
  const key = VAULT_CREDENTIALS[vaultName];
  if (!key) return null;
  return inVault || credentialsFrom({})[key] !== undefined;
}

/** The Vault names of a Setup item that a client or validator reads and this deployment does not hold (D-108). */
export function missingCredentials(secrets: ReadonlyArray<{ name: string; present: boolean }>): string[] {
  return secrets.filter((s) => credentialAvailable(s.name, s.present) === false).map((s) => s.name);
}

let cached: { at: number; value: Record<string, string> } | undefined;

/** Vault's one_* secrets through the service role, cached 60 s. A failed read keeps the last good copy, or none. */
export async function vaultSecrets(db: Pick<OneDb, "appSecrets">, now = Date.now()): Promise<Record<string, string>> {
  if (cached && now - cached.at < 60_000) return cached.value;
  try {
    cached = { at: now, value: await db.appSecrets() };
  } catch (e) {
    // Said once per minute at most (the cache window), with the cause and never a value: every vendor client is
    // "not configured" until the next read succeeds (efficiency review 21).
    log("warn", "vault.read_failed", {
      error: e instanceof Error ? e.message.slice(0, 200) : "error",
      stale: Boolean(cached),
    });
    return cached?.value ?? {};
  }
  return cached.value;
}

export function resetVaultCache(): void {
  cached = undefined;
}
