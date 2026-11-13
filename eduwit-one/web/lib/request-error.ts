import { maskText } from "./ai/pii.ts";
import { log } from "./log.ts";

// One structured line for every error a page, route, server action or the middleware throws (instrumentation.ts,
// D-137): the route as its file names it (`/incidents/[id]`, never the address with its ids or query), the method, the
// kind of render, Next's digest (the id the error page shows the person), and the error's name and message, masked as
// the AI's input is (phones, emails) and cut to 200 characters. No headers, cookies, body or stack. No external service
// (the owner's decision: no Sentry for now); the platform's logs keep the line.
//
// Not recorded in the database: the app's service role holds no table privilege in schema one and reaches it only
// through the functions in one.api_grants (D-055), none of which writes an event, so an "app.error" event would need a
// new SECURITY DEFINER function, which this change does not add.

export const MESSAGE_MAX = 200;

export type RequestErrorInfo = {
  route: string;
  method: string;
  kind: string;
  router: string;
  digest: string | null;
  name: string;
  message: string;
};

export function requestErrorInfo(
  error: unknown,
  request: Readonly<{ method: string }>,
  context: Readonly<{ routePath: string; routeType: string; routerKind: string }>,
): RequestErrorInfo {
  const e =
    typeof error === "object" && error !== null
      ? (error as { name?: unknown; message?: unknown; digest?: unknown })
      : {};
  const raw = typeof e.message === "string" ? e.message : typeof error === "string" ? error : "";
  const masked = maskText(raw.replace(/\s+/g, " ").trim());
  return {
    route: context.routePath.slice(0, 200),
    method: request.method.slice(0, 10),
    kind: context.routeType,
    router: context.routerKind,
    digest: typeof e.digest === "string" ? e.digest.slice(0, 64) : null,
    name: (typeof e.name === "string" && e.name ? e.name : "Error").slice(0, 60),
    message: masked.length > MESSAGE_MAX ? `${masked.slice(0, MESSAGE_MAX)}…` : masked,
  };
}

/** Writes the line; never throws, so reporting an error cannot become a second one. */
export function logRequestError(
  error: unknown,
  request: Readonly<{ method: string }>,
  context: Readonly<{ routePath: string; routeType: string; routerKind: string }>,
): void {
  try {
    log("error", "app.error", requestErrorInfo(error, request, context));
  } catch {
    // nothing more to do
  }
}
