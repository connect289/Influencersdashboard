"use client";
import { useEffect, useId, useRef, useState } from "react";
import { CircleX, LoaderCircle, Power, PowerOff, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { GOLIVE_LABEL, goliveBlocking, golivePasses, type GoliveItem } from "@/lib/routing";
import { setRoutingLive } from "./actions";

/**
 * Turning routing on: a native dialog that lists the go-live items still blocking (b2b.routing_golive_check) and keeps its
 * confirm button disabled while any of them fails. The server re-checks the gate: set_live_switch raises 22023 with the
 * failing items, and that text is shown here.
 */
function TurnOnDialog({ open, onClose, blocking, warnings, livePartners }: {
  open: boolean; onClose: () => void; blocking: GoliveItem[]; warnings: GoliveItem[]; livePartners: number;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const id = useId();
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) { setText(""); setError(null); d.showModal(); }
    if (!open && d.open) d.close();
  }, [open]);

  const confirm = async () => {
    if (!text.trim()) { setError("A reason is required."); return; }
    setPending(true);
    try {
      const err = await setRoutingLive(true, text.trim());
      if (err) setError(err);
      else { toast.success("Automatic routing is on"); onClose(); }
    } catch {
      setError("Something went wrong. Try again.");
    } finally {
      setPending(false);
    }
  };

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => { if (e.target === ref.current && !pending) onClose(); }}
      aria-labelledby={`${id}-title`}
      className="m-auto w-[min(560px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm"
    >
      <div className="p-5">
        <h2 id={`${id}-title`} className="text-[15px] font-semibold">Turn on automatic routing?</h2>
        <div className="mt-1.5 space-y-2 text-[13px] leading-5 text-muted">
          <p>
            Every minute, leads at their decision point are decided in the rulebook&apos;s order: test leads are left alone (R1); partner-barred
            leads, leads with a partner and leads held by B2C stay where they are (R2–R4); junk, programme mismatch, spam and blocked numbers are
            not passed (R5); leads created in the B2C CRM go to B2C sales (R6); unqualified leads go to B2C qualification nurture and come back
            once qualified (R7); qualified leads without partner-sharing consent are asked for it, from Witty&apos;s number or the B2C number (R8);
            every other qualified lead, paid Meta and Google leads included, goes to the best eligible partner (R9).
          </p>
          <p>Witty stops chatting with a student only when a partner accepts the lead or a B2C counsellor is assigned.</p>
          {blocking.length > 0 && (
            <div className="rounded-lg border border-danger/25 bg-danger-bg px-3 py-2 text-danger">
              <p className="font-medium">Routing cannot go live yet. Fix or acknowledge these items in the go-live checklist:</p>
              <ul className="mt-1 space-y-1">
                {blocking.map((i) => (
                  <li key={i.key} className="flex gap-2"><CircleX className="mt-0.5 size-3.5 shrink-0" /> <span><span className="font-medium">{GOLIVE_LABEL[i.key] ?? i.key}</span>{i.why && <>: {i.why}</>}</span></li>
                ))}
              </ul>
            </div>
          )}
          {(warnings.length > 0 || livePartners === 0) && (
            <ul className="space-y-1 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-warning">
              {livePartners === 0 && <li className="flex gap-2"><TriangleAlert className="mt-0.5 size-3.5 shrink-0" /> No partner is live yet, so every qualified lead will go to B2C sales.</li>}
              {warnings.filter((w) => !(w.key === "live_partner" && livePartners === 0)).map((w) => (
                <li key={w.key} className="flex gap-2"><TriangleAlert className="mt-0.5 size-3.5 shrink-0" /> <span>{GOLIVE_LABEL[w.key] ?? w.key}{w.why && <>: {w.why}</>}</span></li>
              ))}
            </ul>
          )}
        </div>
        <div className="mt-4 space-y-1.5">
          <label htmlFor={`${id}-reason`} className="text-[13px] font-medium">Reason for the audit log</label>
          <textarea
            id={`${id}-reason`}
            value={text}
            maxLength={500}
            rows={2}
            onChange={(e) => setText(e.target.value)}
            placeholder="e.g. first partner live, consent texts approved"
            disabled={blocking.length > 0}
            className="w-full resize-none rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 disabled:bg-surface-2 disabled:text-subtle"
          />
        </div>
        {error && <p role="alert" className="mt-3 text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={confirm} disabled={pending || blocking.length > 0} aria-busy={pending}
          title={blocking.length > 0 ? "Blocked by the go-live checklist" : undefined}>
          {pending && <LoaderCircle className="size-3.5 animate-spin" />} Turn on
        </Button>
      </div>
    </dialog>
  );
}

/** The 'routing' live switch: automatic routing of ready leads every minute, behind the Addendum 3 go-live gate. */
export function RoutingSwitch({ live, livePartners, golive }: { live: boolean; livePartners: number; golive: GoliveItem[] }) {
  const [open, setOpen] = useState(false);
  const blocking = goliveBlocking(golive);
  const warnings = golive.filter((i) => !i.blocking && !golivePasses(i));

  if (live) {
    return (
      <>
        <Button variant="danger" size="sm" onClick={() => setOpen(true)}><PowerOff className="size-3.5" /> Turn off automatic routing</Button>
        <ConfirmDialog
          open={open}
          onClose={() => setOpen(false)}
          title="Turn off automatic routing?"
          tone="danger"
          confirmLabel="Turn off"
          reason={{ label: "Reason for the audit log", placeholder: "e.g. partner outage" }}
          onConfirm={async (reason) => {
            const err = await setRoutingLive(false, reason);
            if (err) return err;
            toast.success("Automatic routing is off");
          }}
        >
          <p>
            Ready leads stop routing and wait in the pool; consent requests, re-enquiry detection and the lost grace keep running. Leads already
            routed are not affected. You can still route single leads by hand from Simulate.
          </p>
        </ConfirmDialog>
      </>
    );
  }

  return (
    <div className="flex shrink-0 flex-col items-end gap-1">
      <Button size="sm" onClick={() => setOpen(true)}><Power className="size-3.5" /> Turn on automatic routing</Button>
      {blocking.length > 0 && (
        <span className="text-[11.5px] text-danger">{blocking.length} go-live item{blocking.length === 1 ? "" : "s"} block{blocking.length === 1 ? "s" : ""} it</span>
      )}
      <TurnOnDialog open={open} onClose={() => setOpen(false)} blocking={blocking} warnings={warnings} livePartners={livePartners} />
    </div>
  );
}
