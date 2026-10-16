"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { documentLink, enrollmentVerify } from "../actions";

export function VerifyButtons({ id, proof, canDecide }: { id: number; proof: string; canDecide: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [back, setBack] = useState(false);
  const [note, setNote] = useState("");
  const open = () => start(async () => {
    const r = await documentLink(proof);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "Could not open." : r.error);
    window.open(r.data, "_blank", "noopener,noreferrer");
  });
  const decide = (ok: boolean) => start(async () => {
    const r = await enrollmentVerify(id, ok, note);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    setBack(false);
    router.refresh();
  });
  return (
    <span className="row wrap" style={{ gap: 4 }}>
      <button type="button" className="btn quiet sm" onClick={open} disabled={busy}>Open proof</button>
      {canDecide && (
        <>
          <button type="button" className="btn primary sm" onClick={() => decide(true)} disabled={busy}>Verify</button>
          <button type="button" className="btn ghost sm" onClick={() => setBack(true)} disabled={busy}>Send back</button>
        </>
      )}
      {back && (
        <Sheet title="Send back to the counsellor" onClose={() => setBack(false)}>
          <label className="field"><span>What is missing (required)</span><textarea className="input" value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} /></label>
          <button type="button" className="btn primary block" disabled={busy || note.trim().length < 3} onClick={() => decide(false)}>Send back</button>
        </Sheet>
      )}
    </span>
  );
}
