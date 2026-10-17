/**
 * Same-site path checks for redirects and crawled links. A path is local only if it starts with a single "/", has no
 * backslash, whitespace or control character (browsers read "/\evil.com" and "/<TAB>/evil.com" as "//evil.com"), and
 * still resolves to the same origin.
 */
const BASE = "https://local.invalid";

export function isLocalPath(p: string | null | undefined): boolean {
  if (!p || p[0] !== "/" || p[1] === "/" || /[\\\s\u0000-\u001f\u007f]/.test(p)) return false;
  try {
    return new URL(p, BASE).origin === BASE;
  } catch {
    return false;
  }
}

export const safeLocalPath = (p: string | null | undefined, fallback: string): string => (p && isLocalPath(p) ? p : fallback);
