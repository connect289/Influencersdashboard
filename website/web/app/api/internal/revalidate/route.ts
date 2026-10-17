import { revalidateTag } from "next/cache";
import { NextResponse } from "next/server";
import { z } from "zod";
import { isInternal } from "@/lib/server/internal-auth";

const body = z.object({ tags: z.array(z.string().regex(/^[a-z0-9:_-]{1,120}$/)).min(1).max(50) });

/** POST /api/internal/revalidate {tags} — marks cached data stale (catalogue refresh, admin edits). Bearer-protected. */
export async function POST(req: Request) {
  if (!isInternal(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const parsed = body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "bad_request" }, { status: 400 });
  for (const t of parsed.data.tags) revalidateTag(t, "max");
  return NextResponse.json({ ok: true, revalidated: parsed.data.tags });
}
