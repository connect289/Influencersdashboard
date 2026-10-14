/**
 * The app's second check that no phone number or email address goes to Claude (spec B18). The database already scrubs
 * the brief's input (b2c.scrub_pii); this runs the same rules on the final text just before the call, and
 * `containsPii` lets a caller refuse to send anything that still looks like one.
 */
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const SPELLED_EMAIL = /[A-Za-z0-9._%+-]+\s*(\(at\)|\[at\]| at )\s*[A-Za-z0-9-]+\s*(\(dot\)|\[dot\]| dot |\.)\s*[A-Za-z]{2,}/gi;
const PHONE = /(\+?\d[\s().-]{0,2}){8,}/g;

export function scrubPii(text: string): string {
  return text.replace(EMAIL, "[email]").replace(SPELLED_EMAIL, "[email]").replace(PHONE, "[phone]");
}

export function containsPii(text: string): boolean {
  return new RegExp(EMAIL.source).test(text) || new RegExp(PHONE.source).test(text);
}
