import "server-only";
import { headers } from "next/headers";

/** Request context: id (propagated by proxy.ts) and the client IP for rate limiting only (never stored raw). */
export async function requestContext(): Promise<{ requestId: string; ip: string; userAgent: string }> {
  const h = await headers();
  return {
    requestId: h.get("x-request-id") ?? crypto.randomUUID(),
    ip: (h.get("x-forwarded-for")?.split(",")[0] ?? h.get("x-real-ip") ?? "0.0.0.0").trim(),
    userAgent: h.get("user-agent") ?? "",
  };
}

export function ipFrom(req: Request): string {
  return (req.headers.get("x-forwarded-for")?.split(",")[0] ?? req.headers.get("x-real-ip") ?? "0.0.0.0").trim();
}
