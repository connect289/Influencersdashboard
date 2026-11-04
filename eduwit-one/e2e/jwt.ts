// HS256 tokens for the click-through: signed with the run's key, verified by the shim like Supabase Auth would.
import { createHmac, timingSafeEqual } from "node:crypto";

export type Claims = {
  sub?: string;
  role?: string;
  email?: string;
  session_id?: string;
  exp?: number;
  amr?: Array<{ method: string; timestamp: number }>;
};

const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64url");

export function sign(key: string, claims: Claims): string {
  const head = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(claims));
  return `${head}.${body}.${b64url(createHmac("sha256", key).update(`${head}.${body}`).digest())}`;
}

export function verifyWith(key: string, token: string | undefined): Claims | null {
  if (!token) return null;
  const [head, body, sig] = token.split(".");
  if (!head || !body || !sig) return null;
  const want = createHmac("sha256", key).update(`${head}.${body}`).digest();
  const got = Buffer.from(sig, "base64url");
  if (got.length !== want.length || !timingSafeEqual(got, want)) return null;
  const claims = JSON.parse(Buffer.from(body, "base64url").toString()) as Claims;
  if (claims.exp && claims.exp < Date.now() / 1000) return null;
  return claims;
}
