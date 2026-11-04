import { type Metadata } from "next";
import Link from "next/link";
import { appName, appNames, alertStates } from "@/components/ui/labels.ts";
import { SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { buttonClass } from "@/components/ui/button.tsx";
import { Card } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { Input } from "@/components/ui/field.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ago, ist, num } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { incidentRowSchema, pageOf, type IncidentRow } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Incidents" };

type Params = { status?: string; app?: string; severity?: string; q?: string; before?: string };

function state(i: IncidentRow): string {
  if (i.resolved_at) return i.resolution ?? "resolved";
  if (i.acknowledged_at) return "acknowledged";
  return alertStates[i.alert_state] ?? i.alert_state;
}

export default async function IncidentsPage({ searchParams }: { searchParams: Promise<Params> }) {
  const p = await searchParams;
  const status = p.status === "resolved" || p.status === "all" ? p.status : "open";
  let page;
  try {
    page = await ui("ui_incidents", pageOf(incidentRowSchema), {
      p_status: status,
      p_app: p.app || null,
      p_severity: p.severity || null,
      p_q: p.q?.trim() || null,
      p_limit: 50,
      p_before: p.before ? Number(p.before) : null,
    });
  } catch (e) {
    return <PageError error={e} />;
  }
  const query = (extra: Record<string, string>) =>
    `/incidents?${new URLSearchParams({ ...Object.fromEntries(Object.entries(p).filter(([k, v]) => v && k !== "before")), ...extra })}`;
  return (
    <>
      <PageHeader
        title="Incidents"
        description="One row per failing check. Open an incident to acknowledge, resolve, mute or propose a fix."
      />
      <Filters reset="/incidents">
        <FilterSelect
          name="status"
          label="Status"
          value={status}
          options={[
            ["open", "Open"],
            ["resolved", "Resolved"],
            ["all", "All"],
          ]}
        />
        <FilterSelect
          name="severity"
          label="Severity"
          value={p.severity}
          options={[
            ["", "Any"],
            ["P1", "P1"],
            ["P2", "P2"],
            ["P3", "P3"],
          ]}
        />
        <FilterSelect name="app" label="App" value={p.app} options={[["", "Any"], ...Object.entries(appNames)]} />
        <label className="grid gap-1 text-xs text-fg-muted">
          Search
          <Input name="q" defaultValue={p.q} placeholder="title or check" className="min-h-9 py-1" />
        </label>
      </Filters>
      <Card>
        {page.rows.length === 0 ? (
          <Empty title={status === "open" ? "No open incidents" : "No incidents match"}>
            Every check that runs is passing{p.app ? ` for ${appName(p.app)}` : ""}.
          </Empty>
        ) : (
          <>
            <ul className="divide-y divide-border md:hidden">
              {page.rows.map((i) => (
                <li key={i.id}>
                  <Link href={`/incidents/${i.id}`} className="grid gap-1 px-4 py-3 hover:bg-surface-2">
                    <span className="flex items-center gap-2">
                      <SeverityBadge severity={i.severity} />
                      <span className="text-xs text-fg-muted">
                        {appName(i.app)} · {i.check_id}
                      </span>
                    </span>
                    <span className="font-medium">{i.title}</span>
                    <span className="flex flex-wrap items-center gap-2 text-xs text-fg-muted">
                      <StatusBadge status={state(i)} /> opened {ago(i.opened_at)} · {num(i.occurrences)}×
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
            <div className="hidden md:block">
              <Table>
                <THead>
                  <TR>
                    <TH>Severity</TH>
                    <TH>Incident</TH>
                    <TH>App</TH>
                    <TH>Opened</TH>
                    <TH className="text-right">Seen</TH>
                    <TH>State</TH>
                  </TR>
                </THead>
                <TBody>
                  {page.rows.map((i) => (
                    <TR key={i.id}>
                      <TD>
                        <SeverityBadge severity={i.severity} />
                      </TD>
                      <TD className="max-w-xl">
                        <Link href={`/incidents/${i.id}`} className="font-medium hover:underline">
                          {i.title}
                        </Link>
                        <p className="text-xs text-fg-muted">
                          {i.check_id}
                          {i.subjects.length
                            ? ` · ${i.subjects.slice(0, 3).join(", ")}${i.subjects.length > 3 ? "…" : ""}`
                            : ""}
                        </p>
                        {i.summary ? <p className="mt-1 line-clamp-2 text-sm text-fg-muted">{i.summary}</p> : null}
                      </TD>
                      <TD>{appName(i.app)}</TD>
                      <TD title={ist(i.opened_at)}>{ago(i.opened_at)}</TD>
                      <TD className="text-right tabular-nums">{num(i.occurrences)}</TD>
                      <TD>
                        <StatusBadge status={state(i)} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </div>
          </>
        )}
      </Card>
      {page.next_before ? (
        <div>
          <Link href={query({ before: String(page.next_before) })} className={buttonClass("secondary")}>
            Older incidents
          </Link>
        </div>
      ) : null}
    </>
  );
}
