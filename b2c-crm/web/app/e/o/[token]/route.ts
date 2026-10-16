import { NextResponse, type NextRequest } from "next/server";
import { adminClient } from "@/lib/supabase/admin";
import { decodeLink } from "@/lib/tokens";

export const dynamic = "force-dynamic";
const GIF = Buffer.from("R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==", "base64");

/** Open pixel of a marketing email: the open is recorded (and scored); always answers with a 1×1 image. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const l = decodeLink((await params).token);
  if (l?.kind === "open") await adminClient().rpc("email_event", { p_email: l.email, p_kind: "open", p_link: null }).then(() => undefined, () => undefined);
  return new NextResponse(GIF, { headers: { "content-type": "image/gif", "cache-control": "no-store, max-age=0" } });
}
