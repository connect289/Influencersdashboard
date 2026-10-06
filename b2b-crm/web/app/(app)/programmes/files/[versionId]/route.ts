import { NextResponse, type NextRequest } from "next/server";
import { getMe } from "@/lib/auth";
import { fetchFile } from "@/lib/programme-file";
import { programmeVersion } from "@/lib/programmes-data";

export const dynamic = "force-dynamic";

/** GET /programmes/files/<version id>: the partner's original file for that version, as uploaded. Admin only. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ versionId: string }> }) {
  const result = await getMe();
  if ("setupError" in result || !result.me.is_admin) return new NextResponse("Not allowed", { status: 403 });
  const id = (await params).versionId;
  if (!/^\d{1,15}$/.test(id)) return new NextResponse("Not found", { status: 404 });
  const v = await programmeVersion(Number(id)); // re-checks b2b.is_admin()
  if (!v?.file_path) return new NextResponse("Not found", { status: 404 });

  const bytes = await fetchFile(v.file_path).catch(() => null);
  if (!bytes) return new NextResponse("File not available", { status: 404 });
  const ext = v.file_path.endsWith(".csv") ? "csv" : "xlsx";
  const name = (v.file_name ?? `programmes.${ext}`).replace(/[^\w.\- ]+/g, "_").slice(0, 120) || `programmes.${ext}`;
  return new NextResponse(Buffer.from(bytes), {
    headers: {
      "Content-Type": ext === "csv" ? "text/csv; charset=utf-8" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${name}"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
