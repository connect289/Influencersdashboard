import type { Instrumentation } from "next";
import { createErrorReporter, reportingEnabled } from "./lib/error-report";

/**
 * Server observability (spec 3A, 15). Sentry loads only when SENTRY_DSN is set; otherwise errors go to the structured
 * log with the request id. PII is scrubbed before anything leaves the server.
 */
export async function register() {
  if (process.env.SENTRY_DSN && process.env.NEXT_RUNTIME === "nodejs") {
    const Sentry = await import("@sentry/nextjs");
    const { scrub } = await import("./lib/security/scrub");
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      environment: process.env.APP_ENV ?? "local",
      tracesSampleRate: 0.1,
      beforeSend(event) {
        if (event.request) {
          delete event.request.cookies;
          delete event.request.data;
          if (event.request.headers)
            event.request.headers = { "x-request-id": event.request.headers["x-request-id"] ?? "" };
          if (event.request.query_string) event.request.query_string = "[stripped]";
        }
        if (event.message) event.message = scrub(event.message);
        event.user = undefined;
        return event;
      },
    });
  }
}

// The count of failed requests also goes to Eduwit One (one.app_error_report; its check WEB-ERR alerts when there are too
// many; D-097). lib/error-report.ts says what is sent and when: the route as its file names it, the error's name,
// Next's digest and the kind of render, as the log line below; at most one call a minute, in the background, only from
// a deployment (a production build with a hosted Supabase address and the secret key). The service client is loaded on
// the first send.
const reporter = createErrorReporter({
  enabled: () =>
    reportingEnabled({
      nodeEnv: process.env.NODE_ENV,
      url: process.env.NEXT_PUBLIC_SUPABASE_URL,
      serviceKey: process.env.SUPABASE_SECRET_KEY,
    }),
  send: async (items, signal) => {
    const { db } = await import("./lib/server/db");
    const { error } = await db()
      .schema("one")
      .rpc("app_error_report", { p_app: "web", p_items: items })
      .abortSignal(signal);
    if (error) throw Object.assign(new Error("app_error_report failed"), { code: error.code });
  },
  onFailure: (code) => console.warn(JSON.stringify({ level: "warn", event: "error_report.failed", code })),
});

// Every unhandled server error: one structured, PII-free log line (no external service needed, D-095); Sentry too when
// SENTRY_DSN is set.
export const onRequestError: Instrumentation.onRequestError = async (err, request, context) => {
  const { requestErrorLine } = await import("./lib/security/request-error");
  console.error(requestErrorLine(err, request, context));
  // Only what the line above holds, and never the address: an error with no route file is counted as "(unknown)".
  reporter.record({
    route: context.routePath ?? "(unknown)",
    name: err instanceof Error ? err.name.slice(0, 60) : null,
    digest:
      typeof err === "object" && err !== null && "digest" in err
        ? String((err as { digest: unknown }).digest).slice(0, 64)
        : null,
    kind: context.routeType ?? null,
  });
  if (process.env.SENTRY_DSN) {
    const Sentry = await import("@sentry/nextjs");
    Sentry.captureRequestError(err, request, context);
  }
};
