// Creator tracking codes (INTEGRATION_CONTRACTS §1.2). Uppercase, at least one hyphen, 5–32 characters, so a creator
// code can never look like one of Witty's 6-character access codes. Suffixes use Witty's no-confusion alphabet (no
// 0/O or 1/I) so a code survives being typed from a video. Pure.

export const CODE_RE = /^[A-Z0-9]{2,12}(-[A-Z0-9]{1,8}){1,3}$/;
export const CODE_MIN = 5;
export const CODE_MAX = 32;
export const SUFFIX_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/** A valid creator code in canonical (uppercase) form, or null. Matching is case-insensitive. */
export function normalizeCode(raw: string): string | null {
  const c = raw.trim().toUpperCase();
  return c.length >= CODE_MIN && c.length <= CODE_MAX && CODE_RE.test(c) ? c : null;
}

/** True for anything Witty would read as an access code (exactly six letters or digits). */
export function looksLikeAccessCode(s: string): boolean {
  return /^[A-Z0-9]{6}$/i.test(s.trim());
}

/** The handle as a code stem: letters and digits only, uppercase, 2–12 characters. */
export function codeStem(handle: string): string {
  const s = handle
    .normalize("NFKD")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 12);
  return s.length >= 2 ? s : `${s}CR`.slice(0, 2).padEnd(2, "X");
}

const TAGS: Record<string, string> = {
  instagram: "IG",
  youtube: "YT",
  facebook: "FB",
  linkedin: "LI",
  x: "X",
  telegram: "TG",
  moj_josh: "MJ",
  other: "GO",
  website: "WEB",
  whatsapp: "WA",
};

/** A short tag for a platform or a free label (letters and digits, 1–8 characters). */
export function codeTag(label: string): string {
  const known = TAGS[label.toLowerCase()];
  if (known) return known;
  const t = label
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 8);
  return t || "GO";
}

/** `n` characters from the suffix alphabet, drawn with `random` (0 ≤ x < 1). */
export function suffix(n: number, random: () => number): string {
  let out = "";
  for (let i = 0; i < n; i++) out += SUFFIX_ALPHABET[Math.floor(random() * SUFFIX_ALPHABET.length)] ?? "A";
  return out;
}

/** A new code such as `RIYALEARNS-IG-7K`. Callers retry with a new random suffix if it is taken. */
export function suggestCode(handle: string, tag: string, random: () => number = Math.random): string {
  return `${codeStem(handle)}-${codeTag(tag)}-${suffix(2, random)}`;
}

/** A crypto-backed random source for the server. */
export function cryptoRandom(): number {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return (a[0] ?? 0) / 2 ** 32;
}
