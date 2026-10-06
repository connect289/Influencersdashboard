"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ExternalLink, LoaderCircle, RefreshCw, Sheet, Unlink } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { Notice } from "@/components/ui/Notice";
import { useFormAction } from "@/components/ui/useFormAction";
import { formatDateTime, relativeTime } from "@/lib/format";
import { sheetDue, sheetViewUrl } from "@/lib/gsheet";
import type { PartnerRepo } from "@/lib/programmes-data";
import { connectSheet, disconnectSheet, syncSheet, type SheetState, type Staged } from "../actions";
import { UploadWizard } from "./UploadWizard";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function ConnectForm({ partnerId, source, onDone }: { partnerId: number; source: PartnerRepo["source"]; onDone?: () => void }) {
  const [state, onSubmit, pending] = useFormAction<SheetState>(connectSheet.bind(null, partnerId), undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) { toast.success("Google Sheet connected"); onDone?.(); } }, [state?.ok, onDone]);
  return (
    <form onSubmit={onSubmit} noValidate className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_180px_120px_auto] sm:items-end">
      <label className="block space-y-1"><span className="text-[12px] text-muted">Sheet link</span>
        <input name="link" defaultValue={source?.sheet_id ? sheetViewUrl(source.sheet_id) : ""} placeholder="https://docs.google.com/spreadsheets/d/…" className={field} aria-invalid={Boolean(e.link)} />
        {e.link && <span className="text-xs text-danger">{e.link}</span>}
      </label>
      <label className="block space-y-1"><span className="text-[12px] text-muted">Tab (optional)</span>
        <input name="tab" defaultValue={source?.tab ?? ""} placeholder="First tab" className={field} />
      </label>
      <label className="block space-y-1"><span className="text-[12px] text-muted">Check every (hours)</span>
        <input name="every" inputMode="numeric" defaultValue={source?.sync_every_hours ?? 6} className={field} aria-invalid={Boolean(e.every)} />
        {e.every && <span className="text-xs text-danger">{e.every}</span>}
      </label>
      <Button type="submit" size="sm" disabled={pending} className="h-9">{pending && <LoaderCircle className="size-3.5 animate-spin" />} Connect</Button>
      {state?.error && <p role="alert" className="text-[13px] text-danger sm:col-span-4">{state.error}</p>}
    </form>
  );
}

/** The partner's Google Sheet: connect it, read it now, and see when it last changed. Publishing still goes through review. */
export function SheetSource({ partnerId, source, hasTemplate }: { partnerId: number; source: PartnerRepo["source"]; hasTemplate: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [staged, setStaged] = useState<Staged | null>(null);
  const [editing, setEditing] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const connected = source?.type === "gsheet" && Boolean(source.sheet_id);

  const sync = (force = false) => {
    setError(null);
    start(async () => {
      const r = await syncSheet(partnerId, force);
      if (r.status === "error") setError(r.error);
      else if (r.status === "unchanged") { toast.success("No changes since the last draft"); router.refresh(); }
      else if (r.status === "draft") router.push(`/programmes/${partnerId}/versions/${r.versionId}`);
      else setStaged(r.staged);
    });
  };

  if (staged) return <UploadWizard partnerId={partnerId} hasTemplate={hasTemplate} initial={staged} onCancel={() => setStaged(null)} />;

  return (
    <section className="rounded-[var(--radius-card)] border border-border bg-surface">
      <header className="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-4">
        <div className="min-w-0">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-fg"><Sheet className="size-4 text-success" /> Google Sheet</h2>
          <p className="mt-0.5 text-[13px] text-muted">
            {connected ? "Read on demand; every change becomes a draft to review before it goes live." : "Instead of uploading files, read the partner's live Google Sheet."}
          </p>
        </div>
        {connected && (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => sync(false)} disabled={pending}>{pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />} Sync now</Button>
            <Button size="sm" variant="secondary" onClick={() => setEditing((v) => !v)} disabled={pending}>Change</Button>
            <Button size="sm" variant="ghost" onClick={() => setConfirm(true)} disabled={pending}><Unlink className="size-3.5" /> Disconnect</Button>
          </div>
        )}
      </header>
      <div className="space-y-3 px-5 py-4">
        {connected && source ? (
          <>
            <dl className="grid gap-x-6 gap-y-1.5 text-[13px] sm:grid-cols-[140px_minmax(0,1fr)]">
              <dt className="text-muted">Sheet</dt>
              <dd className="min-w-0"><a href={sheetViewUrl(source.sheet_id!)} target="_blank" rel="noopener noreferrer" className="inline-flex max-w-full items-center gap-1 truncate text-info hover:underline">
                Open in Google Sheets <ExternalLink className="size-3" /></a>{source.tab && <span className="text-muted"> · tab “{source.tab}”</span>}</dd>
              <dt className="text-muted">Last checked</dt>
              <dd className="text-fg">
                {source.last_checked_at ? <span title={formatDateTime(source.last_checked_at)}>{relativeTime(source.last_checked_at)}</span> : "Never"}
                {sheetDue(source.last_checked_at, source.sync_every_hours) && <Badge tone="warning" className="ml-2">Due (every {source.sync_every_hours} h)</Badge>}
              </dd>
              <dt className="text-muted">Last change</dt>
              <dd className="text-fg">{source.last_changed_at ? <span title={formatDateTime(source.last_changed_at)}>{relativeTime(source.last_changed_at)}</span> : "Not read yet"}</dd>
            </dl>
            {source.last_error && !error && <Notice tone="error">Last check failed: {source.last_error}</Notice>}
            {editing && <ConnectForm partnerId={partnerId} source={source} onDone={() => setEditing(false)} />}
            {source.content_hash && (
              <button type="button" onClick={() => sync(true)} disabled={pending} className={cn("text-[12px] text-subtle hover:text-fg hover:underline", pending && "opacity-50")}>
                Read it again even if nothing changed
              </button>
            )}
          </>
        ) : (
          <>
            <ConnectForm partnerId={partnerId} source={source} />
            <p className="text-[12.5px] text-muted">Ask the partner to share the sheet: Share → General access → Anyone with the link → Viewer. Eduwit only reads it.</p>
          </>
        )}
        {error && <Notice tone="error">{error}</Notice>}
      </div>
      <ConfirmDialog open={confirm} onClose={() => setConfirm(false)} title="Disconnect the Google Sheet?" confirmLabel="Disconnect"
        onConfirm={async () => { const err = await disconnectSheet(partnerId); if (err) return err; toast.success("Back to file uploads"); }}>
        The live programmes stay as they are. New versions then come from uploaded files; the link is kept so you can reconnect it.
      </ConfirmDialog>
    </section>
  );
}
