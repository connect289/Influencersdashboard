import { type Metadata } from "next";
import Link from "next/link";
import { Funnel } from "@/components/embeds/funnel.tsx";
import { JsonView } from "@/components/embeds/json-view.tsx";
import { SaveViewForm } from "@/components/embeds/view-form.tsx";
import { appName } from "@/components/ui/labels.ts";
import { buttonClass } from "@/components/ui/button.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ms, num } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { analyticsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Analytics" };

const ranges: Array<[string, string]> = [
  ["7", "7 days"],
  ["30", "30 days"],
  ["90", "90 days"],
  ["365", "a year"],
];

/** How long a section's read took in the database (phase 4: every app read is listed with its latency). */
function Took({ value }: { value: number | undefined }) {
  return value == null ? null : <span className="text-xs text-fg-muted tabular-nums">{ms(value)}</span>;
}

export default async function AnalyticsPage({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const days = Number((await searchParams).days ?? 30);
  const range = ranges.some(([d]) => Number(d) === days) ? days : 30;
  let data;
  try {
    data = await ui("ui_analytics", analyticsSchema, { p_days: range });
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Analytics"
        description="The journey across the apps, from one.events: how many leads reached each step and how long each step took. Counts only; no contact field is read."
        actions={
          <a href={`/analytics/export?days=${range}`} className={buttonClass("secondary", "sm")}>
            Export CSV
          </a>
        }
      />
      <Filters reset="/analytics">
        <FilterSelect name="days" label="Period" value={String(range)} options={ranges} />
      </Filters>
      <Card>
        <CardHeader
          title="Funnel"
          actions={<Took value={data.ms?.funnel} />}
          description={
            <>
              Steps and the event types behind each are in{" "}
              <Link href="/settings/analytics" className="underline">
                Settings → analytics
              </Link>
              .
            </>
          }
        />
        <CardBody className="grid gap-4">
          <Funnel steps={data.funnel} />
          <Table>
            <THead>
              <TR>
                <TH>Step</TH>
                <TH className="text-right">Leads</TH>
                <TH className="text-right">Events</TH>
                <TH className="text-right">Median minutes from the step before</TH>
              </TR>
            </THead>
            <TBody>
              {data.funnel.map((s) => (
                <TR key={s.key}>
                  <TD>{s.label}</TD>
                  <TD className="text-right tabular-nums">{num(s.leads)}</TD>
                  <TD className="text-right tabular-nums">{num(s.events)}</TD>
                  <TD className="text-right tabular-nums">{num(s.median_min_from_previous)}</TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </CardBody>
      </Card>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader
            title="By partner"
            description="B2B allocations in the period, test leads excluded."
            actions={<Took value={data.ms?.partners} />}
          />
          <CardBody>
            {typeof data.partners_error === "string" ? (
              <p className="text-sm text-fg-muted">{data.partners_error}</p>
            ) : (
              <JsonView value={data.partners ?? []} />
            )}
          </CardBody>
        </Card>
        <Card>
          <CardHeader
            title="By counsellor"
            description="Spark leads assigned in the period, test leads excluded."
            actions={<Took value={data.ms?.counsellors} />}
          />
          <CardBody>
            {typeof data.counsellors_error === "string" ? (
              <p className="text-sm text-fg-muted">{data.counsellors_error}</p>
            ) : (
              <JsonView value={data.counsellors ?? []} />
            )}
          </CardBody>
        </Card>
      </div>
      <Card>
        <CardHeader title="Events by app" />
        <CardBody className="flex flex-wrap gap-4">
          {Object.entries(data.events_by_app).map(([app, n]) => (
            <span key={app} className="text-sm">
              {appName(app)}: <span className="font-semibold tabular-nums">{num(n)}</span>
            </span>
          ))}
        </CardBody>
      </Card>
      <Card>
        <CardHeader title="Saved views" />
        <CardBody className="grid gap-3">
          {data.views.length ? (
            <ul className="grid gap-1 text-sm">
              {data.views.map((v) => (
                <li key={v.id}>
                  <Link href={`/analytics?days=${(v.params as { days?: number })?.days ?? 30}`} className="underline">
                    {v.name}
                  </Link>{" "}
                  <span className="text-xs text-fg-muted">
                    {v.schedule ? `${v.schedule} email · ` : ""}
                    {v.created_by}
                  </span>
                </li>
              ))}
            </ul>
          ) : null}
          <SaveViewForm page="analytics" params={JSON.stringify({ days: range })} />
        </CardBody>
      </Card>
    </>
  );
}
