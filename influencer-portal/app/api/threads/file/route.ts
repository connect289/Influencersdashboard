import { type NextRequest } from "next/server";
import { THREADS_BUCKET } from "@/lib/messaging/files";
import { attachment } from "@/lib/messaging/schemas";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Opens a message attachment after inf.thread_file_allowed() confirms the caller may read its thread. */
export async function GET(request: NextRequest) {
  const path = request.nextUrl.searchParams.get("path") ?? "";
  if (!attachment.shape.path.safeParse(path).success) return new Response("Not found", { status: 404 });
  const supabase = await createClient();
  const allowed = await supabase.rpc("thread_file_allowed", { p_path: path });
  if (allowed.data !== true) return new Response("Not found", { status: 404 });
  const { data, error } = await adminClient().storage.from(THREADS_BUCKET).createSignedUrl(path, 60);
  if (error) return new Response("Not found", { status: 404 });
  return new Response(null, { status: 302, headers: { Location: data.signedUrl, "Cache-Control": "no-store" } });
}
