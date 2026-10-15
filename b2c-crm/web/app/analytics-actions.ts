"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { AiUnavailable } from "@/lib/ai";
import { askQuestion, explainChart, type AskAnswer } from "@/lib/analytics-ai";
import { FilterSchema, SpecSchema, VIZ, type Catalog, type Result, type Spec } from "@/lib/analytics";
import { assertUser } from "@/lib/auth";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";

/**
 * Analytics for every role (spec B13). Each call runs as the signed-in person: b2c.analytics_run adds their scope, so a
 * counsellor's numbers (and Claude's answers to them) only ever cover their own leads.
 */
const id = z.coerce.number().int().positive();
const done = () => { revalidatePath("/w/analytics"); revalidatePath("/s/analytics"); };

export async function runSpec(spec: Spec): Promise<ActionResult<Result>> {
  await assertUser();
  const v = SpecSchema.safeParse(spec);
  if (!v.success) return { ok: false, error: "That chart's query is not valid." };
  return act(() => rpc<Result>("analytics_run", { spec: v.data }));
}

/** The leads behind one number: a saved list the Leads page opens with ?drill=. */
export async function drill(spec: Spec, metric: string, cell: Record<string, string | null>): Promise<ActionResult<{ drill_id: string; count: number }>> {
  await assertUser();
  const v = SpecSchema.safeParse(spec);
  if (!v.success || !/^[a-z_]+$/.test(metric)) return { ok: false, error: "That number cannot be opened." };
  const c = Object.fromEntries(Object.entries(cell).filter(([k]) => /^[a-z_]+$/.test(k)).slice(0, 2));
  return act(() => rpc("analytics_drill", { spec: v.data, p_metric: metric, p_cell: c }));
}

export async function ask(question: string): Promise<ActionResult<AskAnswer>> {
  const me = await assertUser();
  try {
    const catalog = await rpc<Catalog>("analytics_catalog");
    const answer = await askQuestion({ question: question.slice(0, 500), catalog, userId: me.user_id!, run: (spec) => rpc<Result>("analytics_run", { spec }) });
    return { ok: true, data: answer };
  } catch (e) {
    return { ok: false, error: e instanceof AiUnavailable ? e.message : friendly(e) };
  }
}

export async function explain(title: string, spec: Spec, labels: Record<string, string>): Promise<ActionResult<{ summary: string; points: string[] }>> {
  const me = await assertUser();
  try {
    // the chart is run again as the person, so only numbers they may see go to Claude
    const result = await rpc<Result>("analytics_run", { spec: SpecSchema.parse(spec) });
    return { ok: true, data: await explainChart({ title: title.slice(0, 200), result, labels, userId: me.user_id! }) };
  } catch (e) {
    return { ok: false, error: e instanceof AiUnavailable ? e.message : friendly(e) };
  }
}

// ---------- dashboards ----------
const WidgetSchema = z.object({ id: z.string().max(40), title: z.string().trim().min(1).max(120), viz: z.enum(VIZ), w: z.number().int().min(1).max(4).optional(), spec: SpecSchema, note: z.string().max(2000).optional() });
const DashFiltersSchema = z.object({ range: z.string().max(10).optional(), from: z.string().optional(), to: z.string().optional(), compare: z.enum(["previous", "year"]).nullable().optional(), filters: z.array(FilterSchema).max(10).optional() });

export async function dashboardSave(p: { id?: number | null; name?: string; description?: string | null; widgets?: unknown; filters?: unknown }): Promise<ActionResult<number>> {
  await assertUser();
  const v = z.object({ id: id.nullable().optional(), name: z.string().trim().max(120).optional(), description: z.string().max(500).nullable().optional(),
    widgets: z.array(WidgetSchema).max(24).optional(), filters: DashFiltersSchema.optional() }).safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the dashboard." };
  const r = await act(() => rpc<number>("dashboard_save", { p: v.data }), "Dashboard saved.");
  done();
  return r;
}
export async function dashboardAct(dashboard: number, action: "duplicate" | "home" | "archive", name?: string): Promise<ActionResult<number>> {
  await assertUser();
  const d = id.parse(dashboard);
  const r = action === "duplicate" ? await act(() => rpc<number>("dashboard_duplicate", { p_id: d, p_name: name ?? null }), "Copied to your dashboards.")
    : action === "home" ? await act(() => rpc<number>("dashboard_home", { p_id: d }), "This is now your home dashboard.")
    : await act(() => rpc<number>("dashboard_archive", { p_id: d }), "Dashboard archived.");
  done();
  return r;
}
export async function dashboardPublish(dashboard: number, roles: string[]): Promise<ActionResult<number>> {
  await assertUser(["admin"]);
  const r = await act(() => rpc<number>("dashboard_publish", { p_id: id.parse(dashboard), p_roles: z.array(z.enum(["admin", "marketing", "sales"])).min(1).parse(roles) }), "Published as a standard dashboard.");
  done();
  return r;
}

// ---------- schedules and alerts ----------
export async function scheduleSave(p: { id?: number; dashboard_id: number; freq: string; format: string; hour_ist: number; weekday?: number | null; monthday?: number | null; active?: boolean }): Promise<ActionResult<number>> {
  await assertUser();
  const v = z.object({ id: id.optional(), dashboard_id: id, freq: z.enum(["daily", "weekly", "monthly"]), format: z.enum(["pdf", "csv"]), hour_ist: z.coerce.number().int().min(0).max(23),
    weekday: z.coerce.number().int().min(1).max(7).nullable().optional(), monthday: z.coerce.number().int().min(1).max(28).nullable().optional(), active: z.boolean().optional() }).safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the schedule." };
  const r = await act(() => rpc<number>("schedule_save", { p: v.data }), v.data.active === false ? "Schedule stopped." : "Schedule saved. It is emailed to you.");
  done();
  return r;
}
export async function alertSave(p: { id?: number; name: string; metric: string; kind: string; op?: string | null; threshold?: number | null; win: string; channels: string[]; filters?: unknown; active?: boolean }): Promise<ActionResult<number>> {
  await assertUser();
  const v = z.object({ id: id.optional(), name: z.string().trim().min(2).max(150), metric: z.string().regex(/^[a-z_]+$/), kind: z.enum(["threshold", "anomaly"]),
    op: z.enum(["above", "below"]).nullable().optional(), threshold: z.coerce.number().nullable().optional(), win: z.enum(["today", "7d"]),
    channels: z.array(z.enum(["push", "email", "whatsapp"])).min(1, "Choose how to be told."), filters: z.array(FilterSchema).max(10).optional(), active: z.boolean().optional() })
    .refine((x) => x.kind === "anomaly" || (x.op && x.threshold !== null && x.threshold !== undefined), "A threshold alert needs above or below and a number.").safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the alert." };
  const r = await act(() => rpc<number>("alert_save", { p: v.data }), v.data.active === false ? "Alert stopped." : "Alert saved. It is checked every 15 minutes.");
  done();
  return r;
}
