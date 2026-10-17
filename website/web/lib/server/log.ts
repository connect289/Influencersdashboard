import "server-only";
import { scrub, scrubString } from "@/lib/security/scrub";

type Level = "debug" | "info" | "warn" | "error";

/**
 * Structured JSON logs (one line per event) with PII scrubbed and the request id attached, so a request can be traced
 * across the page, server actions, the agent route and the outbox worker (spec 3A observability).
 */
export function log(level: Level, event: string, fields: Record<string, unknown> = {}) {
  const line = JSON.stringify({ t: new Date().toISOString(), level, event: scrubString(event), ...scrub(fields) });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.info(line);
}

export function errorFields(err: unknown): Record<string, unknown> {
  if (err instanceof Error)
    return {
      error: err.name,
      message: scrubString(err.message),
      stack: err.stack?.split("\n").slice(0, 6).join(" | "),
    };
  return { error: String(err) };
}
