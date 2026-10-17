import { type NextRequest } from "next/server";
import { z } from "zod";
import { toCsv } from "@/lib/csv";
import { loadFeed, parseFilters } from "@/lib/leads/data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const COLUMNS = [
  "lead_ref",
  "display_name",
  "phone_masked",
  "email_masked",
  "creator_stage",
  "reason_category",
  "temperature",
  "attribution_status",
  "code",
  "campaign_name",
  "deal_title",
  "deliverable_title",
  "lead_at",
] as const;
const FIELDS = [
  "city",
  "state",
  "interested_course",
  "interested_university",
  "program_level",
  "enrollment_timeline",
] as const;

/** CSV of a creator's leads with the same fields and masking as the screen (RLS decides whose rows come back). */
export async function GET(request: NextRequest) {
  const creator = request.nextUrl.searchParams.get("creator") ?? "";
  if (!z.uuid().safeParse(creator).success) return new Response("Not found", { status: 404 });
  const supabase = await createClient();
  const sp = Object.fromEntries(request.nextUrl.searchParams.entries());
  const rows = await loadFeed(supabase, creator, parseFilters(sp), 5000).catch(() => null);
  if (rows === null) return new Response("Not found", { status: 404 });
  const csv = toCsv(
    [...COLUMNS, ...FIELDS],
    rows.map((r) => [...COLUMNS.map((c) => r[c]), ...FIELDS.map((f) => r.fields[f] ?? null)]),
  );
  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="leads-${new Date().toISOString().slice(0, 10)}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
