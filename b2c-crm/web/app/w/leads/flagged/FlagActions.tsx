"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { flagReview } from "../../actions";

/** Keep, close as junk, or close as cannot be served (b2c.flag_review), with an optional note. */
export function FlagActions({ leadId }: { leadId: number }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [note, setNote] = useState("");
  const go = (action: "keep" | "junk" | "cannot_serve") => {
    if (action !== "keep" && !confirm(action === "junk" ? "Close this lead as junk or test?" : "Close this lead as one Eduwit cannot serve?")) return;
    start(async () => {
      const r = await flagReview(leadId, action, note);
      if (!r.ok) return void toast.error(r.error);
      toast.success(r.notice ?? "Done.");
      router.refresh();
    });
  };
  return (
    <div className="row wrap" style={{ gap: 6 }}>
      <input className="input grow" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Note (optional)" aria-label="Note" maxLength={300} />
      <button type="button" className="btn ghost sm" disabled={busy} onClick={() => go("keep")}>Keep</button>
      <button type="button" className="btn danger sm" disabled={busy} onClick={() => go("junk")}>Close as junk</button>
      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => go("cannot_serve")}>Cannot be served</button>
    </div>
  );
}
