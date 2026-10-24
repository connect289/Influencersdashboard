import { createHmac } from "node:crypto";

// RFC 6238 one-time codes (HMAC-SHA1, 30-second steps, 6 digits), the kind Supabase Auth's TOTP factor checks. The test
// runner login proves its second factor with it (D-070); the secret is the factor's base32 secret from Vault.

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** Decodes RFC 4648 base32 (case and spaces ignored, padding optional). */
export function base32Decode(input: string): Buffer {
  const clean = input.replace(/[\s=]/g, "").toUpperCase();
  if (!clean || /[^A-Z2-7]/.test(clean)) throw new Error("the TOTP secret is not base32");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    value = (value << 5) | ALPHABET.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** The HOTP value (RFC 4226) for a counter. */
export function hotp(key: Buffer, counter: number, digits = 6): string {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const mac = createHmac("sha1", key).update(msg).digest();
  const offset = (mac[mac.length - 1] ?? 0) & 0x0f;
  const code = (mac.readUInt32BE(offset) & 0x7fffffff) % 10 ** digits;
  return String(code).padStart(digits, "0");
}

/** The TOTP code for a base32 secret at a time (epoch ms). */
export function totp(secretBase32: string, nowMs: number, digits = 6, stepS = 30): string {
  return hotp(base32Decode(secretBase32), Math.floor(nowMs / 1000 / stepS), digits);
}
