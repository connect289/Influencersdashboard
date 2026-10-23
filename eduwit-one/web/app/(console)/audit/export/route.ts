import { type NextRequest } from "next/server";
import { toCsv } from "@/lib/csv.ts";
import { assertUser } from "@/lib/session.ts";
import { ui, UiError } from "@/lib/ui/api.ts";
import { aiCallsSchema, auditSchema } from "@/lib/ui/schemas.ts";

// The Audit page's export (spec §12): the same rows the page shows, read with the person's own session (the database
// gate applies), up to 1,000 per file.
export async function GET(request: NextRequest) {
  try {
    await assertUser();
  } catch {
    return new Response("not allowed", { status: 403 });
  }
  const kind = request.nextUrl.searchParams.get("kind") === "ai_calls" ? "ai_calls" : "audit";
  const q = request.nextUrl.searchParams.get("q")?.trim() || null;
  try {
    const args = { p_kind: kind, p_q: q, p_limit: 1000, p_before: null };
    const page = kind === "audit" ? await ui("ui_audit", auditSchema, args) : await ui("ui_audit", aiCallsSchema, args);
    const columns =
      kind === "audit"
        ? ["id", "at", "actor", "action", "target", "request_id", "before", "after"]
        : [
            "id",
            "created_at",
            "provider",
            "model",
            "purpose",
            "input_tokens",
            "output_tokens",
            "cost_usd",
            "cost_inr",
            "latency_ms",
            "ok",
            "error",
          ];
    const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date());
    return new Response(toCsv(page.rows as Array<Record<string, unknown>>, columns), {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="eduwit-one-${kind}-${day}.csv"`,
        "cache-control": "no-store",
      },
    });
  } catch (e) {
    return new Response(e instanceof UiError ? e.message : "export failed", {
      status: e instanceof UiError && e.kind === "not_allowed" ? 403 : 500,
    });
  }
}
