import { getTranslations } from "next-intl/server";
import { RetryButton } from "@/components/system/retry-button";
import { StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { env } from "@/lib/env";
import { formatDateTime, formatRelative } from "@/lib/format";

interface Status {
  db_time: string;
  jobs: { queued: number; due: number; running: number; failed: number; dead: number; oldest_due_seconds: number | null };
  deliveries: { queued: number; failed_24h: number };
  cron: { job: string; schedule: string; active: boolean; last_status: string | null; last_run: string | null }[];
}

interface JobRow {
  id: number;
  kind: string;
  status: string;
  attempts: number;
  max_attempts: number;
  run_at: string;
  last_error: string | null;
  created_at: string;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.system") };
}

export default async function SystemPage() {
  const { supabase } = await requireStaff("system.read");
  const t = await getTranslations();
  const [status, jobs] = await Promise.all([supabase.rpc("system_status"), supabase.rpc("jobs_recent", { p_status: undefined, p_limit: 50 })]);
  const s = status.data as Status | null;
  const rows = (jobs.data ?? []) as JobRow[];
  const e = env();
  const stat = (label: string, value: number | string, danger = false) => (
    <div className="rounded-xl bg-surface-2 p-3">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className={`text-xl font-semibold tabular ${danger ? "text-danger" : ""}`}>{value}</dd>
    </div>
  );
  return (
    <>
      <PageHeader title={t("nav.admin.system")} description={t("system.subtitle")} />
      {status.error || jobs.error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      {s ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader title={t("system.jobs.title")} description={t("system.dbTime", { time: formatDateTime(s.db_time) })} />
            <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {stat(t("system.jobs.queued"), s.jobs.queued)}
              {stat(t("system.jobs.due"), s.jobs.due)}
              {stat(t("system.jobs.running"), s.jobs.running)}
              {stat(t("system.jobs.failed"), s.jobs.failed)}
              {stat(t("system.jobs.dead"), s.jobs.dead, s.jobs.dead > 0)}
              {stat(t("system.jobs.oldest"), s.jobs.oldest_due_seconds === null ? "—" : `${Math.round(s.jobs.oldest_due_seconds / 60)} min`, (s.jobs.oldest_due_seconds ?? 0) > 900)}
            </dl>
          </Card>
          <Card>
            <CardHeader title={t("system.providers.title")} />
            <dl className="grid grid-cols-2 gap-2">
              {stat(t("system.providers.email"), e.EMAIL_PROVIDER)}
              {stat(t("system.providers.whatsapp"), e.WHATSAPP_PROVIDER)}
              {stat(t("system.providers.liveMode"), e.LIVE_MODE)}
              {stat(t("system.deliveries.failed"), s.deliveries.failed_24h, s.deliveries.failed_24h > 0)}
            </dl>
          </Card>
          <Card className="lg:col-span-2">
            <CardHeader title={t("system.cron.title")} />
            {s.cron.length === 0 ? (
              <EmptyState title={t("system.cron.none")} />
            ) : (
              <ul className="divide-y divide-line">
                {s.cron.map((c) => (
                  <li key={c.job} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                    <span className="font-mono">{c.job}</span>
                    <span className="text-muted">{c.schedule}</span>
                    <span className="text-muted">{c.last_run ? formatRelative(c.last_run) : t("system.cron.never")}</span>
                    {c.last_status ? <StatusBadge status={c.last_status === "succeeded" ? "ok" : c.last_status} label={c.last_status} /> : null}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      ) : null}
      <h2 className="mt-8 mb-3 text-base font-semibold">{t("system.recentJobs")}</h2>
      {rows.length === 0 && !jobs.error ? <EmptyState title={t("system.noJobs")} /> : null}
      {rows.length > 0 ? (
        <Card className="p-0 md:p-0">
          <Table>
            <thead>
              <tr>
                <Th>#</Th>
                <Th>{t("system.columns.kind")}</Th>
                <Th>{t("system.columns.status")}</Th>
                <Th>{t("system.columns.attempts")}</Th>
                <Th>{t("system.columns.next")}</Th>
                <Th>{t("system.columns.error")}</Th>
                <Th>
                  <span className="sr-only">{t("common.actions")}</span>
                </Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((j) => (
                <tr key={j.id}>
                  <Td className="tabular text-muted">{j.id}</Td>
                  <Td className="font-mono text-xs">{j.kind}</Td>
                  <Td>
                    <StatusBadge status={j.status} label={t(`system.jobStatus.${j.status}`)} />
                  </Td>
                  <Td className="tabular">
                    {j.attempts}/{j.max_attempts}
                  </Td>
                  <Td className="text-muted">{formatRelative(j.run_at)}</Td>
                  <Td className="max-w-64 truncate text-xs text-muted" title={j.last_error ?? undefined}>
                    {j.last_error ?? "—"}
                  </Td>
                  <Td>{["dead", "failed", "cancelled"].includes(j.status) ? <RetryButton id={j.id} /> : null}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </Card>
      ) : null}
    </>
  );
}
