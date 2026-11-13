import "server-only";
import { aiConfigured } from "@/lib/ai";
import { effectiveSpec, fmtValue, istDate, resolveRange, resultTable, type Dashboard, type Result } from "@/lib/analytics";
import { writeBrief, writeInsights } from "@/lib/analytics-ai";
import { toCsv } from "@/lib/csv";
import { siteUrl } from "@/lib/env";
import { handBack, JobBudget, runPart, whileTime } from "@/lib/job-budget";
import { sendMail } from "@/lib/mail";
import { dashboardPdf } from "@/lib/pdf";
import { adminClient } from "@/lib/supabase/admin";

/**
 * The analytics side of the every-minute job (spec B13, B8.3): briefs for calls due within the hour, alert emails,
 * scheduled dashboards (rendered as their owner sees them) and, once a day after the set hour, the insights feed.
 * Each part fails on its own; staff emails only, never a message to a student. When the job's time is up
 * (lib/job-budget.ts) a part is not started, and alerts, schedules and briefs taken but not started are handed back for
 * the next run. A Claude call is started only with time to finish: a brief takes about BRIEF_NEED_MS and the insights
 * about INSIGHTS_NEED_MS, so with less than that left they wait for the next run instead of being cut off part-way.
 */
export const BRIEF_NEED_MS = 10_000;
export const INSIGHTS_NEED_MS = 20_000;

export async function runAnalyticsJobs(now = new Date(), budget: JobBudget = new JobBudget()): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  await runPart(budget, out, "alert_emails", () => alertEmails(budget));
  await runPart(budget, out, "schedules", () => schedules(now, budget));
  if (aiConfigured()) {
    await runPart(budget, out, "briefs", () => briefs(budget), BRIEF_NEED_MS);
    await runPart(budget, out, "insights", () => insights(now), INSIGHTS_NEED_MS);
  }
  return out;
}

async function briefs(budget: JobBudget): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("brief_due_take", { p_limit: 3 });
  if (error) throw new Error(error.message);
  let n = 0;
  const unstarted = await whileTime(budget, (data ?? []) as number[], async (lead) => {
    try { await writeBrief(lead, null); n++; } catch { /* the error is saved on the brief and shown on the lead */ }
  }, BRIEF_NEED_MS);
  await handBack(db, budget, "briefs", "briefs", unstarted);
  return n;
}

async function alertEmails(budget: JobBudget): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("alert_emails_take", { p_limit: 20 });
  if (error) throw new Error(error.message);
  type Row = { event: { id: number; value: number; detail: { mean?: number; threshold?: number; op?: string } }; alert: { id: number; name: string; kind: string; win: string }; email: string; name: string | null; label: string };
  let n = 0;
  const unstarted = await whileTime(budget, (data ?? []) as Row[], async (r) => {
    const what = r.alert.kind === "threshold" ? `is ${r.event.value} (${r.event.detail.op} ${r.event.detail.threshold})` : `is ${r.event.value}, usually about ${Math.round(Number(r.event.detail.mean ?? 0) * 10) / 10}`;
    const sent = await sendMail({ to: r.email, subject: `Alert: ${r.alert.name}`,
      text: `Hi ${(r.name ?? "").split(" ")[0] || "there"},\n\n${r.label} ${r.alert.win === "7d" ? "over the last 7 days" : "today"} ${what}.\n\nOpen Analytics in the CRM: ${siteUrl()}\n\nEduwit Spark` });
    if (sent.sent) n++;
  });
  await handBack(db, budget, "alert_emails", "alert_emails", unstarted.map((r) => r.event.id));
  return n;
}

async function schedules(now: Date, budget: JobBudget): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("schedules_take", { p_limit: 2 });
  if (error) throw new Error(error.message);
  type Row = { schedule: { id: number; user_id: string; format: "pdf" | "csv"; freq: string }; dashboard: Dashboard; email: string; name: string | null };
  let n = 0;
  const unstarted = await whileTime(budget, (data ?? []) as Row[], async (r) => {
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
  });
  await handBack(db, budget, "schedules", "schedules", unstarted.map((r) => r.schedule.id));
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
