import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { isSameOrigin } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Marks notifications read when opened from the centre (before navigating to them). Same-origin JSON only. */
export async function POST(request: NextRequest) {
  if (
    !isSameOrigin(request.headers.get("origin"), request.headers.get("x-forwarded-host") ?? request.headers.get("host"))
  )
    return new NextResponse(null, { status: 403 });
  const body = z.object({ ids: z.array(z.uuid()).min(1).max(100) }).safeParse(await request.json().catch(() => null));
  if (!body.success) return new NextResponse(null, { status: 400 });
  const { error } = await (await createClient()).rpc("notifications_mark_read", { p_ids: body.data.ids });
  return new NextResponse(null, { status: error ? 500 : 204 });
}
