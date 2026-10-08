import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Catalogue, DashboardData, MetricResult } from "@/lib/analytics";

/** Analytics reads as the signed-in Admin; every b2b function re-checks b2b.is_admin(). */
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"}${error.code === "22023" ? `: ${error.message}` : ""})`);
  return data as T;
}

export type DashboardsList = {
  home_dashboard_id: number | null;
  dashboards: { id: number; slug: string; name: string; description: string | null; is_default: boolean; widgets: number; updated_at: string }[];
  views: { id: number; name: string; metric: string; filters: Record<string, string[]>; period: string; created_at: string }[];
};
export type Drill = { metric: string; fact: string; rows: Record<string, unknown>[]; shown: number; limit: number; labels: { partner: Record<string, string> } };
export type AlertsOverview = {
  settings: { enabled: boolean; emails: string[]; whatsapp_numbers: string[]; whatsapp_template: string | null; whatsapp_language?: string; digest_minutes: number; types: string[] };
  settings_version: number; email_ready: boolean;
  alerts: { id: number; name: string; metric: string; metric_label: string; unit: string; filters: Record<string, string[]>; window_hours: number; op: string; threshold: number;
            channels: string[]; cooldown_hours: number; min_volume: number; volume_metric: string | null; active: boolean; last_value: number | null; last_checked_at: string | null;
            last_fired_at: string | null }[];
  schedules: { id: number; name: string; dashboard_id: number | null; report_id: number | null; dashboard: string | null; frequency: string; hour_ist: number; weekday: number | null;
               monthday: number | null; recipients: string[]; active: boolean; failures: number; last_sent_at: string | null; next_due_at: string | null }[];
  messages: { id: number; kind: string; channel: string; recipients: number; subject: string; status: string; error: string | null; created_at: string; sent_at: string | null; attachments: number }[];
};
export type ReportsList = {
  reports: { id: number; name: string; kind: "tabular" | "summary" | "matrix"; definition: Record<string, unknown>; updated_at: string }[];
  facts: Record<string, { name: string; type: string }[]>;
};
export type ReportResult =
  | { kind: "tabular"; columns: string[]; rows: Record<string, unknown>[]; from: string; to: string; limit: number; labels: { partner_id: Record<string, string> } }
  | { kind: "summary"; dims: string[]; metrics: MetricResult["metric"][]; rows: { d: (string | null)[]; values: (number | null)[] }[]; totals: (number | null)[]; from: string; to: string; labels: MetricResult["labels"];
      truncated?: boolean }
  | { kind: "matrix"; metric: MetricResult["metric"]; row_dim: string; col_dim: string; rows: (string | null)[]; cols: (string | null)[]; cells: MetricResult["rows"]; total: MetricResult["total"]; from: string; to: string;
      labels: MetricResult["labels"]; truncated?: boolean };

export const metricCatalogue = () => rpc<Catalogue>("metric_catalogue");
export const metricQuery = (p: Record<string, unknown>) => rpc<MetricResult>("metric_query", { p });
export const metricDrill = (p: Record<string, unknown>) => rpc<Drill>("metric_drill_admin", { p });
export const dashboardsList = () => rpc<DashboardsList>("dashboards_list");
export const dashboardData = (id: number, period?: string | null, filters?: Record<string, string[]> | null) =>
  rpc<DashboardData>("dashboard_data", { p_id: id, p_period: period ?? null, p_filters: filters ?? null });
export const alertsOverview = () => rpc<AlertsOverview>("admin_alerts_overview");
export const reportsList = () => rpc<ReportsList>("reports_list");
export const reportRun = (p: Record<string, unknown>) => rpc<ReportResult & { report?: { id: number; name: string } }>("report_run", { p });
export const slaTimers = () => rpc<{ id: number; lead_id: number; sla: string; due_at: string; status: string; partner: string; reference: string | null }[]>("sla_timers", { p_partner: null, p_limit: 30 });
export const homeDashboardId = async (): Promise<number | null> => (await dashboardsList()).home_dashboard_id;
