"use client";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, RotateCcw, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { DELETE_REASONS, humanize, PARTNER_DELETE_REASONS, type DeleteReason } from "@/lib/leads";
import { deleteLeads, restoreLeads } from "./actions";

type Blocked = { id: number; why: string }[];

function reportBlocked(blocked: Blocked) {
  if (blocked.length === 0) return;
  const why = [...new Set(blocked.map((b) => b.why))].join("; ");
  toast.warning(`${blocked.length} ${blocked.length === 1 ? "lead was" : "leads were"} kept`, { description: `${why}. IDs: ${blocked.slice(0, 10).map((b) => b.id).join(", ")}${blocked.length > 10 ? "…" : ""}` });
}

/** Reason picker for moving leads to the recycle bin. A native <dialog>: focus trap, Escape and top layer for free. */
export function DeleteDialog({ ids, partnerCount, open, onClose, onDone }: {
  ids: number[];
  partnerCount: number;
  open: boolean;
  onClose: () => void;
  onDone: (deleted: number[]) => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState<DeleteReason | null>(null);
  const [pending, start] = useTransition();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) { setReason(null); d.showModal(); }
    if (!open && d.open) d.close();
  }, [open]);

  const allowed = (r: DeleteReason) => partnerCount === 0 || PARTNER_DELETE_REASONS.includes(r);
  const n = ids.length;

  const confirm = () => {
    if (!reason) return;
    start(async () => {
      const res = await deleteLeads(ids, reason);
      if (!res.ok) { toast.error(res.error); return; }
      if (res.deleted.length) toast.success(`${res.deleted.length} ${res.deleted.length === 1 ? "lead" : "leads"} moved to the recycle bin`);
      reportBlocked(res.blocked);
      onDone(res.deleted);
      onClose();
    });
  };

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => { if (e.target === ref.current && !pending) onClose(); }}
      aria-labelledby="delete-title"
      className="m-auto w-[min(440px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm"
    >
      <div className="p-5">
        <h2 id="delete-title" className="text-[15px] font-semibold">Move {n} {n === 1 ? "lead" : "leads"} to the recycle bin?</h2>
        <p className="mt-1 text-[13px] leading-5 text-muted">
          They leave every list, report and routing. You can restore them from the recycle bin. Leads with an enrollment are never deleted.
        </p>
        <fieldset className="mt-4">
          <legend className="mb-2 text-[13px] font-medium">Reason</legend>
          <div className="grid grid-cols-2 gap-2">
            {DELETE_REASONS.map((r) => (
              <label
                key={r}
                className={cn(
                  "flex h-9 cursor-pointer items-center gap-2 rounded-lg border px-3 text-[13px] transition-colors",
                  reason === r ? "border-ring bg-amber/10" : "border-border hover:bg-surface-hover",
                  !allowed(r) && "cursor-not-allowed opacity-50",
                )}
              >
                <input type="radio" name="reason" value={r} checked={reason === r} disabled={!allowed(r)} onChange={() => setReason(r)} className="accent-[var(--primary)]" />
                {humanize(r)}
              </label>
            ))}
          </div>
          {partnerCount > 0 && (
            <p className="mt-2 text-[12px] text-muted">
              {partnerCount === n ? (n === 1 ? "This lead is" : "These leads are") : `${partnerCount} of these leads are`} already with a partner, so only junk, spam or a student request can remove {partnerCount === 1 ? "it" : "them"}.
            </p>
          )}
        </fieldset>
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button variant="danger" size="sm" onClick={confirm} disabled={!reason || pending} aria-busy={pending}>
          {pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <Trash2 className="size-3.5" />}
          Move to recycle bin
        </Button>
      </div>
    </dialog>
  );
}

export function useRestore(onDone: (restored: number[]) => void) {
  const [pending, start] = useTransition();
  const restore = (ids: number[]) =>
    start(async () => {
      const res = await restoreLeads(ids);
      if (!res.ok) { toast.error(res.error); return; }
      if (res.restored.length) toast.success(`${res.restored.length} ${res.restored.length === 1 ? "lead" : "leads"} restored`);
      reportBlocked(res.blocked);
      onDone(res.restored);
    });
  return { restore, pending };
}

/** Delete or restore one lead from its drawer. */
export function LeadActions({ id, deleted, withPartner, hasEnrollment }: { id: number; deleted: boolean; withPartner: boolean; hasEnrollment: boolean }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const { restore, pending } = useRestore(() => router.refresh());

  if (deleted) {
    return (
      <Button variant="secondary" size="sm" onClick={() => restore([id])} disabled={pending}>
        {pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />} Restore
      </Button>
    );
  }
  return (
    <>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => setOpen(true)}
        disabled={hasEnrollment}
        title={hasEnrollment ? "Leads with an enrollment cannot be deleted" : undefined}
        className="hover:text-danger"
      >
        <Trash2 className="size-3.5" /> Delete
      </Button>
      <DeleteDialog ids={[id]} partnerCount={withPartner ? 1 : 0} open={open} onClose={() => setOpen(false)} onDone={() => router.refresh()} />
    </>
  );
}
