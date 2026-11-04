// The reader reads no credential column of the apps (0031, D-121). one.reader_without_credentials() narrows
// eduwit_one_reader by one.is_credential_column(): a column-name pattern, matched in snake_case, and a short list of
// columns that hold a credential under a plain name. This test holds both to the credential columns the apps have and
// keeps them off what Eduwit One reads. Eduwit One reads as the owner (D-030), so the reader's narrowing cannot break a
// check; the last tests keep it that way by name: no check, panel or events source may read a column the pattern takes
// or a relation on the list.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

const root = new URL("../../", import.meta.url);
const read = (p: string) => readFileSync(new URL(p, root), "utf8");
const migration = read("supabase/migrations/0031_audit_hardening.sql");

const declared = /-- reader-credential-pattern[^\n]*\n(?:\s*--[^\n]*\n)*\s*select '((?:[^']|'')*)'::text/.exec(migration);
const pattern = new RegExp((declared?.[1] ?? "(?!)").replaceAll("''", "'"));
const listed = /-- reader-credential-columns[^\n]*\n(?:\s*--[^\n]*\n)*[^\n]*= any \(array\[([^\]]*)\]\)/.exec(migration);
const named = [...(listed?.[1] ?? "").matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");

// As one.is_credential_column: camelCase split at each capital, then lower case.
const snake = (name: string) => name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
const credential = (name: string) => pattern.test(snake(name));

test("0031 declares the reader's credential pattern and named columns", () => {
  assert.ok(declared, "the pattern is in 0031, after its marker comment");
  assert.ok(named.length >= 1 && named.every((n) => /^[a-z0-9_]+\.[a-z0-9_]+\.[a-z0-9_]+$/.test(n)), named.join(", "));
});

test("the pattern takes the apps' credential columns from the reader", () => {
  for (const c of [
    "secret_password",
    "password",
    "password_hash",
    "invite_token_hash",
    "push_subscription",
    "inbound_secret",
    "client_secret",
    "refresh_token",
    "access_token",
    "token",
    "token_sealed",
    "key_hash",
    "code_hash",
    "api_key",
    "secret_key",
    "otp_code",
    "totp_secret",
    "salt",
    "session_cookie",
    "credentials",
    "encrypted_pan",
    "pan_enc",
    "recovery_codes",
    // n8n's tables, in camelCase
    "apiKey",
    "mfaSecret",
    "mfaRecoveryCodes",
    "clientSecret",
    "encryptedSettings",
  ])
    assert.ok(credential(c), c);
});

test("it leaves the columns the checks read and plain ones", () => {
  for (const c of [
    "token_failed_at",
    "token_expires_at",
    "token_error",
    "token_secret_id",
    "inbound_secret_id",
    "input_tokens",
    "prompt_tokens",
    "tokens",
    "invite_token_expires_at",
    "password_set_at",
    "has_password",
    "is_secret",
    "require_totp",
    "api_key_id",
    "key_prefix",
    "idempotency_key",
    "otp_attempts",
    "referral_code",
    "access_code",
    "pincode",
    "full_name",
    "email",
    "user_id",
    "hashtag",
    "secretary",
    // n8n's tables, in camelCase
    "mfaEnabled",
    "credentialId",
    "clientSecretExpiresAt",
    "tokenEndpointAuthMethod",
    "promptTokens",
    "tokenCount",
    "codeChallenge",
  ])
    assert.ok(!credential(c), c);
});

// Eduwit One's own names that the pattern matches, each with why it is not an app column Eduwit One reads.
const OWN = new Map([
  ["code_hash", "one.email_codes (schema one)"],
  ["token_hash", "one.trusted_devices (schema one)"],
  ["salt", "one.email_codes (schema one)"],
  ["v_salt", "a variable"],
  ["p_token", "a parameter"],
  ["v_token", "a variable"],
  ["create_secret", "vault.create_secret()"],
  ["update_secret", "vault.update_secret()"],
  ["ui_secret_put", "an Eduwit One function"],
  ["reader_without_credentials", "this narrowing's own procedure (0031)"],
  ["credential_column_pattern", "this narrowing's own pattern function (0031)"],
  ["is_credential_column", "this narrowing's own test function (0031)"],
  ["decrypted_secret", "vault.decrypted_secrets, read by one.secret()"],
  ["secret", "one.secret(), and a word in seeded settings and proposals"],
  ["token", "a word in seeded settings"],
  ["password", "a word in seeded settings and proposals"],
  ["credential", "a word in a builder proposal"],
  ["totp", "a word in seeded settings"],
  ["secret_password", "named in a builder proposal's text (0013), never read"],
  ["auth_leaked_password_protection", "a Supabase Auth setting named in a builder proposal"],
  ["one_test_runner_password", "a Vault name in seeded settings"],
  ["one_test_runner_totp", "a Vault name in seeded settings"],
  ["one_test_wa_token", "a Vault name in seeded settings"],
]);

// Eduwit One's SQL: the checks and every forward migration (the panels, the events copy and its union sources, the
// tools), quoted strings and comments left out, in one pass from the left (a "--" inside a string is the string's);
// dollar-quoted bodies are code and stay.
const sources = [
  ...readdirSync(new URL("supabase/checks/", root)).map((f) => `supabase/checks/${f}`),
  ...readdirSync(new URL("supabase/migrations/", root))
    .filter((f) => !f.endsWith(".rollback.sql"))
    .map((f) => `supabase/migrations/${f}`),
]
  .filter((f) => f.endsWith(".sql"))
  .map((f) => ({ f, code: read(f).replace(/'(?:[^']|'')*'|--[^\n]*/g, (s) => (s.startsWith("'") ? "''" : " ")) }));

test("no check, panel or events source reads a column the pattern takes", () => {
  const found = new Map<string, string>();
  for (const { f, code } of sources)
    for (const m of code.matchAll(/\b[a-z_][a-z0-9_]*\b/gi)) {
      const w = snake(m[0]);
      if (pattern.test(w) && !OWN.has(w)) found.set(w, f);
    }
  assert.deepEqual(Object.fromEntries(found), {}, "a name the pattern takes is read by Eduwit One: keep it, or rename");
});

test("nor a relation whose plain-named column is on the list", () => {
  const relations = [...new Set(named.map((n) => n.split(".")[1] ?? ""))];
  const found = sources.flatMap(({ f, code }) => relations.filter((r) => new RegExp(`\\b${r}\\b`, "i").test(code)).map((r) => `${r} in ${f}`));
  assert.deepEqual(found, []);
});
