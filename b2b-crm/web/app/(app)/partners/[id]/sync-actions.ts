"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { parseExportText } from "@/lib/sync";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const Note = z.string().trim().min(3).max(300);
export type Result<T = undefined> = { ok: true; data?: T } | { ok: false; error: string };

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function call<T>(partnerId: number, fn: string, args: Record<string, unknown>, fallback: string): Promise<Result<T>> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { ok: false, error: "Invalid partner." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) return { ok: false, error: dbMessage(error, fallback) };
  revalidatePath(`/partners/${partnerId}`);
  revalidatePath("/leads");
  return { ok: true, data: data as T };
}

/** Re-applies a failed or held partner event; returns the new status and result. */
export async function retryEvent(partnerId: number, eventId: number) {
  if (!Id.safeParse(eventId).success) return { ok: false, error: "Invalid event." } as const;
  return call<{ status: string; result: string }>(partnerId, "partner_event_retry", { p_event_id: eventId }, "Could not retry the event. Try again.");
}

export async function discardEvent(partnerId: number, eventId: number, reason: string) {
  if (!Id.safeParse(eventId).success) return { ok: false, error: "Invalid event." } as const;
  if (!Note.safeParse(reason).success) return { ok: false, error: "Give a reason (3 to 300 characters)." } as const;
  return call(partnerId, "partner_event_discard", { p_event_id: eventId, p_reason: reason.trim() }, "Could not discard the event. Try again.");
}

export async function resolveItem(partnerId: number, itemId: number, status: "resolved" | "dismissed", note: string) {
  if (!Id.safeParse(itemId).success || !["resolved", "dismissed"].includes(status)) return { ok: false, error: "Invalid item." } as const;
  if (!Note.safeParse(note).success) return { ok: false, error: "A note is required (3 to 300 characters)." } as const;
  return call(partnerId, "reconciliation_resolve", { p_id: itemId, p_status: status, p_note: note.trim() }, "Could not close the item. Try again.");
}

export type ReconSummary = { run_id: number; new: number; open: number; by_kind: Record<string, number>; export_rows: number | null };

/** Runs reconciliation now; with the partner's export (CSV or JSON text) it also compares the two lists. */
export async function runReconcile(partnerId: number, exportText: string | null) {
  let rows: unknown = null;
  if (exportText !== null) {
    if (exportText.length > 5_000_000) return { ok: false, error: "The export is too large (5 MB at most)." } as const;
    const parsed = parseExportText(exportText);
    if (!parsed.ok) return { ok: false, error: parsed.error } as const;
    rows = parsed.rows;
  }
  return call<ReconSummary>(partnerId, "reconcile_partner_run", { p_partner_id: partnerId, p_export: rows }, "Could not run the comparison. Try again.");
}
