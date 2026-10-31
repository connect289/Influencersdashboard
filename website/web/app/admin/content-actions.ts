"use server";

import { revalidateTag } from "next/cache";
import { redirect } from "next/navigation";
import { ceilingError } from "@/lib/admin/ceilings";
import { entityConfig, parseEntityForm } from "@/lib/admin/entities";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { errorFields, log } from "@/lib/server/log";

/**
 * Admin writes (spec 11): every change goes through an allow-listed database function that writes the audit log, then
 * the affected cache tags are expired so the public pages show it at once ("revalidate pages on publish").
 */
/** `values` echoes what was submitted so a rejected form keeps the editor's input. */
export type AdminFormState = { error?: string; fieldErrors?: Record<string, string>; ok?: string; values?: Record<string, string> } | null;

function expire(tags: unknown) {
  for (const t of Array.isArray(tags) ? tags : []) if (typeof t === "string") revalidateTag(t, { expire: 0 });
}

/** The record key from the form: only the entity's key columns, as strings or numbers (never other fields). */
function parseKey(cols: string[], json: string): Record<string, string | number> | null {
  try {
    const raw = JSON.parse(json) as Record<string, unknown>;
    const out: Record<string, string | number> = {};
    for (const c of cols) {
      const v = raw?.[c];
      if (typeof v !== "string" && typeof v !== "number") return null;
      out[c] = v;
    }
    return out;
  } catch {
    return null;
  }
}

export async function saveEntityAction(_prev: AdminFormState, form: FormData): Promise<AdminFormState> {
  const entity = String(form.get("__entity") ?? "");
  const cfg = entityConfig(entity);
  if (!cfg) return { error: "Unknown content type." };
  const s = await requireAdmin(cfg.minRole);
  const keyJson = String(form.get("__key") ?? "");
  const isNew = !keyJson;
  const values: Record<string, string> = {};
  for (const [k, v] of form.entries()) if (typeof v === "string" && !k.startsWith("__") && !k.startsWith("$")) values[k] = v;
  const { row, errors } = parseEntityForm(cfg, form, isNew);
  if (Object.keys(errors).length) return { error: "Please fix the highlighted fields.", fieldErrors: errors, values };
  if (!isNew) {
    const key = parseKey(cfg.key, keyJson);
    if (!key) return { error: "Invalid record key.", values };
    Object.assign(row, key);
  }
  let saved: { ok: boolean; error?: string; tags?: string[]; row?: Record<string, unknown> };
  try {
    saved = await rpc("web_admin_save", { p_entity: entity, p_row: row, p_actor: s.userId, p_actor_email: s.email, p_role: s.role });
  } catch (err) {
    log("error", "admin.save_failed", { entity, ...errorFields(err) });
    return { error: "Saving failed. Please try again.", values };
  }
  if (!saved.ok) return { error: saved.error === "forbidden" ? "Your role cannot change this." : (saved.error ?? "Saving failed."), values };
  expire(saved.tags);
  if (entity === "university_profiles" || entity === "synonyms") await rpc("web_refresh_read_model").catch(() => undefined);
  log("info", "admin.saved", { entity, actor: s.email });
  const key = Object.fromEntries(cfg.key.map((k) => [k, saved.row?.[k]]));
  redirect(`/admin/content/${entity}/edit?key=${encodeURIComponent(JSON.stringify(key))}&saved=1`);
}

export async function deleteEntityAction(form: FormData): Promise<void> {
  const entity = String(form.get("__entity") ?? "");
  const cfg = entityConfig(entity);
  if (!cfg) return;
  const s = await requireAdmin(cfg.minRole);
  const key = parseKey(cfg.key, String(form.get("__key") ?? ""));
  if (!key) redirect(`/admin/content/${entity}?deleted=0`);
  const r = await rpc<{ ok: boolean; tags?: string[] }>("web_admin_delete", { p_entity: entity, p_key: key, p_actor: s.userId, p_actor_email: s.email, p_role: s.role });
  if (r.ok) expire(r.tags);
  redirect(`/admin/content/${entity}?deleted=${r.ok ? 1 : 0}`);
}

const SETTING_KEYS = new Set([
  "web_advisor_enabled",
  "announcement",
  "sections",
  "counsellor_whatsapp",
  "counsellor_phone",
  "default_theme",
  "design_concept",
  "push_unverified_gate_leads",
  "push_unverified_after_minutes",
  "require_phone_otp",
  "document_upload_enabled",
  "finder_include_regular_mode",
  "application_form",
  "business_hours",
  "code_send_hourly_cap",
  "web_advisor_daily_cap",
]);

export async function saveSettingAction(_prev: AdminFormState, form: FormData): Promise<AdminFormState> {
  const s = await requireAdmin("content_editor");
  const key = String(form.get("key") ?? "");
  if (!SETTING_KEYS.has(key)) return { error: "Unknown setting." };
  const kind = String(form.get("kind") ?? "json");
  let value: unknown;
  if (kind === "bool") value = form.get("value") === "on";
  else if (kind === "text") value = String(form.get("value") ?? "").trim();
  else if (kind === "number") value = Number(form.get("value"));
  else {
    const raw = String(form.get("value") ?? "").trim();
    try {
      value = raw ? JSON.parse(raw) : null;
    } catch {
      return { error: "Not valid JSON." };
    }
  }
  if (key === "counsellor_whatsapp" || key === "counsellor_phone") {
    if (typeof value !== "string" || !/^\+91[6-9]\d{9}$/.test(value)) return { error: "Use +91 followed by a 10-digit mobile number." };
  }
  const ceiling = ceilingError(key, value);
  if (ceiling) return { error: ceiling };
  const r = await rpc<{ ok: boolean; error?: string }>("web_admin_setting", { p_key: key, p_value: value, p_actor: s.userId, p_actor_email: s.email, p_role: s.role });
  if (!r.ok) return { error: r.error === "forbidden" ? "Only a super admin can change this setting." : (r.error ?? "Saving failed.") };
  revalidateTag("settings", { expire: 0 });
  return { ok: `Saved ${key}.` };
}

export async function retryOutboxAction(form: FormData): Promise<void> {
  const s = await requireAdmin("super_admin");
  const id = Number(form.get("id"));
  if (Number.isInteger(id)) await rpc("web_outbox_retry", { p_id: id, p_actor: s.userId });
  redirect("/admin/outbox?retried=1");
}

export async function setMappingAction(_prev: AdminFormState, form: FormData): Promise<AdminFormState> {
  const s = await requireAdmin("content_editor");
  const specs = form.getAll("specialisation_ids").map(String).filter(Boolean);
  const r = await rpc<{ ok: boolean; reason?: string }>("web_tax_set_mapping", {
    p: {
      catalog_program_id: Number(form.get("catalog_program_id")),
      programme_id: String(form.get("programme_id") ?? ""),
      specialisation_ids: specs,
      spec_display: String(form.get("spec_display") ?? ""),
      note: String(form.get("note") ?? ""),
      actor_id: s.userId,
      actor_email: s.email,
    },
  });
  if (!r.ok) return { error: `Not saved: ${r.reason?.replace(/_/g, " ")}.` };
  await rpc("web_refresh_read_model").catch(() => undefined);
  revalidateTag("catalog", { expire: 0 });
  return { ok: "Mapping saved; the finder is updated." };
}

export async function privacyDoneAction(form: FormData): Promise<void> {
  const s = await requireAdmin("super_admin");
  await rpc("web_admin_privacy_done", {
    p_id: Number(form.get("id")),
    p_status: String(form.get("status")),
    p_note: String(form.get("note") ?? ""),
    p_actor: s.userId,
    p_actor_email: s.email,
    p_role: s.role,
  });
  redirect("/admin/privacy");
}
