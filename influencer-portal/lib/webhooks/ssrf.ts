// Outbound webhooks must only reach the public internet (spec 18, security): loopback, private, link-local, carrier
// NAT, multicast and reserved ranges are refused, for IPv4, IPv6 and IPv4-mapped IPv6. The delivery job checks every
// address a host resolves to at connect time, so a DNS answer that changes after the check cannot reach inside. Pure.

/** 4 or 6 for an IP address, 0 otherwise (no node:net, so forms in the browser can use these checks). */
function isIP(s: string): 0 | 4 | 6 {
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(s)) return 4;
  if (!s.includes(":") || !/^[0-9a-f:.]+$/i.test(s)) return 0;
  try {
    new URL(`http://[${s}]/`);
    return 6;
  } catch {
    return 0;
  }
}

function v4Public(ip: string): boolean {
  const p = ip.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  const [a = 0, b = 0, c = 0] = p;
  if (a === 0 || a === 10 || a === 127) return false; // this network, private, loopback
  if (a === 100 && b >= 64 && b <= 127) return false; // carrier-grade NAT
  if (a === 169 && b === 254) return false; // link-local and cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return false; // private
  if (a === 192 && b === 168) return false; // private
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false; // IETF protocol assignments, TEST-NET-1
  if (a === 198 && (b === 18 || b === 19)) return false; // benchmarking
  if (a === 198 && b === 51 && c === 100) return false; // TEST-NET-2
  if (a === 203 && b === 0 && c === 113) return false; // TEST-NET-3
  if (a >= 224) return false; // multicast, reserved, broadcast
  return true;
}

function v6Public(ip: string): boolean {
  const lower =
    ip
      .toLowerCase()
      .replace(/^\[|\]$/g, "")
      .split("%")[0] ?? "";
  const mapped = /^(?:0{0,4}:){0,5}(?:0{0,4}:)?ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(lower);
  if (mapped?.[1]) return v4Public(mapped[1]);
  if (lower === "::" || lower === "::1") return false;
  const first = Number.parseInt(lower.split(":")[0] || "0", 16);
  if ((first & 0xfe00) === 0xfc00) return false; // unique local fc00::/7
  if ((first & 0xffc0) === 0xfe80) return false; // link-local fe80::/10
  if ((first & 0xff00) === 0xff00) return false; // multicast
  if (lower.startsWith("64:ff9b:") || lower.startsWith("2001:db8:") || lower.startsWith("2001:10:")) return false;
  if (/^::(\d+\.\d+\.\d+\.\d+)$/.test(lower)) return false; // deprecated IPv4-compatible
  return true;
}

/** Whether a resolved address is on the public internet. */
export function isPublicAddress(ip: string): boolean {
  const kind = isIP(ip.replace(/^\[|\]$/g, "").split("%")[0] ?? "");
  if (kind === 4) return v4Public(ip);
  if (kind === 6) return v6Public(ip);
  return false;
}

/**
 * Whether a URL's host may be contacted before any DNS lookup: an address written as the host (also in decimal, hex or
 * short forms, which the URL parser turns into dotted IPv4) must be public, because Node skips the connect-time lookup
 * check for literal addresses. Names are checked when they resolve.
 */
export function literalHostAllowed(url: string): boolean {
  let host: string;
  try {
    host = new URL(url).hostname.replace(/^\[|\]$/g, "");
  } catch {
    return false;
  }
  return isIP(host) === 0 || isPublicAddress(host);
}
