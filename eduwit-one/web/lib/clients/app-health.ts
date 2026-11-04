import { z } from "zod";
import { fetchJson, HttpError } from "../http.ts";
import type { AppHealthClient, HealthSummary } from "./types.ts";

// The apps' own health endpoints (website, influencer portal, B2B app, Spark). Real and Mock share the fixture shape:
// the status and the ok flag; the Real client also keeps the names of the parts a 2xx body reports as not ok.

export const appHealthFixture = z.object({ ok: z.boolean(), status: z.number() });
export type AppHealthFixture = z.infer<typeof appHealthFixture>;

// The website and the B2B app answer {ok: true}; the influencer portal answers {status: "ok"} (200) or "degraded" (503)
// with boolean checks; Spark answers {ok, status: "ok" | "degraded" | "down", checks: {part: "ok" | "warn" | "bad"}} (D-134).
const healthBody = z.looseObject({
  ok: z.boolean().optional(),
  status: z.string().optional(),
  checks: z.record(z.string(), z.unknown()).optional(),
});

/** The parts a health body reports as not ok: names only (at most 20, each a plain identifier), never their detail. */
export function healthSummary(body: z.infer<typeof healthBody> | undefined): HealthSummary | undefined {
  if (!body || (body.status === undefined && body.checks === undefined)) return undefined;
  const failing = Object.entries(body.checks ?? {})
    .filter(([k, v]) => /^[a-z][a-z0-9_]{0,39}$/.test(k) && (v === false || (typeof v === "string" && v !== "ok")))
    .map(([k]) => k)
    .slice(0, 20);
  const status = typeof body.status === "string" && /^[a-z_]{1,20}$/.test(body.status) ? body.status : undefined;
  return { ...(status ? { status } : {}), failing };
}

export class RealAppHealthClient implements AppHealthClient {
  answers(url: string) {
    return answersAt(url);
  }

  async health(url: string, expect: "json_ok" | "reachable") {
    const started = Date.now();
    if (expect === "reachable") {
      try {
        const res = await fetch(url, {
          method: "GET",
          signal: AbortSignal.timeout(5000),
          cache: "no-store",
          redirect: "follow",
        });
        await res.body?.cancel();
        return { ok: res.ok, status: res.status, ms: Date.now() - started };
      } catch (e) {
        return {
          ok: false,
          status: e instanceof Error && e.name === "TimeoutError" ? 0 : -1,
          ms: Date.now() - started,
        };
      }
    }
    try {
      const { status, json, ms } = await fetchJson(
        `health:${new URL(url).host}`,
        url,
        {},
        { timeoutMs: 5000, retries: 0, breakerFailures: 1_000_000, breakerCooldownMs: 0 },
      );
      const body = healthBody.safeParse(json).data;
      const summary = healthSummary(body);
      return { ok: body?.ok === true || body?.status === "ok", status, ms, ...(summary ? { summary } : {}) };
    } catch (e) {
      return { ok: false, status: e instanceof HttpError ? (e.status ?? 0) : -1, ms: Date.now() - started };
    }
  }
}

async function probe(url: string, method: "HEAD" | "GET"): Promise<number> {
  try {
    const res = await fetch(url, {
      method,
      signal: AbortSignal.timeout(10_000),
      cache: "no-store",
      redirect: "manual",
    });
    await res.body?.cancel();
    return res.status;
  } catch (e) {
    return e instanceof Error && e.name === "TimeoutError" ? 0 : -1;
  }
}

/** Statuses that show the route is there: a success, or a refusal of this method or of an empty request. */
export const routeAnswers = (status: number) =>
  (status >= 200 && status < 300) || [400, 401, 403, 405, 415, 422].includes(status);

/** HEAD, then GET when HEAD got no such answer: a redirect, a 404 or a 5xx is not an answer (phase 7 review m7). */
export async function answersAt(
  url: string,
): Promise<{ answered: boolean; status: number; method: "HEAD" | "GET"; ms: number }> {
  const started = Date.now();
  let method: "HEAD" | "GET" = "HEAD";
  let status = await probe(url, method);
  if (!routeAnswers(status)) {
    method = "GET";
    status = await probe(url, method);
  }
  return { answered: routeAnswers(status), status, method, ms: Date.now() - started };
}

/** Answers from recorded fixtures, keyed by host; an unknown host answers like a timeout. */
export class MockAppHealthClient implements AppHealthClient {
  private readonly byHost: Record<string, AppHealthFixture>;

  constructor(byHost: Record<string, AppHealthFixture>) {
    this.byHost = byHost;
  }

  async health(url: string) {
    const f = this.byHost[new URL(url).host];
    return f ? { ...f, ms: 1 } : { ok: false, status: 0, ms: 5000 };
  }

  async answers(url: string) {
    const f = this.byHost[new URL(url).host];
    const status = f?.status ?? 0;
    return { answered: routeAnswers(status), status, method: "HEAD" as const, ms: f ? 1 : 10_000 };
  }
}
