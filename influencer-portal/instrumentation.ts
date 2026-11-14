// Error tracking (spec 19): every unhandled server error (pages, route handlers, server actions, proxy) is written as
// one structured log line with the route and the digest the user sees, so it can be found from a support report.
// The line carries no personal data: the message is scrubbed (lib/log.ts scrubText) and only the route pattern is
// kept, never the requested path (its handles, codes and ids) or query string.
// A hosted tracker (Sentry) is added at go-live with its DSN (docs/RUNBOOK.md G-27).
import type { Instrumentation } from "next";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createErrorReporter, reportingEnabled } from "@/lib/error-report";
import { log, scrubText } from "@/lib/log";

// The count of these errors also goes to Eduwit One (D-199: one.app_error_report; its check INF-ERR alerts when there are
// too many). lib/error-report.ts says what is sent and when: the route pattern, the error's name, the scrubbed message
// cut to 200 characters, the digest and the kind, as the log line below; at most one call a minute, in the
// background, only from a deployment (a production build with a hosted Supabase address and the service key). The
// service client is typed for schema inf and loaded on the first send; schema one is Eduwit One's.
const reporter = createErrorReporter({
  enabled: () =>
    reportingEnabled({
      nodeEnv: process.env.NODE_ENV,
      url: process.env.NEXT_PUBLIC_SUPABASE_URL,
      serviceKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    }),
  send: async (items, signal) => {
    const { adminClient } = await import("@/lib/supabase/admin");
    const { error } = await (adminClient() as unknown as SupabaseClient)
      .schema("one")
      .rpc("app_error_report", { p_app: "influencer", p_items: items })
      .abortSignal(signal);
    if (error) throw Object.assign(new Error("app_error_report failed"), { code: error.code });
  },
  onFailure: (code) => log.warn("error_report.failed", { code }),
});

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
  reporter.record({
    route: context.routePath,
    name: e.name,
    message: scrubText(e.message).slice(0, 200),
    digest: e.digest ?? null,
    kind: context.routeType,
  });
};
