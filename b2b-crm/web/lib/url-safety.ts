/**
 * Addresses the CRM's database calls (partner pushes, partner CRM adapters, webhooks, the AI worker) must be on the public
 * internet. Mirrors b2b.url_allowed (m34e), which refuses the same addresses when they are saved and when pg_net sends.
 */

const INTERNAL_NAMES = /(^|\.)(localhost|localdomain|local|internal|intranet|private|lan|home|corp|svc|cluster\.local|arpa)$/;
const ECHO_DNS = /(^|\.)(nip\.io|sslip\.io|xip\.io|rbndr\.us|localtest\.me|lvh\.me|vcap\.me|lacolhost\.com|traefik\.me|localhost\.direct)$/;
const EMBEDDED_QUAD = /^\d{1,3}[.-]\d{1,3}[.-]\d{1,3}[.-]\d{1,3}[.-]/;
const DOTTED_QUAD = /^(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})$/;

export const NOT_PUBLIC = "Use an https address on the public internet, not a private, loopback, link-local or metadata address.";

/** Loopback, private, link-local and metadata ranges, carrier-grade NAT, multicast, reserved and documentation ranges. */
function blockedIpv4(a: number, b: number, c: number): boolean {
  return a === 0 || a === 10 || a === 127 || a >= 224
    || (a === 100 && b >= 64 && b <= 127)
    || (a === 169 && b === 254)
    || (a === 172 && b >= 16 && b <= 31)
    || (a === 192 && b === 168)
    || (a === 192 && b === 0 && (c === 0 || c === 2))
    || (a === 198 && (b === 18 || b === 19))
    || (a === 198 && b === 51 && c === 100)
    || (a === 203 && b === 0 && c === 113);
}

/** Why the CRM may not call this address, or null when it may. */
export function outboundUrlProblem(raw: string): string | null {
  const url = raw.trim();
  if (!/^https:\/\//i.test(url)) return "Must start with https://";
  if (url.length > 2000 || /[\s\u0000-\u001f\u007f\\]/.test(url)) return "No spaces or backslashes in the address.";
  const authority = url.slice(8).split(/[/?#]/, 1)[0] ?? "";
  // user:password@host and IPv6 literals are refused outright
  if (!authority || authority.includes("@") || authority.startsWith("[")) return NOT_PUBLIC;
  let host = authority.toLowerCase();
  const port = /:(\d{1,5})$/.exec(host);
  if (port) {
    const n = Number(port[1]);
    if (n < 1 || n > 65535) return NOT_PUBLIC;
    host = host.slice(0, -port[0].length);
  }
  host = host.replace(/\.+$/, "");
  if (!/^[a-z0-9.-]+$/.test(host) || host.includes("..") || /(^|\.)-/.test(host) || /-(\.|$)/.test(host) || !host.includes(".")) return NOT_PUBLIC;
  if (/^[0-9.]+$/.test(host) || /(^|\.)0x/.test(host)) {
    const m = DOTTED_QUAD.exec(host);
    if (!m) return NOT_PUBLIC;
    const [a, b, c, d] = m.slice(1, 5).map(Number) as [number, number, number, number];
    if (a > 255 || b > 255 || c > 255 || d > 255 || blockedIpv4(a, b, c)) return NOT_PUBLIC;
    return null;
  }
  if (INTERNAL_NAMES.test(host) || ECHO_DNS.test(host) || EMBEDDED_QUAD.test(host)) return NOT_PUBLIC;
  return null;
}
