"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { DashboardSchema, parseFormula, type Dashboard } from "@/lib/analytics";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}
async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}
const refresh = () => { revalidatePath("/dashboards"); revalidatePath("/"); };

export async function saveDashboard(d: Pick<Dashboard, "name" | "description" | "period" | "filters" | "widgets"> & { id: number | null }): Promise<{ ok: true; id: number } | { ok: false; error: string }> {
  await assertAdmin();
  const p = DashboardSchema.safeParse(d);
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the dashboard." };
  const { data, error } = await rpc("dashboard_save", { p: p.data });
  if (error) return { ok: false, error: dbMessage(error, "Could not save the dashboard. Try again.") };
  refresh();
  return { ok: true, id: (data as { id: number }).id };
}

export async function copyDashboard(id: number): Promise<{ ok: true; id: number } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Invalid dashboard." };
  const { data, error } = await rpc("dashboard_copy", { p_id: id });
  if (error) return { ok: false, error: dbMessage(error, "Could not copy. Try again.") };
  refresh();
  return { ok: true, id: (data as { id: number }).id };
}

export async function archiveDashboard(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid dashboard.";
  const { error } = await rpc("dashboard_archive", { p_id: id });
  if (error) return dbMessage(error, "Could not archive. Try again.");
  refresh();
}

export async function setHomeDashboard(id: number | null): Promise<string | void> {
  await assertAdmin();
  if (id !== null && !Id.safeParse(id).success) return "Invalid dashboard.";
  const { error } = await rpc("dashboard_set_home", { p_id: id });
  if (error) return dbMessage(error, "Could not change the home screen. Try again.");
  refresh();
}

export async function saveMetric(input: { key: string; label: string; unit: string; formula: string; higher_is_better: boolean; description?: string }, known: string[]): Promise<string | void> {
  await assertAdmin();
  const tokens = parseFormula(input.formula, new Set(known));
  if (typeof tokens === "string") return tokens;
  const p = z.object({ key: z.string().regex(/^[a-z][a-z0-9_]{1,59}$/, "Key: lower-case letters, digits and _"), label: z.string().trim().min(1, "Give it a name").max(80),
                       unit: z.enum(["count", "pct", "inr", "hours", "days", "minutes", "usd", "number"]) }).safeParse(input);
  if (!p.success) return p.error.issues[0]?.message ?? "Check the metric.";
  const { error } = await rpc("metric_save", { p: { ...p.data, description: input.description?.slice(0, 300), higher_is_better: input.higher_is_better, formula: tokens } });
  if (error) return dbMessage(error, "Could not save the metric. Try again.");
  refresh();
}

export async function saveView(name: string, metric: string, filters: Record<string, string[]>, period: string): Promise<string | void> {
  await assertAdmin();
  if (!name.trim()) return "Give the view a name.";
  const { error } = await rpc("saved_view_save", { p: { name: name.trim().slice(0, 80), metric, filters, period } });
  if (error) return dbMessage(error, "Could not save the view. Try again.");
  refresh();
}

// ---------- alerts and delivery ----------
const emails = z.array(z.string().trim().toLowerCase().regex(/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/, "Enter e-mail addresses"));

export async function saveAlertSettings(input: { enabled: boolean; emails: string; whatsapp_numbers: string; whatsapp_template: string; digest_minutes: number; reason: string }): Promise<string | void> {
  await assertAdmin();
  const list = (s: string) => s.split(/[,\s]+/).map((x) => x.trim()).filter(Boolean);
  const e = emails.max(10, "Up to 10 addresses").safeParse(list(input.emails));
  if (!e.success) return e.error.issues[0]?.message;
  const w = z.array(z.string().regex(/^\d{10,15}$/, "WhatsApp numbers: digits with the country code")).max(5).safeParse(list(input.whatsapp_numbers).map((x) => x.replace(/\D/g, "")));
  if (!w.success) return w.error.issues[0]?.message;
  if (input.reason.trim().length < 3) return "Say why.";
  const { error } = await rpc("admin_alerts_settings_save", { p: { enabled: input.enabled, emails: e.data, whatsapp_numbers: w.data, whatsapp_template: input.whatsapp_template,
                                                                   digest_minutes: input.digest_minutes }, p_reason: input.reason.trim() });
  if (error) return dbMessage(error, "Could not save. Try again.");
  refresh();
}

export async function testAlert(): Promise<string | void> {
  await assertAdmin();
  const { error } = await rpc("admin_alerts_test", {});
  if (error) return dbMessage(error, "Could not queue the test. Try again.");
  refresh();
}

export async function saveMetricAlert(input: { id?: number | null; name: string; metric: string; op: string; threshold: number; window_hours: number;
                                               filters: Record<string, string[]>; channels: string[]; cooldown_hours: number; active?: boolean }): Promise<string | void> {
  await assertAdmin();
  if (!input.name.trim()) return "Give the alert a name.";
  if (!Number.isFinite(input.threshold)) return "Enter the threshold.";
  const { error } = await rpc("metric_alert_save", { p: { ...input, name: input.name.trim() } });
  if (error) return dbMessage(error, "Could not save the alert. Try again.");
  refresh();
}

export async function saveSchedule(input: { id?: number | null; name: string; dashboard_id?: number | null; report_id?: number | null; frequency: string; hour_ist: number;
                                            weekday?: number | null; monthday?: number | null; recipients: string; active?: boolean }): Promise<string | void> {
  await assertAdmin();
  const r = emails.min(1, "Add at least one address").max(20).safeParse(input.recipients.split(/[,\s]+/).filter(Boolean));
  if (!r.success) return r.error.issues[0]?.message;
  const { error } = await rpc("schedule_save", { p: { ...input, recipients: r.data } });
  if (error) return dbMessage(error, "Could not save the schedule. Try again.");
  refresh();
  revalidatePath("/reports");
}
