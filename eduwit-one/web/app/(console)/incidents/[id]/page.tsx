import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { IncidentActions } from "@/components/incidents/incident-actions.tsx";
import { alertStates, appName } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader, Stat } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Code, Empty, PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ago, duration, ist, istTime, json, ms, num } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { incidentSchema, type IncidentPage } from "@/lib/ui/schemas.ts";
import { z } from "zod";

export const metadata: Metadata = { title: "Incident" };

export default async function IncidentPage({ params }: { params: Promise<{ id: string }> }) {
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  let data: IncidentPage | null;
  try {
    data = await ui("ui_incident", incidentSchema.nullable(), { p_id: id });
  } catch (e) {
    return <PageError error={e} />;
  }
  if (!data) notFound();
  const { incident: i, check } = data;
  const open = !i.resolved_at;
  const evidence = (i.evidence ?? {}) as { value?: unknown; error?: string | null; status?: string };
  return (
    <>
      <PageHeader
        title={i.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={i.severity} />
            <StatusBadge status={open ? (i.acknowledged_at ? "acknowledged" : "open") : (i.resolution ?? "resolved")} />
            <span>
              {appName(i.app)} ·{" "}
              <Link href={`/settings/checks?app=${i.app}#${i.check_id}`} className="underline">
                {i.check_id}
              </Link>{" "}
              · #{i.id}
            </span>
          </span>
        }
      />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="grid min-w-0 content-start gap-4 lg:col-span-2">
          <Card>
            <CardBody className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Stat
                label="Opened"
                value={<span className="text-base">{ago(i.opened_at)}</span>}
                hint={ist(i.opened_at)}
              />
              <Stat label="Last seen" value={<span className="text-base">{ago(i.last_seen_at)}</span>} />
              <Stat
                label="Seen"
                value={`${num(i.occurrences)}×`}
                hint={i.reopened_count ? `reopened ${i.reopened_count}×` : undefined}
              />
              <Stat
                label="Alert"
                value={<span className="text-base">{alertStates[i.alert_state] ?? i.alert_state}</span>}
                hint={i.acknowledged_by ? `ack by ${i.acknowledged_by}` : undefined}
              />
            </CardBody>
            {i.subjects.length ? (
              <CardBody className="border-t border-border text-sm">
                <span className="text-fg-muted">Failing now: </span>
                {i.subjects.join(", ")}
              </CardBody>
            ) : null}
            {i.resolved_at ? (
              <CardBody className="border-t border-border text-sm">
                Resolved {ist(i.resolved_at)} by {i.resolved_by}: {i.resolution}
                {i.resolution_note ? ` · ${i.resolution_note}` : ""}
              </CardBody>
            ) : null}
          </Card>
          <AiNotes summary={i.summary} rootCause={i.root_cause ?? null} tasks={data.ai_tasks} />
          <Card>
            <CardHeader
              title="Evidence"
              description={`The check's value when it last failed${evidence.status ? ` (${evidence.status})` : ""}.`}
            />
            <CardBody className="grid gap-2">
              {evidence.error ? <p className="text-sm text-p1">{evidence.error}</p> : null}
              <Code>{json(evidence.value ?? null)}</Code>
            </CardBody>
          </Card>
          <Card>
            <CardHeader title="Recent runs of the check" />
            {data.results.length === 0 ? (
              <Empty title="No runs recorded" />
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>When</TH>
                    <TH>Result</TH>
                    <TH className="text-right">Took</TH>
                    <TH>Error</TH>
                  </TR>
                </THead>
                <TBody>
                  {data.results.slice(0, 15).map((r) => (
                    <TR key={r.id}>
                      <TD title={ist(r.ran_at)}>{ago(r.ran_at)}</TD>
                      <TD>
                        <StatusBadge status={r.status} />
                      </TD>
                      <TD className="text-right tabular-nums">{ms(r.duration_ms)}</TD>
                      <TD className="max-w-xs truncate text-xs text-fg-muted">{r.error ?? ""}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            )}
          </Card>
          <Card>
            <CardHeader
              title="Timeline"
              description={`${appName(i.app)} events from 30 minutes before to 30 minutes after it opened (contact fields removed).`}
            />
            {data.timeline.length === 0 ? (
              <Empty title="No events in that window" />
            ) : (
              <ol className="max-h-96 divide-y divide-border overflow-y-auto text-sm">
                {data.timeline.map((e) => (
                  <li key={e.id} className="flex gap-3 px-4 py-2">
                    <span className="w-20 shrink-0 text-xs text-fg-muted tabular-nums">{istTime(e.at)}</span>
                    <span className="min-w-0">
                      <span className="font-medium">{e.type}</span>
                      <span className="text-xs text-fg-muted">
                        {" "}
                        · {e.source}
                        {e.lead_id ? ` · lead ${e.lead_id}` : ""}
                      </span>
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </Card>
          {check ? (
            <Card>
              <CardHeader title="The check" description={check.description ?? undefined} />
              <CardBody className="grid gap-2 text-sm">
                <p>
                  {check.kind} · every {duration(check.cadence_s)} · {check.severity}
                  {check.muted ? " · muted" : ""}
                  {check.tags.length ? ` · ${check.tags.join(", ")}` : ""}
                </p>
                {check.auto_fix_id ? (
                  <p>
                    Fix {check.auto_fix_id}:{" "}
                    {check.fix_enabled ? <Badge tone="ok">on</Badge> : <Badge tone="off">off</Badge>}{" "}
                    <Link href="/settings/fixes" className="underline">
                      Settings → Fixes
                    </Link>
                  </p>
                ) : null}
                {check.sql ? (
                  <details>
                    <summary className="cursor-pointer">The rule (SQL)</summary>
                    <Code className="mt-2">{check.sql}</Code>
                  </details>
                ) : null}
              </CardBody>
            </Card>
          ) : null}
        </div>
        <div className="order-first grid min-w-0 content-start gap-4 lg:order-none">
          <Card>
            <CardHeader title="Act" />
            <CardBody>
              <IncidentActions
                id={i.id}
                checkId={i.check_id}
                app={i.app}
                open={open}
                acknowledged={Boolean(i.acknowledged_at)}
              />
            </CardBody>
          </Card>
          <Card>
            <CardHeader title="Alerts sent" />
            {data.deliveries.length === 0 ? (
              <Empty title="None">
                {i.severity === "P1"
                  ? "Muted, held by a storm, or not yet sent."
                  : "P2 goes to the digest, P3 to the dashboard."}
              </Empty>
            ) : (
              <ul className="divide-y divide-border text-sm">
                {data.deliveries.map((d) => (
                  <li key={d.id} className="px-4 py-2">
                    <span className="flex items-center gap-2">
                      <StatusBadge status={d.status} /> {d.kind}
                      {d.level ? ` ${d.level}` : ""}
                    </span>
                    <span className="text-xs text-fg-muted">
                      {d.recipient} · {ago(d.sent_at ?? d.created_at)}
                      {d.error ? ` · ${d.error}` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Linked
            title="Proposals"
            items={data.proposals.map((p) => ({ href: `/proposals/${p.id}`, label: p.title, status: p.status }))}
          />
          <Linked
            title="Fixes run"
            items={data.actions.map((a) => ({
              href: `/actions?fix=${a.fix_id}`,
              label: `${a.fix_id}${a.dry_run ? " (dry run)" : ""}`,
              status: a.status,
            }))}
          />
          <Linked
            title="AI tasks"
            items={data.ai_tasks.map((t) => ({
              href: "/audit?kind=ai_calls",
              label: `${t.kind}${t.model_hint ? ` · ${t.model_hint}` : ""}`,
              status: t.status,
            }))}
          />
          <Linked
            title="Related tests"
            items={data.tests.map((t) => ({
              href: `/tests#${t.id}`,
              label: t.title,
              status: !t.enabled ? "not_configured" : t.last_ok === null ? "pending" : t.last_ok ? "ok" : "failed",
            }))}
          />
          {data.children.length ? (
            <Linked
              title="Held under this storm"
              items={data.children.map((c) => ({
                href: `/incidents/${c.id}`,
                label: c.title,
                status: c.resolved_at ? "resolved" : "open",
              }))}
            />
          ) : null}
        </div>
      </div>
    </>
  );
}

function Linked({ title, items }: { title: string; items: Array<{ href: string; label: string; status: string }> }) {
  return (
    <Card>
      <CardHeader title={title} />
      {items.length === 0 ? (
        <p className="px-4 py-3 text-sm text-fg-muted">None.</p>
      ) : (
        <ul className="divide-y divide-border text-sm">
          {items.map((x, n) => (
            <li key={n}>
              <Link href={x.href} className="flex items-center justify-between gap-2 px-4 py-2 hover:bg-surface-2">
                <span className="min-w-0 truncate">{x.label}</span>
                <StatusBadge status={x.status} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

const classified = z.object({ category: z.string(), confidence: z.string(), note: z.string() });
const triaged = z.object({ next_steps: z.array(z.string()), confidence: z.string() });
const explained = z.object({ explanation: z.string(), confidence: z.string() });
const meta = z.object({ meta: z.object({ model: z.string().optional(), tier: z.string().optional() }) });

/** The AI's notes on the incident: advisory, from masked data; the check decides what is broken (D-075). */
function AiNotes({
  summary,
  rootCause,
  tasks,
}: {
  summary: string | null;
  rootCause: string | null;
  tasks: IncidentPage["ai_tasks"];
}) {
  const done = (kind: string) => tasks.find((t) => t.kind === kind && t.status === "done")?.result;
  const cls = classified.safeParse(done("classify"));
  const tri = triaged.safeParse(done("triage"));
  const exp = explained.safeParse(done("explain"));
  const waiting = tasks.find((t) => t.kind === "triage" && t.status !== "done");
  const by = meta.safeParse(done("triage") ?? done("explain"));
  return (
    <Card>
      <CardHeader
        title="What the AI says"
        description="Advice written from masked data. What is broken is decided by the check's SQL, never by the AI."
      />
      <CardBody className="grid gap-2 text-sm">
        {summary ? (
          <p>{summary}</p>
        ) : waiting?.status === "deferred" ? (
          <p className="text-fg-muted">No summary yet: triage is waiting ({waiting.error ?? "deferred"}).</p>
        ) : waiting?.status === "failed" ? (
          <p className="text-fg-muted">No summary: triage failed ({waiting.error ?? "error"}).</p>
        ) : (
          <p className="text-fg-muted">No summary yet: triage is queued for the AI worker.</p>
        )}
        {rootCause ? (
          <p>
            <span className="font-medium">Likely cause: </span>
            {rootCause}
          </p>
        ) : null}
        {cls.success ? (
          <p>
            <span className="font-medium">Kind of problem: </span>
            {cls.data.category.replaceAll("_", " ")} ({cls.data.confidence} confidence). {cls.data.note}
          </p>
        ) : null}
        {tri.success && tri.data.next_steps.length ? (
          <div>
            <p className="font-medium">Next steps</p>
            <ol className="ml-5 list-decimal">
              {tri.data.next_steps.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ol>
          </div>
        ) : null}
        {exp.success ? (
          <details>
            <summary className="cursor-pointer font-medium">Explanation ({exp.data.confidence} confidence)</summary>
            <p className="mt-2 whitespace-pre-line">{exp.data.explanation}</p>
          </details>
        ) : null}
        {by.success && by.data.meta.model ? (
          <p className="text-xs text-fg-muted">
            Written by {by.data.meta.model}
            {by.data.meta.tier ? ` (${by.data.meta.tier} tier)` : ""}.
          </p>
        ) : null}
      </CardBody>
    </Card>
  );
}
