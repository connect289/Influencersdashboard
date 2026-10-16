import Link from "next/link";
import { ExternalLink, GraduationCap, Search, ShieldCheck, SlidersHorizontal } from "lucide-react";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { SuggestCorrection } from "@/app/s/programmes/SuggestCorrection";
import type { Me } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { inr, plural } from "@/lib/format";
import {
  accreditationLabel, commissionText, duration, GROUP_PREVIEW, groupByUniversity, headlineFee, isFiltered, levelLabel, moreOffsets, programmeQuery, SORTS,
  universityCommission, type Facets, type Programme, type ProgrammeParams, type UniversityGroup,
} from "@/lib/programmes";
import { createClient } from "@/lib/supabase/server";
import { FeeRange } from "./FeeRange";
import { SendButton } from "./SendButton";

type SP = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
const ACCREDITATIONS = ["UGC", "UGC-DEB", "AICTE", "NAAC A++", "NAAC A+", "NAAC A", "NIRF", "AIU", "WES"];
const HTTPS = /^https:\/\//;

type Lead = { lead_id: number; name: string | null; email: string | null; status: string; opted_out: boolean };
type Result = { total: number; rows: Programme[]; eligible_rank: number | null; budget: number | null };

/**
 * The Programme page (spec B8.9) for every role: the live catalogue grouped by university, with search and filters in the
 * address (so a view can be shared), compare 2–4 side by side; opened from a lead (?lead=), eligibility and budget for that
 * student and sending to them. Partner and Eduwit commission figures come only for the Admin and Marketing (the database
 * leaves them out for everyone else).
 */
export async function Catalogue({ me, base, leadBase, searchParams }: { me: Me; base: string; leadBase: string; searchParams: SP }) {
  const sp = Object.fromEntries(Object.entries(searchParams).map(([k, v]) => [k, first(v)])) as ProgrammeParams;
  const compareIds = [...new Set((Array.isArray(searchParams.compare) ? searchParams.compare : String(searchParams.compare ?? "").split(","))
    .map(Number).filter((n) => Number.isInteger(n) && n > 0))];
  const money = me.role === "admin" || me.role === "marketing";
  let facets: Facets;
  let rows: Programme[];
  let total: number;
  let catalogue: number;
  let eligibleRank: number | null = null;
  let compared: Programme[] | null = null;
  let compareError: string | null = null;
  let lead: Lead | null = null;
  try {
    facets = await rpc<Facets>("programme_facets");
    const q = programmeQuery(sp, facets.fee);
    const supabase = await createClient();
    const [r, all, l] = await Promise.all([
      rpc<Result>("programme_search", { p: q }),
      rpc<Result>("programme_search", { p: { limit: 1 } }),
      q.lead ? supabase.from("leads_v").select("lead_id, name, email, status, opted_out").eq("lead_id", q.lead).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    const rest = await Promise.all(moreOffsets(r.total).map((offset) => rpc<Result>("programme_search", { p: programmeQuery(sp, facets.fee, offset) })));
    rows = [r, ...rest].flatMap((x) => x.rows);
    total = r.total;
    catalogue = all.total;
    eligibleRank = r.eligible_rank;
    lead = (l.data as Lead | null) ?? null;
    if (compareIds.length > 0) {
      if (compareIds.length < 2 || compareIds.length > 4) compareError = "Choose two to four programmes to compare.";
      else compared = await rpc<Programme[]>("programme_compare", { p_ids: compareIds, p_lead: q.lead }).catch((e: Error) => ((compareError = e.message), null));
    }
  } catch (e) {
    return <Page title="Programmes"><SetupError error={e} /></Page>;
  }
  const canSend = !!lead && me.role !== "marketing" && lead.status === "active" && !lead.opted_out;
  const courses = facets.courses ?? [...new Set(rows.map((r) => r.course).filter((c): c is string => !!c))];
  const groups = groupByUniversity(rows);
  const oneUniversity = !!sp.university;
  const href = (o: Record<string, string | number | undefined>) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries({ ...sp, compare: compareIds.length ? compareIds.join(",") : undefined, ...o })) if (v !== undefined && v !== "" && v !== null) u.set(k, String(v));
    return `${base}?${u}`;
  };
  const keep = Object.entries(sp).filter(([k, v]) => v && k !== "compare");
  const sel = (name: keyof ProgrammeParams, all: string, options: string[], label: (v: string) => string = (v) => v) => (
    <select className="input" name={name} defaultValue={sp[name] ?? ""} aria-label={all.replace(/^All /, "")}>
      <option value="">{all}</option>
      {options.filter(Boolean).sort((a, b) => a.localeCompare(b)).map((o) => <option key={o} value={o}>{label(o)}</option>)}
    </select>
  );
  const send = (p: Programme[], label: string) => (canSend ? <SendButton leadId={lead!.lead_id} rows={p} firstName={lead!.name} counsellor={me.full_name} hasEmail={!!lead!.email} label={label} /> : null);

  return (
    <Page title="Programmes" sub={lead ? <>For <Link href={`${leadBase}/${lead.lead_id}`}>{lead.name ?? `lead #${lead.lead_id}`}</Link></> : "Every programme Eduwit can sell, from the shared catalogue. Read-only: suggest a correction from a card."}>
      <form className="stack tight" action={base} role="search">
        {lead && <input type="hidden" name="lead" value={lead.lead_id} />}
        <div className="prog-toolbar">
          <label className="search"><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Search programme, specialization, course…" aria-label="Search programmes" /></label>
          {sel("university", "All universities", facets.universities)}
          {sel("course", "All programmes", courses)}
          {sel("specialization", "All specializations", facets.specializations)}
          {sel("level", "All levels", facets.levels, (v) => levelLabel(v) ?? v)}
          {sel("mode", "All modes", facets.modes)}
          <button className="btn primary" type="submit">Show</button>
        </div>
        <details className="more" open={!!(sp.duration || sp.intake || sp.accreditation || sp.fee_min || sp.fee_max || sp.emi || sp.eligible || (sp.sort && sp.sort !== "name"))}>
          <summary><SlidersHorizontal className="icon s" aria-hidden /> More filters and sort</summary>
          <div className="row wrap" style={{ gap: 8, alignItems: "flex-end", paddingTop: 8 }}>
            <select className="input" name="duration" defaultValue={sp.duration ?? ""} style={{ width: "auto" }} aria-label="Duration">
              <option value="">Any duration</option>
              {[6, 12, 18, 24, 36, 48].map((m) => <option key={m} value={m}>Up to {duration(m)}</option>)}
            </select>
            <select className="input" name="intake" defaultValue={sp.intake ?? ""} style={{ width: "auto" }} aria-label="Intake">
              <option value="">Any intake</option>
              {facets.intakes.filter(Boolean).map((o) => <option key={o} value={o}>{o}</option>)}
            </select>
            <input className="input" name="accreditation" list="accreditations" defaultValue={sp.accreditation ?? ""} placeholder="Accreditation (UGC, NAAC…)" style={{ width: 200 }} aria-label="Accreditation" />
            <datalist id="accreditations">{ACCREDITATIONS.map((a) => <option key={a} value={a} />)}</datalist>
            {facets.fee.min !== null && facets.fee.max !== null && facets.fee.max > facets.fee.min && (
              <FeeRange min={facets.fee.min} max={facets.fee.max} from={sp.fee_min ? Number(sp.fee_min) : null} to={sp.fee_max ? Number(sp.fee_max) : null} />
            )}
            <label className="checkbox"><input type="checkbox" name="emi" value="1" defaultChecked={sp.emi === "1"} /> EMI available</label>
            {lead && <label className="checkbox"><input type="checkbox" name="eligible" value="1" defaultChecked={sp.eligible === "1"} /> Eligible for this student</label>}
            <select className="input" name="sort" defaultValue={sp.sort ?? "name"} style={{ width: "auto" }} aria-label="Sort">
              {SORTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
            <button className="btn ghost sm" type="submit">Apply</button>
            <Link className="btn quiet sm" href={lead ? `${base}?lead=${lead.lead_id}` : base}>Clear all</Link>
          </div>
        </details>
        {lead && eligibleRank === null && <p className="note">This student&apos;s qualification is not known yet, so eligibility is not checked.</p>}
      </form>

      <p className="prog-count mono muted">
        {total} of {catalogue} programmes{isFiltered(sp) ? " match" : ""}{rows.length < total ? ` · showing the first ${rows.length}: narrow the filters to see the rest` : ""}
      </p>

      {compareError && <div className="banner danger" role="alert">{compareError}</div>}
      {compared && (
        <section className="panel">
          <header><h3>Comparing {compared.length}</h3>
            <span className="row" style={{ gap: 6 }}>
              {send(compared, `Send all ${compared.length} to ${(lead?.name ?? "the student").split(" ")[0]}`)}
              <Link className="btn quiet sm" href={href({ compare: undefined })}>Close</Link>
            </span>
          </header>
          <div className="body"><CompareTable rows={compared} withLead={!!lead} /></div>
        </section>
      )}

      {rows.length === 0 ? <Empty>No programmes match. Clear a filter or widen the fee range.</Empty> : (
        <>
          <form id="compare" action={base} className="row wrap" style={{ gap: 6 }}>
            {keep.map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
            <span className="note grow">Tick two to four programmes, then compare them side by side.</span>
            <button className="btn ghost sm" type="submit">Compare ticked</button>
          </form>
          {groups.map((g) => (
            <UniversitySection key={g.university} g={g} money={money} admin={me.role === "admin"} showAll={oneUniversity} allHref={href({ university: g.university })}
              render={(p) => <ProgrammeCard key={p.id} p={p} money={money} withLead={!!lead} checked={compareIds.includes(p.id)} send={send([p], "Send")} />} />
          ))}
        </>
      )}
    </Page>
  );
}

function UniversitySection({ g, money, admin, showAll, allHref, render }: { g: UniversityGroup; money: boolean; admin: boolean; showAll: boolean; allHref: string; render: (p: Programme) => React.ReactNode }) {
  const visible = showAll ? g.rows : g.rows.slice(0, GROUP_PREVIEW);
  const hidden = g.rows.length - visible.length;
  const c = money ? universityCommission(g.rows) : null;
  return (
    <section className="stack tight" aria-label={g.university}>
      <header className="uni-head">
        <GraduationCap className="icon" aria-hidden />
        <h2 className="ellipsis">{g.university}</h2>
        <span className="mono muted small">{plural(g.rows.length, "programme")}</span>
        {c?.kind === "rate" && <span className="chip ok">Eduwit commission: {c.text}</span>}
        {c?.kind === "varies" && <span className="chip soft">Eduwit commission: varies by programme</span>}
        {c?.kind === "none" && <span className="chip warm">commission: not set</span>}
        {c?.kind === "none" && admin && <Link className="btn quiet sm" href="/w/money?tab=universities">% Set rate</Link>}
      </header>
      <div className="prog-grid">{visible.map(render)}</div>
      {hidden > 0 && <Link className="btn quiet sm" href={allHref} style={{ justifySelf: "start" }}>Show all {g.rows.length} programmes at {g.university_short ?? g.university}</Link>}
    </section>
  );
}

function FitChips({ p }: { p: Programme }) {
  return (
    <>
      {p.eligible !== null && <span className={`chip ${p.eligible ? "ok" : "breach"}`}>{p.eligible ? "Eligible" : "Not eligible"}</span>}
      {p.within_budget !== null && <span className={`chip ${p.within_budget ? "ok" : "risk"}`}>{p.within_budget ? "Within budget" : "Over budget"}</span>}
    </>
  );
}

const extras = (p: Programme) => [p.fee_exam ? `exam ${inr(p.fee_exam)}` : null, p.fee_registration ? `registration ${inr(p.fee_registration)}` : null].filter(Boolean).join(", ");

function ProgrammeCard({ p, money, withLead, checked, send }: { p: Programme; money: boolean; withLead: boolean; checked: boolean; send: React.ReactNode }) {
  const title = p.specialization && !p.name.toLowerCase().includes(p.specialization.toLowerCase()) ? `${p.name} – ${p.specialization}` : p.name;
  const name = `${title} · ${p.university}`;
  const fee = headlineFee(p);
  const accred = accreditationLabel(p.accreditation, p.recognitions);
  const brochure = p.brochure_url && HTTPS.test(p.brochure_url) ? p.brochure_url : null;
  return (
    <article className="card pcard">
      <div className="row between" style={{ alignItems: "flex-start", gap: 8 }}>
        <label className="row" style={{ gap: 8, alignItems: "flex-start", minWidth: 0 }}>
          <input type="checkbox" name="compare" value={p.id} form="compare" defaultChecked={checked} aria-label={`Compare ${name}`} style={{ marginTop: 4 }} />
          <b className="pcard-name">{title}</b>
        </label>
        <SuggestCorrection programmeId={p.id} name={name} />
      </div>
      <div className="row wrap" style={{ gap: 4 }}>
        {levelLabel(p.level) && <span className="chip line">{levelLabel(p.level)}</span>}
        {p.specialization && <span className="chip line">{p.specialization}</span>}
        {p.mode && <span className="chip line">{p.mode}</span>}
        {withLead && <FitChips p={p} />}
      </div>
      <div className="pstats">
        <div><span className="stat-label">{fee.label}</span><span className="stat-value mono">{fee.value ? inr(fee.value) : "—"}</span></div>
        {money ? (
          <div><span className="stat-label">Commission</span>
            <span className={`stat-value mono${p.eduwit_commission?.amount ? "" : " manual"}`}>{p.eduwit_commission?.amount ? inr(p.eduwit_commission.amount) : "manual"}</span></div>
        ) : (
          <div><span className="stat-label">Duration</span><span className="stat-value mono">{duration(p.duration_months) ?? "—"}</span></div>
        )}
      </div>
      {fee.semester && <span className="mono muted small">{inr(fee.semester)} per semester</span>}
      <div className="row between pcard-foot">
        {accred ? <span className="accred"><ShieldCheck className="icon s" aria-hidden />{accred}</span> : <span />}
        <span className="row" style={{ gap: 4 }}>
          {send}
          {brochure && <a className="btn quiet sm" href={brochure} target="_blank" rel="noopener noreferrer">Brochure <ExternalLink className="icon s" aria-hidden /></a>}
        </span>
      </div>
      <details className="more">
        <summary>Details</summary>
        <dl className="kv small" style={{ paddingTop: 8 }}>
          <dt>Duration</dt><dd>{duration(p.duration_months) ?? "—"}</dd>
          <dt>Fees</dt><dd>{[p.fee_total ? `${inr(p.fee_total)} in all` : null, p.fee_yearly ? `${inr(p.fee_yearly)} a year` : null, p.fee_semester ? `${inr(p.fee_semester)} a semester` : null].filter(Boolean).join(" · ") || "Not listed"}
            {extras(p) ? <span className="muted" style={{ display: "block" }}>Plus {extras(p)}</span> : null}</dd>
          <dt>EMI</dt><dd>{p.emi_monthly ? `From ${inr(p.emi_monthly)} a month` : "—"}</dd>
          {p.scholarship && <><dt>Scholarship</dt><dd>{p.scholarship}</dd></>}
          <dt>Intakes</dt><dd>{p.intakes?.length ? p.intakes.join(", ") : "—"}{p.deadline ? <span className="muted" style={{ display: "block" }}>Apply by {p.deadline}</span> : null}</dd>
          <dt>Eligibility</dt><dd>{p.eligibility ?? ([p.min_qualification, p.min_pct ? `${p.min_pct}%` : null].filter(Boolean).join(", ") || "—")}</dd>
          {p.enrollments > 0 && <><dt>Enrolled</dt><dd>{p.enrollments} through Eduwit</dd></>}
          {p.partners && p.partners.length > 0 && <><dt>Partners</dt><dd>{p.partners.map((x) => `${x.name} (${commissionText(x.commission)})`).join(", ")}</dd></>}
          {p.eduwit_commission && <><dt>Eduwit commission</dt><dd>{p.eduwit_commission.amount ? inr(p.eduwit_commission.amount) : "—"} <span className="muted">({p.eduwit_commission.rate_type === "percent" ? `${p.eduwit_commission.value}% of the ${p.eduwit_commission.fee_base.replace("_", "-")} fee` : "fixed"})</span></dd></>}
        </dl>
      </details>
    </article>
  );
}

function CompareTable({ rows, withLead }: { rows: Programme[]; withLead: boolean }) {
  const line = (label: string, f: (p: Programme) => React.ReactNode) => (
    <tr><th scope="row" className="small muted">{label}</th>{rows.map((p) => <td key={p.id} className="small">{f(p)}</td>)}</tr>
  );
  const money = rows.some((p) => p.partners !== undefined);
  const fees = (p: Programme) => [p.fee_total ? `${inr(p.fee_total)} in all` : null, p.fee_yearly ? `${inr(p.fee_yearly)} a year` : null, p.fee_semester ? `${inr(p.fee_semester)} a semester` : null].filter(Boolean).join(" · ") || "Not listed";
  return (
    <div className="table-wrap" style={{ boxShadow: "none" }}>
      <table>
        <thead><tr><th aria-label="Detail" />{rows.map((p) => <th key={p.id}>{p.name}<div className="small muted">{p.university}</div></th>)}</tr></thead>
        <tbody>
          {withLead && line("For this student", (p) => <span className="row wrap" style={{ gap: 4 }}><FitChips p={p} /></span>)}
          {line("Specialization", (p) => p.specialization ?? "—")}
          {line("Level · mode", (p) => [levelLabel(p.level), p.mode].filter(Boolean).join(" · ") || "—")}
          {line("Duration", (p) => duration(p.duration_months) ?? "—")}
          {line("Fees", fees)}
          {line("Exam and registration", (p) => extras(p) || "—")}
          {line("EMI", (p) => (p.emi_monthly ? `${inr(p.emi_monthly)} a month` : "—"))}
          {line("Scholarship", (p) => p.scholarship ?? "—")}
          {line("Intakes", (p) => (p.intakes?.length ? p.intakes.join(", ") : "—"))}
          {line("Deadline", (p) => p.deadline ?? "—")}
          {line("Accreditation", (p) => accreditationLabel(p.accreditation, p.recognitions) ?? "—")}
          {line("Eligibility", (p) => p.eligibility ?? ([p.min_qualification, p.min_pct ? `${p.min_pct}%` : null].filter(Boolean).join(", ") || "—"))}
          {line("Brochure", (p) => (p.brochure_url && HTTPS.test(p.brochure_url) ? <a href={p.brochure_url} target="_blank" rel="noopener noreferrer">Open</a> : "—"))}
          {money && line("Partners", (p) => (p.partners?.length ? p.partners.map((x) => `${x.name} (${commissionText(x.commission)})`).join(", ") : "—"))}
          {money && line("Eduwit commission", (p) => (p.eduwit_commission?.amount ? inr(p.eduwit_commission.amount) : "—"))}
        </tbody>
      </table>
    </div>
  );
}
