"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { programmeFitRows } from "@/app/s/workspace-actions";
import { inr } from "@/lib/format";
import { duration, type Programme } from "@/lib/programmes";
import { ShareSheet } from "@/components/programmes/ShareSheet";

const MATCH: Record<string, string> = { course: "programme", specialization: "specialization", university: "university", mode: "mode" };

const yesNo = (v: boolean | null | undefined, yes: string, no: string) =>
  v === null || v === undefined ? <span className="muted">—</span> : <span className={`chip ${v ? "ok" : "breach"}`}>{v ? yes : no}</span>;

/**
 * Programme fit (spec B8.3): the catalogue ranked against the lead's interest, with eligibility (qualification against the
 * minimum), budget, EMI and duration side by side. Tick up to four, then share them (message and brochures) on WhatsApp or
 * by email, or record that they were explained; or compare them on the Programme page.
 */
export function ProgrammeFit({ leadId, canShare, firstName, counsellor, hasEmail, programmes = "/s/programmes" }: {
  leadId: number; canShare: boolean; firstName: string | null; counsellor: string | null; hasEmail: boolean; programmes?: string;
}) {
  const [fit, setFit] = useState<{ interest: Record<string, string | null>; rows: Programme[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [picked, setPicked] = useState<number[]>([]);
  const [sharing, setSharing] = useState(false);

  useEffect(() => {
    let live = true;
    programmeFitRows(leadId).then((r) => live && (r.ok ? setFit(r.data ?? null) : setError(r.error)));
    return () => { live = false; };
  }, [leadId]);

  const toggle = (id: number) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length >= 4 ? (toast.error("Choose at most four at a time."), p) : [...p, id]));
  const rows = fit?.rows ?? [];
  const chosen = rows.filter((r) => picked.includes(r.id));
  const budget = fit?.interest.budget;

  return (
    <section className="panel">
      <header>
        <h3>Programme fit</h3>
        <Link className="small" href={`${programmes}?lead=${leadId}&eligible=1`}>All programmes for this student</Link>
      </header>
      <div className="body small">
        {error && <p className="error">{error}</p>}
        {!fit && !error && <p className="note">Finding programmes…</p>}
        {fit && rows.length === 0 && <p className="note">{fit.interest.course ? "No programme in the catalogue matches this interest." : "Set the programme under Interest to see programmes that fit."}</p>}
        {rows.length > 0 && (
          <div className="table-wrap" style={{ boxShadow: "none" }}>
            <table>
              <thead><tr>{canShare && <th aria-label="Choose" />}<th>Programme</th><th>Eligible</th><th>{budget ? `Budget ${inr(budget)}` : "Budget"}</th><th className="right">Fee</th><th className="right">EMI</th><th>Duration</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    {canShare && <td><input type="checkbox" checked={picked.includes(r.id)} onChange={() => toggle(r.id)} aria-label={`Choose ${r.name}, ${r.university}`} /></td>}
                    <td>
                      <b>{r.name}</b>{r.specialization ? ` · ${r.specialization}` : ""}
                      <div className="muted">{[r.university, r.mode, r.level].filter(Boolean).join(" · ")}</div>
                      <div className="note">Matches {(r.matched ?? []).map((m) => MATCH[m] ?? m).join(", ")}
                        {r.brochure_url && /^https:\/\//.test(r.brochure_url) && <> · <a href={r.brochure_url} target="_blank" rel="noopener noreferrer">Brochure</a></>}</div>
                    </td>
                    <td title={r.min_qualification ? `Needs ${r.min_qualification}${r.min_pct ? ` (${r.min_pct}%)` : ""}` : undefined}>{yesNo(r.eligible, "Eligible", "Not eligible")}</td>
                    <td>{yesNo(r.within_budget, "Within", "Over")}</td>
                    <td className="right num nowrap">{r.fee_yearly ? `${inr(r.fee_yearly)}/yr` : inr(r.fee_total)}</td>
                    <td className="right num nowrap">{r.emi_monthly ? `${inr(r.emi_monthly)}/mo` : "—"}</td>
                    <td className="nowrap">{duration(r.duration_months) ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {rows.length > 0 && (
          <div className="row wrap" style={{ gap: 6, marginTop: 10 }}>
            {canShare && (
              <button type="button" className="btn ghost sm" disabled={picked.length === 0} onClick={() => setSharing(true)}>
                Share {picked.length > 1 ? `${picked.length} programmes` : picked.length === 1 ? "this programme" : "…"}
              </button>
            )}
            {picked.length >= 2 && <Link className="btn quiet sm" href={`${programmes}?lead=${leadId}&compare=${picked.join(",")}`}>Compare side by side</Link>}
          </div>
        )}
      </div>
      {sharing && <ShareSheet leadId={leadId} rows={chosen} firstName={firstName} counsellor={counsellor} hasEmail={hasEmail}
        onDone={() => { setSharing(false); setPicked([]); }} onClose={() => setSharing(false)} />}
    </section>
  );
}
