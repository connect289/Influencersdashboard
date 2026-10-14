"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Sprout } from "lucide-react";
import { toast } from "sonner";
import { journeyLead, leadNurture, marketingConsent, nurtureHandover, nurtureSend, optOut, type LeadNurture, type NurtureOptions } from "@/app/w/nurture-actions";
import { when } from "@/lib/format";

/**
 * Nurture on the lead screen (spec B9.0 lead-level control): score, consent per channel, journeys and their steps, replies.
 * Marketing and the Admin can start, pause, stop or move a journey, send a one-off message, hand the lead over and record
 * consent; anyone who works the lead can record an opt-out.
 */
export function NurturePanel({ leadId, marketing, canWork, inPool }: { leadId: number; marketing: boolean; canWork: boolean; inPool: boolean }) {
  const router = useRouter();
  const [state, setState] = useState<{ data: LeadNurture; options: NurtureOptions | null } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const [journey, setJourney] = useState(0);
  const [tpl, setTpl] = useState("");
  const load = () => leadNurture(leadId).then((r) => (r.ok ? setState(r.data!) : setError(r.error)));
  useEffect(() => { void load(); }, [leadId]); // eslint-disable-line react-hooks/exhaustive-deps

  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    await load();
    router.refresh();
  });

  const d = state?.data; const o = state?.options;
  const live = d?.runs.find((r) => r.status === "running" || r.status === "paused");
  return (
    <section className="panel">
      <header><h3><Sprout className="icon s" aria-hidden /> Nurture</h3>{d?.score && <span className="small muted">Score {d.score.score ?? 0} (fit {d.score.fit}, engagement {Math.round(Number(d.score.engagement))})</span>}</header>
      <div className="body small">
        {error && <p className="error">{error}</p>}
        {!d && !error && <p className="note">Loading…</p>}
        {d && (
          <>
            <div className="row wrap" style={{ gap: 6 }}>
              <span className={`chip ${d.consent.whatsapp ? "ok" : "line"}`}>WhatsApp marketing {d.consent.whatsapp ? "allowed" : "not allowed"}</span>
              <span className={`chip ${d.consent.email ? "ok" : "line"}`}>Email marketing {d.consent.email ? "allowed" : "not allowed"}</span>
              {d.score?.dormant_at && <span className="chip line">Dormant since {when(d.score.dormant_at)}</span>}
            </div>
            {live ? (
              <div className="row wrap" style={{ gap: 6 }}>
                <span><b>{live.journey}</b> · step {live.step} · {live.status === "paused" ? "paused" : `next ${when(live.next_at)}`}</span>
                {marketing && (live.status === "running"
                  ? <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => journeyLead(leadId, "pause"))}>Pause</button>
                  : <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => journeyLead(leadId, "resume"))}>Resume</button>)}
                {marketing && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => journeyLead(leadId, "stop"))}>Stop</button>}
              </div>
            ) : <p className="muted">Not in a journey.</p>}
            {marketing && o && (
              <div className="stack" style={{ gap: 6 }}>
                <div className="row" style={{ gap: 6 }}>
                  <select className="input grow" value={journey} onChange={(e) => setJourney(Number(e.target.value))} aria-label="Journey">
                    <option value={0}>{live ? "Move to journey…" : "Start a journey…"}</option>
                    {o.journeys.map((j) => <option key={j.id} value={j.id}>{j.name}{j.status !== "active" ? ` (${j.status})` : ""}</option>)}
                  </select>
                  <button type="button" className="btn ghost sm" disabled={busy || !journey} onClick={() => run(() => journeyLead(leadId, "start", journey))}>{live ? "Move" : "Start"}</button>
                </div>
                <div className="row" style={{ gap: 6 }}>
                  <select className="input grow" value={tpl} onChange={(e) => setTpl(e.target.value)} aria-label="One-off message">
                    <option value="">Send one message…</option>
                    {o.templates.map((t) => <option key={`${t.channel}:${t.id}`} value={`${t.channel}:${t.id}`}>{t.channel === "whatsapp" ? "WhatsApp" : "Email"}: {t.name}</option>)}
                  </select>
                  <button type="button" className="btn ghost sm" disabled={busy || !tpl} onClick={() => { const [c, i] = tpl.split(":"); run(() => nurtureSend(leadId, c as "whatsapp" | "email", Number(i))); }}>Send</button>
                </div>
                <div className="row wrap" style={{ gap: 6 }}>
                  {inPool && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => { const why = prompt("Why hand this lead to a counsellor now?"); if (why) run(() => nurtureHandover(leadId, why)); }}>Hand to a counsellor</button>}
                  {(["whatsapp", "email"] as const).map((ch) => (
                    <button key={ch} type="button" className="btn quiet sm" disabled={busy}
                      onClick={() => run(() => marketingConsent(leadId, ch, !d.consent[ch], "staff"))}>{d.consent[ch] ? `Withdraw ${ch} consent` : `Record ${ch} consent`}</button>
                  ))}
                </div>
              </div>
            )}
            {(marketing || canWork) && (
              <div className="row wrap" style={{ gap: 6 }}>
                <button type="button" className="btn quiet sm" disabled={busy} onClick={() => confirm("The student asked to stop emails?") && run(() => optOut(leadId, ["email"]))}>Opt out of emails</button>
                <button type="button" className="btn quiet sm" disabled={busy} onClick={() => confirm("The student asked to stop all messages? This is final until they opt in again.") && run(() => optOut(leadId, null))}>Opt out of everything</button>
              </div>
            )}
            {d.replies.length > 0 && (
              <details className="more"><summary>Replies ({d.replies.length})</summary>
                {d.replies.map((x) => <div key={x.id}>{when(x.created_at)} · {x.channel} · <b>{x.corrected_class ?? x.class ?? "unclassified"}</b>: {x.text ?? x.button}</div>)}
              </details>
            )}
            {d.runs.length > 0 && (
              <details className="more"><summary>Journey history ({d.runs.length})</summary>
                {d.runs.map((r) => (
                  <div key={r.id} style={{ marginTop: 6 }}>
                    <b>{r.journey}</b> · {when(r.entered_at)} → {r.exited_at ? `${when(r.exited_at)} (${r.exit_reason})` : r.status}
                    <div className="muted">{r.log.map((l) => `${l.step}: ${l.outcome}${l.detail?.blocked ? ` (${String(l.detail.blocked)})` : ""}`).join(" · ")}</div>
                  </div>
                ))}
              </details>
            )}
          </>
        )}
      </div>
    </section>
  );
}
