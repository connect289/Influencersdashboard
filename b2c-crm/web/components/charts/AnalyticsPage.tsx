import { Empty, Page, SetupError } from "@/components/shell/Page";
import { AnalyticsApp, type Alert, type DashList, type Insight, type Schedule } from "@/components/charts/AnalyticsApp";
import { rpc } from "@/lib/data";
import type { Catalog, Dashboard } from "@/lib/analytics";

/** Loads what the Analytics screen needs for the signed-in person; the database decides which dashboards and metrics they may see. */
export async function AnalyticsPage({ base, d, admin }: { base: "/w" | "/s"; d?: string; admin: boolean }) {
  try {
    const [catalog, list, insights, schedules, alerts] = await Promise.all([
      rpc<Catalog>("analytics_catalog"), rpc<DashList>("dashboards_list"), rpc<Insight[]>("insights_latest").catch(() => []),
      rpc<Schedule[]>("schedules_mine").catch(() => []), rpc<Alert[]>("alerts_mine").catch(() => []),
    ]);
    const asked = Number(d);
    const pick = Number.isInteger(asked) && asked > 0 ? asked : list.home ?? list.standard[0]?.id ?? list.mine[0]?.id;
    if (!pick) return <Page title="Analytics"><Empty>No dashboards yet.</Empty></Page>;
    const dash = await rpc<Dashboard>("dashboard_get", { p_id: pick });
    return (
      <Page title="Analytics" sub={`${dash.name} · ${catalog.scope === "all" ? "all leads" : catalog.scope === "team" ? "your team's leads" : "your own leads"}`}>
        <AnalyticsApp base={base} catalog={catalog} list={list} dash={dash} insights={insights} schedules={schedules} alerts={alerts} admin={admin} />
      </Page>
    );
  } catch (e) {
    return <Page title="Analytics"><SetupError error={e} /></Page>;
  }
}
