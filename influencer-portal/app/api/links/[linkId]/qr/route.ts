import { type NextRequest } from "next/server";
import QRCode from "qrcode";
import { z } from "zod";
import { shortLinkFor } from "@/lib/attribution/short-link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** The QR code of a link's short URL, as PNG or SVG, for anyone who may see the link (RLS decides). */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ linkId: string }> },
) {
  const { linkId } = await params;
  if (!z.uuid().safeParse(linkId).success) return new Response("Not found", { status: 404 });
  const format = request.nextUrl.searchParams.get("format") === "svg" ? "svg" : "png";
  const supabase = await createClient();
  const { data: link } = await supabase
    .from("tracking_links")
    .select("code")
    .eq("id", linkId)
    .maybeSingle();
  if (!link) return new Response("Not found", { status: 404 });
  const url = await shortLinkFor(supabase, link.code);
  const options = {
    errorCorrectionLevel: "M" as const,
    margin: 2,
    color: { dark: "#0b2545", light: "#ffffff" },
  };
  const headers = {
    "Content-Disposition": `attachment; filename="${link.code}.${format}"`,
    "Cache-Control": "private, max-age=3600",
  };
  if (format === "svg")
    return new Response(await QRCode.toString(url, { ...options, type: "svg" }), {
      headers: { ...headers, "Content-Type": "image/svg+xml" },
    });
  const png = await QRCode.toBuffer(url, { ...options, type: "png", width: 1024 });
  return new Response(new Uint8Array(png), {
    headers: { ...headers, "Content-Type": "image/png" },
  });
}
