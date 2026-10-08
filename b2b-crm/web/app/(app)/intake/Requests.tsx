"use client";
import { useState } from "react";
import { CircleCheck } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { REQUEST_STATUS, SOURCE_LABEL, type IntakeOverview } from "@/lib/intake";
import { discardRequest, retryRequest } from "./actions";

type Row = IntakeOverview["problems"][number];

/** Requests that failed or are held: Meta leads can be fetched again; anything can be discarded with a reason. */
export function Requests({ rows }: { rows: Row[] }) {
  const [discard, setDiscard] = useState<Row | null>(null);
  const [busy, setBusy] = useState<number | null>(null);
  if (rows.length === 0) return <EmptyState icon={CircleCheck} title="Nothing failed">Leads from the API, Meta and Google that could not be stored appear here.</EmptyState>;
  return (
    <>
      <ul className="divide-y divide-border">
        {rows.map((q) => (
          <li key={q.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3 text-[13px]">
            <div className="min-w-0 flex-1 basis-[16rem]">
              <p className="flex items-center gap-2 font-medium text-fg">{SOURCE_LABEL[q.source] ?? q.source}
                <span className="truncate font-mono text-[11.5px] font-normal text-subtle">{q.key}{q.form_ref && ` · form ${q.form_ref}`}</span></p>
              {q.error && <p className="truncate text-[12px] text-danger" title={q.error}>{q.error}</p>}
            </div>
            <span className="text-[12px] text-muted" title={formatDateTime(q.received_at)}>{relativeTime(q.received_at)}{q.attempts > 1 && ` · ${q.attempts} tries`}</span>
            <Badge tone={REQUEST_STATUS[q.status]?.tone ?? "neutral"}>{REQUEST_STATUS[q.status]?.label ?? q.status}</Badge>
            <div className="flex gap-1.5">
              {q.source === "meta" && (
                <Button size="sm" variant="secondary" disabled={busy === q.id}
                  onClick={async () => { setBusy(q.id); const e = await retryRequest(q.id); setBusy(null); if (e) toast.error(e); else toast.success("Queued again"); }}>Retry</Button>
              )}
              <Button size="sm" variant="ghost" onClick={() => setDiscard(q)}>Discard</Button>
            </div>
          </li>
        ))}
      </ul>
      <ConfirmDialog open={Boolean(discard)} onClose={() => setDiscard(null)} title="Discard this request?" confirmLabel="Discard" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. test submission" }}
        onConfirm={async (reason) => { if (!discard) return; const e = await discardRequest(discard.id, reason); if (!e) toast.success("Discarded"); return e; }}>
        <p>No lead is created from it. The raw request is kept for the audit trail.</p>
      </ConfirmDialog>
    </>
  );
}
