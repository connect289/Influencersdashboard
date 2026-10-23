// Shared helpers for the access preflight. No vendor SDKs, no dependencies: plain fetch and node:crypto,
// so the script runs anywhere Node 22 runs. Nothing here ever prints or returns a secret value.
import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";

export type Status = "verified" | "refused" | "not_provided" | "unfilled";

export type Row = {
  id: string;
  status: Status;
  ran: string;
  detail: string;
  fix?: string;
};

export type HttpResult = { status: number; body: unknown; error?: string };

export type HostKey = "website" | "website_internal" | "spark" | "b2b_app" | "influencer" | "chatwoot" | "n8n" | "one";

export type Defaults = {
  repo: string;
  hosts: Record<HostKey, string>;
  health_paths: Partial<Record<HostKey, string>>;
  vendors: Record<"vercel_api" | "uptimerobot_api" | "resend_api" | "graph_api" | "github_api" | "gemini_api" | "anthropic_api", string>;
  vercel: { team: string; projects: Record<string, string> };
  n8n: Record<"witty_workflow_id" | "test_harness_workflow_id" | "nurture_workflow_id" | "learning_workflow_id", string>;
  aws: { lightsail_default_region: string };
  email: { domain: string };
  test_identities: Record<string, string | null>;
  required_repo_folders: string[];
};

/** Reads a JSON file by its path inside eduwit-one/ (for example "config/defaults.json"). */
export function loadJson<T>(pathFromAppRoot: string): T {
  return JSON.parse(readFileSync(new URL(`../../${pathFromAppRoot}`, import.meta.url), "utf8")) as T;
}

/** First non-empty value among the given env names. Aliases exist because the build environment and Vercel name things differently. */
export function env(...names: string[]): string | undefined {
  for (const name of names) {
    const value = process.env[name]?.trim();
    if (value) return value;
  }
  return undefined;
}

function errorCode(e: unknown): string {
  const cause = (e as { cause?: { code?: string; message?: string } }).cause;
  if (cause?.code) return cause.code;
  if (e instanceof Error) return e.name === "TimeoutError" ? "timeout" : e.message.slice(0, 80);
  return "error";
}

export async function http(url: string, init: RequestInit = {}, timeoutMs = 15_000): Promise<HttpResult> {
  try {
    const response = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
    const text = await response.text();
    let body: unknown = text;
    try {
      body = JSON.parse(text);
    } catch {
      // not JSON; keep the text
    }
    return { status: response.status, body };
  } catch (e) {
    return { status: 0, body: null, error: errorCode(e) };
  }
}

/** A failed connection from the build environment is usually its network policy, not the credential. */
export function unreachable(result: HttpResult, host: string): Row["fix"] {
  return result.status === 0
    ? `could not connect (${result.error ?? "error"}); allow ${host} in the environment's network settings, or run the preflight from the deployed app`
    : undefined;
}

export function hostOf(url: string): string {
  return new URL(url).host;
}

const sha256 = (data: string): string => createHash("sha256").update(data).digest("hex");
const hmac = (key: Buffer | string, data: string): Buffer => createHmac("sha256", key).update(data).digest();

/** SigV4-signed JSON call to the Lightsail API (X-Amz-Target protocol). */
export async function lightsail(action: string, region: string, accessKey: string, secretKey: string): Promise<HttpResult> {
  const host = `lightsail.${region}.amazonaws.com`;
  const body = "{}";
  const now = new Date();
  const amzDate = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const day = amzDate.slice(0, 8);
  const headers: Record<string, string> = {
    "content-type": "application/x-amz-json-1.1",
    host,
    "x-amz-date": amzDate,
    "x-amz-target": `Lightsail_20161128.${action}`,
  };
  const names = Object.keys(headers).sort();
  const canonical = ["POST", "/", "", names.map((n) => `${n}:${headers[n]}\n`).join(""), names.join(";"), sha256(body)].join("\n");
  const scope = `${day}/${region}/lightsail/aws4_request`;
  const toSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(canonical)].join("\n");
  const signingKey = hmac(hmac(hmac(hmac(`AWS4${secretKey}`, day), region), "lightsail"), "aws4_request");
  const signature = createHmac("sha256", signingKey).update(toSign).digest("hex");
  headers.authorization = `AWS4-HMAC-SHA256 Credential=${accessKey}/${scope}, SignedHeaders=${names.join(";")}, Signature=${signature}`;
  const { host: _host, ...sendHeaders } = headers;
  return http(`https://${host}/`, { method: "POST", headers: sendHeaders, body });
}

export function field(value: unknown, ...path: string[]): unknown {
  let current: unknown = value;
  for (const key of path) {
    if (current === null || typeof current !== "object") return undefined;
    current = (current as Record<string, unknown>)[key];
  }
  return current;
}

export function list(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? (value as Record<string, unknown>[]) : [];
}
