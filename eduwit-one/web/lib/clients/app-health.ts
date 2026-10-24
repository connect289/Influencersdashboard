import { z } from "zod";
import { fetchJson, HttpError } from "../http.ts";
import type { AppHealthClient } from "./types.ts";

// The apps' own health endpoints (website, influencer portal, B2B app; Spark answers at "/"). Real and Mock share the
// fixture shape: the status and the ok flag, nothing from the body.

export const appHealthFixture = z.object({ ok: z.boolean(), status: z.number() });
export type AppHealthFixture = z.infer<typeof appHealthFixture>;

// The website and the B2B app answer {ok: true}; the influencer portal answers {status: "ok"} (200) or "degraded" (503).
const healthBody = z.looseObject({ ok: z.boolean().optional(), status: z.string().optional() });

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
      return { ok: body?.ok === true || body?.status === "ok", status, ms };
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

/** HEAD, then GET when HEAD got no answer or a 5xx; answered is a status from 1 to 499. */
export async function answersAt(
  url: string,
): Promise<{ answered: boolean; status: number; method: "HEAD" | "GET"; ms: number }> {
  const started = Date.now();
  let method: "HEAD" | "GET" = "HEAD";
  let status = await probe(url, method);
  if (status <= 0 || status >= 500) {
    method = "GET";
    status = await probe(url, method);
  }
  return { answered: status > 0 && status < 500, status, method, ms: Date.now() - started };
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
    return { answered: status > 0 && status < 500, status, method: "HEAD" as const, ms: f ? 1 : 10_000 };
  }
}
