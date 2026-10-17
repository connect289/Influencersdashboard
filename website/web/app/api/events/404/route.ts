import { z } from "zod";
import { dbConfigured, rpc } from "@/lib/server/db";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { ipFrom } from "@/lib/server/request";
import { scrubString } from "@/lib/security/scrub";

/** 404 monitor beacon (spec 13.4): path and referring host only. */
const body = z.object({
  path: z.string().regex(/^\/[^?#\s\\]{0,300}$/),
  // the referring host only (the beacon never sends a full URL); anything else is dropped
  referrer: z.string().max(200).optional(),
});
const HOST = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/i;

export async function POST(req: Request) {
  const p = body.safeParse(await req.json().catch(() => null));
  if (!p.success || !dbConfigured()) return new Response(null, { status: 204 });
  if (/^\/(api|_next|admin)\//.test(p.data.path)) return new Response(null, { status: 204 });
  if (!(await rateLimit(LIMITS.beaconPerIp, ipFrom(req))).ok) return new Response(null, { status: 204 });
  const path = scrubString(p.data.path);
  const referrer = p.data.referrer && HOST.test(p.data.referrer) ? p.data.referrer.toLowerCase() : null;
  await rpc("web_404_hit", { p_path: path, p_referrer: referrer }).catch(() => undefined);
  return new Response(null, { status: 204 });
}
