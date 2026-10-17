/**
 * Removes personal data from strings and objects before they reach logs, analytics or error trackers
 * (spec rule 5: no PII in URLs, logs or analytics events).
 */
const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
// Indian mobiles with optional +91/91/0 prefix and separators, plus any long digit run (OTP codes, phone-like ids).
const PHONE = /(?:\+?91[\s-]?|0)?[6-9]\d{4}[\s-]?\d{5}\b/g;
const LONG_DIGITS = /\b\d{6,}\b/g;
const SENSITIVE_KEYS =
  /^(email|e-?mail|phone|mobile|whatsapp|name|full_?name|first_?name|last_?name|code|otp|token|password|secret|authorization|cookie|address|guardian.*)$/i;

export function scrubString(s: string): string {
  return s.replace(EMAIL, "[email]").replace(PHONE, "[phone]").replace(LONG_DIGITS, "[digits]");
}

export function scrub<T>(value: T, depth = 0): T {
  if (depth > 6) return "[depth]" as T;
  if (typeof value === "string") return scrubString(value) as T;
  if (Array.isArray(value)) return value.map((v) => scrub(v, depth + 1)) as T;
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = SENSITIVE_KEYS.test(k) ? "[redacted]" : scrub(v, depth + 1);
    }
    return out as T;
  }
  return value;
}
