import type { Metadata } from "next";
import { ExternalLink, Search } from "lucide-react";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { inr } from "@/lib/format";
import { SuggestCorrection } from "./SuggestCorrection";

export const metadata: Metadata = { title: "Programmes" };

type Prog = {
  id: number; name: string; course: string; specialization: string | null; level: string | null; mode: string | null; university: string;
  university_short: string | null; accreditation: string | null; fee_total: number | null; fee_yearly: number | null; fee_semester: number | null;
  min_qualification: string | null; min_pct: number | null; eligibility: string | null; brochure_url: string | null;
};

/** The course catalogue (read-only, from the shared catalog): fees, eligibility, brochure. */
export default async function ProgrammesPage({ searchParams }: { searchParams: Promise<{ q?: string; level?: string; mode?: string; max?: string }> }) {
  await requireUser("sales", "/s/programmes");
  const sp = await searchParams;
  let res: { total: number; rows: Prog[] } | null;
  try {
    res = await rpc("programme_search", { p: { q: sp.q || null, level: sp.level || null, mode: sp.mode || null, fee_max: sp.max || null, limit: 100 } });
  } catch (e) {
    return <Page title="Programmes"><SetupError error={e} /></Page>;
  }
  const rows = res?.rows ?? [];
  return (
    <Page title="Programmes" sub={`${res?.total ?? 0} programmes`}>
      <form className="row wrap" action="/s/programmes" role="search">
        <label className="search grow"><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Programme, university, specialization" aria-label="Search programmes" /></label>
        <select className="input" name="level" defaultValue={sp.level ?? ""} style={{ width: "auto" }} aria-label="Level">
          <option value="">Any level</option><option>UG</option><option>PG</option><option>Diploma</option><option>Certificate</option><option>Doctorate</option>
        </select>
        <select className="input" name="mode" defaultValue={sp.mode ?? ""} style={{ width: "auto" }} aria-label="Mode">
          <option value="">Any mode</option><option>Online</option><option>Distance</option><option>Regular</option><option>Hybrid</option>
        </select>
        <input className="input" name="max" type="number" min={0} defaultValue={sp.max ?? ""} placeholder="Max fee ₹" style={{ width: 130 }} aria-label="Maximum fee" />
        <button className="btn ghost" type="submit">Search</button>
      </form>
      {rows.length === 0 ? <Empty>No programmes match.</Empty> : (
        <div className="table-wrap">
          <table>
            <thead><tr><th>Programme</th><th>University</th><th>Level · mode</th><th>Eligibility</th><th className="right">Fee (total)</th><th /></tr></thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}>
                  <td><b>{p.name}</b>{p.specialization ? <div className="small muted">{p.specialization}</div> : null}</td>
                  <td>{p.university}{p.accreditation ? <div className="small muted">{p.accreditation}</div> : null}</td>
                  <td>{[p.level, p.mode].filter(Boolean).join(" · ") || "—"}</td>
                  <td className="small">{p.eligibility ?? [p.min_qualification, p.min_pct ? `${p.min_pct}%` : null].filter(Boolean).join(", ") ?? "—"}</td>
                  <td className="right num">{inr(p.fee_total ?? p.fee_yearly)}</td>
                  <td className="row" style={{ gap: 2, justifyContent: "flex-end" }}>{p.brochure_url && <a className="btn quiet sm" href={p.brochure_url} target="_blank" rel="noopener noreferrer">Brochure <ExternalLink className="icon s" aria-hidden /></a>}<SuggestCorrection programmeId={p.id} name={`${p.name}${p.specialization ? ` · ${p.specialization}` : ""} · ${p.university}`} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Page>
  );
}
