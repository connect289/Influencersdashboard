import "server-only";
import { randomUUID } from "node:crypto";
import { headers } from "next/headers";
import { clientIp } from "@/lib/security";

export interface RequestContext {
  ip: string | null;
  userAgent: string | null;
  requestId: string;
}

/** Facts about the current HTTP request, forwarded to the database for the audit log. */
export async function requestContext(): Promise<RequestContext> {
  const h = await headers();
  const given = h.get("x-request-id");
  return {
    ip: clientIp(h),
    userAgent: h.get("user-agent")?.slice(0, 500) ?? null,
    requestId: given && /^[A-Za-z0-9-]{8,64}$/.test(given) ? given : randomUUID(),
  };
}

/** Headers PostgREST exposes to SQL as request.headers (read by inf.request_ip() and friends). */
export function forwardedHeaders(ctx: RequestContext): Record<string, string> {
  const out: Record<string, string> = { "x-request-id": ctx.requestId };
  if (ctx.ip) out["x-inf-client-ip"] = ctx.ip;
  if (ctx.userAgent) out["x-inf-user-agent"] = ctx.userAgent;
  return out;
}
