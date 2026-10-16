import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { CommissionLines } from "@/components/money/CommissionLines";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { date, inr } from "@/lib/format";
import { rateText, type CommissionLine, type PartnerRate } from "@/lib/money";
import {
  BillingButton, EnrollmentMoney, FallbackButton, InvoiceActions, InvoiceDraftButton, OverrideButton, OverrideRetire, PeriodCloseButton, RateButton, RateRetire,
  ReceiptButton, ReleaseLine, RunActions, RunPrepareButton, StatementUpload,
} from "./parts";
import { AdImportButton, AdMapButton } from "./AdSpend";
import { CommissionDashboard, type CommissionDash } from "./CommissionDashboard";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Money" };

const TABS = [["overview", "Overview"], ["enrolments", "Enrolments"], ["universities", "Universities"], ["receivables", "Receivables"], ["statements", "Statements"],
  ["commission", "Counsellor commission"], ["runs", "Runs"], ["ads", "Ad spend"]] as const;
type Tab = (typeof TABS)[number][0];

type Admin = {
  from: string; to: string;
  university: { month: string; university_id: number; university: string | null; expected_gross: number | null; realised_gross: number | null; gross: number; gst: number; net: number }[];
  counsellor: { counsellor_id: string; name: string; month: string; status: string; amount: number; lines: number }[];
  side_by_side: { university_id: number; university: string | null; enrollments: number; university_net: number | null; university_gross: number | null; counsellor_owed: number | null }[];
  enrollments: { enrollment_id: number; lead_id: number; student: string | null; university: string; university_id: number | null; programme_id: number | null; programme: string;
    enrolled_on: string; status: string; fee: number | null; counsellor: string | null; university_gross: number | null; university_net: number | null; counsellor_owed: number | null;
    commission_status: string | null }[];
  needs_rate: CommissionLine[];
  unlinked: { enrollment_id: number; lead_id: number; university: string; programme: string; enrolled_on: string }[];
  no_university_rate: { enrollment_id: number; university: string; university_id: number; enrolled_on: string }[];
  receivables: Receivables;
  tier_watch: { rate_id: number; university_id: number; university: string; tiers: { from: number; to?: number; value: number }[]; now: { leads: number; verified: number; conversion: number }; tier: { value: number } | null }[];
  statements: { import_id: number; university: string | null; from: string; to: string; file: string | null; summary: Record<string, number>; at: string }[];
  runs: { id: number; period: string; status: string; totals: RunTotals | null; approved_at: string | null }[];
  next_run: string;
  settings: Record<string, unknown>;
};
type RunTotals = { net: number; tds: number; lines: number; amount: number; clawbacks: number; adjustments: number; counsellors: number };
type Receivables = { total: number; buckets: Record<string, number>; unallocated: number;
  invoices: { id: number; number: string | null; university_id: number; university: string | null; issue_date: string; due_on: string; gross: number; balance: number; days_late: number; status: string }[] };
type Uni = { id: number; name: string; programmes: number; rate: { rate_type: string; value: number | null; tiers: unknown; valid_from: string } | null; programme_rates: number;
  billing: boolean; fallback: { rate_type: string; value: number; fee_base: string } | null; enrollments: number };
type UniDetail = {
  university: { id: number; name: string }; billing: Record<string, unknown> | null; fallback: Record<string, unknown> | null;
  rates: { id: number; programme: string | null; rate_type: string; value: number | null; tiers: unknown; fee_base: string; gst_inclusive: boolean; valid_from: string; valid_to: string | null; retired_at: string | null; note: string | null }[];
  closes: { period: string; leads: number; verified: number; conversion: number; adjustments: number; denominator: string }[];
  invoices: { id: number; kind: string; number: string | null; status: string; issue_date: string | null; due_on: string | null; gross: number; paid: number }[];
  uninvoiced: { lines: number; gross: number };
  receipts: { id: number; amount: number; tds: number; reference: string; received_on: string; unallocated: number }[];
  programmes: { id: number; name: string }[];
};
type Piles = { rows: { id: number; ref: string; pile: string; amount: number; student: string | null; expected: number | null; programme: string | null; enrollment_id: number | null }[];
  eduwit_only_rows: { lead_id: number; student: string | null; expected: number; programme: string | null; enrolled_on: string; enrollment_id: number }[] } & Record<string, unknown>;
type Rules = { overrides: { id: number; counsellor: string | null; programme: string | null; rate_type: string; fee_base: string; value: number; valid_from: string; valid_to: string | null; reason: string }[];
  fallbacks: { university_id: number; university: string | null; rate_type: string; fee_base: string; value: number; reason: string; set_at: string }[];
  counsellors: { user_id: string; name: string | null }[] };
type PartnerTable = { error?: string; rows: { programme_id: number; programme: string; university: string; fee_yearly: number | null; partners: { partner_id: number; name: string; rate: PartnerRate | null }[] | null }[];
  changes: { at: string; detail: Record<string, unknown> }[] };
type AdOverview = { from: string; to: string;
  imports: { id: number; platform: string; file_name: string | null; rows: number; from_day: string | null; to_day: string | null; spend: number; created_at: string; by: string | null }[];
  campaigns: { platform: string; campaign_id: string; campaign: string | null; spend: number; clicks: number; platform_leads: number; map: { lead_source: string | null; lead_campaign: string | null } | null;
    leads: number; enrolled: number; commission_net: number }[];
  lead_values: { source: string | null; campaign: string | null; leads: number }[] };
type RunView = { id: number; period: string; status: string; is_test: boolean; totals: RunTotals | null; counsellors: { counsellor_id: string; name: string; email: string; amount: number; tds: number; net: number; lines: CommissionLine[] }[] };

const PILES: [string, string, string][] = [["matched", "Matched", "ok"], ["mismatch", "Amount differs", "warm"], ["university_only", "Only in their statement", "breach"], ["eduwit_only", "Only in ours", "breach"]];

/** Money (spec B11): what universities owe Eduwit and what counsellors owe, side by side. Admin changes; Marketing reads. */
export default async function MoneyPage({ searchParams }: { searchParams: Promise<{ tab?: string; u?: string; run?: string; imp?: string; test?: string }> }) {
  const me = await requireUser("workspace", "/w/money");
  if (me.role !== "admin" && me.role !== "marketing") return <Page title="Money"><Empty>Money is for the Admin.</Empty></Page>;
  const admin = me.role === "admin";
  const sp = await searchParams;
  const tab: Tab = TABS.some(([k]) => k === sp.tab) ? (sp.tab as Tab) : "overview";
  let body: React.ReactNode;
  try {
    const [m, unis] = await Promise.all([rpc<Admin>("money_admin", { p: {} }), rpc<Uni[]>("money_universities")]);
    const uniList = unis.map((u) => ({ id: u.id, name: u.name }));
    if (tab === "overview") body = <Overview m={m} />;
    else if (tab === "enrolments") body = <Enrolments m={m} admin={admin} unis={uniList} />;
    else if (tab === "universities") {
      const u = Number(sp.u);
      body = Number.isInteger(u) && u > 0 ? <UniversityView d={await rpc<UniDetail>("university_money", { p_university: u })} admin={admin} /> : <Universities unis={unis} />;
    } else if (tab === "receivables") body = <ReceivablesView r={m.receivables} />;
    else if (tab === "statements") {
      const imp = Number(sp.imp);
      body = (
        <div className="stack">
          {admin && <div className="row"><StatementUpload universities={uniList} /></div>}
          {Number.isInteger(imp) && imp > 0 && <PilesView p={await rpc<Piles>("statement_piles", { p_import: imp })} />}
          <StatementList m={m} />
        </div>
      );
    } else if (tab === "commission") {
      const test = sp.test === "1";
      const [rules, partners, dash] = await Promise.all([rpc<Rules>("money_rules"), rpc<PartnerTable>("partner_rate_table", { p_university: null }),
        rpc<CommissionDash>("commission_dashboard", { p: { test } })]);
      body = <div className="stack"><CommissionDashboard d={dash} test={test} /><Commission m={m} rules={rules} partners={partners} unis={uniList} admin={admin} /></div>;
    } else if (tab === "ads") {
      const [ads, dash] = await Promise.all([rpc<AdOverview>("ad_spend_overview", { p_from: null, p_to: null }),
        (await createClient()).from("dashboards").select("id").eq("key", "ad_spend").maybeSingle()]);
      body = <AdSpend o={ads} dashboardId={(dash.data as { id: number } | null)?.id ?? null} />;
    } else {
      const r = Number(sp.run);
      body = Number.isInteger(r) && r > 0 ? <RunDetail v={await rpc<RunView>("commission_run_view", { p_run: r })} admin={admin} /> : <Runs m={m} admin={admin} />;
    }
  } catch (e) {
    body = <SetupError error={e} />;
  }
  return (
    <Page title="Money" sub="The CRM moves no money: it books what is owed, raises invoices and records what came in.">
      <div className="tabs" role="tablist" style={{ marginBottom: 12 }}>
        {TABS.map(([k, n]) => (
          <Link key={k} href={`/w/money?tab=${k}`} role="tab" aria-selected={tab === k}
            style={{ padding: "9px 12px", fontWeight: 600, textDecoration: "none", color: tab === k ? "var(--ink)" : "var(--muted)", borderBottom: `2px solid ${tab === k ? "var(--amber)" : "transparent"}`, whiteSpace: "nowrap" }}>
            {n}
          </Link>
        ))}
      </div>
      {body}
    </Page>
  );
}

function sum<T>(xs: T[], f: (x: T) => number | null | undefined) { return xs.reduce((a, x) => a + Number(f(x) ?? 0), 0); }

function Overview({ m }: { m: Admin }) {
  const expected = sum(m.university, (x) => x.expected_gross), realised = sum(m.university, (x) => x.realised_gross);
  const owed = sum(m.counsellor, (x) => x.amount), due = sum(m.counsellor.filter((c) => c.status === "due"), (x) => x.amount);
  const months = [...new Set(m.university.map((x) => x.month))].sort().slice(-6);
  const todo = m.needs_rate.length + m.unlinked.length + m.no_university_rate.length;
  return (
    <div className="stack">
      {!m.settings.ca_confirmed && <div className="banner">GST rate, SAC and refund windows are not yet confirmed by the CA (Settings → money). Invoices show SAC “{String(m.settings.sac)}”.</div>}
      {todo > 0 && <div className="banner danger"><div className="grow">
        {m.unlinked.length > 0 && <div>{m.unlinked.length} enrolments are not linked to the catalogue, so nothing is booked for them.</div>}
        {m.no_university_rate.length > 0 && <div>{m.no_university_rate.length} enrolments have no university rate on their date.</div>}
        {m.needs_rate.length > 0 && <div>{m.needs_rate.length} counsellor lines need a rate.</div>}
      </div><Link className="btn ghost sm" href="/w/money?tab=enrolments">Open</Link></div>}
      <div className="grid g4">
        <div className="stat"><span className="small muted">Universities, expected</span><b>{inr(expected)}</b><span className="delta">booked, refund window still open</span></div>
        <div className="stat"><span className="small muted">Universities, realised</span><b>{inr(realised)}</b><span className="delta">past the refund window, last 12 months</span></div>
        <div className="stat"><span className="small muted">Receivable</span><b>{inr(m.receivables.total)}</b><span className="delta">{inr(sum(["d1_30", "d31_60", "d61_90", "d90_plus"], (k) => m.receivables.buckets[k]))} overdue</span></div>
        <div className="stat"><span className="small muted">Counsellors owed</span><b>{inr(owed)}</b><span className="delta">{inr(due)} due in the run on {date(m.next_run)}</span></div>
      </div>
      <section className="card pad stack">
        <h2>University and counsellor commission, side by side</h2>
        <p className="note">University figures are what the university owes Eduwit (net of GST); counsellor figures are what counsellors owe for the same enrolments. Test leads are left out.</p>
        {m.side_by_side.length === 0 ? <p className="note">No enrolments in the last 12 months.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>University</th><th className="right">Enrolments</th><th className="right">University, net</th><th className="right">With GST</th><th className="right">Counsellors owe</th></tr></thead>
            <tbody>{m.side_by_side.map((r) => (
              <tr key={r.university_id ?? "none"}><td>{r.university_id ? <Link href={`/w/money?tab=universities&u=${r.university_id}`}>{r.university ?? "—"}</Link> : "Not linked"}</td>
                <td className="right num">{r.enrollments}</td><td className="right num">{inr(r.university_net)}</td><td className="right num">{inr(r.university_gross)}</td><td className="right num">{inr(r.counsellor_owed)}</td></tr>
            ))}</tbody>
            <tfoot><tr><th>Total</th><th className="right num">{sum(m.side_by_side, (x) => x.enrollments)}</th><th className="right num">{inr(sum(m.side_by_side, (x) => x.university_net))}</th>
              <th className="right num">{inr(sum(m.side_by_side, (x) => x.university_gross))}</th><th className="right num">{inr(sum(m.side_by_side, (x) => x.counsellor_owed))}</th></tr></tfoot>
          </table></div>
        )}
      </section>
      <div className="grid g2">
        <section className="card pad stack">
          <h2>University commission by month</h2>
          {months.length === 0 ? <p className="note">Nothing booked yet.</p> : (
            <div className="table-wrap"><table>
              <thead><tr><th>Month</th><th className="right">Expected</th><th className="right">Realised</th><th className="right">Net</th><th className="right">GST</th></tr></thead>
              <tbody>{months.map((mo) => { const xs = m.university.filter((x) => x.month === mo); return (
                <tr key={mo}><td>{mo.slice(0, 7)}</td><td className="right num">{inr(sum(xs, (x) => x.expected_gross))}</td><td className="right num">{inr(sum(xs, (x) => x.realised_gross))}</td>
                  <td className="right num">{inr(sum(xs, (x) => x.net))}</td><td className="right num">{inr(sum(xs, (x) => x.gst))}</td></tr>); })}</tbody>
            </table></div>
          )}
        </section>
        <section className="card pad stack">
          <h2>Tiers this month</h2>
          {m.tier_watch.length === 0 ? <p className="note">No tiered rates in force.</p> : m.tier_watch.map((t) => (
            <div key={t.rate_id ?? t.university_id} className="stack small" style={{ gap: 2 }}>
              <b>{t.university}</b>
              <span>Conversion so far {t.now.conversion}% ({t.now.verified} of {t.now.leads} leads) → tier {t.tier ? `${t.tier.value}%` : "none"}</span>
              <span className="muted">{t.tiers.map((x) => `${x.from}–${x.to ?? "∞"}%: ${x.value}%`).join(" · ")}</span>
            </div>
          ))}
        </section>
      </div>
    </div>
  );
}

function Enrolments({ m, admin, unis }: { m: Admin; admin: boolean; unis: { id: number; name: string }[] }) {
  return (
    <div className="stack">
      {m.unlinked.length > 0 && (
        <section className="card pad stack">
          <h2>Not linked to the catalogue ({m.unlinked.length})</h2>
          <p className="note">Commission is booked once an enrolment points to a catalogue university and programme.</p>
          <div className="table-wrap"><table>
            <thead><tr><th>Lead</th><th>Reported as</th><th>Enrolled</th>{admin && <th />}</tr></thead>
            <tbody>{m.unlinked.map((e) => (
              <tr key={e.enrollment_id}><td><Link href={`/w/leads/${e.lead_id}`}>#{e.lead_id}</Link></td><td>{e.university}<div className="small muted">{e.programme}</div></td><td>{date(e.enrolled_on)}</td>
                {admin && <td><EnrollmentMoney e={{ ...e, university_id: null, programme_id: null, status: "reported", fee: null }} universities={unis} /></td>}</tr>
            ))}</tbody>
          </table></div>
        </section>
      )}
      {m.no_university_rate.length > 0 && <div className="banner">{m.no_university_rate.length} linked enrolments have no university rate on their date: add a rate under Universities, then “Book again”.</div>}
      <section className="card pad stack">
        <h2>Enrolments, last 12 months</h2>
        {m.enrollments.length === 0 ? <p className="note">No enrolments yet.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Student</th><th>Counsellor</th><th>Programme</th><th>Enrolled</th><th>Status</th><th className="right">University owes</th><th className="right">Counsellor owes</th>{admin && <th />}</tr></thead>
            <tbody>{m.enrollments.map((e) => (
              <tr key={e.enrollment_id}>
                <td><Link href={`/w/leads/${e.lead_id}`}>{e.student ?? `#${e.lead_id}`}</Link></td><td>{e.counsellor ?? "—"}</td>
                <td>{e.programme}<div className="small muted">{e.university}</div></td><td className="nowrap">{date(e.enrolled_on)}</td>
                <td><span className="chip soft">{e.status}</span>{e.commission_status && <div className="small muted">{e.commission_status}</div>}</td>
                <td className="right num">{inr(e.university_gross)}</td><td className="right num">{inr(e.counsellor_owed)}</td>
                {admin && <td><EnrollmentMoney e={e} universities={unis} /></td>}
              </tr>
            ))}</tbody>
          </table></div>
        )}
      </section>
    </div>
  );
}

function Universities({ unis }: { unis: Uni[] }) {
  if (!unis.length) return <Empty>The course catalogue has no universities.</Empty>;
  return (
    <div className="table-wrap"><table>
      <thead><tr><th>University</th><th>Rate in force</th><th className="right">Programme rates</th><th>Billing</th><th>Counsellor fallback</th><th className="right">Enrolments</th></tr></thead>
      <tbody>{unis.map((u) => (
        <tr key={u.id}>
          <td><Link href={`/w/money?tab=universities&u=${u.id}`}>{u.name}</Link><div className="small muted">{u.programmes} programmes</div></td>
          <td>{u.rate ? <>{rateText(u.rate, inr)}<div className="small muted">from {date(u.rate.valid_from)}</div></> : <span className="chip breach">no rate</span>}</td>
          <td className="right num">{u.programme_rates || "–"}</td>
          <td>{u.billing ? <span className="chip ok">GSTIN set</span> : <span className="chip line">missing</span>}</td>
          <td>{u.fallback ? rateText(u.fallback, inr) : "–"}</td>
          <td className="right num">{u.enrollments}</td>
        </tr>
      ))}</tbody>
    </table></div>
  );
}

function UniversityView({ d, admin }: { d: UniDetail; admin: boolean }) {
  const b = d.billing as Record<string, string | number | null> | null;
  const open = d.invoices.filter((i) => i.kind === "invoice" && ["approved", "sent", "part_paid"].includes(i.status)).map((i) => ({ id: i.id, number: i.number, open: Number(i.gross) - Number(i.paid) }));
  return (
    <div className="stack">
      <div className="row"><Link className="btn quiet sm" href="/w/money?tab=universities">← All universities</Link><h2 className="grow">{d.university?.name}</h2></div>
      <div className="grid g2">
        <section className="card pad stack">
          <div className="row"><h2 className="grow">Billing</h2>{admin && <BillingButton university={d.university.id} billing={d.billing as never} name={d.university.name} />}</div>
          {b ? <dl className="kv small"><dt>Legal name</dt><dd>{b.legal_name}</dd><dt>GSTIN</dt><dd className="mono">{b.gstin ?? "—"}</dd><dt>State</dt><dd>{b.state_code ?? "—"}</dd>
            <dt>Payment terms</dt><dd>{b.payment_terms_days ?? "default"} days</dd><dt>Refund window</dt><dd>{b.refund_days ?? "default"} days</dd></dl>
            : <p className="note">No billing details: invoices cannot be approved without the university's GSTIN.</p>}
        </section>
        <section className="card pad stack">
          <div className="row"><h2 className="grow">Invoices</h2>{admin && d.uninvoiced.lines > 0 && <InvoiceDraftButton university={d.university.id} uninvoiced={d.uninvoiced} />}
            {admin && <ReceiptButton university={d.university.id} invoices={open} />}</div>
          <p className="note">{d.uninvoiced.lines} realised lines ({inr(d.uninvoiced.gross)}) not yet invoiced.</p>
          {d.invoices.length === 0 ? <p className="note">No invoices.</p> : (
            <div className="table-wrap"><table>
              <thead><tr><th>Number</th><th>Status</th><th>Issued · due</th><th className="right">Total</th><th className="right">Paid</th><th /></tr></thead>
              <tbody>{d.invoices.map((i) => (
                <tr key={i.id}><td className="mono">{i.number ?? "draft"}{i.kind === "credit_note" && <div className="small muted">credit note</div>}</td><td><span className="chip soft">{i.status}</span></td>
                  <td className="small">{date(i.issue_date)} · {date(i.due_on)}</td><td className="right num">{inr(i.gross)}</td><td className="right num">{inr(i.paid)}</td>
                  <td>{admin ? <InvoiceActions invoice={i.id} status={i.status} kind={i.kind} /> : <a className="btn quiet sm" href={`/w/money/invoice/${i.id}`} target="_blank" rel="noopener">PDF</a>}</td></tr>
              ))}</tbody>
            </table></div>
          )}
        </section>
      </div>
      <section className="card pad stack">
        <div className="row"><h2 className="grow">Rates</h2>{admin && <PeriodCloseButton university={d.university.id} />}{admin && <RateButton university={d.university.id} programmes={d.programmes} />}</div>
        {d.rates.length === 0 ? <p className="note">No rate yet. Enrolments here book nothing until a rate covers their date.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Applies to</th><th>Rate</th><th>GST</th><th>Valid</th><th>Note</th>{admin && <th />}</tr></thead>
            <tbody>{d.rates.map((r) => (
              <tr key={r.id} style={r.retired_at ? { opacity: 0.55 } : undefined}><td>{r.programme ?? "Every programme"}</td><td>{rateText(r, inr)}</td><td>{r.gst_inclusive ? "included" : "on top"}</td>
                <td className="small">{date(r.valid_from)} – {r.valid_to ? date(r.valid_to) : "open"}{r.retired_at && <div className="muted">retired</div>}</td><td className="small">{r.note ?? ""}</td>
                {admin && <td>{!r.retired_at && <RateRetire rate={r.id} />}</td>}</tr>
            ))}</tbody>
          </table></div>
        )}
        {d.closes.length > 0 && <>
          <h3>Closed periods</h3>
          <div className="table-wrap"><table>
            <thead><tr><th>Month</th><th className="right">Leads</th><th className="right">Enrolled</th><th className="right">Conversion</th><th className="right">Adjustments</th></tr></thead>
            <tbody>{d.closes.map((c) => <tr key={c.period}><td>{c.period.slice(0, 7)}</td><td className="right num">{c.leads}{c.denominator === "manual" ? "*" : ""}</td><td className="right num">{c.verified}</td>
              <td className="right num">{Number(c.conversion).toFixed(2)}%</td><td className="right num">{c.adjustments}</td></tr>)}</tbody>
          </table></div>
          <p className="note">* the university's own lead count.</p>
        </>}
      </section>
      {d.receipts.length > 0 && (
        <section className="card pad stack">
          <h2>Receipts</h2>
          <div className="table-wrap"><table>
            <thead><tr><th>Received</th><th>Reference</th><th className="right">Amount</th><th className="right">TDS</th><th className="right">Not allocated</th></tr></thead>
            <tbody>{d.receipts.map((r) => <tr key={r.id}><td>{date(r.received_on)}</td><td className="mono">{r.reference}</td><td className="right num">{inr(r.amount)}</td><td className="right num">{inr(r.tds)}</td><td className="right num">{inr(r.unallocated)}</td></tr>)}</tbody>
          </table></div>
        </section>
      )}
    </div>
  );
}

function ReceivablesView({ r }: { r: Receivables }) {
  const B: [string, string][] = [["current", "Not yet due"], ["d1_30", "1–30 days late"], ["d31_60", "31–60"], ["d61_90", "61–90"], ["d90_plus", "Over 90"]];
  return (
    <div className="stack">
      <div className="grid g4" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))" }}>
        {B.map(([k, l]) => <div key={k} className="stat"><span className="small muted">{l}</span><b>{inr(r.buckets[k])}</b></div>)}
      </div>
      {Number(r.unallocated) > 0 && <div className="banner">{inr(r.unallocated)} received but not matched to an invoice.</div>}
      {r.invoices.length === 0 ? <Empty>Nothing is owed.</Empty> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Invoice</th><th>University</th><th>Issued</th><th>Due</th><th className="right">Days late</th><th className="right">Balance</th></tr></thead>
          <tbody>{r.invoices.map((i) => (
            <tr key={i.id}><td className="mono"><a href={`/w/money/invoice/${i.id}`} target="_blank" rel="noopener">{i.number}</a></td>
              <td><Link href={`/w/money?tab=universities&u=${i.university_id}`}>{i.university ?? "—"}</Link></td><td>{date(i.issue_date)}</td><td>{date(i.due_on)}</td>
              <td className="right num">{i.days_late || "–"}</td><td className="right num">{inr(i.balance)}</td></tr>
          ))}</tbody>
        </table></div>
      )}
    </div>
  );
}

function StatementList({ m }: { m: Admin }) {
  if (!m.statements.length) return <Empty>No statements uploaded yet.</Empty>;
  return (
    <div className="table-wrap"><table>
      <thead><tr><th>University</th><th>Period</th><th>File</th>{PILES.map(([k, l]) => <th key={k} className="right">{l}</th>)}<th /></tr></thead>
      <tbody>{m.statements.map((s) => (
        <tr key={s.import_id}><td>{s.university ?? "—"}</td><td className="small">{date(s.from)} – {date(s.to)}</td><td className="small">{s.file ?? ""}</td>
          {PILES.map(([k]) => <td key={k} className="right num">{s.summary?.[k] ?? 0}</td>)}
          <td><Link className="btn quiet sm" href={`/w/money?tab=statements&imp=${s.import_id}`}>Open</Link></td></tr>
      ))}</tbody>
    </table></div>
  );
}

function PilesView({ p }: { p: Piles }) {
  return (
    <section className="card pad stack">
      <h2>Reconciliation</h2>
      {PILES.map(([k, l, chip]) => {
        const rows = k === "eduwit_only" ? p.eduwit_only_rows.map((r) => ({ key: `e${r.enrollment_id}`, student: r.student, programme: r.programme, theirs: null as number | null, ours: r.expected, enrollment: r.enrollment_id }))
          : p.rows.filter((r) => r.pile === k).map((r) => ({ key: `r${r.id}`, student: r.student, programme: r.programme, theirs: r.amount, ours: r.expected, enrollment: r.enrollment_id }));
        return (
          <div key={k} className="stack" style={{ gap: 4 }}>
            <h3><span className={`chip ${chip}`}>{l}</span> <span className="muted small">{rows.length}</span></h3>
            {rows.length > 0 && (
              <div className="table-wrap"><table>
                <thead><tr><th>Student</th><th>Programme</th><th className="right">Theirs</th><th className="right">Ours</th><th className="right">Difference</th></tr></thead>
                <tbody>{rows.map((r) => <tr key={r.key}><td>{r.student ?? "—"}{r.enrollment ? <span className="small muted"> · #{r.enrollment}</span> : null}</td><td>{r.programme ?? "—"}</td>
                  <td className="right num">{inr(r.theirs)}</td><td className="right num">{inr(r.ours)}</td>
                  <td className="right num">{r.theirs !== null && r.ours !== null ? inr(Number(r.theirs) - Number(r.ours)) : "–"}</td></tr>)}</tbody>
              </table></div>
            )}
          </div>
        );
      })}
    </section>
  );
}

function Commission({ m, rules, partners, unis, admin }: { m: Admin; rules: Rules; partners: PartnerTable; unis: { id: number; name: string }[]; admin: boolean }) {
  return (
    <div className="stack">
      <section className="card pad stack">
        <h2>Needs a rate ({m.needs_rate.length})</h2>
        <p className="note">No active partner has a rate for these programmes and the university has no fallback. Set a fallback below and they are booked again.</p>
        {m.needs_rate.length > 0 && <CommissionLines lines={m.needs_rate} leadHref={(id) => `/w/leads/${id}`} />}
      </section>
      <div className="grid g2">
        <section className="card pad stack">
          <div className="row"><h2 className="grow">University fallbacks</h2>{admin && <FallbackButton universities={unis} />}</div>
          {rules.fallbacks.length === 0 ? <p className="note">None.</p> : (
            <div className="table-wrap"><table>
              <thead><tr><th>University</th><th>Rate</th><th>Reason</th>{admin && <th />}</tr></thead>
              <tbody>{rules.fallbacks.map((f) => <tr key={f.university_id}><td>{f.university}</td><td>{rateText(f, inr)}</td><td className="small">{f.reason}</td>
                {admin && <td><FallbackButton universities={unis} current={{ university_id: f.university_id }} /></td>}</tr>)}</tbody>
            </table></div>
          )}
        </section>
        <section className="card pad stack">
          <div className="row"><h2 className="grow">Overrides</h2>{admin && <OverrideButton counsellors={rules.counsellors} />}</div>
          {rules.overrides.length === 0 ? <p className="note">None. Every counsellor earns the highest partner rate.</p> : (
            <div className="table-wrap"><table>
              <thead><tr><th>Who · programme</th><th>Rate</th><th>Valid</th>{admin && <th />}</tr></thead>
              <tbody>{rules.overrides.map((o) => <tr key={o.id}><td>{o.counsellor ?? "Everyone"}<div className="small muted">{o.programme ?? "every programme"}</div></td><td>{rateText(o, inr)}<div className="small muted">{o.reason}</div></td>
                <td className="small">{date(o.valid_from)} – {o.valid_to ? date(o.valid_to) : "open"}</td>{admin && <td><OverrideRetire id={o.id} /></td>}</tr>)}</tbody>
            </table></div>
          )}
        </section>
      </div>
      <section className="card pad stack">
        <h2>Partner rates by programme</h2>
        <p className="note">Read from the B2B CRM. A counsellor's line uses the highest of these on the enrolment date.</p>
        {partners.error ? <div className="banner">{partners.error}</div> : partners.rows.length === 0 ? <p className="note">No partner offers a catalogue programme yet.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Programme</th><th className="right">First-year fee</th><th>Partners and rates</th></tr></thead>
            <tbody>{partners.rows.map((r) => {
              const best = Math.max(0, ...(r.partners ?? []).map((p) => (p.rate?.rate_type === "percent" ? Number(p.rate.value) : 0)));
              return (
                <tr key={r.programme_id}><td>{r.programme}<div className="small muted">{r.university}</div></td><td className="right num">{inr(r.fee_yearly)}</td>
                  <td className="small">{(r.partners ?? []).map((p) => (
                    <div key={p.partner_id}>{p.rate?.rate_type === "percent" && Number(p.rate.value) === best ? <b>{p.name}</b> : p.name}: {p.rate ? rateText(p.rate, inr) : "no rate"}</div>
                  ))}</td></tr>
              );
            })}</tbody>
          </table></div>
        )}
        {partners.changes.length > 0 && <details><summary className="small">Recent partner rate changes ({partners.changes.length})</summary>
          <ul className="small">{partners.changes.map((c, i) => <li key={i}>{date(c.at)}: {String(c.detail.scope)} {String(c.detail.rate_type)} {String(c.detail.value)}{c.detail.partner_id ? ` (partner ${String(c.detail.partner_id)})` : ""}</li>)}</ul></details>}
      </section>
    </div>
  );
}

function Runs({ m, admin }: { m: Admin; admin: boolean }) {
  return (
    <div className="stack">
      <div className="row"><p className="grow small">Next run is prepared on <b>{date(m.next_run)}</b> with every due line.</p>{admin && <RunPrepareButton nextRun={date(m.next_run)} />}</div>
      {m.runs.length === 0 ? <Empty>No runs yet.</Empty> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Month</th><th>Status</th><th className="right">Counsellors</th><th className="right">Lines</th><th className="right">Amount</th><th className="right">Clawbacks</th><th /></tr></thead>
          <tbody>{m.runs.map((r) => (
            <tr key={r.id}><td>{r.period.slice(0, 7)}</td><td><span className={`chip ${r.status === "approved" ? "ok" : "warm"}`}>{r.status === "approved" ? "approved, settled" : r.status}</span></td>
              <td className="right num">{r.totals?.counsellors ?? 0}</td><td className="right num">{r.totals?.lines ?? 0}</td><td className="right num">{inr(r.totals?.amount)}</td><td className="right num">{inr(r.totals?.clawbacks)}</td>
              <td><Link className="btn quiet sm" href={`/w/money?tab=runs&run=${r.id}`}>Open</Link></td></tr>
          ))}</tbody>
        </table></div>
      )}
    </div>
  );
}

function RunDetail({ v, admin }: { v: RunView; admin: boolean }) {
  return (
    <div className="stack">
      <div className="row wrap"><Link className="btn quiet sm" href="/w/money?tab=runs">← All runs</Link><h2 className="grow">Run for {v.period.slice(0, 7)} {v.is_test && <span className="chip warm">test</span>}</h2>
        <RunActions run={v.id} status={admin ? v.status : "view"} /></div>
      <div className="grid g4">
        <div className="stat"><span className="small muted">Amount</span><b>{inr(v.totals?.amount)}</b></div>
        <div className="stat"><span className="small muted">TDS</span><b>{inr(v.totals?.tds)}</b></div>
        <div className="stat"><span className="small muted">Net</span><b>{inr(v.totals?.net)}</b></div>
        <div className="stat"><span className="small muted">Counsellors · lines</span><b>{v.totals?.counsellors ?? 0} · {v.totals?.lines ?? 0}</b></div>
      </div>
      {v.counsellors.map((c) => (
        <section key={c.counsellor_id} className="card pad stack">
          <div className="row"><h3 className="grow">{c.name} <span className="small muted">{c.email}</span></h3><span className="num">{inr(c.net)}</span></div>
          <CommissionLines lines={c.lines} leadHref={(id) => `/w/leads/${id}`} actions={admin && v.status === "draft" ? (l) => <ReleaseLine run={v.id} line={l.id} /> : undefined} />
        </section>
      ))}
    </div>
  );
}

function AdSpend({ o, dashboardId }: { o: AdOverview; dashboardId: number | null }) {
  const total = sum(o.campaigns, (c) => c.spend), leads = sum(o.campaigns, (c) => c.leads), net = sum(o.campaigns, (c) => c.commission_net);
  return (
    <div className="stack">
      <div className="row wrap"><p className="grow small">Last 90 days ({date(o.from)} – {date(o.to)}): leads are those that arrived in the period; commission is the net university commission booked for them.</p>
        {dashboardId && <Link className="btn ghost sm" href={`/w/analytics?d=${dashboardId}`}>Ad spend dashboard</Link>}<AdImportButton /></div>
      <div className="grid g4">
        <div className="stat"><span className="small muted">Spend</span><b>{inr(total)}</b></div>
        <div className="stat"><span className="small muted">Leads from ads</span><b>{leads}</b><span className="delta">{leads ? `${inr(total / leads)} a lead` : "none matched yet"}</span></div>
        <div className="stat"><span className="small muted">Commission from them (net)</span><b>{inr(net)}</b></div>
        <div className="stat"><span className="small muted">Return on ad spend</span><b>{total ? (net / total).toFixed(2) : "–"}</b><span className="delta">rupees back per rupee spent</span></div>
      </div>
      {o.campaigns.length === 0 ? <Empty>No spend imported yet. Export a day-by-day campaign report from Meta or Google and import it.</Empty> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Campaign</th><th className="right">Spend</th><th className="right">Clicks</th><th className="right">Platform leads</th><th className="right">Our leads</th>
            <th className="right">Cost a lead</th><th className="right">Enrolled</th><th className="right">ROAS</th><th>Matched by</th><th /></tr></thead>
          <tbody>{o.campaigns.map((c) => (
            <tr key={c.platform + c.campaign_id}>
              <td>{c.campaign ?? c.campaign_id}<div className="small muted">{c.platform === "meta" ? "Meta" : "Google"} · {c.campaign_id}</div></td>
              <td className="right num">{inr(c.spend)}</td><td className="right num">{c.clicks}</td><td className="right num">{c.platform_leads}</td>
              <td className="right num">{c.leads}</td><td className="right num">{c.leads ? inr(c.spend / c.leads) : "–"}</td><td className="right num">{c.enrolled}</td>
              <td className="right num">{c.spend ? (c.commission_net / c.spend).toFixed(2) : "–"}</td>
              <td className="small">{c.map ? (c.map.lead_campaign ? `campaign = ${c.map.lead_campaign}` : `source = ${c.map.lead_source}`) : c.leads ? "same campaign value" : <span className="chip risk">no leads matched</span>}</td>
              <td><AdMapButton platform={c.platform} campaignId={c.campaign_id} campaign={c.campaign ?? c.campaign_id} current={c.map} values={o.lead_values} /></td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
      {o.imports.length > 0 && <details><summary className="small">Imports ({o.imports.length})</summary>
        <div className="table-wrap"><table>
          <thead><tr><th>When</th><th>Platform</th><th>File</th><th>Days</th><th className="right">Rows</th><th className="right">Spend</th><th>By</th></tr></thead>
          <tbody>{o.imports.map((i) => <tr key={i.id}><td>{date(i.created_at)}</td><td>{i.platform}</td><td className="small">{i.file_name}</td><td className="small">{date(i.from_day)} – {date(i.to_day)}</td>
            <td className="right num">{i.rows}</td><td className="right num">{inr(i.spend)}</td><td>{i.by ?? "—"}</td></tr>)}</tbody>
        </table></div></details>}
    </div>
  );
}
