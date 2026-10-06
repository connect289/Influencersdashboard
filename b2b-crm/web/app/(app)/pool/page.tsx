import type { Metadata } from "next";
import Link from "next/link";
import { Inbox, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { AGE_BUCKETS, OUTLOOK_LABEL, POOL_GROUPS, POOL_GROUP_HINT, POOL_GROUP_LABEL, type PoolGroup, type PoolOverview } from "@/lib/overview";
import { poolOverview } from "@/lib/overview-data";

export const metadata: Metadata = { title: "Pre-routing pool" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const GROUP_TONE: Record<PoolGroup, "info" | "warning" | "success" | "neutral" | "brand"> = {
  chatting: "info", routing_off: "warning", due: "success", opted_out: "neutral", too_old: "warning", test: "brand",
};

function GroupCard({ g, o, active }: { g: PoolGroup; o: PoolOverview; active: boolean }) {
  const s = o.groups[g];
  return (
    <Link href={active ? "/pool" : `/pool?group=${g}`} aria-current={active ? "true" : undefined}
      className={cn("block rounded-[var(--radius-card)] border bg-surface p-4 transition-colors hover:border-border-strong",
        active ? "border-amber ring-2 ring-amber/30" : "border-border")}>
      <p className="text-[12px] font-medium text-muted">{POOL_GROUP_LABEL[g]}</p>
      <p className="tabular mt-1 text-2xl font-semibold text-fg">{s?.n ?? 0}</p>
      <p className="mt-0.5 text-[11.5px] text-subtle">{s ? <>oldest <span title={formatDateTime(s.oldest)}>{relativeTime(s.oldest)}</span></> : "none"}</p>
      <dl className="mt-3 grid grid-cols-4 gap-1 border-t border-border pt-2" aria-label="By age">
        {AGE_BUCKETS.map((b, i) => (
          <div key={b} className="min-w-0 text-center">
            <dd className={cn("tabular text-[13px] font-medium", s?.ages[i] ? "text-fg" : "text-subtle")}>{s?.ages[i] ?? 0}</dd>
            <dt className="truncate text-[10px] text-subtle">{b}</dt>
          </div>
        ))}
      </dl>
    </Link>
  );
}

export default async function PoolPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const group = POOL_GROUPS.find((g) => g === sp.group) ?? null;
  const o = await poolOverview(group);
  const shown = POOL_GROUPS.filter((g) => (o.groups[g]?.n ?? 0) > 0 || g === "chatting" || g === (o.routing_on ? "due" : "routing_off"));
  const outlook = Object.entries(o.outlook).sort((a, b) => b[1] - a[1]);
  const missing = Object.entries(o.missing).sort((a, b) => b[1] - a[1]);

  return (
    <>
      <PageHeader title="Pre-routing pool"
        description="Leads with no destination yet, grouped by why they are waiting, with what each will be decided as once it is ready." />

      {!o.routing_on && (o.groups.routing_off?.n ?? 0) > 0 && (
        <p className="mb-6 flex items-start gap-2 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[13px] text-warning">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          <span>Automatic routing is off, so {o.groups.routing_off?.n} ready {o.groups.routing_off?.n === 1 ? "lead waits" : "leads wait"} here.{" "}
            <Link href="/routing" className="underline">Open Routing</Link></span>
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        {shown.map((g) => <GroupCard key={g} g={g} o={o} active={group === g} />)}
      </div>

      <div className="mt-6 grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader title="Once decided" description="Where the waiting leads would go today (test leads left out)." />
          {outlook.length === 0 ? <p className="px-5 py-4 text-[13px] text-muted">Nothing waiting.</p> : (
            <ul className="space-y-1.5 px-5 py-4 text-[13px]">
              {outlook.map(([k, n]) => <li key={k} className="flex justify-between gap-3"><span className="text-muted">{OUTLOOK_LABEL[k] ?? k}</span><span className="tabular text-fg">{n}</span></li>)}
            </ul>
          )}
        </Card>
        <Card>
          <CardHeader title="What is missing" description="Why leads would go to B2C nurture instead of a partner." />
          {missing.length === 0 ? <p className="px-5 py-4 text-[13px] text-muted">Every waiting lead is qualified.</p> : (
            <ul className="space-y-1.5 px-5 py-4 text-[13px]">
              {missing.map(([k, n]) => <li key={k} className="flex justify-between gap-3"><span className="text-muted">{k}</span><span className="tabular text-fg">{n}</span></li>)}
            </ul>
          )}
        </Card>
      </div>

      <Card className="mt-6 min-w-0 overflow-hidden">
        <CardHeader title={group ? POOL_GROUP_LABEL[group] : `All waiting leads (${o.total})`}
          description={group ? POOL_GROUP_HINT[group] : `Oldest first, up to 200. Witty leads are decided once the chat has been quiet for ${o.idle_minutes} minutes.`}
          action={group ? <Link href="/pool" className="shrink-0 text-[13px] text-info hover:underline">Show all</Link> : undefined} />
        {o.rows.length === 0 ? (
          <EmptyState icon={Inbox} title="Nothing waiting">Every lead has been decided: to a partner, to B2C or not passed.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[860px] text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">Lead</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Source</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Waiting because</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Will go to</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">In</th>
                  <th scope="col" className="px-5 py-2.5 font-medium">Last activity</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {o.rows.map((r) => (
                  <tr key={r.id}>
                    <td className="px-5 py-2.5">
                      <Link href={`/leads?lead=${r.id}`} className="whitespace-nowrap font-medium text-fg hover:underline">{r.name || `Lead #${r.id}`}</Link>
                      <span className="block text-[12px] text-muted">{r.course || "No course yet"}</span>
                    </td>
                    <td className="px-3 py-2.5 text-muted">{r.source ?? "—"}</td>
                    <td className="px-3 py-2.5"><Badge tone={GROUP_TONE[r.group]}>{POOL_GROUP_LABEL[r.group]}</Badge></td>
                    <td className="px-3 py-2.5">
                      <span className="text-fg">{OUTLOOK_LABEL[r.outlook] ?? r.outlook}</span>
                      {r.not_qualified.length > 0 && <span className="block text-[12px] text-muted">Missing: {r.not_qualified.join(", ")}</span>}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-muted" title={formatDateTime(r.created_at)}>{relativeTime(r.created_at)}</td>
                    <td className="whitespace-nowrap px-5 py-2.5 text-muted" title={formatDateTime(r.last_seen)}>{relativeTime(r.last_seen)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
