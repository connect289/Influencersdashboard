import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { shortLinkFor } from "@/lib/attribution/short-link";
import { publicEnv } from "@/lib/env-public";
import { avatarUrl } from "@/lib/media-kit/data";
import { rateLimit } from "@/lib/rate-limit";
import { rateIp } from "@/lib/security";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const row = z.object({
  handle: z.string(),
  display_name: z.string(),
  bio: z.string().nullable(),
  avatar_path: z.string().nullable(),
  code: z.string().nullable(),
  featured_programmes: z.array(
    z.object({
      programme_id: z.number(),
      name: z.string().nullable(),
      university: z.string(),
      level: z.string().nullable(),
      mode: z.string().nullable(),
      fee_total_inr: z.number().nullable(),
    }),
  ),
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET",
  "X-Robots-Tag": "noindex",
};

/**
 * Public landing data for the website's co-branded pages (INTEGRATION_CONTRACTS §4): active creators with a public
 * page only; no contact details, legal name, KYC, earnings or follower data. Rate-limited per IP, cached five minutes.
 */
export async function GET(request: NextRequest, { params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  if (!/^[a-z0-9._]{3,30}$/i.test(handle))
    return NextResponse.json({ error: "not_found" }, { status: 404, headers: cors });
  const limited = await rateLimit("public_api", rateIp(request.headers));
  if (!limited.ok)
    return NextResponse.json(
      { error: "rate_limited" },
      { status: 429, headers: { ...cors, "Retry-After": String(limited.retryAfter) } },
    );
  const db = adminClient();
  const { data, error } = await db.rpc("public_creator", { p_handle: handle });
  const c = row.nullable().safeParse(data);
  if (error || !c.success || !c.data) return NextResponse.json({ error: "not_found" }, { status: 404, headers: cors });
  const body = {
    handle: c.data.handle,
    display_name: c.data.display_name,
    photo_url: avatarUrl(publicEnv.supabaseUrl, c.data.avatar_path),
    bio: c.data.bio,
    code: c.data.code,
    featured_programmes: c.data.featured_programmes,
    whatsapp_link: c.data.code ? await shortLinkFor(db, c.data.code) : null,
  };
  return NextResponse.json(body, {
    headers: { ...cors, "Cache-Control": "public, s-maxage=300, stale-while-revalidate=60" },
  });
}
