import { NextResponse, type NextRequest } from "next/server";
import { loadThread } from "@/lib/messaging/data";
import { threadRef } from "@/lib/messaging/schemas";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** A thread as the caller sees it (the open panel re-reads it while visible); 404 when they may not read it. */
export async function GET(request: NextRequest) {
  const sp = request.nextUrl.searchParams;
  const ref = threadRef.safeParse({
    type: sp.get("type"),
    entityId: sp.get("entity"),
    creatorId: sp.get("creator") || undefined,
  });
  if (!ref.success) return new NextResponse(null, { status: 400 });
  const view = await loadThread(await createClient(), ref.data).catch(() => undefined);
  if (view === undefined) return new NextResponse(null, { status: 500 });
  if (view === null) return new NextResponse(null, { status: 404 });
  return NextResponse.json(view, { headers: { "Cache-Control": "no-store" } });
}
