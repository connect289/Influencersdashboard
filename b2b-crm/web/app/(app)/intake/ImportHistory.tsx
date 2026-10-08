"use client";
import { useState } from "react";
import Link from "next/link";
import { FileSpreadsheet } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button, buttonClass } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { IMPORT_STATUS, ROUTE_CHOICE, type IntakeOverview } from "@/lib/intake";
import { abandonImport, releaseHeld, rollbackImport } from "./actions";

type Row = IntakeOverview["imports"][number];

export function ImportHistory({ rows }: { rows: Row[] }) {
  const [rollback, setRollback] = useState<Row | null>(null);
  const [abandon, setAbandon] = useState<Row | null>(null);
  if (rows.length === 0) return <EmptyState icon={FileSpreadsheet} title="No imports yet">Files you import appear here, with what each created and a 24-hour rollback.</EmptyState>;
  return (
    <>
      <ul className="divide-y divide-border">
        {rows.map((i) => {
          const s = IMPORT_STATUS[i.status] ?? { label: i.status, tone: "neutral" as const };
          const c = i.counts ?? {};
          return (
            <li key={i.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3">
              <div className="min-w-0 flex-1 basis-[16rem]">
                <p className="truncate text-[13.5px] font-medium text-fg">{i.file_name}</p>
                <p className="text-[12px] text-subtle">
                  <span className="tabular">{i.total_rows.toLocaleString("en-IN")}</span> rows
                  {i.source_label && <> · {i.source_label}</>}
                  {i.routing_choice && <> · {ROUTE_CHOICE[i.routing_choice as keyof typeof ROUTE_CHOICE]?.label ?? i.routing_choice}{i.b2c_lane && ` (${i.b2c_lane})`}</>}
                  {" · "}<span title={formatDateTime(i.created_at)}>{relativeTime(i.created_at)}</span>
                </p>
                {i.status === "done" && (
                  <p className="tabular text-[12px] text-muted">{c.created ?? 0} new · {c.merged ?? 0} merged · {c.reopened ?? 0} reopened · {c.skipped ?? 0} skipped{(c.errors ?? 0) > 0 && <span className="text-danger"> · {c.errors} errors</span>}</p>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <Badge tone={s.tone}>{s.label}</Badge>
                {i.held > 0 && <Badge tone="warning"><span className="tabular">{i.held}</span> held</Badge>}
              </div>
              <div className="flex flex-wrap gap-1.5">
                {i.held > 0 && (
                  <Button size="sm" variant="secondary" onClick={async () => { const r = await releaseHeld(i.id, null); if (r.ok) toast.success(`${r.data} leads released for routing`); else toast.error(r.error); }}>Release held</Button>
                )}
                {(i.status === "staging" || i.status === "committing" || i.status === "done") && (
                  <Link href={`/intake?tab=import&import=${i.id}`} className={buttonClass("secondary", "sm")}>{i.status === "staging" ? "Continue" : "Open"}</Link>
                )}
                {i.status === "staging" && <Button size="sm" variant="ghost" onClick={() => setAbandon(i)}>Abandon</Button>}
                {i.can_rollback && <Button size="sm" variant="ghost" onClick={() => setRollback(i)}>Roll back</Button>}
              </div>
            </li>
          );
        })}
      </ul>
      <ConfirmDialog open={Boolean(rollback)} onClose={() => setRollback(null)} title={`Roll back ${rollback?.file_name ?? ""}?`} confirmLabel="Roll back" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. wrong file" }}
        onConfirm={async (note) => { if (!rollback) return; const e = await rollbackImport(rollback.id, note); if (!e) toast.success("Import rolled back"); return e; }}>
        <p>The {rollback?.counts?.created ?? 0} leads this import created are moved to the recycle bin, unless something already routed them. Leads it merged into or reopened keep the new values: a rollback cannot undo a merge.</p>
      </ConfirmDialog>
      <ConfirmDialog open={Boolean(abandon)} onClose={() => setAbandon(null)} title="Abandon this import?" confirmLabel="Abandon"
        onConfirm={async () => { if (!abandon) return; const e = await abandonImport(abandon.id); if (!e) toast.success("Import abandoned"); return e; }}>
        <p>Nothing was written to the leads yet. The checked rows are kept with the import for reference.</p>
      </ConfirmDialog>
    </>
  );
}
