import { NextResponse } from "next/server";
import { loadUnreadCounts } from "@/lib/messaging/data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * The signed-in person's unread counts for the header bell. A route handler rather than a server action so the bell's
 * background checks never hold up navigation (the router runs server actions and navigations in one queue).
 */
export async function GET() {
  const counts = await loadUnreadCounts(await createClient());
  return NextResponse.json(counts, { headers: { "Cache-Control": "no-store" } });
}
