import Link from "next/link";
import { ExternalLink, Search } from "lucide-react";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { SuggestCorrection } from "@/app/s/programmes/SuggestCorrection";
import type { Me } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { inr } from "@/lib/format";
import { commissionText, duration, PAGE_SIZE, programmeQuery, SORTS, type Facets, type Programme, type ProgrammeParams } from "@/lib/programmes";
import { createClient } from "@/lib/supabase/server";
import { FeeRange } from "./FeeRange";
import { SendButton } from "./SendButton";

type SP = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
const ACCREDITATIONS = ["UGC", "UGC-DEB", "AICTE", "NAAC A++", "NAAC A+", "NAAC A", "NIRF", "AIU", "WES"];

type Lead = { lead_id: number; name: string | null; email: string | null; status: string; opted_out: boolean };

/**
 * The Programme page (spec B8.9) for every role: the live catalogue with filters, sort and paging; compare 2–4 side by side;
 * opened from a lead (?lead=), eligibility and budget for that student and sending to them. Partner and Eduwit commission
 * figures come only for the Admin and Marketing (the database leaves them out for everyone else).
 */
export async function Catalogue({ me, base, leadBase, searchParams }: { me: Me; base: string; leadBase: string; searchParams: SP }) {
  const sp = Object.fromEntries(Object.entries(searchParams).map(([k, v]) => [k, first(v)])) as ProgrammeParams;
  const compareIds = [...new Set((Array.isArray(searchParams.compare) ? searchParams.compare : String(searchParams.compare ?? "").split(","))
    .map(Number).filter((n) => Number.isInteger(n) && n > 0))];
  let facets: Facets;
  let res: { total: number; rows: Programme[]; eligible_rank: number | null; budget: number | null };
  let compared: Programme[] | null = null;
  let compareError: string | null = null;
  let lead: Lead | null = null;
  try {
    facets = await rpc<Facets>("programme_facets");
    const q = programmeQuery(sp, facets.fee);
    const supabase = await createClient();
    const [r, l] = await Promise.all([
      rpc<typeof res>("programme_search", { p: q }),
      q.lead ? supabase.from("leads_v").select("lead_id, name, email, status, opted_out").eq("lead_id", q.lead).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    res = r;
    lead = (l.data as Lead | null) ?? null;
    if (compareIds.length > 0) {
      if (compareIds.length < 2 || compareIds.length > 4) compareError = "Choose two to four programmes to compare.";
      else compared = await rpc<Programme[]>("programme_compare", { p_ids: compareIds, p_lead: q.lead }).catch((e: Error) => ((compareError = e.message), null));
    }
  } catch (e) {
    return <Page title="Programmes"><SetupError error={e} /></Page>;
  }
  const page = Math.max(0, Number(sp.page) || 0);
  const canSend = !!lead && me.role !== "marketing" && lead.status === "active" && !lead.opted_out;
  const href = (o: Record<string, string | number | undefined>) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries({ ...sp, compare: compareIds.length ? compareIds.join(",") : undefined, ...o })) if (v !== undefined && v !== "" && v !== null) u.set(k, String(v));
    return `${base}?${u}`;
  };
  const keep = Object.entries(sp).filter(([k, v]) => v && !["page", "compare"].includes(k));
  const sel = (name: keyof ProgrammeParams, label: string, options: string[]) => (
    <select className="input" name={name} defaultValue={sp[name] ?? ""} style={{ width: "auto", maxWidth: 220 }} aria-label={label}>
      <option value="">{label}: any</option>
      {options.filter(Boolean).sort().map((o) => <option key={o} value={o}>{o}</option>)}
    </select>
  );

  return (
    <Page title="Programmes" sub={lead ? <>For <Link href={`${leadBase}/${lead.lead_id}`}>{lead.name ?? `lead #${lead.lead_id}`}</Link> · {res.total} programmes</> : `${res.total} programmes`}>
      <form className="stack tight" action={base} role="search">
        {lead && <input type="hidden" name="lead" value={lead.lead_id} />}
        <label className="search"><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Programme, university, specialization" aria-label="Search programmes" /></label>
        <div className="row wrap" style={{ gap: 6, alignItems: "flex-end" }}>
          {sel("university", "University", facets.universities)}
          {sel("specialization", "Specialization", facets.specializations)}
          {sel("level", "Level", facets.levels)}
          {sel("mode", "Mode", facets.modes)}
          <select className="input" name="duration" defaultValue={sp.duration ?? ""} style={{ width: "auto" }} aria-label="Duration">
            <option value="">Duration: any</option>
            {[6, 12, 18, 24, 36, 48].map((m) => <option key={m} value={m}>Up to {duration(m)}</option>)}
          </select>
          {sel("intake", "Intake", facets.intakes)}
          <input className="input" name="accreditation" list="accreditations" defaultValue={sp.accreditation ?? ""} placeholder="Accreditation (UGC, NAAC…)" style={{ width: 190 }} aria-label="Accreditation" />
          <datalist id="accreditations">{ACCREDITATIONS.map((a) => <option key={a} value={a} />)}</datalist>
          {facets.fee.min !== null && facets.fee.max !== null && facets.fee.max > facets.fee.min && (
            <FeeRange min={facets.fee.min} max={facets.fee.max} from={sp.fee_min ? Number(sp.fee_min) : null} to={sp.fee_max ? Number(sp.fee_max) : null} />
          )}
          <label className="checkbox"><input type="checkbox" name="emi" value="1" defaultChecked={sp.emi === "1"} /> EMI available</label>
          {lead && <label className="checkbox"><input type="checkbox" name="eligible" value="1" defaultChecked={sp.eligible === "1"} /> Eligible for this student</label>}
          <select className="input" name="sort" defaultValue={sp.sort ?? "name"} style={{ width: "auto" }} aria-label="Sort">
            {SORTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
          <button className="btn ghost" type="submit">Show</button>
          <Link className="btn quiet sm" href={lead ? `${base}?lead=${lead.lead_id}` : base}>Clear</Link>
        </div>
        {lead && res.eligible_rank === null && <p className="note">This student&apos;s qualification is not known yet, so eligibility is not checked.</p>}
      </form>

      {compareError && <div className="banner danger" role="alert">{compareError}</div>}
      {compared && (
        <section className="panel">
          <header><h3>Comparing {compared.length}</h3>
            <span className="row" style={{ gap: 6 }}>
              {canSend && <SendButton leadId={lead!.lead_id} rows={compared} firstName={lead!.name} counsellor={me.full_name} hasEmail={!!lead!.email} label={`Send all ${compared.length} to ${(lead!.name ?? "the student").split(" ")[0]}`} />}
              <Link className="btn quiet sm" href={href({ compare: undefined })}>Close</Link>
            </span>
          </header>
          <div className="body"><CompareTable rows={compared} withLead={!!lead} /></div>
        </section>
      )}

      {res.rows.length === 0 ? <Empty>No programmes match. Clear a filter or widen the fee range.</Empty> : (
        <>
          <form id="compare" action={base} className="row wrap" style={{ gap: 6 }}>
            {keep.map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
            <span className="note grow">Tick two to four programmes, then compare them side by side.</span>
            <button className="btn ghost sm" type="submit">Compare ticked</button>
          </form>
          <div className="grid g3">
            {res.rows.map((p) => <ProgrammeCard key={p.id} p={p} withLead={!!lead} checked={compareIds.includes(p.id)}
              send={canSend ? <SendButton leadId={lead!.lead_id} rows={[p]} firstName={lead!.name} counsellor={me.full_name} hasEmail={!!lead!.email} label="Send" /> : null} />)}
          </div>
          {res.total > PAGE_SIZE && (
            <div className="pager">
              {page > 0 && <Link className="btn ghost sm" href={href({ page: page - 1 })}>Previous</Link>}
              <span className="muted">{page * PAGE_SIZE + 1}–{Math.min(res.total, (page + 1) * PAGE_SIZE)} of {res.total}</span>
              {(page + 1) * PAGE_SIZE < res.total && <Link className="btn ghost sm" href={href({ page: page + 1 })}>Next</Link>}
            </div>
          )}
        </>
      )}
    </Page>
  );
}

const fees = (p: Programme) => [
  p.fee_total ? `${inr(p.fee_total)} in all` : null, p.fee_yearly ? `${inr(p.fee_yearly)} a year` : null, p.fee_semester ? `${inr(p.fee_semester)} a semester` : null,
].filter(Boolean).join(" · ") || "Fee not listed";
const extras = (p: Programme) => [p.fee_exam ? `exam ${inr(p.fee_exam)}` : null, p.fee_registration ? `registration ${inr(p.fee_registration)}` : null].filter(Boolean).join(", ");

function FitChips({ p }: { p: Programme }) {
  return (
    <span className="row wrap" style={{ gap: 4 }}>
      {p.eligible !== null && <span className={`chip ${p.eligible ? "ok" : "breach"}`}>{p.eligible ? "Eligible" : "Not eligible"}</span>}
      {p.within_budget !== null && <span className={`chip ${p.within_budget ? "ok" : "risk"}`}>{p.within_budget ? "Within budget" : "Over budget"}</span>}
    </span>
  );
}

function ProgrammeCard({ p, withLead, checked, send }: { p: Programme; withLead: boolean; checked: boolean; send: React.ReactNode }) {
  const name = `${p.name}${p.specialization ? ` · ${p.specialization}` : ""} · ${p.university}`;
  return (
    <article className="card pad stack tight">
      <div className="row between" style={{ alignItems: "flex-start" }}>
        <label className="row" style={{ gap: 8, alignItems: "flex-start" }}>
          <input type="checkbox" name="compare" value={p.id} form="compare" defaultChecked={checked} aria-label={`Compare ${name}`} style={{ marginTop: 4 }} />
          <span><b>{p.name}</b>{p.specialization ? <span className="muted"> · {p.specialization}</span> : null}
            <span className="small muted" style={{ display: "block" }}>{p.university}{p.accreditation ? ` · ${p.accreditation}` : ""}</span></span>
        </label>
        <SuggestCorrection programmeId={p.id} name={name} />
      </div>
      {withLead && <FitChips p={p} />}
      <dl className="kv small">
        <dt>Level · mode</dt><dd>{[p.level, p.mode].filter(Boolean).join(" · ") || "—"}</dd>
        <dt>Duration</dt><dd>{duration(p.duration_months) ?? "—"}</dd>
        <dt>Fees</dt><dd>{fees(p)}{extras(p) ? <span className="muted" style={{ display: "block" }}>Plus {extras(p)}</span> : null}</dd>
        <dt>EMI</dt><dd>{p.emi_monthly ? `From ${inr(p.emi_monthly)} a month` : "—"}</dd>
        {p.scholarship && <><dt>Scholarship</dt><dd>{p.scholarship}</dd></>}
        <dt>Intakes</dt><dd>{p.intakes?.length ? p.intakes.join(", ") : "—"}{p.deadline ? <span className="muted" style={{ display: "block" }}>Apply by {p.deadline}</span> : null}</dd>
        <dt>Eligibility</dt><dd>{p.eligibility ?? ([p.min_qualification, p.min_pct ? `${p.min_pct}%` : null].filter(Boolean).join(", ") || "—")}</dd>
        {p.enrollments > 0 && <><dt>Enrolled</dt><dd>{p.enrollments} through Eduwit</dd></>}
        {p.partners && p.partners.length > 0 && <><dt>Partners</dt><dd>{p.partners.map((x) => `${x.name} (${commissionText(x.commission)})`).join(", ")}</dd></>}
        {p.eduwit_commission && <><dt>Eduwit commission</dt><dd>{p.eduwit_commission.amount ? inr(p.eduwit_commission.amount) : "—"} <span className="muted">({p.eduwit_commission.rate_type === "percent" ? `${p.eduwit_commission.value}% of the ${p.eduwit_commission.fee_base} fee` : "fixed"})</span></dd></>}
      </dl>
      <div className="row wrap" style={{ gap: 6 }}>
        {p.brochure_url && /^https:\/\//.test(p.brochure_url) && <a className="btn quiet sm" href={p.brochure_url} target="_blank" rel="noopener noreferrer">Brochure <ExternalLink className="icon s" aria-hidden /></a>}
        {send}
      </div>
    </article>
  );
}

function CompareTable({ rows, withLead }: { rows: Programme[]; withLead: boolean }) {
  const line = (label: string, f: (p: Programme) => React.ReactNode) => (
    <tr><th scope="row" className="small muted">{label}</th>{rows.map((p) => <td key={p.id} className="small">{f(p)}</td>)}</tr>
  );
  const money = rows.some((p) => p.partners !== undefined);
  return (
    <div className="table-wrap" style={{ boxShadow: "none" }}>
      <table>
        <thead><tr><th aria-label="Detail" />{rows.map((p) => <th key={p.id}>{p.name}<div className="small muted">{p.university}</div></th>)}</tr></thead>
        <tbody>
          {withLead && line("For this student", (p) => <FitChips p={p} />)}
          {line("Specialization", (p) => p.specialization ?? "—")}
          {line("Level · mode", (p) => [p.level, p.mode].filter(Boolean).join(" · ") || "—")}
          {line("Duration", (p) => duration(p.duration_months) ?? "—")}
          {line("Fees", (p) => fees(p))}
          {line("Exam and registration", (p) => extras(p) || "—")}
          {line("EMI", (p) => (p.emi_monthly ? `${inr(p.emi_monthly)} a month` : "—"))}
          {line("Scholarship", (p) => p.scholarship ?? "—")}
          {line("Intakes", (p) => (p.intakes?.length ? p.intakes.join(", ") : "—"))}
          {line("Deadline", (p) => p.deadline ?? "—")}
          {line("Accreditation", (p) => p.accreditation ?? "—")}
          {line("Eligibility", (p) => p.eligibility ?? ([p.min_qualification, p.min_pct ? `${p.min_pct}%` : null].filter(Boolean).join(", ") || "—"))}
          {line("Brochure", (p) => (p.brochure_url && /^https:\/\//.test(p.brochure_url) ? <a href={p.brochure_url} target="_blank" rel="noopener noreferrer">Open</a> : "—"))}
          {money && line("Partners", (p) => (p.partners?.length ? p.partners.map((x) => `${x.name} (${commissionText(x.commission)})`).join(", ") : "—"))}
          {money && line("Eduwit commission", (p) => (p.eduwit_commission?.amount ? inr(p.eduwit_commission.amount) : "—"))}
        </tbody>
      </table>
    </div>
  );
}
