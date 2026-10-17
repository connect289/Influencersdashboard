import { type NextRequest } from "next/server";
import { resolveRedirect } from "@/lib/attribution/redirect";

export const dynamic = "force-dynamic";

async function handle(request: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const r = await resolveRedirect(code, {
    method: request.method,
    headers: request.headers,
    url: request.url,
  });
  return new Response(null, {
    status: r.status,
    headers: {
      Location: r.location,
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
      "Referrer-Policy": "no-referrer",
    },
  });
}

/** A creator's short link: logs the click and redirects (crawlers get the redirect without a click or access code). */
export const GET = handle;
export const HEAD = handle;
