// One HTTP path for every client (spec standard 6): a timeout, retries with jitter on transient failures, and a
// circuit breaker per client so a dead vendor costs one fast failure per tick instead of a timeout per call. Errors
// carry a category and status, never a URL with credentials or a response body.

export type HttpPolicy = { timeoutMs: number; retries: number; breakerFailures: number; breakerCooldownMs: number };

export const DEFAULT_POLICY: HttpPolicy = {
  timeoutMs: 5000,
  retries: 1,
  breakerFailures: 3,
  breakerCooldownMs: 120_000,
};

export class HttpError extends Error {
  readonly category: "timeout" | "network" | "status" | "parse" | "breaker_open";
  readonly status: number | undefined;

  constructor(category: "timeout" | "network" | "status" | "parse" | "breaker_open", status?: number) {
    super(status === undefined ? category : `${category} ${status}`);
    this.category = category;
    this.status = status;
  }
}

type Breaker = { failures: number; openUntil: number };
const breakers = new Map<string, Breaker>();

export function breakerOpen(client: string, now = Date.now()): boolean {
  return (breakers.get(client)?.openUntil ?? 0) > now;
}

function record(client: string, ok: boolean, policy: HttpPolicy): void {
  const b = breakers.get(client) ?? { failures: 0, openUntil: 0 };
  if (ok) {
    breakers.set(client, { failures: 0, openUntil: 0 });
    return;
  }
  const failures = b.failures + 1;
  breakers.set(client, {
    failures,
    openUntil: failures >= policy.breakerFailures ? Date.now() + policy.breakerCooldownMs : 0,
  });
}

/** Test hook: forget every breaker. */
export function resetBreakers(): void {
  breakers.clear();
}

const transient = (status: number) => status === 429 || status >= 500;
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** GETs or POSTs JSON. 4xx other than 429 is not retried: the request itself is wrong. */
export async function fetchJson(
  client: string,
  url: string,
  init: { method?: "GET" | "POST"; headers?: Record<string, string>; body?: unknown } = {},
  policy: HttpPolicy = DEFAULT_POLICY,
): Promise<{ status: number; json: unknown; ms: number }> {
  if (breakerOpen(client)) throw new HttpError("breaker_open");
  const started = Date.now();
  let last: HttpError = new HttpError("network");
  for (let attempt = 0; attempt <= policy.retries; attempt++) {
    if (attempt > 0) await sleep(200 * 2 ** attempt + Math.floor(Math.random() * 200));
    try {
      const res = await fetch(url, {
        method: init.method ?? "GET",
        headers: {
          accept: "application/json",
          ...(init.body === undefined ? {} : { "content-type": "application/json" }),
          ...init.headers,
        },
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
        signal: AbortSignal.timeout(policy.timeoutMs),
        cache: "no-store",
        redirect: "follow",
      });
      if (!res.ok) {
        last = new HttpError("status", res.status);
        if (!transient(res.status)) break;
        continue;
      }
      let json: unknown;
      try {
        json = await res.json();
      } catch {
        last = new HttpError("parse", res.status);
        break;
      }
      record(client, true, policy);
      return { status: res.status, json, ms: Date.now() - started };
    } catch (e) {
      last = new HttpError(e instanceof Error && e.name === "TimeoutError" ? "timeout" : "network");
    }
  }
  record(client, false, policy);
  throw last;
}
