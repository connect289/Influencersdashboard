// M34i: what the server logs when a request fails (instrumentation.ts onRequestError). Pure, unit-tested in
// request-error.test.ts. No personal data: never the error message (a database error can quote a phone number or an
// email), the URL's query string, headers or cookies; the route pattern (/leads/[id]) instead of the concrete path.

export type RequestErrorLine = {
  event: "request_error";
  name: string;
  digest: string | null;
  code: string | null;
  method: string;
  route: string;
  route_type: string;
  router: string;
  render_source: string | null;
};

type ErrorRequest = Readonly<{ path: string; method: string }>;
type ErrorContext = Readonly<{ routerKind: string; routePath: string; routeType: string; renderSource?: string }>;

const short = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.length > 0 ? v.slice(0, max) : typeof v === "number" ? String(v).slice(0, max) : null;

/** A code is kept only when it looks like one (PGRST116, 23505, ECONNRESET), never free text. */
const codeOf = (v: unknown): string | null => {
  const c = short(v, 40);
  return c && /^[A-Za-z0-9_.-]{1,40}$/.test(c) ? c : null;
};

export function requestErrorLine(error: unknown, request: ErrorRequest, context: ErrorContext): RequestErrorLine {
  const e = (typeof error === "object" && error !== null ? error : {}) as { name?: unknown; digest?: unknown; code?: unknown };
  const name = short(e.name, 60);
  return {
    event: "request_error",
    name: name && /^[A-Za-z][A-Za-z0-9_]{0,59}$/.test(name) ? name : "Error",
    digest: codeOf(e.digest),
    code: codeOf(e.code),
    method: /^[A-Z]{3,7}$/.test(request.method) ? request.method : "?",
    route: short(context.routePath, 200) ?? request.path.split("?")[0]!.replace(/\/\d+(?=\/|$)/g, "/[id]").slice(0, 200),
    route_type: context.routeType,
    router: context.routerKind,
    render_source: context.renderSource ?? null,
  };
}
