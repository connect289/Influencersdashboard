import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * The creator's data export (DPDP), built on each download from inf.privacy_export_data and never stored. Only the
 * creator who asked may download it, while the request is ready (7 days).
 */
export async function GET(_request: Request, { params }: { params: Promise<{ requestId: string }> }) {
  const { requestId } = await params;
  if (!z.uuid().safeParse(requestId).success) return new Response("Not found", { status: 404 });
  const allowed = await (await createClient()).rpc("privacy_export_allowed", { p_request: requestId });
  if (allowed.data !== true) return new Response("Not found", { status: 404 });
  const { data, error } = await adminClient().rpc("privacy_export_data", { p_request: requestId });
  if (error || !data) return new Response("Not found", { status: 404 });
  return new Response(JSON.stringify(data, null, 2), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="eduwit-creator-data-${requestId.slice(0, 8)}.json"`,
      "Cache-Control": "no-store",
    },
  });
}
