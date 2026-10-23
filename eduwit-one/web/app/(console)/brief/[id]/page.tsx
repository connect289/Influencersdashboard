import { type Metadata } from "next";
import { notFound } from "next/navigation";
import { Markdown } from "@/components/brief/markdown.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Code, PageHeader } from "@/components/ui/state.tsx";
import { istDate, json, usd } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { briefSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Brief" };

export default async function BriefPage({ params }: { params: Promise<{ id: string }> }) {
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  let data;
  try {
    data = await ui("ui_brief", briefSchema, { p_id: id });
  } catch (e) {
    return <PageError error={e} />;
  }
  if (!data) notFound();
  const b = data.brief;
  return (
    <>
      <PageHeader
        title={`Brief for ${istDate(b.for_date)}`}
        description={`${b.tier ?? "regular"} tier · ${b.model ?? "model ?"} · ${usd(b.cost_usd)}`}
      />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardBody>
            <Markdown text={b.body_md} />
          </CardBody>
        </Card>
        <div className="grid content-start gap-4">
          <Card>
            <CardHeader title="Pinned answers" />
            {data.pins.length === 0 ? (
              <p className="px-4 py-3 text-sm text-fg-muted">None pinned for this day.</p>
            ) : (
              <ul className="divide-y divide-border text-sm">
                {data.pins.map((p) => (
                  <li key={p.task_id} className="grid gap-1 px-4 py-2">
                    <span className="font-medium">{p.question}</span>
                    <span>{p.answer}</span>
                    <span className="text-xs text-fg-muted">pinned by {p.pinned_by}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Card>
            <CardHeader title="Built from" description="The numbers the brief was written from." />
            <CardBody>
              <Code>{json(b.stats)}</Code>
            </CardBody>
          </Card>
        </div>
      </div>
    </>
  );
}
