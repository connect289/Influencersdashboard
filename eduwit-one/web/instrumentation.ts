import type { Instrumentation } from "next";
import { createErrorReporter, reportingEnabled } from "./lib/error-report.ts";
import { log } from "./lib/log.ts";
import { logRequestError, requestErrorInfo } from "./lib/request-error.ts";

// The counts of those errors go to the database (one.app_error_report, migration 0041, D-141), where the check ONE-ERR
// reads them: in the background, at most once a minute, only from a deployment (a production build with a hosted
// Supabase address and the service key), and never in a way that can fail a request (lib/error-report.ts). The
// service client is loaded when the first report is sent, not with this file.
const reporter = createErrorReporter({
  enabled: () =>
    reportingEnabled({
      nodeEnv: process.env.NODE_ENV,
      url: process.env.ONE_SUPABASE_URL,
      serviceKey: process.env.ONE_SUPABASE_SERVICE_KEY,
    }),
  send: async (items, signal) => {
    const { SupabaseOneDb } = await import("./lib/db.ts");
    const db = SupabaseOneDb.fromEnv();
    if (!db) throw Object.assign(new Error("no database client"), { code: "not_configured" });
    await db.appErrorReport(items, signal);
  },
  onFailure: (code) => log("warn", "app.error_report_failed", { code }),
});

// Next calls this for every error a page, route, server action or the middleware throws on the server (D-137): one
// structured, contact-free line in the platform's logs (lib/request-error.ts), then the count (D-141). No external
// service.
export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  logRequestError(error, request, context);
  try {
    const info = requestErrorInfo(error, request, context);
    reporter.record({
      route: info.route,
      name: info.name,
      message: info.message,
      digest: info.digest,
      kind: info.kind,
    });
  } catch {
    // nothing more to do
  }
};
