// Structured logs (spec standard 7): one JSON line per event with the request id. Never a secret, a URL with a token,
// or a contact; callers pass counts and categories.
export function log(level: "info" | "warn" | "error", event: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ at: new Date().toISOString(), level, event, ...fields });
  if (level === "error") console.error(line);
  else console.warn(line);
}
