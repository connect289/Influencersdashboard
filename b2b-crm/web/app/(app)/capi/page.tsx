import type { Metadata } from "next";
import Link from "next/link";
import { BarChart3 } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { BLOCKER_LABEL, EVENT_STATUS, MATCH_KEY_LABEL, STAGE_LABEL, formatInr, keyShare, platformTotals, type CapiOverview, type Platform } from "@/lib/capi";
import { capiOverview } from "@/lib/capi-data";
import { CapiSwitch } from "./CapiSwitch";
import { EventLog } from "./EventLog";
import { LeadCheck } from "./LeadCheck";
import { SetupForm } from "./SetupForm";

export const metadata: Metadata = { title: "Conversions (CAPI)" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "log", label: "Event log" },
  { id: "setup", label: "Setup" },
  { id: "check", label: "Check a lead" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const NAME: Record<Platform, string> = { meta: "Meta", google: "Google Ads" };
const KEYS: Record<Platform, string[]> = { meta: ["lead_id", "email", "phone", "fbc", "fbp"], google: ["gclid", "gbraid", "wbraid", "email", "phone"] };

function PlatformCard({ p, o }: { p: Platform; o: CapiOverview }) {
  const sw = o.switches[p];
  const t = platformTotals(o.status, p);
  const m = o.match[p];
  return (
    <Card className="min-w-0">
      <header className="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-4">
        <div className="min-w-0">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-fg">{NAME[p]} {sw.live ? <Badge tone="success">Live</Badge> : <Badge>Off</Badge>}</h2>
          <p className="mt-0.5 text-[12.5px] text-muted">
            {sw.switched_at ? <>Switched {sw.live ? "on" : "off"} <span title={formatDateTime(sw.switched_at)}>{relativeTime(sw.switched_at)}</span></> : "Never switched on"}
            {p === "meta" && o.settings.meta.test_event_code && <> · <span className="text-warning">test event code set: events go to Test events only</span></>}
          </p>
        </div>
        <CapiSwitch platform={p} live={sw.live} blockers={sw.blockers} />
      </header>
      {sw.blockers.length > 0 && (
        <div className="border-b border-border bg-warning-bg/50 px-5 py-2.5 text-[12.5px] text-warning">
          Before it can go live: {sw.blockers.map((b) => BLOCKER_LABEL[b] ?? b).join("; ")}. <Link href="/capi?tab=setup" className="font-medium underline">Setup</Link>
        </div>
      )}
      <dl className="grid grid-cols-2 gap-px bg-border sm:grid-cols-4">
        {([["Sent (30 days)", t.sent, ""], ["Waiting", t.waiting, t.waiting > 0 && !sw.live ? "text-warning" : ""], ["Failed or rejected", t.problems, t.problems > 0 ? "text-danger" : ""],
           ["Dry runs (test leads)", t.dry_run, ""]] as const).map(([l, v, c]) => (
          <div key={l} className="bg-surface px-5 py-3">
            <dt className="text-[12px] text-muted">{l}</dt>
            <dd className={cn("tabular mt-0.5 text-xl font-semibold text-fg", c)}>{v}</dd>
          </div>
        ))}
      </dl>
      <div className="px-5 py-4">
        <p className="mb-2 text-[12px] font-medium text-muted">Match keys {m ? <>on {m.events} events</> : ""}</p>
        <ul className="space-y-1.5">
          {KEYS[p].map((k) => {
            const pct = keyShare(m, k);
            return (
              <li key={k} className="flex items-center gap-3 text-[12.5px]">
                <span className="w-32 shrink-0 text-fg">{MATCH_KEY_LABEL[k] ?? k}</span>
                <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2" aria-hidden><span className="block h-full rounded-full bg-amber" style={{ width: `${pct}%` }} /></span>
                <span className="tabular w-10 text-right text-muted">{pct}%</span>
              </li>
            );
          })}
        </ul>
      </div>
    </Card>
  );
}

export default async function CapiPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const status = typeof sp.status === "string" && (sp.status === "problems" || sp.status in EVENT_STATUS) ? sp.status : null;
  const platform = sp.platform === "meta" || sp.platform === "google" ? sp.platform : null;
  const o = await capiOverview(status, platform);
  const problems = (["meta", "google"] as const).reduce((n, p) => n + platformTotals(o.status, p).problems, 0);
  const lead = Number(sp.lead);

  return (
    <>
      <PageHeader title="Conversions (CAPI)"
        description="What happens to leads from Meta and Google ads, reported back so the ad platforms optimise on qualified leads and enrolments, not form fills. Hashed contact details only, consent-gated, test leads never sent." />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="Conversions sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/capi?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}{t.id === "log" && problems > 0 && <Badge tone="danger" className="ml-1.5">{problems}</Badge>}
          </Link>
        ))}
      </nav>

      {tab === "overview" && (
        <div className="space-y-6">
          <div className="grid gap-6 xl:grid-cols-2">
            <PlatformCard p="meta" o={o} />
            <PlatformCard p="google" o={o} />
          </div>
          <Card className="min-w-0">
            <CardHeader title="By milestone, last 30 days" description="Each milestone is sent once per lead and enquiry (event ID lead:stage:cycle), so retries never double count." />
            {o.events.length === 0 ? (
              <EmptyState icon={BarChart3} title="Nothing yet">Leads need an ad identifier (a Meta lead ID, fbclid, gclid…) to make events. Use Check a lead to see why a lead makes none.</EmptyState>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[640px] text-left text-[12.5px]">
                  <thead className="text-[11px] uppercase tracking-wider text-subtle">
                    <tr className="border-b border-border">
                      <th scope="col" className="px-5 py-2 font-medium">Platform</th>
                      <th scope="col" className="px-3 py-2 font-medium">Milestone</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">Sent</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">7 days</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">Waiting</th>
                      <th scope="col" className="px-3 py-2 text-right font-medium">Failed</th>
                      <th scope="col" className="px-5 py-2 text-right font-medium">Value sent</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {o.events.map((e) => (
                      <tr key={`${e.platform}.${e.stage}`}>
                        <td className="px-5 py-2 text-muted">{NAME[e.platform]}</td>
                        <td className="px-3 py-2 font-medium text-fg">{STAGE_LABEL[e.stage]?.label ?? e.stage}{e.platform === "meta" && <span className="ml-1.5 font-normal text-subtle">“{e.event_name}”</span>}</td>
                        <td className="tabular px-3 py-2 text-right">{e.sent}</td>
                        <td className="tabular px-3 py-2 text-right">{e.sent_7d}</td>
                        <td className="tabular px-3 py-2 text-right">{e.waiting}</td>
                        <td className={cn("tabular px-3 py-2 text-right", e.failed > 0 && "text-danger")}>{e.failed}</td>
                        <td className="tabular px-5 py-2 text-right">{formatInr(e.value_inr)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </div>
      )}

      {tab === "log" && (
        <Card className="min-w-0">
          <CardHeader title="Event log" description="The latest 150. Retried after 1, 5 and 30 minutes, 2 and 6 hours; events a platform refuses are not retried." />
          <div className="flex flex-wrap gap-1.5 border-b border-border px-5 py-2.5 text-[12.5px]">
            {[["All", null], ["Problems", "problems"], ["Held", "held"], ["Sent", "sent"], ["Dry runs", "dry_run"], ["Skipped", "skipped"]].map(([l, v]) => (
              <Link key={l} href={`/capi?tab=log${v ? `&status=${v}` : ""}${platform ? `&platform=${platform}` : ""}`}
                className={cn("rounded-md border px-2 py-1", status === v ? "border-amber bg-amber/10 text-fg" : "border-border text-muted hover:text-fg")}>{l}</Link>
            ))}
            <span className="mx-1 w-px bg-border" aria-hidden />
            {[["Both", null], ["Meta", "meta"], ["Google", "google"]].map(([l, v]) => (
              <Link key={l} href={`/capi?tab=log${status ? `&status=${status}` : ""}${v ? `&platform=${v}` : ""}`}
                className={cn("rounded-md border px-2 py-1", platform === v ? "border-amber bg-amber/10 text-fg" : "border-border text-muted hover:text-fg")}>{l}</Link>
            ))}
          </div>
          <EventLog rows={o.log} />
        </Card>
      )}

      {tab === "setup" && (
        <Card className="min-w-0">
          <CardHeader title="Setup" description="Accounts, credentials and which milestones each platform receives. Credentials are stored in the database vault and never shown again." />
          <SetupForm s={o.settings} />
        </Card>
      )}

      {tab === "check" && (
        <Card className="min-w-0">
          <CardHeader title="Check a lead" description="Its ad identifiers, consent, milestones and the exact event each platform gets. Use a test lead to try a setup: test leads are logged as dry runs, never sent." />
          <LeadCheck initial={Number.isInteger(lead) && lead > 0 ? lead : null} />
        </Card>
      )}
    </>
  );
}
