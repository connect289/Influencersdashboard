import { type Metadata } from "next";
import Link from "next/link";
import { IconExternal } from "@/components/icons.tsx";
import { appName } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge, type Tone } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader, Stat } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, inr, istDate, num, usd } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { overviewSchema, type Overview } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Overview" };

function tileTone(a: Overview["apps"][number]): { tone: Tone; label: string } {
  if (a.open.P1 > 0) return { tone: "p1", label: "P1 open" };
  if (a.heartbeats_ok === false) return { tone: "p1", label: "heartbeat lost" };
  if (a.open.P2 > 0) return { tone: "p2", label: "P2 open" };
  if (a.open.P3 > 0) return { tone: "p3", label: "P3 open" };
  return { tone: "ok", label: "ok" };
}

export default async function OverviewPage() {
  let data: Overview;
  try {
    data = await ui("ui_overview", overviewSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Overview"
        description="Every app at a glance: open incidents, heartbeats and today's events. Each number opens the list behind it."
      />
      <section aria-label="Apps" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {data.apps.map((a) => {
          const t = tileTone(a);
          return (
            <Card key={a.key}>
              <CardHeader
                title={
                  <Link href={`/apps/${a.key}`} className="hover:underline">
                    {appName(a.key)}
                  </Link>
                }
                actions={<Badge tone={t.tone}>{t.label}</Badge>}
              />
              <CardBody className="grid grid-cols-3 gap-3">
                {(["P1", "P2", "P3"] as const).map((s) => (
                  <Link
                    key={s}
                    href={`/incidents?app=${a.key}&severity=${s}`}
                    className="rounded-md hover:bg-surface-2"
                  >
                    <Stat label={`Open ${s}`} value={num(a.open[s])} />
                  </Link>
                ))}
                <Stat label="Last heartbeat" value={<span className="text-base">{ago(a.last_heartbeat_at)}</span>} />
                <Link href={`/analytics?app=${a.key}`} className="rounded-md hover:bg-surface-2">
                  <Stat label="Events today" value={num(a.events_today)} />
                </Link>
                <Link href={`/settings/checks?app=${a.key}`} className="rounded-md hover:bg-surface-2">
                  <Stat
                    label="Checks on"
                    value={num(a.checks_on)}
                    hint={a.checks_waiting_setup ? `${a.checks_waiting_setup} wait for Setup` : undefined}
                  />
                </Link>
              </CardBody>
              {a.link ? (
                <div className="border-t border-border px-4 py-2">
                  <a
                    href={a.link}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-sm text-fg-muted hover:underline"
                  >
                    Open {appName(a.key)} <IconExternal size={14} />
                  </a>
                </div>
              ) : null}
            </Card>
          );
        })}
      </section>
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader
            title="What needs attention"
            description="Unacknowledged incidents, open proposals, failing tests and failed alert emails, most urgent first."
          />
          {data.actions.length === 0 ? (
            <Empty title="Nothing waiting">
              No unacknowledged incident, open proposal, failing test or failed alert.
            </Empty>
          ) : (
            <ul className="divide-y divide-border">
              {data.actions.map((x) => (
                <li key={`${x.kind}:${x.id}`}>
                  <Link href={x.href} className="flex items-start gap-3 px-4 py-3 hover:bg-surface-2">
                    {x.kind === "incident" ? (
                      <SeverityBadge severity={x.level} />
                    ) : (
                      <StatusBadge status={x.kind === "proposal" ? "open" : "failed"} />
                    )}
                    <span className="min-w-0 flex-1">
                      <span className="block font-medium">{x.title}</span>
                      <span className="text-xs text-fg-muted">
                        {x.kind} · {appName(x.app)} · {ago(x.at)}
                      </span>
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <div className="grid content-start gap-4">
          <Card>
            <CardHeader
              title="Latest brief"
              actions={
                <Link href="/brief" className="text-sm underline">
                  All briefs
                </Link>
              }
            />
            <CardBody>
              {data.brief ? (
                <>
                  <p className="text-xs text-fg-muted">{istDate(data.brief.for_date)}</p>
                  <p className="mt-1 text-sm whitespace-pre-line">{data.brief.excerpt}</p>
                  <Link href={`/brief/${data.brief.id}`} className="mt-2 inline-block text-sm underline">
                    Read it
                  </Link>
                </>
              ) : (
                <p className="text-sm text-fg-muted">
                  No brief yet: the AI worker writes the first one after its setup (phase 6).
                </p>
              )}
            </CardBody>
          </Card>
          <Card>
            <CardHeader
              title="AI spend today"
              actions={
                <Link href="/audit?kind=ai_calls" className="text-sm underline">
                  Calls
                </Link>
              }
            />
            <CardBody className="grid grid-cols-2 gap-3">
              <Stat
                label="Rupees"
                value={inr(data.ai_today.inr)}
                hint={data.ai_today.cap_inr != null ? `cap ${inr(data.ai_today.cap_inr)}` : "no cap set"}
              />
              <Stat label="Dollars" value={usd(data.ai_today.usd)} hint={`${num(data.ai_today.calls)} calls`} />
            </CardBody>
          </Card>
        </div>
      </div>
    </>
  );
}
