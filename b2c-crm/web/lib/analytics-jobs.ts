import "server-only";
import { aiConfigured } from "@/lib/ai";
import { effectiveSpec, fmtValue, istDate, resolveRange, resultTable, type Dashboard, type Result } from "@/lib/analytics";
import { writeBrief, writeInsights } from "@/lib/analytics-ai";
import { toCsv } from "@/lib/csv";
import { siteUrl } from "@/lib/env";
import { sendMail } from "@/lib/mail";
import { dashboardPdf } from "@/lib/pdf";
import { adminClient } from "@/lib/supabase/admin";

/**
 * The analytics side of the every-minute job (spec B13, B8.3): briefs for calls due within the hour, alert emails,
 * scheduled dashboards (rendered as their owner sees them) and, once a day after the set hour, the insights feed.
 * Each part fails on its own; staff emails only, never a message to a student.
 */
export async function runAnalyticsJobs(now = new Date()): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const part = async (name: string, fn: () => Promise<unknown>) => {
    try { out[name] = await fn(); } catch (e) { out[`${name}_error`] = e instanceof Error ? e.message : String(e); }
  };
  await part("alert_emails", alertEmails);
  await part("schedules", () => schedules(now));
  if (aiConfigured()) {
    await part("briefs", briefs);
    await part("insights", () => insights(now));
  }
  return out;
}

async function briefs(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("brief_due_take", { p_limit: 3 });
  if (error) throw new Error(error.message);
  let n = 0;
  for (const lead of (data ?? []) as number[]) {
    try { await writeBrief(lead, null); n++; } catch { /* the error is saved on the brief and shown on the lead */ }
  }
  return n;
}

async function alertEmails(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("alert_emails_take", { p_limit: 20 });
  if (error) throw new Error(error.message);
  type Row = { event: { value: number; detail: { mean?: number; threshold?: number; op?: string } }; alert: { id: number; name: string; kind: string; win: string }; email: string; name: string | null; label: string };
  let n = 0;
  for (const r of (data ?? []) as Row[]) {
    const what = r.alert.kind === "threshold" ? `is ${r.event.value} (${r.event.detail.op} ${r.event.detail.threshold})` : `is ${r.event.value}, usually about ${Math.round(Number(r.event.detail.mean ?? 0) * 10) / 10}`;
    const sent = await sendMail({ to: r.email, subject: `Alert: ${r.alert.name}`,
      text: `Hi ${(r.name ?? "").split(" ")[0] || "there"},\n\n${r.label} ${r.alert.win === "7d" ? "over the last 7 days" : "today"} ${what}.\n\nOpen Analytics in the CRM: ${siteUrl()}\n\nEduwit Spark` });
    if (sent.sent) n++;
  }
  return n;
}

async function schedules(now: Date): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("schedules_take", { p_limit: 2 });
  if (error) throw new Error(error.message);
  type Row = { schedule: { id: number; user_id: string; format: "pdf" | "csv"; freq: string }; dashboard: Dashboard; email: string; name: string | null };
  let n = 0;
  for (const r of (data ?? []) as Row[]) {
    try {
      const userId = r.schedule.user_id;
      const { data: labelsData } = await db.from("metric_defs").select("key, label");
      const labels = Object.fromEntries(((labelsData ?? []) as { key: string; label: string }[]).map((m) => [m.key, m.label]));
      const range = resolveRange(r.dashboard.filters?.range, now, r.dashboard.filters);
      const sections: { title: string; columns: string[]; rows: Record<string, unknown>[] }[] = [];
      for (const w of r.dashboard.widgets) {
        if (w.viz === "text") continue;
        const { data: res, error: e } = await db.rpc("analytics_run_for", { p_user: userId, spec: { ...effectiveSpec(w, r.dashboard.filters ?? {}, false, now), compare: null } });
        if (e) { sections.push({ title: `${w.title} (could not run: ${e.message})`, columns: [], rows: [] }); continue; }
        const result = res as Result;
        const fmts = Object.fromEntries((result.defs ?? []).map((d) => [d.label, d.fmt]));
        const t = resultTable(result, labels);
        sections.push({ title: w.title, columns: t.columns, rows: t.rows.map((row) => Object.fromEntries(Object.entries(row).map(([k, v]) => [k, fmts[k] ? fmtValue(v, fmts[k]) : v]))) });
      }
      const period = `${range.from} to ${range.to}`;
      const stamp = istDate(now);
      const file = r.schedule.format === "pdf"
        ? { filename: `${r.dashboard.name}-${stamp}.pdf`, content: Buffer.from(await dashboardPdf({ name: r.dashboard.name, range: period, sections })), contentType: "application/pdf" }
        : { filename: `${r.dashboard.name}-${stamp}.csv`, content: sections.map((s) => `${s.title}\r\n${toCsv(s.columns, s.rows).replace(/^﻿/, "")}`).join("\r\n"), contentType: "text/csv" };
      const sent = await sendMail({ to: r.email, subject: `${r.dashboard.name}: ${period}`, attachments: [file],
        text: `Hi ${(r.name ?? "").split(" ")[0] || "there"},\n\nYour ${r.schedule.freq} copy of "${r.dashboard.name}" for ${period} is attached.\n\nEduwit Spark` });
      await db.rpc("schedule_done", { p_id: r.schedule.id, p_error: sent.sent ? null : "email is not configured" });
      if (sent.sent) n++;
    } catch (e) {
      await db.rpc("schedule_done", { p_id: r.schedule.id, p_error: (e instanceof Error ? e.message : String(e)).slice(0, 300) });
    }
  }
  return n;
}

async function insights(now: Date): Promise<number> {
  const db = adminClient();
  const { data: s } = await db.from("settings").select("value").eq("key", "ai").maybeSingle();
  const hour = Number((s?.value as { insights_hour_ist?: number } | null)?.insights_hour_ist ?? 7);
  const istHour = new Date(now.getTime() + 330 * 60_000).getUTCHours();
  if (istHour < hour) return 0;
  const { data, error } = await db.rpc("insights_due");
  if (error) throw new Error(error.message);
  let n = 0;
  for (const d of ((data ?? []) as { role_group: string; user_id: string }[]).slice(0, 1)) n += await writeInsights({ roleGroup: d.role_group, userId: d.user_id });
  return n;
}
