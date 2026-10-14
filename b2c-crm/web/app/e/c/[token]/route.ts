import { NextResponse, type NextRequest } from "next/server";
import { siteUrl } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";
import { decodeLink } from "@/lib/tokens";

export const dynamic = "force-dynamic";

/** A tracked link in a marketing email: recorded (an "I'm interested" click re-engages the lead), then on to the
 *  destination the signed token carries. Never redirects anywhere a token does not name. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const l = decodeLink((await params).token);
  if (!l || l.kind !== "click" || !/^https:\/\//.test(l.url)) return NextResponse.redirect(new URL("/thanks?link=expired", siteUrl()));
  await adminClient().rpc("email_event", { p_email: l.email, p_kind: "click", p_link: l.link }).then(() => undefined, () => undefined);
  return NextResponse.redirect(l.url, { headers: { "cache-control": "no-store" } });
}
