"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { ChevronDown, FileUp, LoaderCircle, RefreshCw, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ITEM_LABEL, itemDetail, parseExportText, type DeadLetter, type ReconItem } from "@/lib/sync";
import { discardEvent, resolveItem, retryEvent, runReconcile, type ReconSummary } from "./sync-actions";

const EXAMPLE = "record_id,stage,sub_stage\nLS-10021,Attempted,RNR\nLS-10022,Admission,";

function summaryText(s: ReconSummary | undefined) {
  if (!s) return "Done";
  return s.new ? `${s.new} new mismatch${s.new === 1 ? "" : "es"}; ${s.open} open in all` : `No new mismatches; ${s.open} open`;
}

export function DeadLetters({ partnerId, items }: { partnerId: number; items: DeadLetter[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<number | null>(null);
  const [discard, setDiscard] = useState<DeadLetter | null>(null);
  const [open, setOpen] = useState<number | null>(null);

  const retry = async (d: DeadLetter) => {
    setBusy(d.id);
    const r = await retryEvent(partnerId, d.id);
    setBusy(null);
    if (!r.ok) { toast.error(r.error); return; }
    const st = r.data?.status;
    if (st === "applied" || st === "ignored") toast.success(`Applied: ${r.data?.result ?? ""}`);
    else toast.warning(`Still ${st === "held_unmapped" ? "held" : "failing"}: ${r.data?.result ?? ""}`);
    router.refresh();
  };

  return (
    <>
      <ul className="divide-y divide-border">
        {items.map((d) => (
          <li key={d.id} className="px-5 py-3 text-[13px]">
            <div className="flex flex-wrap items-start gap-x-3 gap-y-2">
              <div className="min-w-0 flex-1 basis-[16rem]">
                <p className="flex flex-wrap items-center gap-1.5">
                  <Badge tone={d.status === "error" ? "danger" : "warning"}>{d.status === "error" ? "Failed" : "Held"}</Badge>
                  <span className="font-medium text-fg">{d.event_type}</span>
                  <span className="font-mono text-[11.5px] text-subtle">{d.event_id}</span>
                  {d.lead_id && <Link href={`/leads?lead=${d.lead_id}&tab=partner`} className="text-[12px] text-info hover:underline">Lead #{d.lead_id}</Link>}
                </p>
                <p className="mt-0.5 break-words text-[12.5px] text-muted">{d.result ?? "No result recorded"}</p>
                <p className="text-[12px] text-subtle">
                  {d.reference ?? d.record_id ?? "No reference"} · received <span title={formatDateTime(d.received_at)}>{relativeTime(d.received_at)}</span>
                </p>
              </div>
              <div className="flex shrink-0 gap-1.5">
                <Button size="sm" variant="ghost" aria-expanded={open === d.id} onClick={() => setOpen(open === d.id ? null : d.id)}>
                  Raw <ChevronDown className={`size-3.5 transition-transform ${open === d.id ? "rotate-180" : ""}`} />
                </Button>
                <Button size="sm" variant="secondary" disabled={busy !== null} onClick={() => retry(d)}>
                  {busy === d.id ? <LoaderCircle className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />} Retry
                </Button>
                <Button size="sm" variant="ghost" disabled={busy !== null} onClick={() => setDiscard(d)}>Discard</Button>
              </div>
            </div>
            {open === d.id && (
              <pre className="mt-2 max-h-64 overflow-auto rounded-md border border-border bg-surface-2 p-3 font-mono text-[11.5px] leading-5 text-fg">{JSON.stringify(d.raw, null, 2)}</pre>
            )}
          </li>
        ))}
      </ul>
      {items.some((d) => d.status === "held_unmapped") && (
        <p className="border-t border-border px-5 py-3 text-[12.5px] text-muted">
          Held events are applied by themselves when a mapping that covers them is published in the{" "}
          <Link href={`/mapping/${partnerId}?tab=queue`} className="text-info hover:underline">Mapping studio</Link>.
        </p>
      )}
      <ConfirmDialog
        open={discard !== null}
        onClose={() => setDiscard(null)}
        title="Discard this event?"
        confirmLabel="Discard"
        tone="danger"
        reason={{ label: "Reason for the audit log", placeholder: "e.g. partner test event, not a real lead" }}
        onConfirm={async (reason) => {
          if (!discard) return;
          const r = await discardEvent(partnerId, discard.id, reason);
          if (!r.ok) return r.error;
          toast.success("Event discarded");
          router.refresh();
        }}
      >
        The event leaves this list and is never applied, even after a new mapping is published. Its raw payload is kept with your reason.
      </ConfirmDialog>
    </>
  );
}

export function ReconItems({ partnerId, items }: { partnerId: number; items: ReconItem[] }) {
  const router = useRouter();
  const [close, setClose] = useState<{ item: ReconItem; status: "resolved" | "dismissed" } | null>(null);
  return (
    <>
      <ul className="max-h-[520px] divide-y divide-border overflow-y-auto">
        {items.map((i) => {
          const label = ITEM_LABEL[i.kind];
          return (
            <li key={i.id} className="flex flex-wrap items-start gap-x-3 gap-y-2 px-5 py-3 text-[13px]">
              <div className="min-w-0 flex-1 basis-[16rem]">
                <p className="font-medium text-fg" title={label.hint}>{label.title}</p>
                <p className="break-words text-[12.5px] text-muted">
                  {i.lead_id && <><Link href={`/leads?lead=${i.lead_id}&tab=partner`} className="text-info hover:underline">{i.name || `Lead #${i.lead_id}`}</Link> · </>}
                  {itemDetail(i)}
                </p>
                <p className="text-[12px] text-subtle">
                  First seen <span title={formatDateTime(i.first_seen)}>{relativeTime(i.first_seen)}</span>
                  {i.last_seen !== i.first_seen && <> · still there <span title={formatDateTime(i.last_seen)}>{relativeTime(i.last_seen)}</span></>}
                </p>
              </div>
              <div className="flex shrink-0 gap-1.5">
                <Button size="sm" variant="secondary" onClick={() => setClose({ item: i, status: "resolved" })}>Resolved</Button>
                <Button size="sm" variant="ghost" onClick={() => setClose({ item: i, status: "dismissed" })}>Dismiss</Button>
              </div>
            </li>
          );
        })}
      </ul>
      <ConfirmDialog
        open={close !== null}
        onClose={() => setClose(null)}
        title={close?.status === "resolved" ? "Mark as resolved?" : "Dismiss this mismatch?"}
        confirmLabel={close?.status === "resolved" ? "Resolved" : "Dismiss"}
        reason={{ label: "Note for the audit log", placeholder: close?.status === "resolved" ? "e.g. partner re-sent the stage" : "e.g. partner's export runs a day behind" }}
        onConfirm={async (note) => {
          if (!close) return;
          const r = await resolveItem(partnerId, close.item.id, close.status, note);
          if (!r.ok) return r.error;
          toast.success(close.status === "resolved" ? "Marked resolved" : "Dismissed");
          router.refresh();
        }}
      >
        If the next comparison finds the same mismatch, it opens again as a new item.
      </ConfirmDialog>
    </>
  );
}

export function RunNow({ partnerId }: { partnerId: number }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  return (
    <Button size="sm" variant="secondary" disabled={pending} onClick={async () => {
      setPending(true);
      const r = await runReconcile(partnerId, null);
      setPending(false);
      if (!r.ok) { toast.error(r.error); return; }
      toast.success(summaryText(r.data));
      router.refresh();
    }}>
      {pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />} Check now
    </Button>
  );
}

export function ExportCompare({ partnerId }: { partnerId: number }) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [pending, setPending] = useState(false);
  const parsed = text.trim() ? parseExportText(text) : null;

  const onFile = async (f: File | undefined) => {
    if (!f) return;
    if (f.size > 5_000_000) { toast.error("The file is too large (5 MB at most)."); return; }
    if (!/\.(csv|tsv|txt|json)$/i.test(f.name)) { toast.error("Upload a CSV or JSON file. Save Excel sheets as CSV first."); return; }
    setText(await f.text());
  };

  return (
    <div className="space-y-3 px-5 py-4">
      <label className="flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-dashed border-border px-3 py-3 text-[13px] text-muted hover:bg-surface-hover">
        <FileUp className="size-4" /> Choose a CSV or JSON file
        <input type="file" accept=".csv,.tsv,.txt,.json,text/csv,application/json" className="sr-only" onChange={(e) => onFile(e.target.files?.[0])} />
      </label>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={5}
        spellCheck={false}
        aria-label="Partner export"
        placeholder={EXAMPLE}
        className="w-full rounded-lg border border-border bg-surface px-3 py-2 font-mono text-[12px] text-fg placeholder:text-subtle focus:border-amber focus:outline-none"
      />
      {parsed && !parsed.ok && <p className="text-[12.5px] text-danger">{parsed.error}</p>}
      {parsed?.ok && (
        <p className="text-[12.5px] text-muted">
          {parsed.rows.length.toLocaleString("en-IN")} row{parsed.rows.length === 1 ? "" : "s"}
          {parsed.ignored.length > 0 && <> · ignoring {parsed.ignored.join(", ")}</>}
        </p>
      )}
      <p className="text-[12px] text-subtle">Columns: reference (EDW-…) or record_id (the partner&apos;s ID), plus stage and sub_stage. Leads pushed in the last day are not reported missing.</p>
      <Button size="sm" disabled={pending || !parsed?.ok} onClick={async () => {
        setPending(true);
        const r = await runReconcile(partnerId, text);
        setPending(false);
        if (!r.ok) { toast.error(r.error); return; }
        toast.success(summaryText(r.data));
        setText("");
        router.refresh();
      }}>
        {pending ? <LoaderCircle className="size-3.5 animate-spin" /> : null} Compare
      </Button>
    </div>
  );
}
