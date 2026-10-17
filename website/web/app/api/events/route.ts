import { z } from "zod";
import { dbConfigured, rpc } from "@/lib/server/db";
import { ipFrom } from "@/lib/server/request";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { funnelContext } from "@/lib/analytics/events";

/** Funnel counters for the admin insights (spec 11). Anonymous; no personal data accepted or stored. */
const body = z.object({
  funnel: z.enum(["gate", "form", "enquiry", "finder"]),
  step: z.string().regex(/^[a-z][a-z0-9_]{1,40}$/),
  anon: z
    .string()
    .min(8)
    .max(64)
    .regex(/^[\w-]+$/),
  context: z.record(z.string(), z.union([z.string().max(100), z.number(), z.boolean()])).optional(),
});

export async function POST(req: Request) {
  const parsed = body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return new Response(null, { status: 204 });
  const rl = await rateLimit(LIMITS.beaconPerIp, ipFrom(req));
  if (!rl.ok || !dbConfigured()) return new Response(null, { status: 204 });
  try {
    await rpc("web_funnel_track", {
      p_funnel: parsed.data.funnel,
      p_step: parsed.data.step,
      p_anon_id: parsed.data.anon,
      p_context: funnelContext(parsed.data.funnel, parsed.data.step, parsed.data.context),
    });
  } catch {
    // analytics never fails the client
  }
  return new Response(null, { status: 204 });
}
