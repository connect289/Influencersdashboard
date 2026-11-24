/**
 * A programme's brochure link from the catalogue, or null when it is not one the site will show: only an https
 * address counts (the link opens in a new tab on someone else's server, so nothing but a plain web address is passed on).
 */
export function brochureHref(raw: string | null | undefined): string | null {
  const v = raw?.trim();
  if (!v) return null;
  try {
    const u = new URL(v);
    return u.protocol === "https:" && !u.username && !u.password ? u.toString() : null;
  } catch {
    return null;
  }
}
