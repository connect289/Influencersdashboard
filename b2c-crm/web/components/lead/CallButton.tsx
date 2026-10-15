"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Copy, PhoneCall, Phone } from "lucide-react";
import QRCode from "qrcode";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { callLog, numberCopied } from "@/app/s/actions";
import { callGet, callMock, callNote, callStart, type CallView } from "@/app/s/call-actions";
import { maskPhone } from "@/lib/format";
import { OUTCOME_LABEL, OUTCOMES } from "@/lib/labels";
import { NextPicker } from "./NextPicker";

type Open = { callId: number; number: string; tel: string; tappedAt: number };
type Bridge = { callId: number; provider: string; agent: string; number: string };

/**
 * Call (spec B8.2, B8.4). Without telephony (today): records the tap, opens the phone's dialler, then asks for the
 * outcome; the log needs an outcome and the next follow-up, talk time is estimated from the time away, and an unlogged tap
 * is flagged after 10 minutes. With telephony on: the provider rings the counsellor's phone, then the student, and the
 * call logs itself (outcome, real talk time, recording) when it ends; the sheet only follows it and takes a note.
 */
export function CallButton({ leadId, name, small, label = "Call", pending: unlogged }: { leadId: number; name: string; small?: boolean; label?: string; pending?: { id: number; number: string; tapped_at: string; provider?: string } | null }) {
  const pending = unlogged && (unlogged.provider ?? "manual") === "manual" ? unlogged : null;
  const [open, setOpen] = useState<Open | null>(null);
  const [bridge, setBridge] = useState<Bridge | null>(null);
  const [busy, start] = useTransition();

  function tap() {
    if (pending) {
      setOpen({ callId: pending.id, number: pending.number, tel: `tel:+${pending.number.replace(/\D/g, "")}`, tappedAt: new Date(pending.tapped_at).getTime() });
      return;
    }
    start(async () => {
      const r = await callStart(leadId);
      if (!r.ok || !r.data) return void toast.error(r.ok ? "The call could not start." : r.error);
      const d = r.data;
      if (d.mode === "bridge") return void setBridge({ callId: d.call_id, provider: d.provider, agent: d.agent, number: d.number });
      setOpen({ callId: d.call_id, number: d.number, tel: d.tel, tappedAt: Date.now() });
      if (window.matchMedia("(pointer: coarse)").matches) window.location.href = d.tel;
    });
  }

  return (
    <>
      <button type="button" className={`btn call${small ? " sm" : ""}`} onClick={tap} disabled={busy} aria-label={`Call ${name}`}>
        <Phone className="icon s" aria-hidden />
        {pending ? "Log call" : label}
      </button>
      {open && <CallLogSheet leadId={leadId} name={name} call={open} onClose={() => setOpen(null)} />}
      {bridge && <BridgeSheet leadId={leadId} name={name} call={bridge} onClose={() => setBridge(null)} />}
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

const STATUS_TEXT: Record<string, string> = {
  initiated: "Calling your phone…", ringing: "Ringing…", answered: "Connected", completed: "Call ended", no_answer: "No answer", busy: "Busy",
  failed: "Could not connect", agent_no_answer: "Your phone did not answer: the student was not called", missed: "Missed",
};

/** A bridged call: the provider rings the counsellor, then the student; the CRM logs it when it ends. */
function BridgeSheet({ leadId, name, call, onClose }: { leadId: number; name: string; call: Bridge; onClose: () => void }) {
  const router = useRouter();
  const [view, setView] = useState<CallView | null>(null);
  const [note, setNote] = useState("");
  const [busy, start] = useTransition();
  const mock = call.provider === "mock";
  useEffect(() => {
    let live = true;
    const tick = async () => {
      const r = await callGet(call.callId);
      if (live && r.ok && r.data) {
        setView(r.data);
        if (r.data.ended) router.refresh();
      }
    };
    void tick();
    const t = setInterval(() => { if (!view?.ended) void tick(); }, 3000);
    return () => { live = false; clearInterval(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [call.callId, view?.ended]);
  const play = (status: "answered" | "completed" | "no_answer" | "busy" | "agent_no_answer", minutes = 0) => start(async () => {
    const r = await callMock(call.callId, status, minutes, leadId);
    if (!r.ok) return void toast.error(r.error);
    const g = await callGet(call.callId);
    if (g.ok && g.data) setView(g.data);
    router.refresh();
  });
  const saveNote = () => start(async () => {
    const r = await callNote(call.callId, note, leadId);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Note added.");
    onClose();
    router.refresh();
  });
  const ended = !!view?.ended;
  return (
    <Sheet title={`Call ${name}`} onClose={onClose}>
      <div className="dialer">
        <span className="eyebrow">{mock ? "Test call (mock provider: nobody is dialled)" : `Through ${call.provider}: your phone ${call.agent} rings first`}</span>
        <span className="bignum"><PhoneCall className="icon" aria-hidden /> {STATUS_TEXT[view?.status ?? "initiated"] ?? view?.status}</span>
        {ended && view?.outcome && <span className="small">Logged: {OUTCOME_LABEL[view.outcome] ?? view.outcome}{view.duration_s ? ` · ${Math.floor(view.duration_s / 60)} min ${view.duration_s % 60} s` : ""}. The recording is attached when it arrives.</span>}
        {!ended && <span className="note">Pick up your phone; the student is called when you answer. Nothing to log: the call records and logs itself.</span>}
      </div>
      {mock && !ended && (
        <div className="field">
          <span>Play what the provider would report</span>
          <div className="pills">
            <button type="button" className="pill" disabled={busy} onClick={() => play("answered")}>Answered</button>
            <button type="button" className="pill" disabled={busy} onClick={() => play("completed", 3.5)}>Ended after 3½ min</button>
            <button type="button" className="pill" disabled={busy} onClick={() => play("no_answer")}>Student did not answer</button>
            <button type="button" className="pill" disabled={busy} onClick={() => play("busy")}>Busy</button>
            <button type="button" className="pill" disabled={busy} onClick={() => play("agent_no_answer")}>My phone did not answer</button>
          </div>
        </div>
      )}
      {ended && view?.logged && view.outcome && (
        <>
          <label className="field"><span>Add a note (optional)</span>
            <textarea className="input" value={note} onChange={(e) => setNote(e.target.value)} placeholder="What did you learn?" maxLength={2000} /></label>
          <p className="note">A follow-up was suggested from the outcome; change it under Follow-ups if needed.</p>
          <button type="button" className="btn primary block" disabled={busy || !note.trim()} onClick={saveNote}>Save note</button>
        </>
      )}
      {ended && <button type="button" className="btn ghost block" onClick={onClose}>Close</button>}
    </Sheet>
  );
}
