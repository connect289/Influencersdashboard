import { NextResponse, type NextRequest } from "next/server";
import { siteUrl } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";
import { decodeLink } from "@/lib/tokens";

export const dynamic = "force-dynamic";

/** One-click unsubscribe (RFC 8058, the List-Unsubscribe-Post header): the mail app posts here; email marketing stops. */
export async function POST(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const l = decodeLink((await params).token);
  if (!l || l.kind !== "unsubscribe") return NextResponse.json({ ok: false }, { status: 400 });
  const { error } = await adminClient().rpc("opt_out", { p_lead: l.lead, p_channels: l.channel === "all" ? null : ["email"], p_source: "unsubscribe_link", p_note: "one-click" });
  return NextResponse.json({ ok: !error }, { status: error ? 500 : 200 });
}

/** A person who opens the link: the page that asks. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  return NextResponse.redirect(new URL(`/u/${(await params).token}`, siteUrl()));
}
