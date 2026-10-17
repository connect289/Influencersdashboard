import "server-only";
// Sends one signed webhook (spec 18): HTTPS POST, JSON body, X-Eduwit-Signature, 10-second timeout, no redirects.
// Every address the host resolves to is checked at connect time (isPublicAddress), so internal services stay out of
// reach even if DNS changes between checks.
import { lookup as dnsLookup, type LookupAddress } from "node:dns";
import { request } from "node:https";
import type { LookupFunction } from "node:net";
import { SIGNATURE_HEADER, signatureHeader } from "./sign";
import { isPublicAddress, literalHostAllowed } from "./ssrf";

const TIMEOUT_MS = 10_000;

export class BlockedAddressError extends Error {}

const safeLookup: LookupFunction = (hostname, options, callback) => {
  dnsLookup(hostname, { ...options, all: true }, (err, addresses) => {
    if (err) return callback(err, "", 4);
    const list = addresses;
    const blocked = list.find((a) => !isPublicAddress(a.address));
    if (blocked || list.length === 0) return callback(new BlockedAddressError("address not allowed"), "", 4);
    if (options.all) return (callback as unknown as (e: null, a: LookupAddress[]) => void)(null, list);
    const first = list[0] as LookupAddress;
    callback(null, first.address, first.family);
  });
};

export interface DeliveryAttempt {
  status: number | null;
  error: string | null;
  /** True when the address itself is refused: retrying cannot help. */
  blocked: boolean;
}

export function postWebhook(url: string, secret: string, body: string, now = new Date()): Promise<DeliveryAttempt> {
  const target = new URL(url);
  if (target.protocol !== "https:") return Promise.resolve({ status: null, error: "https only", blocked: true });
  // The lookup below is skipped for literal addresses, so check those here.
  if (!literalHostAllowed(url)) return Promise.resolve({ status: null, error: "address not allowed", blocked: true });
  const timestamp = Math.floor(now.getTime() / 1000);
  return new Promise((resolve) => {
    const req = request(
      {
        protocol: "https:",
        hostname: target.hostname,
        port: target.port || 443,
        path: `${target.pathname}${target.search}`,
        method: "POST",
        lookup: safeLookup,
        timeout: TIMEOUT_MS,
        headers: {
          "content-type": "application/json",
          "content-length": Buffer.byteLength(body),
          "user-agent": "Eduwit-Webhooks/1",
          [SIGNATURE_HEADER]: signatureHeader(secret, timestamp, body),
        },
      },
      (res) => {
        res.resume();
        res.on("end", () => resolve({ status: res.statusCode ?? null, error: null, blocked: false }));
        res.on("error", (e) => resolve({ status: res.statusCode ?? null, error: e.message, blocked: false }));
      },
    );
    req.on("timeout", () => req.destroy(new Error("timed out")));
    req.on("error", (e) =>
      resolve({ status: null, error: e.message.slice(0, 300), blocked: e instanceof BlockedAddressError }),
    );
    req.end(body);
  });
}
