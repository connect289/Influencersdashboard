import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { credentialAvailable, credentialsFrom, missingCredentials, VAULT_CREDENTIALS } from "./credentials.ts";
import { clientsFor } from "./index.ts";

// Which credentials this deployment holds, for the Setup page and the probes' heartbeats (D-108). Names and presence
// only: no value is ever read back or shown.

// Every variable credentialsFrom reads, blanked: a machine's own environment (a build box may export VERCEL_TOKEN) must
// neither decide these tests nor appear in a failure message.
const ENV_NAMES = [
  "ONE_VERCEL_TOKEN",
  "VERCEL_TOKEN",
  "ONE_CHATWOOT_TOKEN",
  "CHATWOOT_API_TOKEN",
  "ONE_N8N_API_KEY",
  "ONE_WHATSAPP_TOKEN",
  "ONE_EMAIL_KEY",
  "RESEND_API_KEY",
  "ONE_UPTIMEROBOT_KEY",
  "UPTIMEROBOT_API_KEY",
  "ONE_META_TOKEN",
  "ONE_B2B_INTAKE_KEY",
  "B2B_INTAKE_TEST_KEY",
  "ONE_TEST_PARTNER_SECRET",
  "ONE_TEST_RUNNER_PASSWORD",
  "ONE_TEST_RUNNER_TOTP",
  "ONE_TEST_WA_TOKEN",
  "ONE_ANTHROPIC_API_KEY",
];
beforeEach(() => {
  for (const name of ENV_NAMES) vi.stubEnv(name, "");
});
afterEach(() => vi.unstubAllEnvs());

describe("VAULT_CREDENTIALS", () => {
  it("names the Vault secret credentialsFrom reads for each credential", () => {
    for (const [name, key] of Object.entries(VAULT_CREDENTIALS)) {
      expect(credentialsFrom({ [name]: "from-vault" })[key], name).toBe("from-vault");
    }
    // Every credential has its Vault name here, so none is left out of the Setup page's check.
    const read = Object.keys(credentialsFrom(Object.fromEntries(Object.keys(VAULT_CREDENTIALS).map((n) => [n, "x"]))));
    expect(new Set(Object.values(VAULT_CREDENTIALS))).toEqual(new Set(read));
  });
});

describe("credentialAvailable and missingCredentials", () => {
  it("counts a name present in Vault, or an environment variable that supplies it, and nothing else", () => {
    expect(credentialAvailable("one_vercel_token", true)).toBe(true);
    expect(credentialAvailable("one_vercel_token", false)).toBe(false);
    vi.stubEnv("ONE_VERCEL_TOKEN", "from-env");
    expect(credentialAvailable("one_vercel_token", false)).toBe(true);
    vi.stubEnv("ONE_CHATWOOT_TOKEN", "  ");
    expect(credentialAvailable("one_chatwoot_token", false)).toBe(false);
  });

  it("says nothing about a name no client or validator reads", () => {
    expect(credentialAvailable("one_b2b_read_key", false)).toBeNull();
    expect(credentialAvailable("b2c_internal_key", false)).toBeNull();
  });

  it("lists the app's credentials an item lacks", () => {
    expect(
      missingCredentials([
        { name: "one_n8n_key", present: false },
        { name: "one_email_key", present: true },
        { name: "one_b2b_read_key", present: false },
      ]),
    ).toEqual(["one_n8n_key"]);
  });
});

describe("clientsFor names what a client lacks (D-108)", () => {
  it("names the Vault secret when the credential is missing, and the settings when they do not parse", () => {
    vi.stubEnv("ONE_CLIENT_MODE", "");
    const none = clientsFor(null, {});
    expect(none.vercel).toMatchObject({ mode: "not_configured", client: null });
    expect(none.vercel.missing).toBe("one_vercel_token (in neither Vault nor the environment)");
    expect(none.chatwoot.missing).toBe("one_chatwoot_token (in neither Vault nor the environment)");
    expect(none.n8n.missing).toBe("one_n8n_key (in neither Vault nor the environment)");
    expect(clientsFor(null, { vercel: "t" }).vercel.missing).toBe("the hosts and vendors settings do not parse");
  });
});
