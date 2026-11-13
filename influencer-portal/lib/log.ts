// Structured JSON logs (one line per event). Values under sensitive keys are redacted; never log codes, tokens,
// passwords, phone numbers or email addresses.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 } as const;
type Level = keyof typeof LEVELS;
// Keys whose values are never logged: secrets, one-time codes, contact details, PAN and bank data.
const SENSITIVE = /^(code|otp)$|pass(word)?|token|secret|authorization|cookie|phone|email|^pan$|account|ifsc/i;

function threshold(): number {
  const l = process.env.LOG_LEVEL;
  return l && l in LEVELS ? LEVELS[l as Level] : LEVELS.info;
}

export function redact(value: unknown, depth = 0): unknown {
  if (depth > 4 || value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.slice(0, 50).map((v) => redact(v, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) out[k] = SENSITIVE.test(k) ? "[redacted]" : redact(v, depth + 1);
  return out;
}

function write(level: Level, event: string, fields: Record<string, unknown> = {}): void {
  if (LEVELS[level] < threshold()) return;
  const line = JSON.stringify({
    t: new Date().toISOString(),
    level,
    event,
    ...(redact(fields) as Record<string, unknown>),
  });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.info(line);
}

export const log = {
  debug: (event: string, fields?: Record<string, unknown>) => write("debug", event, fields),
  info: (event: string, fields?: Record<string, unknown>) => write("info", event, fields),
  warn: (event: string, fields?: Record<string, unknown>) => write("warn", event, fields),
  error: (event: string, fields?: Record<string, unknown>) => write("error", event, fields),
};

export function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/**
 * Free text (an error message from a library or the database) with personal data replaced: email addresses, phone
 * and account numbers (runs of 9 or more digits, spaces allowed between them), PAN, Indian GSTIN and bearer tokens or
 * JWTs. UUIDs, dates and short numbers are kept so the line can still be matched to a record.
 */
export function scrubText(text: string): string {
  return text
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[email]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[token]")
    .replace(/\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+/gi, "$1 [token]")
    .replace(/\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b/g, "[gstin]")
    .replace(/\b[A-Z]{5}\d{4}[A-Z]\b/g, "[pan]")
    .replace(/(?<![\w-])\+?\d(?: ?\d){8,}(?![\w-])/g, "[number]");
}
