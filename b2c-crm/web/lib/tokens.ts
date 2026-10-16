import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Signed tokens for the links in marketing email (spec B9.6): unsubscribe, open pixel, click tracking. A click token
 * carries its destination, so the redirect only ever goes where Eduwit sent it. Unit-tested in tokens.test.ts.
 */
const b64 = (b: Buffer | string) => Buffer.from(b).toString("base64url");

function secret(): string {
  const s = process.env.LINK_SECRET || process.env.B2C_INTERNAL_KEY;
  if (!s || s.length < 32) throw new Error("LINK_SECRET (or B2C_INTERNAL_KEY) of at least 32 characters is needed for email links");
  return s;
}

export function signToken(payload: string, key = secret()): string {
  const sig = createHmac("sha256", key).update(payload).digest().subarray(0, 16);
  return `${b64(payload)}.${b64(sig)}`;
}

export function readToken(token: string, key = secret()): string | null {
  const [p, s] = token.split(".");
  if (!p || !s) return null;
  let payload: string;
  try { payload = Buffer.from(p, "base64url").toString("utf8"); } catch { return null; }
  const want = createHmac("sha256", key).update(payload).digest().subarray(0, 16);
  const got = Buffer.from(s, "base64url");
  return got.length === want.length && timingSafeEqual(got, want) ? payload : null;
}

export type Link =
  | { kind: "unsubscribe"; lead: number; channel: "email" | "all" }
  | { kind: "open"; email: number }
  | { kind: "click"; email: number; link: "interested" | "brochure" | "other"; url: string };

export function encodeLink(l: Link, key?: string): string {
  const payload = l.kind === "unsubscribe" ? `u|${l.lead}|${l.channel}` : l.kind === "open" ? `o|${l.email}` : `c|${l.email}|${l.link}|${l.url}`;
  return signToken(payload, key);
}

export function decodeLink(token: string, key?: string): Link | null {
  const p = readToken(token, key);
  if (!p) return null;
  const [k, a, b, ...rest] = p.split("|");
  if (k === "u" && (b === "email" || b === "all")) return { kind: "unsubscribe", lead: Number(a), channel: b };
  if (k === "o") return { kind: "open", email: Number(a) };
  if (k === "c" && (b === "interested" || b === "brochure" || b === "other")) return { kind: "click", email: Number(a), link: b, url: rest.join("|") };
  return null;
}
