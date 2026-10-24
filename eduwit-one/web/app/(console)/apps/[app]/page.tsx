import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { PanelCard } from "@/components/embeds/panel-card.tsx";
import { IconExternal } from "@/components/icons.tsx";
import { SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ago, ms } from "@/lib/format.ts";
import { embeds } from "@/lib/embeds/index.ts";
import { ui } from "@/lib/ui/api.ts";
import { checksSchema, embedSchema, incidentRowSchema, pageOf, settingsSchema, type Embed } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "App" };

export default async function AppPage({ params }: { params: Promise<{ app: string }> }) {
  const key = (await params).app;
  const app = embeds[key];
  if (!app) notFound();
  // Panels are read in parallel; one that fails shows its own error and the rest still render.
  const [panels, settings, checks, incidents] = await Promise.all([
    Promise.all(app.panels.map((p) => ui("ui_embed", embedSchema, { p_panel: p.id }).catch((): Embed | null => null))),
    ui("ui_settings", settingsSchema).catch(() => null),
    ui("ui_checks", checksSchema, { p_app: key }).catch(() => null),
    ui("ui_incidents", pageOf(incidentRowSchema), { p_status: "open", p_app: key, p_limit: 20 }).catch(() => null),
  ]);
  const hosts = (settings?.hosts?.value ?? {}) as Record<string, string | undefined>;
  const links = app
    .links({
      hosts,
      chatwootAccount: (settings?.chatwoot?.value as { account_id?: string } | undefined)?.account_id,
      wittyWorkflow: (settings?.n8n?.value as { witty_workflow_id?: string } | undefined)?.witty_workflow_id,
    })
    .filter((l): l is { label: string; href: string } => Boolean(l.href));
  return (
    <>
      <PageHeader
        title={app.title}
        description={app.about}
        actions={
          <>
            <Link
              href={`/apps/${key}/operate`}
              className="inline-flex min-h-9 items-center gap-1 rounded-md border border-border bg-surface px-3 text-sm hover:bg-surface-2"
            >
              Operate: set up and run
            </Link>
            {links.map((l) => (
              <a
                key={l.label}
                href={l.href}
                target="_blank"
                rel="noreferrer"
                className="inline-flex min-h-9 items-center gap-1 rounded-md border border-border bg-surface px-3 text-sm hover:bg-surface-2"
              >
                {l.label} <IconExternal size={14} />
              </a>
            ))}
          </>
        }
      />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader title="Open incidents" />
          {!incidents || incidents.rows.length === 0 ? (
            <Empty title="None open" />
          ) : (
            <ul className="divide-y divide-border">
              {incidents.rows.map((i) => (
                <li key={i.id}>
                  <Link href={`/incidents/${i.id}`} className="flex items-center gap-2 px-4 py-2 hover:bg-surface-2">
                    <SeverityBadge severity={i.severity} />
                    <span className="min-w-0 flex-1 truncate">{i.title}</span>
                    <span className="text-xs text-fg-muted">{ago(i.opened_at)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardHeader title="Calls on this page" description="Each panel's read and how long it took." />
          <Table>
            <THead>
              <TR>
                <TH>Panel</TH>
                <TH className="text-right">Took</TH>
              </TR>
            </THead>
            <TBody>
              {app.panels.map((p, n) => (
                <TR key={p.id}>
                  <TD className="text-xs">{p.id}</TD>
                  <TD className="text-right tabular-nums">{panels[n] ? ms(panels[n]?.ms) : "failed"}</TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </Card>
      </div>
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        {app.panels.map((p, n) => (
          <PanelCard key={p.id} panel={p} embed={panels[n] ?? null} />
        ))}
      </div>
      {checks && checks.length ? (
        <Card>
          <CardHeader title="Checks" description="This app's rules and their last result." />
          <ul className="grid gap-x-4 divide-y divide-border sm:grid-cols-2 sm:divide-y-0">
            {checks.map((c) => (
              <li key={c.id}>
                <Link
                  href={`/settings/checks?app=${key}#${c.id}`}
                  className="flex items-center gap-2 px-4 py-2 text-sm hover:bg-surface-2"
                >
                  <StatusBadge status={c.enabled ? (c.last_status ?? "pending") : "not_configured"} />
                  <span className="min-w-0 flex-1 truncate">
                    {c.id}: {c.title}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
      {app.gaps?.length ? (
        <Card>
          <CardHeader title="Done in the app itself" />
          <CardBody className="grid gap-1 text-sm text-fg-muted">
            {app.gaps.map((g) => (
              <p key={g}>{g}</p>
            ))}
          </CardBody>
        </Card>
      ) : null}
    </>
  );
}
