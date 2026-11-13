// Error tracking (spec 19): every unhandled server error (pages, route handlers, server actions, proxy) is written as
// one structured log line with the route and the digest the user sees, so it can be found from a support report.
// The line carries no personal data: the message is scrubbed (lib/log.ts scrubText) and only the route pattern is
// kept, never the requested path (its handles, codes and ids) or query string.
// A hosted tracker (Sentry) is added at go-live with its DSN (docs/RUNBOOK.md G-27).
import type { Instrumentation } from "next";
import { log, scrubText } from "@/lib/log";

export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  const e = error as Error & { digest?: string };
  log.error("request.error", {
    message: scrubText(e.message).slice(0, 500),
    digest: e.digest ?? null,
    method: request.method,
    route: context.routePath,
    kind: context.routeType,
    request_id: request.headers["x-request-id"] ?? null,
  });
};
