import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, CircleCheck, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { aiRunDetail } from "@/lib/ai/data";
import { changeLine, REC_STATUS_LABEL, RUN_KIND_LABEL, TRIGGER_LABEL } from "@/lib/ai/labels";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "AI run" };
type Props = { params: Promise<{ id: string }> };

/** One optimiser run: what triggered it, every tool call with its output, the report and the validator's verdict. */
export default async function AiRunPage({ params }: Props) {
  await requireAdmin();
  const raw = (await params).id;
  if (!/^\d{1,15}$/.test(raw)) notFound();
  const r = await aiRunDetail(Number(raw));
  if (!r) notFound();
  const v = r.validation;
  // an evidence chip on a recommendation links to #tool-<name>: the first output of that tool carries the anchor (C42)
  const anchorFor = (name: string, i: number) => (r.tool_outputs.findIndex((u) => u.name === name) === i ? `tool-${name}` : undefined);
  return (
    <>
      <Link href="/ai?tab=runs" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Runs</Link>
      <div className="mb-5">
        <h1 className="text-xl font-semibold tracking-tight text-fg">Run #{r.id} · {RUN_KIND_LABEL[r.kind] ?? r.kind}</h1>
        <p className="text-[13px] text-muted">{formatDateTime(r.created_at)} · {TRIGGER_LABEL[r.trigger] ?? r.trigger} · {r.model} · prompt {r.prompt_version ?? "—"} ·
          {" "}{r.tokens_in.toLocaleString("en-IN")} in / {r.tokens_out.toLocaleString("en-IN")} out ({r.cache_read.toLocaleString("en-IN")} cached) · ${Number(r.cost_usd).toFixed(4)}
          {" "}<Badge tone={r.status === "done" ? "success" : r.status === "failed" || r.status === "rejected" ? "danger" : "neutral"}>{r.status}</Badge></p>
      </div>
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Report" />
            <div className="space-y-3 px-5 pb-5 text-[13px]">
              {r.error && <p className="text-danger">{r.error}</p>}
              {r.output?.summary && <p className="text-fg">{r.output.summary}</p>}
              {(r.output?.findings ?? []).map((f, i) => <div key={i}><p className="font-medium text-fg">{f.title}</p><p className="whitespace-pre-line text-muted">{f.detail}</p></div>)}
              {r.recommendations_rows.length > 0 && (
                <div className="border-t border-border pt-3">
                  <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Recommendations filed by this run</p>
                  <ul className="space-y-1">
                    {r.recommendations_rows.map((x) => (
                      <li key={x.id}>
                        <Link href={x.status === "open" ? "/ai?tab=inbox" : "/ai?tab=inbox#change-log"} className="text-info hover:underline">#{x.id}</Link> {x.title}
                        <span className="text-subtle"> · {changeLine(x)} · {REC_STATUS_LABEL[x.status] ?? x.status}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Validator" description="Every number in the report must come from a tool result of this run." />
            <div className="space-y-2 px-5 pb-5 text-[13px]">
              {v ? (v.ok ? <p className="text-success"><CircleCheck className="mr-1 inline size-4" /> {v.checked} numbers checked, all traced to tool results.</p>
                        : <p className="text-danger"><TriangleAlert className="mr-1 inline size-4" /> Not traceable: {(v.unverified ?? []).join(", ")}. Nothing from this run was filed.</p>)
                 : <p className="text-muted">Not validated (the run did not finish).</p>}
              {(v?.rejected_changes ?? []).map((x, i) => <p key={i} className="text-warning">Refused change “{x.title}”: {x.why}</p>)}
            </div>
          </Card>
        </div>
        <Card className="min-w-0">
          <CardHeader title={`Tool calls (${r.tool_outputs.length})`} description="Aggregated and pseudonymised data, exactly as Claude received it. An evidence chip on a recommendation lands on the first call of the tool it cites." />
          <ul className="divide-y divide-border">
            {r.tool_outputs.map((t, i) => (
              <li key={t.call_no} id={anchorFor(t.name, i)} className="scroll-mt-20 px-5 py-2.5 target:bg-amber/10">
                <details>
                  <summary className="cursor-pointer text-[13px]"><span className="font-mono text-fg">{t.name}</span> <span className="text-subtle">{JSON.stringify(t.input)}</span></summary>
                  <pre className="mt-2 max-h-72 overflow-auto rounded-lg bg-surface-2 p-2 text-[11px] text-muted">{JSON.stringify(t.output, null, 2)}</pre>
                </details>
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </>
  );
}
