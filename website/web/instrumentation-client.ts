/**
 * Client observability: Sentry is fetched only when NEXT_PUBLIC_SENTRY_DSN is set at build time (otherwise this file
 * is a no-op and adds nothing to the page), after the page is idle, with PII scrubbing and low sample rates.
 */
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;
if (dsn) {
  const start = () =>
    import("@sentry/nextjs").then((Sentry) =>
      Sentry.init({
        dsn,
        tracesSampleRate: 0.05,
        replaysSessionSampleRate: 0,
        beforeSend(event) {
          if (event.request?.url) event.request.url = event.request.url.split("?")[0];
          event.user = undefined;
          return event;
        },
      }),
    );
  if ("requestIdleCallback" in window) window.requestIdleCallback(() => void start(), { timeout: 4000 });
  else setTimeout(() => void start(), 2000);
}
