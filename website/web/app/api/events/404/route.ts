import { z } from "zod";
import { dbConfigured, rpc } from "@/lib/server/db";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { ipFrom } from "@/lib/server/request";

/** 404 monitor beacon (spec 13.4): path and referring host only. */
const body = z.object({ path: z.string().regex(/^\/[^?#\s]{0,300}$/), referrer: z.string().max(200).optional() });

export async function POST(req: Request) {
  const p = body.safeParse(await req.json().catch(() => null));
  if (!p.success || !dbConfigured()) return new Response(null, { status: 204 });
  if (/^\/(api|_next|admin)\//.test(p.data.path)) return new Response(null, { status: 204 });
  if (!(await rateLimit(LIMITS.searchPerIp, ipFrom(req))).ok) return new Response(null, { status: 204 });
  await rpc("web_404_hit", { p_path: p.data.path, p_referrer: p.data.referrer || null }).catch(() => undefined);
  return new Response(null, { status: 204 });
}
