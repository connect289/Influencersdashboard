import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { CONTRACTS_BUCKET, sha256Hex } from "@/lib/contracts/finalize";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const integrity = z.object({
  ok: z.boolean(),
  number: z.string(),
  file_path: z.string().nullable(),
  file_sha256: z.string().nullable(),
});

/**
 * The signed contract PDF, for anyone who may open the contract (inf.contract_integrity decides). Every download
 * re-verifies the hashes (spec 8.4): the stored document against the hash every signature recorded, and the stored
 * PDF against the hash recorded when it was made. Any mismatch flags the contract as invalid and nothing is served.
 */
export async function GET(_: NextRequest, { params }: { params: Promise<{ contractId: string }> }) {
  const { contractId } = await params;
  if (!z.uuid().safeParse(contractId).success)
    return new NextResponse("Not found", { status: 404 });
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) return new NextResponse("Sign in required", { status: 401 });
  const { data, error } = await supabase.rpc("contract_integrity", { p_contract: contractId });
  if (error) return new NextResponse("Error", { status: 500 });
  const r = integrity.safeParse(data);
  if (!r.success) return new NextResponse("Not found", { status: 404 });
  if (!r.data.ok)
    return new NextResponse("This contract failed its integrity check and is flagged as invalid.", {
      status: 409,
    });
  if (!r.data.file_path || !r.data.file_sha256)
    return new NextResponse("The signed PDF isn't ready yet. Try again in a minute.", {
      status: 404,
    });
  try {
    const dl = await adminClient().storage.from(CONTRACTS_BUCKET).download(r.data.file_path);
    if (dl.error) throw new Error(dl.error.message);
    const bytes = new Uint8Array(await dl.data.arrayBuffer());
    if (sha256Hex(bytes) !== r.data.file_sha256) {
      await adminClient().rpc("contract_flag", {
        p_contract: contractId,
        p_reason: "stored PDF hash mismatch",
      });
      log.error("contracts.pdf_hash_mismatch", { contract_id: contractId });
      return new NextResponse(
        "This contract failed its integrity check and is flagged as invalid.",
        { status: 409 },
      );
    }
    return new NextResponse(bytes, {
      headers: {
        "content-type": "application/pdf",
        "content-disposition": `attachment; filename="${r.data.number}.pdf"`,
        "cache-control": "private, no-store",
        "x-content-sha256": r.data.file_sha256,
      },
    });
  } catch (e) {
    log.error("contracts.pdf_download_failed", { error: errorMessage(e) });
    return new NextResponse("Could not fetch the PDF", { status: 500 });
  }
}
