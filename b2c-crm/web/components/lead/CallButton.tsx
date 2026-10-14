"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Copy, Phone } from "lucide-react";
import QRCode from "qrcode";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { callLog, callTap, numberCopied } from "@/app/s/actions";
import { maskPhone } from "@/lib/format";
import { OUTCOME_LABEL, OUTCOMES } from "@/lib/labels";
import { NextPicker } from "./NextPicker";

type Open = { callId: number; number: string; tel: string; tappedAt: number };

/**
 * Call (spec B8.2): records the tap, opens the phone's dialler, then asks for the outcome. The log needs an outcome and the
 * next follow-up; talk time is estimated from the time away. An unlogged tap is flagged after 10 minutes by the database.
 */
export function CallButton({ leadId, name, small, label = "Call", pending }: { leadId: number; name: string; small?: boolean; label?: string; pending?: { id: number; number: string; tapped_at: string } | null }) {
  const [open, setOpen] = useState<Open | null>(null);
  const [busy, start] = useTransition();

  function tap() {
    if (pending) {
      setOpen({ callId: pending.id, number: pending.number, tel: `tel:+${pending.number.replace(/\D/g, "")}`, tappedAt: new Date(pending.tapped_at).getTime() });
      return;
    }
    start(async () => {
      const r = await callTap(leadId);
      if (!r.ok || !r.data) return void toast.error(r.ok ? "The call could not start." : r.error);
      setOpen({ callId: r.data.call_id, number: r.data.number, tel: r.data.tel, tappedAt: Date.now() });
      if (window.matchMedia("(pointer: coarse)").matches) window.location.href = r.data.tel;
    });
  }

  return (
    <>
      <button type="button" className={`btn call${small ? " sm" : ""}`} onClick={tap} disabled={busy} aria-label={`Call ${name}`}>
        <Phone className="icon s" aria-hidden />
        {pending ? "Log call" : label}
      </button>
      {open && <CallLogSheet leadId={leadId} name={name} call={open} onClose={() => setOpen(null)} />}
    </>
  );
}

function CallLogSheet({ leadId, name, call, onClose }: { leadId: number; name: string; call: Open; onClose: () => void }) {
  const router = useRouter();
  const [outcome, setOutcome] = useState<string | null>(null);
  const [minutes, setMinutes] = useState(() => Math.max(1, Math.round((Date.now() - call.tappedAt) / 60000)));
  const [note, setNote] = useState("");
  const [next, setNext] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const [desk] = useState(() => typeof window !== "undefined" && !window.matchMedia("(pointer: coarse)").matches);

  function save() {
    if (!outcome || !next) return;
    start(async () => {
      const r = await callLog({ call: call.callId, outcome: outcome as never, duration: outcome === "connected" ? minutes * 60 : 0, note: note || undefined, next }, leadId);
      if (!r.ok) return setError(r.error);
      const moved = r.data?.moved_to ? ` Stage: ${r.data.moved_to} · ${r.data.sub_stage}.` : "";
      toast.success((r.notice ?? "Call logged.") + moved);
      onClose();
      router.refresh();
    });
  }

  return (
    <Sheet title={`Call ${name}`} onClose={onClose}>
      {desk ? <DeskDialer leadId={leadId} call={call} /> : (
        <div className="dialer">
          <span className="eyebrow">Dial from your phone</span>
          <a className="bignum" href={call.tel}>{maskPhone(call.number)}</a>
        </div>
      )}
      <div className="field">
        <span>Outcome</span>
        <div className="pills">
          {OUTCOMES.map((o) => (
            <button key={o} type="button" className="pill" aria-pressed={outcome === o} onClick={() => setOutcome(o)}>{OUTCOME_LABEL[o]}</button>
          ))}
        </div>
      </div>
      {outcome === "connected" && (
        <label className="field">
          <span>Talk time (minutes)</span>
          <input className="input num" type="number" min={0} max={600} value={minutes} onChange={(e) => setMinutes(Number(e.target.value))} style={{ maxWidth: 120 }} />
        </label>
      )}
      <label className="field">
        <span>Notes</span>
        <textarea className="input" value={note} onChange={(e) => setNote(e.target.value)} placeholder="What did you learn?" maxLength={2000} />
      </label>
      <NextPicker value={next} onChange={setNext} />
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={save} disabled={!outcome || !next || busy}>{busy ? "Saving…" : "Save call log"}</button>
    </Sheet>
  );
}

/** On a laptop (spec B8.2): the number in full, a copy button (logged) and a QR code to scan with the work phone. */
function DeskDialer({ leadId, call }: { leadId: number; call: Open }) {
  const [svg, setSvg] = useState<string | null>(null);
  const display = "+" + call.number.replace(/\D/g, "");
  useEffect(() => {
    let live = true;
    QRCode.toString(call.tel, { type: "svg", margin: 0, errorCorrectionLevel: "M", color: { dark: "#052244", light: "#FFFFFF" } }).then((s) => live && setSvg(s)).catch(() => undefined);
    return () => { live = false; };
  }, [call.tel]);
  async function copy() {
    try {
      await navigator.clipboard.writeText(display);
      toast.success("Number copied.");
      void numberCopied(leadId);
    } catch {
      toast.error("Copy did not work; type the number instead.");
    }
  }
  return (
    <div className="dialer">
      <span className="eyebrow">Dial on your work phone</span>
      <span className="bignum">{display}</span>
      <button type="button" className="btn ghost sm" onClick={copy}><Copy className="icon s" aria-hidden />Copy number</button>
      {svg && <div className="qr" role="img" aria-label="QR code: scan with your phone to dial" dangerouslySetInnerHTML={{ __html: svg }} />}
      <span className="note">Scan with your phone's camera to dial, then log the call here.</span>
    </div>
  );
}
