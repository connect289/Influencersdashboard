import { NextResponse, type NextRequest } from "next/server";
import { publicEnv } from "@/lib/env-public";
import { errorMessage, log } from "@/lib/log";
import { avatarUrl, mediaKitFileName, mediaKitSchema } from "@/lib/media-kit/data";
import { pdfLabels } from "@/lib/media-kit/labels";
import { renderMediaKitPdf } from "@/lib/media-kit/pdf";
import { rateLimit } from "@/lib/rate-limit";
import { rateIp } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

/** Public media-kit PDF (only when the creator turned on their public page). */
export async function GET(request: NextRequest, { params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  if (!/^[a-z0-9._]{3,30}$/i.test(handle)) return new NextResponse("Not found", { status: 404 });
  if (!(await rateLimit("public_api", rateIp(request.headers))).ok)
    return new NextResponse("Too many requests", { status: 429, headers: { "retry-after": "60" } });
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("media_kit_public", { p_handle: handle });
  const kit = error ? null : mediaKitSchema.safeParse(data);
  if (!kit?.success) return new NextResponse("Not found", { status: 404 });
  try {
    const pdf = await renderMediaKitPdf(
      kit.data,
      await pdfLabels(),
      avatarUrl(publicEnv.supabaseUrl, kit.data.avatar_path),
    );
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "content-type": "application/pdf",
        "content-disposition": `inline; filename="${mediaKitFileName(kit.data.handle)}"`,
        "cache-control": "public, max-age=300",
      },
    });
  } catch (e) {
    log.error("media_kit.pdf_failed", { error: errorMessage(e) });
    return new NextResponse("Could not create the PDF", { status: 500 });
  }
}
