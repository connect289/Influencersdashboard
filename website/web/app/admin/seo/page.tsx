import { Suspense } from "react";
import { syncGscAction } from "@/app/admin/seo-actions";
import { AdminShell, Card, Stat } from "@/components/admin/AdminShell";
import { SeoNav } from "@/components/admin/SeoNav";
import { requireAdmin, hasRole } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "SEO toolkit" };

type Row = Record<string, string | number>;
interface Dash {
  source: string | null;
  last_sync: { finished_at: string; rows_written: number; source: string } | null;
  totals: { clicks: number; impressions: number; ctr: number; position: number | null };
  trend: { day: string; clicks: number; impressions: number }[];
  top_queries: Row[];
  top_pages: Row[];
  rising: Row[];
  falling: Row[];
  low_ctr: Row[];
}

function Table({ rows, cols }: { rows: Row[]; cols: string[] }) {
  if (!rows.length) return <p className="text-muted text-sm">No data yet.</p>;
  return (
    <table className="w-full text-left text-sm">
      <thead className="text-muted"><tr>{cols.map((c) => <th key={c} scope="col" className="border-border border-b py-1 pr-2 font-medium">{c}</th>)}</tr></thead>
      <tbody>{rows.map((r, i) => <tr key={i} className="border-border border-b">{cols.map((c) => <td key={c} className="py-1 pr-2">{String(r[c] ?? "—")}</td>)}</tr>)}</tbody>
    </table>
  );
}

async function View({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const d = await rpc<Dash>("web_seo_dashboard", { p_days: 28 });
  const max = Math.max(1, ...d.trend.map((t) => t.impressions));
  return (
    <AdminShell session={s} title="SEO toolkit">
      <SeoNav current="/admin/seo" msg={sp.msg} />
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className="text-muted">
          Source: {d.source === "sample" ? <strong className="text-amber-text">sample data (Search Console not connected — S-20)</strong> : d.source ? "Google Search Console" : "none yet"}
          {d.last_sync ? ` · last sync ${new Date(d.last_sync.finished_at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata" })}` : ""}
        </span>
        {hasRole(s, "content_editor") ? (
          <form action={syncGscAction}><button className="border-border h-9 rounded-full border px-3">Sync now</button></form>
        ) : null}
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Clicks (28 days)" value={d.totals.clicks} />
        <Stat label="Impressions" value={d.totals.impressions} />
        <Stat label="CTR" value={`${d.totals.ctr}%`} />
        <Stat label="Average position" value={d.totals.position ?? "—"} />
      </div>
      <Card title="Impressions per day">
        <div className="flex h-24 items-end gap-0.5" role="img" aria-label="Impressions per day over the last 28 days">
          {d.trend.map((t) => <span key={t.day} className="bg-primary/70 flex-1 rounded-t" style={{ height: `${(t.impressions / max) * 100}%` }} title={`${t.day}: ${t.impressions}`} />)}
        </div>
      </Card>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card title="Top queries"><Table rows={d.top_queries} cols={["query", "clicks", "impressions", "position"]} /></Card>
        <Card title="Top pages"><Table rows={d.top_pages} cols={["page", "clicks", "impressions"]} /></Card>
        <Card title="Rising pages"><Table rows={d.rising} cols={["page", "clicks", "prev"]} /></Card>
        <Card title="Falling pages"><Table rows={d.falling} cols={["page", "clicks", "prev"]} /></Card>
        <Card title="Impressions but low CTR (fix the title and description)"><Table rows={d.low_ctr} cols={["page", "impressions", "clicks", "ctr"]} /></Card>
        <Card title="Index coverage and Core Web Vitals">
          <p className="text-muted text-sm">Shown once Search Console is connected (the Search Analytics API does not expose them for sample data). Lab Core Web Vitals are enforced in CI (docs/PERFORMANCE.md).</p>
        </Card>
      </div>
    </AdminShell>
  );
}

export default function SeoPage({ searchParams }: { searchParams: Promise<{ msg?: string }> }) {
  return <Suspense fallback={<div className="skeleton m-8 h-40" />}><View searchParams={searchParams} /></Suspense>;
}
