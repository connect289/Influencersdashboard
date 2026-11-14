import type { Instrumentation } from "next";
import { createErrorReporter, reportingEnabled } from "@/lib/error-report";
import { requestErrorLine } from "@/lib/request-error";

// Audit M11 (13 Nov 2026): the count of failed requests also goes to Eduwit One (one.app_error_report; its check B2B-ERR
// alerts when there are too many). lib/error-report.ts says what is sent and when: route pattern, error name, digest
// and render kind, as the log line below; at most one call a minute, in the background, only from a deployment (a
// production build with a hosted Supabase address and the service key). The service client is loaded on the first send.
const reporter = createErrorReporter({
  enabled: () =>
    reportingEnabled({
      nodeEnv: process.env.NODE_ENV,
      url: process.env.NEXT_PUBLIC_SUPABASE_URL,
      serviceKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    }),
  send: async (items, signal) => {
    const { adminClient } = await import("@/lib/supabase/admin");
    const { error } = await adminClient()
      .schema("one")
      .rpc("app_error_report", { p_app: "b2b", p_items: items })
      .abortSignal(signal);
    if (error) throw Object.assign(new Error("app_error_report failed"), { code: error.code });
  },
  onFailure: (code) => console.warn(JSON.stringify({ event: "error_report_failed", code })),
});

/** M34i: one JSON line per failed server request, with no personal data (lib/request-error.ts says what is left out). */
export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  const line = requestErrorLine(error, request, context);
  console.error(JSON.stringify(line));
  reporter.record({ route: line.route, name: line.name, digest: line.digest, kind: line.route_type });
};
