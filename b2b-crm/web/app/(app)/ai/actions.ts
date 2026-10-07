"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { AI_PRICE_KEYS, AiSettingsSchema, aiSettingsPayload, editedChange, MlSettingsSchema, mlSettingsPayload, RUN_NOW_KINDS, type Change } from "@/lib/ai/labels";
import { createClient } from "@/lib/supabase/server";
import { ask, ASK_PROMPT_VERSION, type AskSource } from "@/lib/ai/ask";
import { anthropicMessages } from "@/lib/ai/worker";

const Id = z.number().int().positive();
const Reason = z.string().trim().min(3).max(500);

/** Messages raised for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}
async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}
const refresh = () => { revalidatePath("/ai"); revalidatePath("/routing"); };

export async function decideRecommendation(id: number, decision: "approve" | "reject", note: string, change: Change | null, typed?: string): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success || !["approve", "reject"].includes(decision)) return "Invalid request.";
  if (decision === "reject" && !Reason.safeParse(note).success) return "Say why you reject it (3 characters or more).";
  let edited: Change | null = null;
  if (decision === "approve" && change && typed !== undefined && typed.trim() !== "") {
    const e = editedChange(change, typed);
    if (typeof e === "string") return e;
    edited = e;
  }
  const { error } = await rpc("ai_recommendation_decide", { p_id: id, p_decision: decision, p_note: note.trim().slice(0, 500), p_change: edited });
  if (error) return dbMessage(error, "Could not save your decision. Try again.");
  refresh();
}

export async function rollbackRecommendation(id: number, reason: string): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid request.";
  if (!Reason.safeParse(reason).success) return "Say why you roll it back.";
  const { error } = await rpc("ai_recommendation_rollback", { p_id: id, p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not roll back. Try again.");
  refresh();
}

export async function runNow(kind: string, reason: string): Promise<string | void> {
  await assertAdmin();
  if (!(RUN_NOW_KINDS as readonly string[]).includes(kind)) return "Unknown kind of run.";
  if (!Reason.safeParse(reason).success) return "Say why (3 characters or more).";
  const { error } = await rpc("ai_run_now", { p_kind: kind, p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not queue the run. Try again.");
  refresh();
}

export type FormState = { errors?: Record<string, string>; error?: string; ok?: number } | undefined;

export async function saveAiSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const keys = ["enabled", "mode", "min_gain_pct", "max_per_day", "daily_budget_usd", "worker_url", "model_regular", "model_deep", "model_quick", "light", "hourly", "nightly", "weekly",
                ...AI_PRICE_KEYS, "reason"];
  const p = AiSettingsSchema.safeParse(Object.fromEntries(keys.map((k) => [k, form.get(k) ?? undefined])));
  if (!p.success) {
    const errors: Record<string, string> = {};
    for (const i of p.error.issues) errors[String(i.path[0])] ??= i.message;
    return { errors, error: "Check the highlighted fields." };
  }
  const { error } = await rpc("ai_settings_save", { p: aiSettingsPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the settings. Try again.") };
  refresh();
  return { ok: Date.now() };
}

// ---------- model registry (M25) ----------

export async function trainModel(reason: string): Promise<string | void> {
  await assertAdmin();
  if (!Reason.safeParse(reason).success) return "Say why (3 characters or more).";
  const { error } = await rpc("ml_train_request", { p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not queue training. Try again.");
  refresh();
}

export async function setModelStatus(id: number, status: "challenger" | "champion" | "shadow" | "retired", reason: string): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success || !["challenger", "champion", "shadow", "retired"].includes(status)) return "Invalid request.";
  if (!Reason.safeParse(reason).success) return "Say why (3 characters or more).";
  const { error } = await rpc("ml_set_status", { p_id: id, p_status: status, p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not change the model. Try again.");
  refresh();
}

export async function rollbackModel(reason: string): Promise<string | void> {
  await assertAdmin();
  if (!Reason.safeParse(reason).success) return "Say why (3 characters or more).";
  const { error } = await rpc("ml_rollback", { p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not roll back. Try again.");
  refresh();
}

export async function saveMlSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const keys = ["min_outcomes", "challenger_pct", "ece_fallback", "train_hour_ist", "auto_train", "reason"];
  const p = MlSettingsSchema.safeParse(Object.fromEntries(keys.map((k) => [k, form.get(k) ?? undefined])));
  if (!p.success) { const errors: Record<string, string> = {}; for (const i of p.error.issues) errors[String(i.path[0])] ??= i.message; return { errors, error: "Check the highlighted fields." }; }
  const { error } = await rpc("ml_settings_save", { p: mlSettingsPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the model settings. Try again.") };
  refresh();
  return { ok: Date.now() };
}

// ---------- Ask the CRM ----------
export type AskAnswer = { ok: true; answer: string | null; sources: AskSource[]; unverified: string[]; cost_usd: number; error?: string } | { ok: false; error: string };

export async function askCrm(question: string): Promise<AskAnswer> {
  await assertAdmin();
  const q = question.trim();
  if (q.length < 5 || q.length > 500) return { ok: false, error: "Ask a question of 5 to 500 characters." };
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return { ok: false, error: "The Anthropic API key is not set on the server yet (ANTHROPIC_API_KEY)." };
  const supabase = await createClient();
  const b = await supabase.schema("b2b").rpc("ai_ask_budget");
  if (b.error) return { ok: false, error: "Could not check the AI budget. Try again." };
  const budget = b.data as { ok: boolean; model: string };
  if (!budget.ok) return { ok: false, error: "Today's AI budget is spent. Raise it in AI settings or ask tomorrow." };
  const db = {
    catalogue: async () => { const r = await supabase.schema("b2b").rpc("metric_catalogue"); if (r.error) throw new Error("catalogue unavailable"); return r.data; },
    query: async (p: Record<string, unknown>) => { const r = await supabase.schema("b2b").rpc("metric_query", { p }); if (r.error) throw new Error(r.error.code === "22023" ? r.error.message : "query failed"); return r.data; },
  };
  const res = await ask(q, budget.model, db, anthropicMessages(apiKey));
  const log = await supabase.schema("b2b").rpc("ai_ask_log", { p: { question: q, answer: res.answer, sources: res.sources, tool_calls: res.tool_calls, usage: res.usage,
    model: budget.model, prompt_version: ASK_PROMPT_VERSION, validation: res.validation, error: res.error ?? null } });
  revalidatePath("/ai");
  if (res.error) return { ok: false, error: `Claude could not answer: ${res.error}` };
  return { ok: true, answer: res.validation.ok ? res.answer : null, sources: res.sources, unverified: res.validation.unverified,
           cost_usd: Number((log.data as { cost_usd?: number } | null)?.cost_usd ?? 0) };
}
