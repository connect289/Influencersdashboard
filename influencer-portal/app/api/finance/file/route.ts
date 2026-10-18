import { type NextRequest } from "next/server";
import { bucketForPath } from "@/lib/ledger/files";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Opens a finance file (GST invoice, payment advice, Form 16A) after inf.finance_file_allowed() for the caller. */
export async function GET(request: NextRequest) {
  const path = request.nextUrl.searchParams.get("path") ?? "";
  const bucket = bucketForPath(path);
  if (!bucket) return new Response("Not found", { status: 404 });
  const supabase = await createClient();
  const allowed = await supabase.rpc("finance_file_allowed", { p_path: path });
  if (allowed.data !== true) return new Response("Not found", { status: 404 });
  const { data, error } = await adminClient().storage.from(bucket).createSignedUrl(path, 60);
  if (error) return new Response("Not found", { status: 404 });
  return new Response(null, { status: 302, headers: { Location: data.signedUrl, "Cache-Control": "no-store" } });
}
