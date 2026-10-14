"use client";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { programmeFit, programmeShare, type Fit, type FitRow } from "@/app/s/actions";
import { shareText } from "@/lib/compose";
import { inr } from "@/lib/format";

const MATCH: Record<string, string> = { course: "programme", specialization: "specialization", university: "university", mode: "mode" };

/**
 * Programme fit (spec B8.3): the catalogue ranked against the lead's interest. Tick up to three, then share them on
 * WhatsApp or by email, or record that they were explained on a call. Each share goes on the timeline (stage 6 needs one).
 */
export function ProgrammeFit({ leadId, canShare, firstName, counsellor, hasEmail }: { leadId: number; canShare: boolean; firstName: string | null; counsellor: string | null; hasEmail: boolean }) {
  const [fit, setFit] = useState<Fit | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [picked, setPicked] = useState<number[]>([]);
  const [sharing, setSharing] = useState(false);

  useEffect(() => {
    let live = true;
    programmeFit(leadId).then((r) => live && (r.ok ? setFit(r.data ?? null) : setError(r.error)));
    return () => { live = false; };
  }, [leadId]);

  const toggle = (id: number) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length >= 3 ? (toast.error("Share at most three at a time."), p) : [...p, id]));
  const rows = fit?.rows ?? [];
  const chosen = rows.filter((r) => picked.includes(r.id));

  return (
    <section className="panel">
      <header>
        <h3>Programme fit</h3>
        <Link className="small" href="/s/programmes">All programmes</Link>
      </header>
      <div className="body small">
        {error && <p className="error">{error}</p>}
        {!fit && !error && <p className="note">Finding programmes…</p>}
        {fit && rows.length === 0 && <p className="note">{fit.interest.course ? "No programme in the catalogue matches this interest." : "Set the programme under Interest to see programmes that fit."}</p>}
        <div className="stack" style={{ gap: 8 }}>
          {rows.map((r) => (
            <label key={r.id} className="row" style={{ alignItems: "flex-start", gap: 8 }}>
              {canShare && <input type="checkbox" checked={picked.includes(r.id)} onChange={() => toggle(r.id)} aria-label={`Choose ${r.name}, ${r.university}`} style={{ marginTop: 3 }} />}
              <span className="grow">
                <b>{r.name}</b>{r.specialization ? ` · ${r.specialization}` : ""} <span className="muted">· {r.university}</span>
                <span className="muted" style={{ display: "block" }}>
                  {[r.mode, r.level, r.fee_total ? `${inr(r.fee_total)} total` : r.fee_yearly ? `${inr(r.fee_yearly)} a year` : null,
                    r.min_qualification ? `needs ${r.min_qualification}${r.min_pct ? ` (${r.min_pct}%)` : ""}` : null].filter(Boolean).join(" · ")}
                </span>
                <span className="note">Matches {r.matched.map((m) => MATCH[m] ?? m).join(", ")}{r.brochure_url ? " · " : ""}
                  {r.brochure_url && /^https:\/\//.test(r.brochure_url) && <a href={r.brochure_url} target="_blank" rel="noopener noreferrer">Brochure</a>}
                </span>
              </span>
            </label>
          ))}
        </div>
        {canShare && rows.length > 0 && (
          <button type="button" className="btn ghost sm" style={{ marginTop: 10 }} disabled={picked.length === 0} onClick={() => setSharing(true)}>
            Share {picked.length > 1 ? `${picked.length} programmes` : picked.length === 1 ? "this programme" : "…"}
          </button>
        )}
      </div>
      {sharing && <ShareSheet leadId={leadId} rows={chosen} firstName={firstName} counsellor={counsellor} hasEmail={hasEmail} onDone={() => { setSharing(false); setPicked([]); }} onClose={() => setSharing(false)} />}
    </section>
  );
}

function ShareSheet({ leadId, rows, firstName, counsellor, hasEmail, onDone, onClose }: { leadId: number; rows: FitRow[]; firstName: string | null; counsellor: string | null; hasEmail: boolean; onDone: () => void; onClose: () => void }) {
  const router = useRouter();
  const [channel, setChannel] = useState<"whatsapp" | "email" | "call" | "meeting">("whatsapp");
  const [text, setText] = useState(() => shareText(rows, firstName, counsellor));
  const [subject, setSubject] = useState(rows.length > 1 ? "The programmes we discussed" : `${rows[0]?.name}, ${rows[0]?.university}`);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const sends = channel === "whatsapp" || channel === "email";

  function share() {
    setError(null);
    start(async () => {
      const r = await programmeShare({ lead: leadId, programmes: rows.map((x) => x.id), channel, text: sends ? text : undefined, subject: channel === "email" ? subject : undefined, note: sends ? undefined : note });
      if (!r.ok) return setError(r.error);
      toast.success(r.notice ?? "Shared.");
      onDone();
      router.refresh();
    });
  }

  return (
    <Sheet title="Share programmes" onClose={onClose}>
      <div className="pills" role="radiogroup" aria-label="How">
        {([["whatsapp", "WhatsApp"], ["email", "Email"], ["call", "Explained on a call"], ["meeting", "In a meeting"]] as const).map(([k, l]) => (
          <button key={k} type="button" className="pill" role="radio" aria-checked={channel === k} aria-pressed={channel === k} onClick={() => setChannel(k)}
            disabled={k === "email" && !hasEmail} title={k === "email" && !hasEmail ? "This lead has no email" : undefined}>{l}</button>
        ))}
      </div>
      {channel === "whatsapp" && <p className="note">Free text goes only within 24 hours of the student&apos;s last message. Outside it, open the chat with a template first.</p>}
      {channel === "email" && (
        <label className="field"><span>Subject</span><input className="input" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={300} /></label>
      )}
      {sends ? (
        <label className="field"><span>Message</span><textarea className="input" rows={10} value={text} onChange={(e) => setText(e.target.value)} maxLength={4000} /></label>
      ) : (
        <label className="field"><span>Note (optional)</span><input className="input" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} placeholder="For example: fees and EMI explained" /></label>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={share} disabled={busy || (sends && !text.trim())}>{busy ? "Saving…" : sends ? "Send" : "Record"}</button>
    </Sheet>
  );
}
