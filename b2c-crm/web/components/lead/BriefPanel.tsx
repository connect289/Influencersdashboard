"use client";
import { useEffect, useState, useTransition } from "react";
import { RefreshCw, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { briefGet, briefRefresh, type Brief } from "@/app/brief-actions";
import { when } from "@/lib/format";

function sourceLabel(s: string): string {
  if (s === "partner") return "partner history";
  if (s.startsWith("witty:")) return "Witty chat";
  if (s.startsWith("activity:")) return "activity";
  if (s.startsWith("field:")) return s.slice(6).replace(/[._]/g, " ");
  return s;
}

/**
 * Brief before you call (spec B8.3): 3-5 lines from the lead's fields, Witty chat and activity, each with its source.
 * Written by Claude from input with phone numbers and emails removed; refreshed when a key fact changes.
 */
export function BriefPanel({ leadId, autoWrite }: { leadId: number; autoWrite: boolean }) {
  const [b, setB] = useState<Brief | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const refresh = (quiet = false) => start(async () => {
    const r = await briefRefresh(leadId);
    if (!r.ok) { if (!quiet) toast.error(r.error); else setErr(r.error); return; }
    setB(r.data ?? null);
    setErr(null);
  });
  useEffect(() => {
    let live = true;
    briefGet(leadId).then((r) => {
      if (!live) return;
      if (!r.ok) return setErr(r.error);
      setB(r.data ?? null);
      if (autoWrite && r.data && r.data.stale && !r.data.error) refresh(true);
    });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [leadId]);
  return (
    <section className="brief" aria-label="Brief before you call" aria-busy={busy}>
      <div className="row" style={{ gap: 6 }}>
        <b className="grow"><Sparkles className="icon s" aria-hidden /> Brief before you call</b>
        {b?.written_at && <span className="small muted">{b.stale ? "out of date · " : ""}{when(b.written_at)}</span>}
        <button type="button" className="btn quiet sm" disabled={busy} onClick={() => refresh()} aria-label="Write the brief again"><RefreshCw className="icon s" aria-hidden />{busy ? "Writing…" : "Refresh"}</button>
      </div>
      {b && b.lines.length > 0 ? (
        <ul>{b.lines.map((l, i) => <li key={i}>{l.text}<span className="brief-src">{sourceLabel(l.source)}</span></li>)}</ul>
      ) : busy ? <p className="note">Claude is reading the record…</p> : (
        <p className="note">{err ?? b?.error ?? "No brief yet. Press Refresh to write one."}</p>
      )}
      {b && b.lines.length > 0 && <p className="note">Written by Claude without the student's phone or email. Check what matters before relying on it.</p>}
    </section>
  );
}
