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

export const onRequestError: Instrumentation.onRequestError = async (err, request, context) => {
  const message = err instanceof Error ? err.message : String(err);
  const digest =
    typeof err === "object" && err !== null && "digest" in err
      ? String((err as { digest: unknown }).digest)
      : undefined;
  const { scrubString } = await import("./lib/security/scrub");
  console.error(
    JSON.stringify({
      t: new Date().toISOString(),
      level: "error",
      event: "request.error",
      message: scrubString(message),
      digest,
      path: request.path.split("?")[0],
      method: request.method,
      requestId: (request.headers["x-request-id"] as string | undefined) ?? undefined,
      route: context.routePath,
      kind: context.routeType,
    }),
  );
  if (process.env.SENTRY_DSN) {
    const Sentry = await import("@sentry/nextjs");
    Sentry.captureRequestError(err, request, context);
  }
};
