"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { FileUp, History, LoaderCircle, Radar, Wand2 } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { DRIFT_LABEL, STAGE_LABEL, parseSchemaText, type PartnerSchema, type Studio } from "@/lib/mapping";
import { runBackfill, saveSnapshot } from "./actions";
import { area } from "./Modal";

const EXAMPLE = "kind,name,parent,type\nfield,mx_Highest_Education,,picklist\nvalue,Graduate,mx_Highest_Education,\nstage,Attempted,,\nsub_stage,RNR,Attempted,\npipeline,Online MBA,,\nactivity,Call Log,,\noutcome,Connected,Call Log,";

function fromDiscovered(s: Studio): PartnerSchema {
  return {
    fields: s.discovered.fields.map((f) => ({ name: f.name, values: f.values })),
    stages: s.discovered.stages.map((x) => ({ stage: x.stage, sub_stages: x.sub_stages })),
    pipelines: s.discovered.pipelines,
    activities: s.discovered.activities.map((a) => ({ type: a.type, outcomes: a.outcomes })),
  };
}

export function SchemaPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [pending, setPending] = useState(false);
  const [backfill, setBackfill] = useState(false);
  const snap = studio.snapshot;
  const parsed = text.trim() ? parseSchemaText(text) : null;
  const disc = studio.discovered;

  const save = async (source: "upload" | "events") => {
    setPending(true);
    const r = await saveSnapshot(studio.partner.id, source, source === "upload" ? text : null, source === "events" ? fromDiscovered(studio) : undefined);
    setPending(false);
    if (!r.ok) { toast.error(r.error); return; }
    const n = r.data?.drift.length ?? 0;
    toast.success(snap ? (n ? `Saved; ${n} change${n === 1 ? "" : "s"} since the last schema (see the queue)` : "Saved; no changes since the last schema") : "Schema saved");
    setText(""); router.refresh();
  };

  return (
    <div className="grid gap-6 p-5 xl:grid-cols-2">
      <div className="space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Latest schema" description="The partner's fields, stages, pipelines and activities, as last uploaded or discovered. Each new one is compared with it." />
          <div className="space-y-3 px-5 py-4 text-[13px]">
            {snap ? (
              <>
                <p className="text-muted">
                  <History className="mr-1 inline size-4 text-subtle" />
                  {snap.source === "upload" ? "Uploaded" : snap.source === "events" ? "Discovered from events" : "From the partner's API"} <span title={formatDateTime(snap.created_at)}>{relativeTime(snap.created_at)}</span>
                  {" · "}{snap.schema.fields?.length ?? 0} fields · {snap.schema.stages?.length ?? 0} stages · {snap.schema.pipelines?.length ?? 0} pipelines · {snap.schema.activities?.length ?? 0} activity types
                </p>
                {snap.drift && snap.drift.length > 0 && (
                  <div>
                    <p className="mb-1 font-medium text-fg">Changes against the schema before it</p>
                    <ul className="space-y-1">
                      {snap.drift.map((d, i) => (
                        <li key={i} className="flex flex-wrap items-center gap-1.5 text-[12.5px]">
                          <Badge tone={d.what.startsWith("removed") || d.what === "type_changed" ? "warning" : "info"}>{DRIFT_LABEL[d.what]}</Badge>
                          <span className="text-fg">{d.item}</span>{d.detail && <span className="text-muted">({d.detail})</span>}
                          {d.required && <Badge tone="danger">used by a required mapping</Badge>}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                {snap.drift && snap.drift.length === 0 && <p className="text-success">No changes against the schema before it.</p>}
              </>
            ) : <p className="text-muted">No schema yet. Upload the partner&apos;s field list and status export, or save what its events show.</p>}
          </div>
        </Card>
        <Card className="min-w-0">
          <CardHeader title="What the partner's events show" description="Built from every raw event received, so nothing the partner actually sends is missed." />
          <div className="space-y-3 px-5 py-4 text-[13px]">
            <p className="text-muted">{disc.stages.length} stages · {disc.fields.length} fields · {disc.activities.length} activity types · {disc.pipelines.length} pipelines</p>
            {disc.stages.length > 0 && <p className="text-[12.5px] text-subtle">Stages: {disc.stages.map((s) => s.stage).join(", ")}</p>}
            <Button size="sm" variant="secondary" disabled={pending || (disc.stages.length + disc.fields.length + disc.activities.length === 0)} onClick={() => save("events")}>
              <Radar className="size-3.5" /> Save as the latest schema
            </Button>
          </div>
        </Card>
      </div>
      <div className="space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Upload the partner's field list" description="CSV with the columns kind, name, parent, type, or JSON {fields, stages, pipelines, activities}." />
          <div className="space-y-3 px-5 py-4">
            <textarea value={text} onChange={(e) => setText(e.target.value)} rows={9} className={area} placeholder={EXAMPLE} aria-label="Schema" spellCheck={false} />
            {parsed && !parsed.ok && <p className="text-[12.5px] text-danger">{parsed.error}</p>}
            {parsed?.ok && <p className="text-[12.5px] text-muted">{parsed.schema.fields?.length ?? 0} fields, {parsed.schema.stages?.length ?? 0} stages, {parsed.schema.pipelines?.length ?? 0} pipelines, {parsed.schema.activities?.length ?? 0} activity types.</p>}
            <Button size="sm" disabled={pending || !parsed?.ok} onClick={() => save("upload")}>{pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <FileUp className="size-3.5" />} Save schema</Button>
          </div>
        </Card>
        {studio.backfill && (
          <Card className="min-w-0">
            <CardHeader title="Correct leads already with the partner" description="After changing a stage mapping, apply the active version to the stored partner stage of every lead the partner holds." />
            <div className="space-y-3 px-5 py-4 text-[13px]">
              {studio.backfill.count === 0 ? <p className="text-muted">Every lead&apos;s Eduwit stage already matches the active version.</p> : (
                <>
                  <ul className="space-y-1">
                    {studio.backfill.by_change.map((c) => (
                      <li key={`${c.from}-${c.to}`}><span className="tabular font-medium text-fg">{c.n}</span> <span className="text-muted">lead{c.n === 1 ? "" : "s"}: {STAGE_LABEL[c.from] ?? c.from} → {STAGE_LABEL[c.to] ?? c.to}</span></li>
                    ))}
                  </ul>
                  <Button size="sm" variant="secondary" onClick={() => setBackfill(true)}><Wand2 className="size-3.5" /> Apply to {studio.backfill.count} lead{studio.backfill.count === 1 ? "" : "s"}</Button>
                </>
              )}
            </div>
          </Card>
        )}
      </div>
      <ConfirmDialog
        open={backfill}
        onClose={() => setBackfill(false)}
        title="Correct these leads' stages?"
        confirmLabel="Apply"
        reason={{ label: "Reason for the audit log", placeholder: "e.g. 'Admission' was mapped to Applied by mistake" }}
        onConfirm={async (reason) => {
          const r = await runBackfill(studio.partner.id, reason);
          if (!r.ok) return r.error;
          toast.success(`${r.data} lead${r.data === 1 ? "" : "s"} corrected`);
          router.refresh();
        }}
      >
        A correction may move a stage back; each change is logged on the lead. Lost and duplicate are not applied this way: they need the partner&apos;s event.
      </ConfirmDialog>
    </div>
  );
}
