import type { Instrumentation } from "next";

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

// Every unhandled server error: one structured, PII-free log line (no external service needed, D-095); Sentry too when
// SENTRY_DSN is set.
export const onRequestError: Instrumentation.onRequestError = async (err, request, context) => {
  const { requestErrorLine } = await import("./lib/security/request-error");
  console.error(requestErrorLine(err, request, context));
  if (process.env.SENTRY_DSN) {
    const Sentry = await import("@sentry/nextjs");
    Sentry.captureRequestError(err, request, context);
  }
};
