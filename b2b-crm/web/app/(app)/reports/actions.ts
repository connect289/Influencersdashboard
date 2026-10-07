"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import type { ReportResult } from "@/lib/analytics-data";
import { ReportDefSchema, type ReportDef } from "@/lib/reports";
import { createClient } from "@/lib/supabase/server";

function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}
async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

export async function runReport(def: ReportDef): Promise<{ ok: true; result: ReportResult } | { ok: false; error: string }> {
  await assertAdmin();
  const p = ReportDefSchema.safeParse(def);
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the report." };
  const { data, error } = await rpc("report_run", { p: p.data });
  if (error) return { ok: false, error: dbMessage(error, "The report failed. Try again.") };
  return { ok: true, result: data as ReportResult };
}

export async function saveReport(id: number | null, name: string, def: ReportDef): Promise<{ ok: true; id: number } | { ok: false; error: string }> {
  await assertAdmin();
  const p = ReportDefSchema.safeParse(def);
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the report." };
  if (!name.trim()) return { ok: false, error: "Give the report a name." };
  const { data, error } = await rpc("report_save", { p: { id, name: name.trim().slice(0, 80), ...p.data } });
  if (error) return { ok: false, error: dbMessage(error, "Could not save the report. Try again.") };
  revalidatePath("/reports");
  return { ok: true, id: (data as { id: number }).id };
}

export async function archiveReport(id: number): Promise<string | void> {
  await assertAdmin();
  if (!z.number().int().positive().safeParse(id).success) return "Invalid report.";
  const { error } = await rpc("report_archive", { p_id: id });
  if (error) return dbMessage(error, "Could not archive. Try again.");
  revalidatePath("/reports");
}
