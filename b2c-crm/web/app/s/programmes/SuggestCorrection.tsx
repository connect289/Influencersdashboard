"use client";
import { useState, useTransition } from "react";
import { Flag } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { catalogueSuggest } from "../bulk-actions";

/** "Suggest a correction" on a programme (spec B8.9): the note reaches the Admin as a support ticket; nothing here is edited. */
export function SuggestCorrection({ programmeId, name }: { programmeId: number; name: string }) {
  const [open, setOpen] = useState(false);
  const [busy, start] = useTransition();
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)} aria-label={`Suggest a correction to ${name}`} title="Suggest a correction"><Flag className="icon s" aria-hidden /></button>
      {open && (
        <Sheet title="Suggest a correction" onClose={() => setOpen(false)}>
          <form className="body stack" action={(f) => start(async () => {
            const r = await catalogueSuggest(programmeId, String(f.get("note") ?? ""));
            if (!r.ok) return void toast.error(r.error);
            toast.success(r.notice ?? "Sent.");
            setOpen(false);
          })}>
            <p className="note">{name}. The catalogue is maintained in the B2B CRM; your note goes to the Admin as a support ticket.</p>
            <label className="field"><span>What is wrong, and what should it say?</span><textarea className="input" name="note" required minLength={5} maxLength={4000} rows={5} placeholder="e.g. The total fee is now ₹1,89,000; the brochure link is dead." /></label>
            <div className="row" style={{ justifyContent: "flex-end" }}>
              <button type="button" className="btn quiet" onClick={() => setOpen(false)}>Cancel</button>
              <button className="btn primary" type="submit" disabled={busy}>{busy ? "Sending…" : "Send to the Admin"}</button>
            </div>
          </form>
        </Sheet>
      )}
    </>
  );
}
