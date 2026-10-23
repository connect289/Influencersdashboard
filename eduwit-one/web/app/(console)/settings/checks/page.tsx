import { type Metadata } from "next";
import Link from "next/link";
import { CheckForm } from "@/components/settings/check-form.tsx";
import { appName, appNames } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, duration } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { checksSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Checks" };

export default async function ChecksPage({ searchParams }: { searchParams: Promise<{ app?: string }> }) {
  const { app } = await searchParams;
  let checks;
  try {
    checks = await ui("ui_checks", checksSchema, { p_app: app || null });
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Checks and thresholds"
        description={
          <>
            Each check is one rule in SQL (docs/CHECKS.md). Change its switch, severity or cadence here, with a reason;
            the shared numbers are in{" "}
            <Link href="/settings/thresholds" className="underline">
              thresholds
            </Link>
            .
          </>
        }
      />
      <Filters reset="/settings/checks">
        <FilterSelect name="app" label="App" value={app} options={[["", "All"], ...Object.entries(appNames)]} />
      </Filters>
      {checks.length === 0 ? (
        <Card>
          <Empty title="No checks" />
        </Card>
      ) : (
        <div className="grid gap-2">
          {checks.map((c) => (
            <Card key={c.id} id={c.id}>
              <details>
                <summary className="flex cursor-pointer flex-wrap items-center gap-2 px-4 py-3">
                  <SeverityBadge severity={c.severity} />
                  <span className="font-medium">{c.id}</span>
                  <span className="min-w-0 flex-1 text-sm">{c.title}</span>
                  {c.enabled ? (
                    <StatusBadge status={c.last_status ?? "pending"} />
                  ) : (
                    <Badge tone="off">{c.disabled_reason?.startsWith("setup:") ? "not configured" : "off"}</Badge>
                  )}
                  {c.muted ? <Badge tone="off">muted</Badge> : null}
                  {c.open_incident ? (
                    <Link href={`/incidents/${c.open_incident}`} className="text-xs underline">
                      incident #{c.open_incident}
                    </Link>
                  ) : null}
                </summary>
                <div className="grid gap-3 border-t border-border px-4 py-3 text-sm">
                  <p className="text-fg-muted">
                    {appName(c.app)} · {c.kind} · every {duration(c.cadence_s)} · last ran {ago(c.last_ran_at)} · v
                    {c.version} by {c.updated_by}
                    {c.disabled_reason ? ` · off: ${c.disabled_reason}` : ""}
                    {c.killed_count ? ` · killed ${c.killed_count}×` : ""}
                  </p>
                  <CheckForm
                    id={c.id}
                    enabled={c.enabled}
                    severity={c.severity}
                    cadence_s={c.cadence_s}
                    open_after={c.open_after}
                    resolve_after={c.resolve_after}
                    blocked={Boolean(c.disabled_reason?.startsWith("blocked:"))}
                  />
                </div>
              </details>
            </Card>
          ))}
        </div>
      )}
    </>
  );
}
