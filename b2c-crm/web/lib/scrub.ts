/**
 * The app's second check that no phone number or email address goes to Claude (spec B18). The database already scrubs
 * the brief's input (b2c.scrub_pii); this runs the same rules on the final text just before the call, and
 * `containsPii` lets a caller refuse to send anything that still looks like one.
 */
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const SPELLED_EMAIL = /[A-Za-z0-9._%+-]+\s*(\(at\)|\[at\]| at )\s*[A-Za-z0-9-]+\s*(\(dot\)|\[dot\]| dot |\.)\s*[A-Za-z]{2,}/gi;
const PHONE = /(\+?\d[\s().-]{0,2}){8,}/g;

/** Dates and timestamps (2026-10-15, 2026-10-15T10:45:08.443+00:00) are not phone numbers, though their digits count to 8. */
const DATE = /\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)?/g;

/** Runs `fn` on the text between dates, leaving every date as it was. */
function outsideDates(text: string, fn: (part: string) => string): string {
  let out = "", last = 0;
  for (const m of text.matchAll(new RegExp(DATE.source, "g"))) {
    out += fn(text.slice(last, m.index)) + m[0];
    last = m.index + m[0].length;
  }
  return out + fn(text.slice(last));
}

export function scrubPii(text: string): string {
  return outsideDates(text, (t) => t.replace(EMAIL, "[email]").replace(SPELLED_EMAIL, "[email]").replace(PHONE, "[phone]"));
}

export function containsPii(text: string): boolean {
  const rest = text.replace(new RegExp(DATE.source, "g"), " ");
  return new RegExp(EMAIL.source).test(rest) || new RegExp(PHONE.source).test(rest);
}
