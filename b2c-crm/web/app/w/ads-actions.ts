"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adRows } from "@/lib/ad-csv";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";

/** Ad spend (spec B13.2): the Admin and Marketing import the platforms' CSV exports and map campaigns to lead sources. */
const WHO = ["admin", "marketing"] as const;

export async function adImport(platform: "meta" | "google", fileName: string, csv: string): Promise<ActionResult<{ rows: number; spend: number }>> {
  await assertUser([...WHO]);
  if (csv.length > 5_000_000) return { ok: false, error: "The file is too large (5 MB at most)." };
  const parsed = adRows(csv);
  if (parsed.missing.length) return { ok: false, error: `The file needs ${parsed.missing.join(" and ")}.` };
  if (!parsed.rows.length) return { ok: false, error: "No rows with a day, a campaign and an amount." };
  if (parsed.guess && parsed.guess !== platform) return { ok: false, error: `This looks like a ${parsed.guess === "meta" ? "Meta" : "Google"} export: choose that platform.` };
  const r = await act(() => rpc<{ rows: number; spend: number }>("ad_spend_import", { p: { platform: z.enum(["meta", "google"]).parse(platform), file_name: fileName.slice(0, 200), rows: parsed.rows } }),
    `${parsed.rows.length} rows read${parsed.skipped ? ` (${parsed.skipped} totals or blank rows skipped)` : ""}. A second import of the same days replaces them.`);
  revalidatePath("/w/money");
  return r;
}

export async function adMap(p: { platform: string; campaign_id: string; lead_source?: string; lead_campaign?: string }): Promise<ActionResult<number>> {
  await assertUser([...WHO]);
  const r = await act(() => rpc<number>("ad_campaign_map_save", { p: { platform: p.platform, campaign_id: p.campaign_id, lead_source: p.lead_source ?? null, lead_campaign: p.lead_campaign ?? null } }),
    "Campaign mapped. Its leads count from now on in every period.");
  revalidatePath("/w/money");
  return r;
}
