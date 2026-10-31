import { lookup as dnsLookup, type LookupAddress } from "node:dns";
import type { ClientRequest, IncomingMessage } from "node:http";
import { request as httpsRequest, type RequestOptions } from "node:https";
import { isIP } from "node:net";

/**
 * Server-side downloads of links that people or providers hand Spark (a template's header sample, a call recording):
 * https on port 443 only, to a host on the caller's allow-list, and never to a private, loopback, link-local (cloud
 * metadata), shared, multicast, reserved or documentation address. The address is checked when the connection is made
 * (the DNS answer itself), on every redirect hop. Credentials go only to the hosts named for them; the body is capped and
 * the whole transfer has a deadline. The pure parts are unit-tested in safe-fetch.test.ts.
 */
export type FetchRules = {
  /** Host names allowed: "example.com" for that host, ".example.com" for it and its subdomains. */
  hosts: readonly string[];
  /** The hosts that may receive the credentials (a subset of `hosts`); everything else gets the request without them. */
  credentialHosts?: readonly string[];
  maxBytes: number;
  timeoutMs: number;
  maxRedirects?: number;
};
export type FetchedFile = { status: number; contentType: string | null; body: Buffer; url: string };

type LookupFn = typeof dnsLookup;
type RequestFn = (url: URL, options: RequestOptions, callback: (res: IncomingMessage) => void) => ClientRequest;
export type FetchDeps = { request?: RequestFn; lookup?: LookupFn };

// ---------- addresses ----------

function v4(ip: string): number | null {
  const p = ip.split(".");
  if (p.length !== 4 || p.some((x) => !/^\d{1,3}$/.test(x) || Number(x) > 255)) return null;
  return p.reduce((n, x) => n * 256 + Number(x), 0);
}

/** This network, private, shared (CGNAT), loopback, link-local, IETF, documentation, 6to4 relay, benchmarking, multicast, reserved. */
const V4_RANGES: readonly (readonly [string, number])[] = [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.0.0.0", 24],
  ["192.0.2.0", 24], ["192.88.99.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24], ["203.0.113.0", 24], ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];
const V4_BLOCKED = V4_RANGES.map(([a, bits]) => [v4(a)!, bits] as const);

function v4Public(n: number): boolean {
  return !V4_BLOCKED.some(([base, bits]) => Math.floor(n / 2 ** (32 - bits)) === Math.floor(base / 2 ** (32 - bits)));
}

/** The eight 16-bit groups of an IPv6 address (an embedded dotted IPv4 tail included), or null. */
function v6Groups(ip: string): number[] | null {
  let s = ip.toLowerCase().replace(/^\[|\]$/g, "").replace(/%.*$/, "");
  const tail = s.match(/(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (tail) {
    const n = v4(tail[1]!);
    if (n === null) return null;
    s = s.slice(0, -tail[1]!.length) + Math.floor(n / 65536).toString(16) + ":" + (n % 65536).toString(16);
  }
  if ((s.match(/::/g) ?? []).length > 1) return null;
  const [head, rest] = s.includes("::") ? s.split("::") : [s, null];
  const h = head ? head.split(":") : [];
  const t = rest ? rest.split(":") : [];
  const fill = rest === null ? 0 : 8 - h.length - t.length;
  if (fill < 0 || (rest === null && h.length !== 8)) return null;
  const groups = [...h, ...Array<string>(fill).fill("0"), ...t];
  if (groups.length !== 8 || groups.some((g) => !/^[0-9a-f]{1,4}$/.test(g))) return null;
  return groups.map((g) => parseInt(g, 16));
}

/** True only for an address a server-side download may reach (public unicast). Anything unreadable is refused. */
export function isPublicAddress(ip: string): boolean {
  const kind = isIP(ip.replace(/^\[|\]$/g, "").replace(/%.*$/, ""));
  if (kind === 4) return v4Public(v4(ip)!);
  if (kind !== 6) return false;
  const g = v6Groups(ip);
  if (!g) return false;
  const embedded = () => g[6]! * 65536 + g[7]!;
  if (g.slice(0, 6).every((x) => x === 0)) return false;                                        // ::, ::1, IPv4-compatible
  if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) return v4Public(embedded());       // IPv4-mapped
  if (g[0] === 0x64 && g[1] === 0xff9b && g.slice(2, 6).every((x) => x === 0)) return v4Public(embedded());  // NAT64
  if (g[0] === 0x64 && g[1] === 0xff9b) return false;                                           // local-use NAT64
  if (g[0] === 0x100 && g.slice(1, 4).every((x) => x === 0)) return false;                       // discard 100::/64
  if (g[0] === 0x2001 && (g[1] === 0 || g[1] === 0xdb8)) return false;                          // Teredo, documentation
  if (g[0] === 0x2002) return false;                                                            // 6to4
  if ((g[0]! & 0xfe00) === 0xfc00) return false;                                                // unique local fc00::/7 (fd00:ec2::254 too)
  if ((g[0]! & 0xffc0) === 0xfe80 || (g[0]! & 0xffc0) === 0xfec0) return false;                 // link-local, site-local
  if ((g[0]! & 0xff00) === 0xff00) return false;                                                // multicast
  return (g[0]! & 0xe000) === 0x2000;                                                           // global unicast 2000::/3 only
}

// ---------- host names and links ----------

const RESERVED_NAMES = /(^|\.)(localhost|local|internal|localdomain|home\.arpa|in-addr\.arpa|ip6\.arpa)$|^metadata$|^instance-data$/;

function cleanHost(h: string): string {
  return h.toLowerCase().replace(/\.$/, "");
}

/** Whether a host name is on the allow-list: "example.com" names that host, ".example.com" it and every subdomain. */
export function hostAllowed(host: string, allow: readonly string[]): boolean {
  const h = cleanHost(host);
  return allow.some((entry) => {
    const e = cleanHost(entry);
    return e.startsWith(".") ? h === e.slice(1) || h.endsWith(e) : h === e;
  });
}

/** Host-list settings ("a.example.com, .example.org"): valid names only, lower case. */
export function hostList(value: string | undefined | null): string[] {
  return (value ?? "").split(",").map((s) => cleanHost(s.trim())).filter((s) => /^\.?[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(s));
}

/** The host of a configured URL (NEXT_PUBLIC_SITE_URL and the like), or null. */
export function hostOf(url: string | undefined | null): string | null {
  try {
    return url ? cleanHost(new URL(url).hostname) : null;
  } catch {
    return null;
  }
}

/** Why a link may not be downloaded, or null when it may. */
export function urlProblem(raw: string, hosts: readonly string[]): string | null {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return "not a link";
  }
  if (u.protocol !== "https:") return "only https links";
  if (u.username || u.password) return "links with a user name or password are refused";
  if (u.port && u.port !== "443") return "only the standard https port";
  const host = cleanHost(u.hostname.replace(/^\[|\]$/g, ""));
  if (!host || isIP(host)) return "use a host name, not an address";
  if (RESERVED_NAMES.test(host)) return "a local or internal host name";
  if (!hostAllowed(host, hosts)) return `${host} is not an allowed host`;
  return null;
}

// ---------- the download ----------

/** dns.lookup that refuses an answer with any non-public address (so a host name cannot point inside). */
export function guardedLookup(base: LookupFn = dnsLookup): LookupFn {
  return ((hostname: string, options: unknown, callback: unknown) => {
    const cb = (typeof options === "function" ? options : callback) as (err: Error | null, address?: string | LookupAddress[], family?: number) => void;
    const opts = (typeof options === "object" && options !== null ? options : {}) as { all?: boolean; family?: number };
    base(hostname, { family: opts.family ?? 0, all: true }, (err, addresses) => {
      if (err) return cb(err);
      const list = (addresses ?? []) as LookupAddress[];
      if (list.length === 0) return cb(new Error(`${hostname} has no address`));
      if (list.some((a) => !isPublicAddress(a.address))) return cb(new Error(`${hostname} resolves to a private or reserved address`));
      if (opts.all) return cb(null, list);
      return cb(null, list[0]!.address, list[0]!.family);
    });
  }) as unknown as LookupFn;
}

function once(u: URL, headers: Record<string, string>, rules: FetchRules, deps: FetchDeps, deadline: number): Promise<{ redirect: string | null; file: Omit<FetchedFile, "url"> }> {
  return new Promise((resolve, reject) => {
    const left = deadline - Date.now();
    if (left <= 0) return reject(new Error("the download timed out"));
    const send = deps.request ?? (httpsRequest as unknown as RequestFn);
    const lookup = guardedLookup(deps.lookup) as unknown as RequestOptions["lookup"];
    const req = send(u, { method: "GET", headers, lookup, agent: false, timeout: left }, (res) => {
      const status = res.statusCode ?? 0;
      const location = res.headers.location;
      if (status >= 300 && status < 400 && location) {
        res.resume();
        return resolve({ redirect: String(location), file: { status, contentType: null, body: Buffer.alloc(0) } });
      }
      if (status < 200 || status >= 300) {
        res.resume();
        return resolve({ redirect: null, file: { status, contentType: null, body: Buffer.alloc(0) } });
      }
      const declared = Number(res.headers["content-length"] ?? 0);
      if (declared > rules.maxBytes) {
        res.destroy();
        return reject(new Error(`the file is larger than ${Math.round(rules.maxBytes / 1048576)} MB`));
      }
      const chunks: Buffer[] = [];
      let size = 0;
      res.on("data", (c: Buffer) => {
        size += c.length;
        if (size > rules.maxBytes) {
          res.destroy();
          reject(new Error(`the file is larger than ${Math.round(rules.maxBytes / 1048576)} MB`));
        } else chunks.push(c);
      });
      res.on("end", () => resolve({ redirect: null, file: { status, contentType: res.headers["content-type"] ?? null, body: Buffer.concat(chunks) } }));
      res.on("error", reject);
    });
    const timer = setTimeout(() => req.destroy(new Error("the download timed out")), left);
    req.on("timeout", () => req.destroy(new Error("the download timed out")));
    req.on("error", (e) => { clearTimeout(timer); reject(e); });
    req.on("close", () => clearTimeout(timer));
    req.end();
  });
}

/**
 * GET a link under the rules. Every hop (redirects too) must pass urlProblem and resolve to public addresses only;
 * `credentials` (e.g. an authorization header) are added only on hops whose host is in rules.credentialHosts.
 */
export async function fetchChecked(raw: string, rules: FetchRules, credentials?: Record<string, string>, deps: FetchDeps = {}): Promise<FetchedFile> {
  const deadline = Date.now() + rules.timeoutMs;
  let url = raw;
  for (let hop = 0; ; hop++) {
    const problem = urlProblem(url, rules.hosts);
    if (problem) throw new Error(problem);
    const u = new URL(url);
    const headers = credentials && hostAllowed(u.hostname, rules.credentialHosts ?? []) ? { ...credentials } : {};
    const r = await once(u, headers, rules, deps, deadline);
    if (r.redirect === null) return { ...r.file, url };
    if (hop >= (rules.maxRedirects ?? 3)) throw new Error("too many redirects");
    url = new URL(r.redirect, u).toString();
  }
}
