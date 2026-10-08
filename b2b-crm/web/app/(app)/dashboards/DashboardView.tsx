import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { Badge } from "@/components/ui/Card";
import { WidgetCard } from "@/components/charts/WidgetView";
import { dashboardFilterDims, viewParams } from "@/lib/analytics";
import { dashboardData, metricCatalogue } from "@/lib/analytics-data";
import { relativeTime } from "@/lib/format";
import { DashboardActions, DashboardControls } from "./DashboardClient";

/** Renders the dashboard with the shared widget grid; used by the dashboard page and the home screen. */
export async function DashboardView({ id, sp, home }: { id: number; sp: Record<string, string | string[] | undefined>; home?: boolean }) {
  const first = await dashboardData(id);
  const v = viewParams(sp, first.dashboard.period);
  const d = v.period === first.dashboard.period && !v.filters ? first : await dashboardData(id, v.period, v.filters);
  const filters = v.filters ?? d.dashboard.filters;
  const cat = await metricCatalogue();
  const dims = dashboardFilterDims(d.dashboard.widgets, cat.metrics);
  return (
    <>
      {!home && <Link href="/dashboards" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg print:hidden"><ChevronLeft className="size-4" /> Dashboards</Link>}
      <div className="mb-4 flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="flex flex-wrap items-center gap-2 text-xl font-semibold tracking-tight text-fg">
            {d.dashboard.name}
            {d.dashboard.is_default && <Badge>Built in</Badge>}
            {home && <Badge tone="brand">Home</Badge>}
          </h1>
          {d.dashboard.description && <p className="mt-0.5 max-w-3xl text-[13px] text-muted">{d.dashboard.description}</p>}
          <p className="mt-0.5 text-[12px] text-subtle">Data as of {d.facts_at ? relativeTime(d.facts_at) : "the last refresh"} (refreshed every minute). Click any number for the leads behind it.
            {home && <> · <Link href="/?view=command" className="text-info hover:underline">Open the Command Center</Link></>}</p>
        </div>
        <div className="print:hidden"><DashboardActions id={d.dashboard.id} isDefault={d.dashboard.is_default} isHome={Boolean(d.dashboard.is_home) || Boolean(home)} /></div>
      </div>
      <div className="print:hidden"><DashboardControls period={v.period} filters={filters} dims={dims}
        partners={Object.values(d.data).flatMap((x) => x.series ?? []).find((x) => x.labels?.partner)?.labels.partner ?? {}} /></div>
      <div className="grid grid-cols-12 gap-4">
        {d.dashboard.widgets.map((w) => <WidgetCard key={w.id} w={w} data={d.data[w.id]} filters={filters} period={v.period} />)}
      </div>
    </>
  );
}

