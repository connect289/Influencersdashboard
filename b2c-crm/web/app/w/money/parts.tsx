"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Upload } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { parseTiers } from "@/lib/money";
import {
  billingSave, commissionAdjust, enrollmentLink, enrollmentRefund, fallbackSave, invoiceAct, invoiceCancel, invoiceDraft, moneyRebook, overrideRetire, overrideSave,
  periodClose, rateRetire, rateSave, receiptRecord, runAct, runPrepare, runRelease, statementUpload,
} from "../money-actions";
import { invoiceEmail, runStatementsEmail } from "../admin-actions";

type Res<T> = { ok: true; data?: T; notice?: string } | { ok: false; error: string };
function useAct() {
  const router = useRouter();
  const [busy, start] = useTransition();
  const run = <T,>(fn: () => Promise<Res<T>>, after?: (d?: T) => void) =>
    start(async () => {
      const r = await fn();
      if (!r.ok) return void toast.error(r.error);
      if (r.notice) toast.success(r.notice);
      after?.(r.data);
      router.refresh();
    });
  return { busy, run };
}
const today = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
const num = (s: string) => (s.trim() === "" ? null : Number(s));

/** A button that opens a sheet; the sheet gets a close function. */
function Opener({ label, kind = "ghost", title, children }: { label: React.ReactNode; kind?: string; title: string; children: (close: () => void) => React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={`btn ${kind} sm`} onClick={() => setOpen(true)}>{label}</button>
      {open && <Sheet title={title} onClose={() => setOpen(false)}>{children(() => setOpen(false))}</Sheet>}
    </>
  );
}

/** One reason box and a confirm button, for every action that needs a why. */
function ReasonAction({ label, title, kind = "quiet", confirm, onConfirm, extra }: {
  label: string; title: string; kind?: string; confirm: string; onConfirm: (why: string) => Promise<Res<unknown>>; extra?: React.ReactNode;
}) {
  const { busy, run } = useAct();
  const [why, setWhy] = useState("");
  return (
    <Opener label={label} kind={kind} title={title}>
      {(close) => (
        <div className="stack">
          {extra}
          <label className="field"><span>Reason (kept in the audit log)</span><textarea className="input" value={why} onChange={(e) => setWhy(e.target.value)} maxLength={300} /></label>
          <button type="button" className="btn primary block" disabled={busy || why.trim().length < 3} onClick={() => run(() => onConfirm(why), close)}>{confirm}</button>
        </div>
      )}
    </Opener>
  );
}

// ---------- university rates and billing ----------
export function RateButton({ university, programmes }: { university: number; programmes: { id: number; name: string }[] }) {
  const { busy, run } = useAct();
  const [f, setF] = useState({ programme_id: "", rate_type: "percent", fee_base: "first_year", value: "", tiers: "", gst_inclusive: false, valid_from: today(), valid_to: "", note: "" });
  const set = (k: keyof typeof f, v: string | boolean) => setF({ ...f, [k]: v });
  const tiers = f.rate_type === "tiered" ? parseTiers(f.tiers) : null;
  return (
    <Opener label={<><Plus className="icon s" aria-hidden />New rate</>} title="New university rate">
      {(close) => (
        <div className="stack">
          <label className="field"><span>Applies to</span>
            <select className="input" value={f.programme_id} onChange={(e) => set("programme_id", e.target.value)}>
              <option value="">Every programme of this university</option>
              {programmes.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select></label>
          <div className="grid g2">
            <label className="field"><span>Kind</span>
              <select className="input" value={f.rate_type} onChange={(e) => set("rate_type", e.target.value)}>
                <option value="percent">Percent of the fee</option><option value="fixed">Fixed amount</option><option value="tiered">Tiered on conversion</option>
              </select></label>
            <label className="field"><span>Fee it is taken on</span>
              <select className="input" value={f.fee_base} onChange={(e) => set("fee_base", e.target.value)} disabled={f.rate_type === "fixed"}>
                <option value="first_year">First-year fee</option><option value="total">Total fee</option><option value="amount_paid">Amount paid</option>
              </select></label>
          </div>
          {f.rate_type === "tiered" ? (
            <label className="field"><span>Tiers: conversion from–to % : rate %</span>
              <input className="input mono" value={f.tiers} onChange={(e) => set("tiers", e.target.value)} placeholder="0-7:22.42, 7-9:20.42, 9-:18.42" />
              <span className="note">{f.tiers && !tiers ? "Tiers must start at 0, join with no gap and end open (e.g. 9-)." : "The tier is settled when the period closes."}</span></label>
          ) : (
            <label className="field"><span>{f.rate_type === "percent" ? "Rate %" : "Amount ₹"}</span><input className="input num" inputMode="decimal" value={f.value} onChange={(e) => set("value", e.target.value)} /></label>
          )}
          <label className="row small"><input type="checkbox" checked={f.gst_inclusive} onChange={(e) => set("gst_inclusive", e.target.checked)} /> The rate already includes GST</label>
          <div className="grid g2">
            <label className="field"><span>Valid from</span><input className="input" type="date" value={f.valid_from} onChange={(e) => set("valid_from", e.target.value)} /></label>
            <label className="field"><span>Valid to (optional)</span><input className="input" type="date" value={f.valid_to} onChange={(e) => set("valid_to", e.target.value)} /></label>
          </div>
          <label className="field"><span>Note (agreement, email…)</span><input className="input" value={f.note} onChange={(e) => set("note", e.target.value)} maxLength={300} /></label>
          <button type="button" className="btn primary block" disabled={busy || (f.rate_type === "tiered" ? !tiers : f.value === "")}
            onClick={() => run(() => rateSave({ university_id: university, programme_id: f.programme_id ? Number(f.programme_id) : null, rate_type: f.rate_type as "percent",
              fee_base: f.fee_base as "first_year", value: f.rate_type === "tiered" ? null : num(f.value), tiers, gst_inclusive: f.gst_inclusive, valid_from: f.valid_from,
              valid_to: f.valid_to || null, note: f.note || null }), close)}>Save rate</button>
          <p className="note">A new rate never changes what was booked before its start date. To correct past bookings, use “Book again” on the enrolment.</p>
        </div>
      )}
    </Opener>
  );
}
export function RateRetire({ rate }: { rate: number }) {
  return <ReasonAction label="Retire" title="Retire this rate" confirm="Retire" onConfirm={(why) => rateRetire(rate, why)} />;
}

type Billing = { legal_name?: string | null; gstin?: string | null; state_code?: string | null; address?: string | null; email?: string | null; payment_terms_days?: number | null; refund_days?: number | null };
export function BillingButton({ university, billing, name }: { university: number; billing: Billing | null; name: string }) {
  const { busy, run } = useAct();
  const [f, setF] = useState({ legal_name: billing?.legal_name ?? name, gstin: billing?.gstin ?? "", state_code: billing?.state_code ?? "", address: billing?.address ?? "",
    email: billing?.email ?? "", payment_terms_days: String(billing?.payment_terms_days ?? ""), refund_days: String(billing?.refund_days ?? "") });
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });
  return (
    <Opener label={billing ? "Edit billing" : "Add billing details"} title="University billing details">
      {(close) => (
        <div className="stack">
          <label className="field"><span>Legal name</span><input className="input" value={f.legal_name} onChange={(e) => set("legal_name", e.target.value)} /></label>
          <div className="grid g2">
            <label className="field"><span>GSTIN</span><input className="input mono" value={f.gstin} onChange={(e) => set("gstin", e.target.value.toUpperCase())} maxLength={15} /></label>
            <label className="field"><span>State code</span><input className="input mono" value={f.state_code} onChange={(e) => set("state_code", e.target.value)} maxLength={2} placeholder="07" /></label>
          </div>
          <label className="field"><span>Billing address</span><textarea className="input" value={f.address} onChange={(e) => set("address", e.target.value)} /></label>
          <label className="field"><span>Accounts email</span><input className="input" type="email" value={f.email} onChange={(e) => set("email", e.target.value)} /></label>
          <div className="grid g2">
            <label className="field"><span>Payment terms, days</span><input className="input num" inputMode="numeric" value={f.payment_terms_days} onChange={(e) => set("payment_terms_days", e.target.value)} placeholder="default" /></label>
            <label className="field"><span>Refund window, days</span><input className="input num" inputMode="numeric" value={f.refund_days} onChange={(e) => set("refund_days", e.target.value)} placeholder="default" /></label>
          </div>
          <button type="button" className="btn primary block" disabled={busy}
            onClick={() => run(() => billingSave({ university_id: university, ...f, payment_terms_days: num(f.payment_terms_days), refund_days: num(f.refund_days) }), close)}>Save</button>
        </div>
      )}
    </Opener>
  );
}

export function PeriodCloseButton({ university }: { university: number }) {
  const { busy, run } = useAct();
  const lastMonth = (() => { const d = new Date(today()); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString().slice(0, 10); })();
  const [period, setPeriod] = useState(lastMonth);
  const [leads, setLeads] = useState("");
  return (
    <Opener label="Close a period" title="Close a period and settle the tier">
      {(close) => (
        <div className="stack">
          <label className="field"><span>Month (first day)</span><input className="input" type="date" value={period} onChange={(e) => setPeriod(e.target.value)} /></label>
          <label className="field"><span>Leads the university counts (optional)</span><input className="input num" inputMode="numeric" value={leads} onChange={(e) => setLeads(e.target.value)} />
            <span className="note">Leave empty to use the CRM's count. Enter the university's number when the agreement uses theirs.</span></label>
          <button type="button" className="btn primary block" disabled={busy} onClick={() => run(() => periodClose(university, period, num(leads)), close)}>Close period</button>
        </div>
      )}
    </Opener>
  );
}

// ---------- enrolments ----------
export function EnrollmentMoney({ e, universities, programmes }: {
  e: { enrollment_id: number; university_id: number | null; programme_id: number | null; university: string; programme: string; status: string; fee: number | null };
  universities: { id: number; name: string }[]; programmes?: { id: number; name: string }[];
}) {
  const { busy, run } = useAct();
  const [uni, setUni] = useState(String(e.university_id ?? ""));
  const [prog, setProg] = useState(String(e.programme_id ?? ""));
  const [fee, setFee] = useState("");
  const [on, setOn] = useState(today());
  const [amount, setAmount] = useState("");
  return (
    <span className="row wrap" style={{ gap: 2 }}>
      {(!e.university_id || !e.programme_id) && (
        <Opener label="Link" kind="primary" title="Link to the catalogue">
          {(close) => (
            <div className="stack">
              <p className="small">Reported as <b>{e.university}</b> · {e.programme}</p>
              <label className="field"><span>University</span>
                <select className="input" value={uni} onChange={(x) => setUni(x.target.value)}><option value="">Choose</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
              <label className="field"><span>Programme id (from the catalogue)</span><input className="input num" value={prog} onChange={(x) => setProg(x.target.value)} />
                {programmes?.length ? <span className="note">{programmes.map((p) => `${p.id}: ${p.name}`).join(" · ")}</span> : null}</label>
              <label className="field"><span>First-year fee ₹ (if different from the catalogue)</span><input className="input num" value={fee} onChange={(x) => setFee(x.target.value)} /></label>
              <button type="button" className="btn primary block" disabled={busy || !uni} onClick={() => run(() => enrollmentLink(e.enrollment_id, Number(uni), prog ? Number(prog) : null, num(fee)), close)}>Link and book</button>
            </div>
          )}
        </Opener>
      )}
      {e.status !== "refunded" && (
        <ReasonAction label="Refund" title="Record a refund" confirm="Record refund" onConfirm={(why) => enrollmentRefund(e.enrollment_id, on, why)}
          extra={<label className="field"><span>Refunded on</span><input className="input" type="date" value={on} onChange={(x) => setOn(x.target.value)} />
            <span className="note">Inside the refund window both commissions reverse. After settlement the counsellor's is clawed back from the next run.</span></label>} />
      )}
      <ReasonAction label="Book again" title="Book this enrolment again" confirm="Reverse and book again" onConfirm={(why) => moneyRebook(e.enrollment_id, why)}
        extra={<p className="note">Reverses what was booked and books again at the rates valid on the enrolment date. Settled counsellor lines are never changed; the difference becomes an adjustment.</p>} />
      <ReasonAction label="Adjust" title="Adjust the counsellor's commission" confirm="Book adjustment" onConfirm={(why) => commissionAdjust(e.enrollment_id, Number(amount), why)}
        extra={<label className="field"><span>Amount ₹ (negative to reduce)</span><input className="input num" value={amount} onChange={(x) => setAmount(x.target.value)} /></label>} />
    </span>
  );
}

// ---------- invoices, receipts, statements ----------
export function InvoiceDraftButton({ university, uninvoiced }: { university: number; uninvoiced: { lines: number; gross: number } }) {
  const { busy, run } = useAct();
  const [upto, setUpto] = useState(today());
  const [test, setTest] = useState(false);
  return (
    <Opener label="Draft invoice" kind="primary" title="Draft an invoice">
      {(close) => (
        <div className="stack">
          <p className="small">{uninvoiced.lines} realised lines are not invoiced yet.</p>
          <label className="field"><span>Include lines realised up to</span><input className="input" type="date" value={upto} onChange={(e) => setUpto(e.target.value)} /></label>
          <label className="row small"><input type="checkbox" checked={test} onChange={(e) => setTest(e.target.checked)} /> Test invoice (test leads only, TEST- series)</label>
          <button type="button" className="btn primary block" disabled={busy} onClick={() => run(() => invoiceDraft(university, upto, test), close)}>Make draft</button>
        </div>
      )}
    </Opener>
  );
}
export function InvoiceActions({ invoice, status, kind }: { invoice: number; status: string; kind: string }) {
  const { busy, run } = useAct();
  return (
    <span className="row wrap" style={{ gap: 2 }}>
      <a className="btn quiet sm" href={`/w/money/invoice/${invoice}`} target="_blank" rel="noopener">PDF</a>
      {status === "draft" && <>
        <button type="button" className="btn primary sm" disabled={busy} onClick={() => run(() => invoiceAct(invoice, "approve"))}>Approve</button>
        <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run(() => invoiceAct(invoice, "discard"))}>Discard</button>
      </>}
      {status === "approved" && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => invoiceAct(invoice, "sent"))}>Mark sent</button>}
      {["approved", "sent", "part_paid"].includes(status) && <InvoiceEmailButton invoice={invoice} again={status !== "approved"} />}
      {kind === "invoice" && ["approved", "sent", "part_paid"].includes(status) && (
        <ReasonAction label="Cancel" title="Cancel this invoice" confirm="Cancel and raise a credit note" onConfirm={(why) => invoiceCancel(invoice, why)}
          extra={<p className="note">The number is never reused: a credit note for the full amount is raised and its lines can be invoiced again.</p>} />
      )}
    </span>
  );
}
/** The approved invoice to the university's billing email with the PDF (b2c.invoice_send); it is marked sent too. */
function InvoiceEmailButton({ invoice, again }: { invoice: number; again: boolean }) {
  const { busy, run } = useAct();
  const [note, setNote] = useState("");
  return (
    <Opener label={again ? "Email again" : "Email to university"} title="Email this invoice to the university">
      {(close) => (
        <div className="stack">
          <p className="note">It goes to the billing email under the university&apos;s billing details, with the invoice PDF attached, from the system mailbox.</p>
          <label className="field"><span>A line to add (optional)</span><textarea className="input" rows={3} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} /></label>
          <button type="button" className="btn primary block" disabled={busy} onClick={() => run(() => invoiceEmail(invoice, note), close)}>Send</button>
        </div>
      )}
    </Opener>
  );
}
export function ReceiptButton({ university, invoices }: { university: number; invoices: { id: number; number: string | null; open: number }[] }) {
  const { busy, run } = useAct();
  const [f, setF] = useState({ invoice_id: "", amount: "", tds: "", received_on: today(), reference: "", note: "" });
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });
  return (
    <Opener label="Record receipt" title="Record money received">
      {(close) => (
        <div className="stack">
          <label className="field"><span>Against invoice</span>
            <select className="input" value={f.invoice_id} onChange={(e) => set("invoice_id", e.target.value)}>
              <option value="">Match automatically (exact amount, then oldest first)</option>
              {invoices.map((i) => <option key={i.id} value={i.id}>{i.number ?? `#${i.id}`} · open {i.open}</option>)}
            </select></label>
          <div className="grid g2">
            <label className="field"><span>Amount received ₹</span><input className="input num" value={f.amount} onChange={(e) => set("amount", e.target.value)} /></label>
            <label className="field"><span>TDS deducted ₹</span><input className="input num" value={f.tds} onChange={(e) => set("tds", e.target.value)} /></label>
          </div>
          <div className="grid g2">
            <label className="field"><span>Received on</span><input className="input" type="date" value={f.received_on} onChange={(e) => set("received_on", e.target.value)} /></label>
            <label className="field"><span>UTR or cheque number</span><input className="input mono" value={f.reference} onChange={(e) => set("reference", e.target.value)} /></label>
          </div>
          <label className="field"><span>Note</span><input className="input" value={f.note} onChange={(e) => set("note", e.target.value)} /></label>
          <button type="button" className="btn primary block" disabled={busy}
            onClick={() => run(() => receiptRecord({ university_id: university, invoice_id: f.invoice_id ? Number(f.invoice_id) : null, amount: Number(f.amount), tds: Number(f.tds || 0),
              received_on: f.received_on, reference: f.reference, note: f.note }), close)}>Record</button>
        </div>
      )}
    </Opener>
  );
}
export function StatementUpload({ universities }: { universities: { id: number; name: string }[] }) {
  const { busy, run } = useAct();
  const [uni, setUni] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [file, setFile] = useState<File | null>(null);
  return (
    <Opener label={<><Upload className="icon s" aria-hidden />Upload statement</>} kind="primary" title="Upload a university's commission statement">
      {(close) => (
        <div className="stack">
          <label className="field"><span>University</span>
            <select className="input" value={uni} onChange={(e) => setUni(e.target.value)}><option value="">Choose</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
          <div className="grid g2">
            <label className="field"><span>Period from</span><input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
            <label className="field"><span>Period to</span><input className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
          </div>
          <label className="field"><span>CSV file</span><input className="input" type="file" accept=".csv,text/csv" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            <span className="note">Needs an amount column and a reference (enrolment id) or student name column. Save Excel files as CSV first.</span></label>
          <button type="button" className="btn primary block" disabled={busy || !uni || !from || !to || !file}
            onClick={() => file && run(async () => statementUpload(Number(uni), from, to, file.name, await file.text()), close)}>Reconcile</button>
        </div>
      )}
    </Opener>
  );
}

// ---------- counsellor commission ----------
function RuleFields({ f, set }: { f: { rate_type: string; fee_base: string; value: string }; set: (k: "rate_type" | "fee_base" | "value", v: string) => void }) {
  return (
    <div className="grid g3">
      <label className="field"><span>Kind</span><select className="input" value={f.rate_type} onChange={(e) => set("rate_type", e.target.value)}><option value="percent">Percent</option><option value="fixed">Fixed ₹</option></select></label>
      <label className="field"><span>Fee</span><select className="input" value={f.fee_base} onChange={(e) => set("fee_base", e.target.value)} disabled={f.rate_type === "fixed"}>
        <option value="first_year">First-year</option><option value="total">Total</option><option value="amount_paid">Amount paid</option></select></label>
      <label className="field"><span>{f.rate_type === "percent" ? "Rate %" : "Amount ₹"}</span><input className="input num" value={f.value} onChange={(e) => set("value", e.target.value)} /></label>
    </div>
  );
}
export function FallbackButton({ universities, current }: { universities: { id: number; name: string }[]; current?: { university_id: number } }) {
  const { busy, run } = useAct();
  const [f, setF] = useState({ university_id: String(current?.university_id ?? ""), rate_type: "percent", fee_base: "first_year", value: "", reason: "" });
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });
  return (
    <Opener label={current ? "Change" : <><Plus className="icon s" aria-hidden />Set a fallback</>} kind={current ? "quiet" : "ghost"} title="Fallback rate for a university">
      {(close) => (
        <div className="stack">
          <p className="note">Used only when no active partner has a rate for the programme. Lines waiting for a rate are booked again at once.</p>
          <label className="field"><span>University</span>
            <select className="input" value={f.university_id} onChange={(e) => set("university_id", e.target.value)} disabled={!!current}><option value="">Choose</option>
              {universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}</select></label>
          <RuleFields f={f} set={set} />
          <label className="field"><span>Reason</span><input className="input" value={f.reason} onChange={(e) => set("reason", e.target.value)} /></label>
          <button type="button" className="btn primary block" disabled={busy || !f.university_id || !f.value}
            onClick={() => run(() => fallbackSave({ university_id: Number(f.university_id), rate_type: f.rate_type as "percent", fee_base: f.fee_base as "first_year", value: Number(f.value), reason: f.reason }), close)}>Save fallback</button>
        </div>
      )}
    </Opener>
  );
}
export function OverrideButton({ counsellors }: { counsellors: { user_id: string; name: string | null }[] }) {
  const { busy, run } = useAct();
  const [f, setF] = useState({ counsellor_id: "", programme_id: "", rate_type: "percent", fee_base: "first_year", value: "", valid_from: today(), valid_to: "", reason: "" });
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });
  return (
    <Opener label={<><Plus className="icon s" aria-hidden />New override</>} title="Commission override">
      {(close) => (
        <div className="stack">
          <p className="note">Replaces the partner rate for one counsellor, one programme, or one counsellor on one programme, for bookings from its start date.</p>
          <label className="field"><span>Counsellor (optional)</span>
            <select className="input" value={f.counsellor_id} onChange={(e) => set("counsellor_id", e.target.value)}><option value="">Everyone</option>
              {counsellors.map((c) => <option key={c.user_id} value={c.user_id}>{c.name ?? c.user_id}</option>)}</select></label>
          <label className="field"><span>Programme id (optional)</span><input className="input num" value={f.programme_id} onChange={(e) => set("programme_id", e.target.value)} placeholder="every programme" /></label>
          <RuleFields f={f} set={set} />
          <div className="grid g2">
            <label className="field"><span>Valid from</span><input className="input" type="date" value={f.valid_from} onChange={(e) => set("valid_from", e.target.value)} /></label>
            <label className="field"><span>Valid to (optional)</span><input className="input" type="date" value={f.valid_to} onChange={(e) => set("valid_to", e.target.value)} /></label>
          </div>
          <label className="field"><span>Reason</span><input className="input" value={f.reason} onChange={(e) => set("reason", e.target.value)} /></label>
          <button type="button" className="btn primary block" disabled={busy || !f.value || (!f.counsellor_id && !f.programme_id)}
            onClick={() => run(() => overrideSave({ counsellor_id: f.counsellor_id || null, programme_id: f.programme_id ? Number(f.programme_id) : null, rate_type: f.rate_type as "percent",
              fee_base: f.fee_base as "first_year", value: Number(f.value), valid_from: f.valid_from, valid_to: f.valid_to || null, reason: f.reason }), close)}>Save override</button>
        </div>
      )}
    </Opener>
  );
}
export function OverrideRetire({ id }: { id: number }) {
  return <ReasonAction label="Retire" title="Retire this override" confirm="Retire" onConfirm={(why) => overrideRetire(id, why)} />;
}
export function RunPrepareButton({ nextRun }: { nextRun: string }) {
  const { busy, run } = useAct();
  const [period, setPeriod] = useState(() => { const d = new Date(today()); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString().slice(0, 10); });
  const [test, setTest] = useState(false);
  return (
    <Opener label="Prepare a run now" title="Prepare a commission run">
      {(close) => (
        <div className="stack">
          <p className="note">Runs are prepared by themselves on the run day ({nextRun}). A run takes every due line not in another run.</p>
          <label className="field"><span>Month the run is for (first day)</span><input className="input" type="date" value={period} onChange={(e) => setPeriod(e.target.value)} /></label>
          <label className="row small"><input type="checkbox" checked={test} onChange={(e) => setTest(e.target.checked)} /> Test run (test leads only)</label>
          <button type="button" className="btn primary block" disabled={busy} onClick={() => run(() => runPrepare(period, test), close)}>Prepare</button>
        </div>
      )}
    </Opener>
  );
}
export function RunActions({ run: runId, status }: { run: number; status: string }) {
  const { busy, run } = useAct();
  return (
    <span className="row wrap" style={{ gap: 2 }}>
      <a className="btn quiet sm" href={`/w/money/run/${runId}/csv`}>Finance CSV</a>
      {status === "draft" && <>
        <button type="button" className="btn primary sm" disabled={busy} onClick={() => run(() => runAct(runId, "approve"))}>Approve</button>
        <ReasonAction label="Cancel" title="Cancel this run" confirm="Cancel run" onConfirm={(why) => runAct(runId, "cancel", why)} />
      </>}
      {(status === "approved" || status === "paid") && (
        <button type="button" className="btn ghost sm" disabled={busy} onClick={() => confirm("Email each counsellor their statement for this run, with the PDF?") && run(() => runStatementsEmail(runId))}>Email statements</button>
      )}
    </span>
  );
}
export function ReleaseLine({ run, line }: { run: number; line: number }) {
  return <ReasonAction label="Hold back" title="Hold this line for the next run" confirm="Hold back" onConfirm={(why) => runRelease(run, line, why)} />;
}
