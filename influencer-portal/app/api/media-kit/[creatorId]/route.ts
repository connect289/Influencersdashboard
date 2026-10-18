import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { publicEnv } from "@/lib/env-public";
import { errorMessage, log } from "@/lib/log";
import { avatarUrl, mediaKitFileName, mediaKitSchema } from "@/lib/media-kit/data";
import { pdfLabels } from "@/lib/media-kit/labels";
import { renderMediaKitPdf } from "@/lib/media-kit/pdf";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

/**
 * Internal media-kit PDF (includes the rate card) for the creator, staff with creator.read and agencies with "view".
 * Access is decided by inf.media_kit().
 */
export async function GET(_: NextRequest, { params }: { params: Promise<{ creatorId: string }> }) {
  const { creatorId } = await params;
  if (!z.uuid().safeParse(creatorId).success) return new NextResponse("Not found", { status: 404 });
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) return new NextResponse("Sign in required", { status: 401 });
  const { data, error } = await supabase.rpc("media_kit", { p_creator: creatorId });
  if (error)
    return new NextResponse(error.code === "42501" ? "Not found" : "Error", {
      status: error.code === "42501" ? 404 : 500,
    });
  const kit = mediaKitSchema.safeParse(data);
  if (!kit.success) return new NextResponse("Not found", { status: 404 });
  try {
    const pdf = await renderMediaKitPdf(
      kit.data,
      await pdfLabels(),
      avatarUrl(publicEnv.supabaseUrl, kit.data.avatar_path),
    );
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "content-type": "application/pdf",
        "content-disposition": `attachment; filename="${mediaKitFileName(kit.data.handle)}"`,
        "cache-control": "private, no-store",
      },
    });
  } catch (e) {
    log.error("media_kit.pdf_failed", { error: errorMessage(e) });
    return new NextResponse("Could not create the PDF", { status: 500 });
  }
}
