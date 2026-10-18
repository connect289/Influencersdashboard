// Test environment: read .env.local explicitly so variables exported by the shell (e.g. keys for hosted projects)
// never reach the app under test.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export function localEnv(): Record<string, string> {
  const file = join(import.meta.dirname, "..", ".env.local");
  const out: Record<string, string> = {};
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
      if (m?.[1]) out[m[1]] = m[2] ?? "";
    }
  }
  return out;
}

export const MAILPIT = process.env.MAILPIT_URL ?? "http://127.0.0.1:54424";
export const BASE_URL = process.env.E2E_BASE_URL ?? "http://localhost:3200";
export const SEED_PASSWORD = "Local-Demo-Password-2026";
