import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { isSameOrigin } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Marks a thread read for the caller (and clears its message notifications). Same-origin JSON only. */
export async function POST(request: NextRequest) {
  if (
    !isSameOrigin(request.headers.get("origin"), request.headers.get("x-forwarded-host") ?? request.headers.get("host"))
  )
    return new NextResponse(null, { status: 403 });
  const body = z.object({ threadId: z.uuid() }).safeParse(await request.json().catch(() => null));
  if (!body.success) return new NextResponse(null, { status: 400 });
  const { error } = await (await createClient()).rpc("thread_mark_read", { p_thread: body.data.threadId });
  return new NextResponse(null, { status: error ? (error.code === "42501" ? 403 : 500) : 204 });
}
