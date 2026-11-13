import { scrubString } from "./scrub";

/**
 * The one log line for an unhandled request error (instrumentation.ts onRequestError): structured JSON, no personal
 * data (message and path scrubbed, no query string, headers, cookies or body), bounded size. Pure, so it is tested.
 */
export interface RequestErrorInfo {
  path: string;
  method: string;
  headers: Record<string, string | string[] | undefined>;
}
export interface RequestErrorContext {
  routePath?: string;
  routeType?: string;
  routerKind?: string;
  renderSource?: string;
}

const REQUEST_ID = /^[\w-]{1,100}$/;

export function requestErrorLine(
  err: unknown,
  request: RequestErrorInfo,
  context: RequestErrorContext,
  now = new Date(),
): string {
  const e = err instanceof Error ? err : null;
  const digest =
    typeof err === "object" && err !== null && "digest" in err
      ? String((err as { digest: unknown }).digest).slice(0, 64)
      : undefined;
  const rid = request.headers["x-request-id"];
  const requestId = typeof rid === "string" && REQUEST_ID.test(rid) ? rid : undefined;
  return JSON.stringify({
    t: now.toISOString(),
    level: "error",
    event: "request.error",
    error: e ? e.name.slice(0, 60) : typeof err,
    message: scrubString(e ? e.message : String(err)).slice(0, 500),
    digest,
    path: scrubString(request.path.split("?")[0] ?? "").slice(0, 200),
    method: request.method,
    requestId,
    route: context.routePath,
    kind: context.routeType,
    router: context.routerKind,
    source: context.renderSource,
  });
}
