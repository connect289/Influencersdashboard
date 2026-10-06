"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { parseSchemaText } from "@/lib/mapping";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const Note = z.string().trim().min(3).max(500);
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
  revalidatePath(`/mapping/${partnerId}`);
  revalidatePath("/mapping");
  return { ok: true, data: data as T };
}

export async function startDraft(partnerId: number) {
  return call<number>(partnerId, "mapping_draft_start", { p_partner_id: partnerId }, "Could not start a draft. Try again.");
}

export async function discardDraft(partnerId: number, profileId: number) {
  if (!Id.safeParse(profileId).success) return { ok: false, error: "Invalid draft." } as const;
  return call(partnerId, "mapping_draft_discard", { p_profile_id: profileId }, "Could not discard the draft. Try again.");
}

export async function publishDraft(partnerId: number, profileId: number, note: string) {
  if (!Id.safeParse(profileId).success) return { ok: false, error: "Invalid draft." } as const;
  if (!Note.safeParse(note).success) return { ok: false, error: "Say what changed (3 to 500 characters)." } as const;
  return call<{ version: number; queue_resolved: number; reprocess: { reprocessed: number; applied: number } }>(
    partnerId, "mapping_publish", { p_profile_id: profileId, p_note: note.trim() }, "Could not publish. Try again.");
}

export async function restoreVersion(partnerId: number, profileId: number, reason: string) {
  if (!Id.safeParse(profileId).success) return { ok: false, error: "Invalid version." } as const;
  if (!Note.safeParse(reason).success) return { ok: false, error: "A reason is required." } as const;
  return call<{ version: number }>(partnerId, "mapping_restore", { p_profile_id: profileId, p_reason: reason.trim() }, "Could not restore. Try again.");
}

const Kind = z.enum(["status", "field", "value", "activity", "pipeline"]);

/** Saves a rule on the draft. The payload is validated again, in full, by b2b.mapping_rule_save. */
export async function saveRule(partnerId: number, kind: string, payload: Record<string, unknown>) {
  if (!Kind.safeParse(kind).success) return { ok: false, error: "Unknown rule." } as const;
  if (!Id.safeParse(payload.profile_id).success) return { ok: false, error: "Start a draft first." } as const;
  return call<number>(partnerId, "mapping_rule_save", { p_kind: kind, p: payload }, "Could not save the rule. Try again.");
}

export async function removeRule(partnerId: number, kind: string, id: number) {
  if (!Kind.safeParse(kind).success || !Id.safeParse(id).success) return { ok: false, error: "Unknown rule." } as const;
  return call<number>(partnerId, "mapping_rule_remove", { p_kind: kind, p_id: id }, "Could not remove the rule. Try again.");
}

export async function savePipelineField(partnerId: number, profileId: number, field: string) {
  if (!Id.safeParse(profileId).success) return { ok: false, error: "Start a draft first." } as const;
  return call(partnerId, "mapping_profile_settings", { p_profile_id: profileId, p_pipeline_field: field }, "Could not save. Try again.");
}

export async function testInbound(partnerId: number, profileId: number, kind: string, sample: string) {
  if (!Id.safeParse(profileId).success) return { ok: false, error: "There is no mapping to test yet." } as const;
  let data: unknown;
  try { data = JSON.parse(sample); } catch { return { ok: false, error: "The sample is not valid JSON." } as const; }
  return call<Record<string, unknown>>(partnerId, "mapping_test", { p_profile_id: profileId, p_kind: kind, p_data: data }, "Could not run the test. Try again.");
}

export async function testOutbound(partnerId: number, profileId: number, leadId: number) {
  if (!Id.safeParse(profileId).success || !Id.safeParse(leadId).success) return { ok: false, error: "Give a lead number." } as const;
  return call<Record<string, unknown>>(partnerId, "mapping_test_out", { p_profile_id: profileId, p_lead_id: leadId }, "Could not run the test. Try again.");
}

export async function saveGolden(partnerId: number, name: string, input: string, expected: string) {
  let i: unknown, e: unknown;
  try { i = JSON.parse(input); e = JSON.parse(expected); } catch { return { ok: false, error: "Input and expected result must be JSON." } as const; }
  return call<number>(partnerId, "mapping_golden_save", { p_partner_id: partnerId, p_name: name, p_input: i, p_expected: e }, "Could not save the golden file. Try again.");
}

export async function archiveGolden(partnerId: number, id: number) {
  if (!Id.safeParse(id).success) return { ok: false, error: "Unknown golden file." } as const;
  return call(partnerId, "mapping_golden_archive", { p_id: id }, "Could not remove the golden file. Try again.");
}

export async function resolveQueue(partnerId: number, id: number, status: "ignored" | "open", note: string) {
  if (!Id.safeParse(id).success || !["ignored", "open"].includes(status)) return { ok: false, error: "Unknown item." } as const;
  return call(partnerId, "mapping_queue_resolve", { p_id: id, p_status: status, p_note: note }, "Could not update the item. Try again.");
}

export async function saveSnapshot(partnerId: number, source: "upload" | "events", text: string | null, discovered?: unknown) {
  let schema: unknown = discovered;
  if (source === "upload") {
    const p = parseSchemaText(text ?? "");
    if (!p.ok) return { ok: false, error: p.error } as const;
    schema = p.schema;
  }
  return call<{ id: number; drift: unknown[] }>(partnerId, "mapping_snapshot_save", { p_partner_id: partnerId, p_source: source, p_schema: schema },
    "Could not save the schema. Try again.");
}

export async function runBackfill(partnerId: number, reason: string) {
  if (!Note.safeParse(reason).success) return { ok: false, error: "A reason is required." } as const;
  return call<number>(partnerId, "mapping_backfill", { p_partner_id: partnerId, p_reason: reason.trim() }, "Could not apply the correction. Try again.");
}
