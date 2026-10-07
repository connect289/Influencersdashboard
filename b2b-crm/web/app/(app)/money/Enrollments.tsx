"use client";
import { Fragment, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronDown, ChevronRight, Plus, Scale } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { Label, Modal, field } from "@/components/ui/Modal";
import { cn } from "@/components/ui/cn";
import { ENROLLMENT_STATUS, LINE_KIND, PROOF_TYPE, dayLabel, formatInr, monthLabel, type EnrollmentRow, type ProofType } from "@/lib/money";
import { addAdjustment, addEnrollment, cancelEnrollment, refundEnrollment, verifyEnrollment } from "./actions";

const today = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);

function Lines({ e }: { e: EnrollmentRow }) {
  if (e.lines.length === 0) return <p className="text-[12px] text-warning">No commission line yet: no rate in force on the enrolment date, or the fee is unknown. Verifying asks for what is missing.</p>;
  return (
    <table className="w-full text-[12px]">
      <thead className="text-[10.5px] uppercase tracking-wider text-subtle">
        <tr><th className="py-1 text-left font-medium">Line</th><th className="py-1 text-left font-medium">Month</th><th className="py-1 text-left font-medium">Basis</th>
          <th className="py-1 text-right font-medium">Net</th><th className="py-1 text-right font-medium">GST</th><th className="py-1 text-right font-medium">Gross</th><th className="py-1 text-left font-medium pl-3">Invoice</th></tr>
      </thead>
      <tbody>
        {e.lines.map((l) => (
          <tr key={l.id} className={cn(l.status === "void" && "text-subtle line-through")}>
            <td className="py-1 text-fg">{LINE_KIND[l.kind]} <span className="text-subtle">· {l.status}</span>{l.provisional && <Badge tone="warning" className="ml-1">provisional tier</Badge>}</td>
            <td className="py-1 text-muted">{monthLabel(l.period)}</td>
            <td className="py-1 text-muted">{l.pct !== null ? `${Number(l.pct)}% of ${formatInr(l.fee_base_inr)}` : l.rate_type === "fixed" ? "fixed" : l.note ?? "—"}
              {l.gst_inclusive && <span className="text-subtle"> (rate incl. GST)</span>}</td>
            <td className="tabular py-1 text-right text-fg">{formatInr(l.net_inr, true)}</td>
            <td className="tabular py-1 text-right text-muted">{formatInr(l.gst_inr, true)}</td>
            <td className="tabular py-1 text-right text-muted">{formatInr(l.gross_inr, true)}</td>
            <td className="py-1 pl-3">{l.invoice_id ? <Link href={`/money/invoices/${l.invoice_id}`} className="font-mono text-info hover:underline">{l.invoice_number ?? `Draft #${l.invoice_id}`}</Link> : <span className="text-subtle">—</span>}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Enrolments with their commission lines; verify with proof, cancel a wrong report, or refund inside the window. */
export function EnrollmentTable({ rows, refundDays }: { rows: EnrollmentRow[]; refundDays: number }) {
  const router = useRouter();
  const [open, setOpen] = useState<Set<number>>(new Set());
  const [verify, setVerify] = useState<EnrollmentRow | null>(null);
  const [cancel, setCancel] = useState<EnrollmentRow | null>(null);
  const [refund, setRefund] = useState<EnrollmentRow | null>(null);
  const toggle = (id: number) => setOpen((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });

  return (
    <>
      <div className="relative overflow-x-auto">
        <table className="w-full min-w-[900px] text-left text-[12.5px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="w-8 py-2 pl-5"><span className="sr-only">Lines</span></th>
              <th scope="col" className="px-3 py-2 font-medium">Student</th>
              <th scope="col" className="px-3 py-2 font-medium">Partner and programme</th>
              <th scope="col" className="px-3 py-2 font-medium">Enrolled</th>
              <th scope="col" className="px-3 py-2 text-right font-medium">Fee</th>
              <th scope="col" className="px-3 py-2 text-right font-medium">Commission (net)</th>
              <th scope="col" className="px-3 py-2 font-medium">Status</th>
              <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((e) => {
              const st = ENROLLMENT_STATUS[e.status];
              const net = e.status === "verified" ? e.realised_net_inr : e.expected_net_inr;
              const provisional = e.lines.some((l) => l.provisional && l.status !== "void");
              return (
                <Fragment key={e.id}>
                  <tr className="align-top">
                    <td className="py-2.5 pl-5">
                      <button type="button" onClick={() => toggle(e.id)} aria-expanded={open.has(e.id)} aria-label="Show commission lines" className="text-muted hover:text-fg">
                        {open.has(e.id) ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
                      </button>
                    </td>
                    <td className="px-3 py-2.5">
                      <Link href={`/leads?lead=${e.lead_id}`} className="font-medium text-fg hover:underline">{e.name ?? `Lead #${e.lead_id}`}</Link>
                      <span className="block whitespace-nowrap font-mono text-[11.5px] text-subtle">{e.reference}{e.record_id && ` · ${e.record_id}`}</span>
                    </td>
                    <td className="px-3 py-2.5"><span className="text-fg">{e.partner_name}</span>
                      <span className="block max-w-[260px] truncate text-[11.5px] text-muted">{[e.programme, e.university].filter(Boolean).join(", ") || "Programme not known"}</span></td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-muted">{dayLabel(e.enrolled_on)}</td>
                    <td className="tabular px-3 py-2.5 text-right text-muted">{formatInr(e.fee_amount_inr)}</td>
                    <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(net)}{provisional && <span className="block font-sans text-[11px] text-warning">tier provisional</span>}</td>
                    <td className="px-3 py-2.5"><Badge tone={st.tone}>{st.label}</Badge>
                      {e.proof_ref && <span className="mt-0.5 block max-w-[200px] truncate text-[11px] text-subtle" title={e.proof_ref}>{e.proof_ref}</span>}
                      {e.status === "verified" && e.refund_window_ends_on && <span className="block text-[11px] text-subtle">refund window to {dayLabel(e.refund_window_ends_on)}</span>}
                      {e.refund_reason && e.status !== "verified" && <span className="block max-w-[200px] truncate text-[11px] text-subtle">{e.refund_reason}</span>}</td>
                    <td className="whitespace-nowrap px-5 py-2.5 text-right">
                      {e.status === "reported" && <>
                        <Button size="sm" onClick={() => setVerify(e)}>Verify</Button>
                        <Button size="sm" variant="ghost" onClick={() => setCancel(e)}>Cancel</Button>
                      </>}
                      {e.status === "verified" && <Button size="sm" variant="ghost" onClick={() => setRefund(e)}>Refund</Button>}
                    </td>
                  </tr>
                  {open.has(e.id) && <tr><td /><td colSpan={7} className="px-3 pb-3"><div className="rounded-lg bg-surface-2/60 px-3 py-2"><Lines e={e} /></div></td></tr>}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
      {verify && <VerifyDialog e={verify} onClose={() => setVerify(null)} onDone={() => router.refresh()} />}
      {refund && <RefundDialog e={refund} refundDays={refundDays} onClose={() => setRefund(null)} onDone={() => router.refresh()} />}
      <ConfirmDialog open={Boolean(cancel)} onClose={() => setCancel(null)} title="Cancel this enrolment report?" confirmLabel="Cancel enrolment" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. the partner reported the wrong student" }}
        onConfirm={async (reason) => { const r = await cancelEnrollment(cancel!.id, reason); if (!r.ok) return r.error; toast.success("Enrolment cancelled"); router.refresh(); }}>
        <p className="text-[13px] text-muted">The expected commission line is voided. The money scan will not record this lead again; record it by hand if the partner reports it later.</p>
      </ConfirmDialog>
    </>
  );
}

function VerifyDialog({ e, onClose, onDone }: { e: EnrollmentRow; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState({ proof_type: "statement_line" as ProofType, proof_ref: "", proof_url: "", fee_amount_inr: e.fee_amount_inr ? String(e.fee_amount_inr) : "",
                               fee_paid_inr: e.fee_paid_inr ? String(e.fee_paid_inr) : "", enrolled_on: e.enrolled_on });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const submit = async () => {
    setPending(true); setError(null);
    try {
      const r = await verifyEnrollment(e.id, f);
      if (!r.ok) { setError(r.error); return; }
      toast.success(`Verified: ${formatInr(r.data.amounts.net)} commission booked`);
      onClose(); onDone();
    } finally { setPending(false); }
  };
  return (
    <Modal open onClose={onClose} title={`Verify ${e.name ?? "enrolment"} · ${e.partner_name}`} error={error} pending={pending} onSubmit={submit} submitLabel="Verify and book">
      <p className="text-[12.5px] text-muted">Verifying turns the expected commission into a realised line (net of GST) for the next invoice. Correct the fee or date if the proof says otherwise.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Proof">
          <select className={field} value={f.proof_type} onChange={(x) => setF({ ...f, proof_type: x.target.value as ProofType })}>
            {Object.entries(PROOF_TYPE).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Label>
        <Label text="Reference" hint="Statement row, confirmation or receipt number">
          <input className={field} value={f.proof_ref} onChange={(x) => setF({ ...f, proof_ref: x.target.value })} maxLength={300} required />
        </Label>
        <Label text="Link to the proof (optional)" hint="A Drive or partner-portal link"><input className={field} value={f.proof_url} placeholder="https://" onChange={(x) => setF({ ...f, proof_url: x.target.value })} /></Label>
        <Label text="Enrolment date"><input type="date" className={field} value={f.enrolled_on} max={today()} onChange={(x) => setF({ ...f, enrolled_on: x.target.value })} /></Label>
        <Label text="Programme fee (₹)" hint="Total fee; percentage rates use it when the partner's file has none"><input className={field} inputMode="decimal" value={f.fee_amount_inr} onChange={(x) => setF({ ...f, fee_amount_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
        <Label text="Fee paid so far (₹)"><input className={field} inputMode="decimal" value={f.fee_paid_inr} onChange={(x) => setF({ ...f, fee_paid_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
      </div>
    </Modal>
  );
}

function RefundDialog({ e, refundDays, onClose, onDone }: { e: EnrollmentRow; refundDays: number; onClose: () => void; onDone: () => void }) {
  const [f, setF] = useState({ refunded_on: today(), reason: "", outside_window: false });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const outside = Boolean(e.refund_window_ends_on && f.refunded_on > e.refund_window_ends_on);
  const submit = async () => {
    setPending(true); setError(null);
    try {
      const r = await refundEnrollment(e.id, f);
      if (!r.ok) { setError(r.error); return; }
      toast.success(`Refund recorded: ${formatInr(-r.data.reversed_net_inr)} reverses on the next invoice`);
      onClose(); onDone();
    } finally { setPending(false); }
  };
  return (
    <Modal open onClose={onClose} title={`Refund · ${e.name ?? "enrolment"}`} error={error} pending={pending} onSubmit={submit} submitLabel="Record refund">
      <p className="text-[12.5px] text-muted">Within {refundDays} days of enrolment (until {dayLabel(e.refund_window_ends_on)}) the commission is reversed with negative lines; an invoiced one is credited on the next invoice.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Refunded on"><input type="date" className={field} value={f.refunded_on} min={e.enrolled_on} max={today()} onChange={(x) => setF({ ...f, refunded_on: x.target.value })} /></Label>
        <Label text="Reason"><input className={field} value={f.reason} maxLength={300} onChange={(x) => setF({ ...f, reason: x.target.value })} /></Label>
      </div>
      {outside && (
        <label className="flex items-start gap-2 text-[12.5px] text-warning">
          <input type="checkbox" className="mt-0.5 accent-[var(--primary)]" checked={f.outside_window} onChange={(x) => setF({ ...f, outside_window: x.target.checked })} />
          The refund window has ended. Tick only if Eduwit agreed to give the commission back anyway.
        </label>
      )}
    </Modal>
  );
}

/** Records an enrolment the partner reported outside its CRM (a call, an email), by the lead's Eduwit reference. */
export function AddEnrollment() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({ reference: "", enrolled_on: "", fee_amount_inr: "", fee_paid_inr: "", proof_ref: "" });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const submit = async () => {
    setPending(true); setError(null);
    try {
      const r = await addEnrollment(f);
      if (!r.ok) { setError(r.error); return; }
      toast.success(r.data.existing ? "That lead already has an enrolment" : "Enrolment recorded; verify it when the proof arrives");
      setOpen(false); setF({ reference: "", enrolled_on: "", fee_amount_inr: "", fee_paid_inr: "", proof_ref: "" }); router.refresh();
    } finally { setPending(false); }
  };
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}><Plus className="size-3.5" /> Record enrolment</Button>
      <Modal open={open} onClose={() => setOpen(false)} title="Record an enrolment" error={error} pending={pending} onSubmit={submit} submitLabel="Record">
        <p className="text-[12.5px] text-muted">For a partner lead the partner says enrolled. It is added as “to verify” with its expected commission. Test leads never earn commission.</p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Label text="Eduwit reference"><input className={cn(field, "font-mono")} placeholder="EDW-5502" value={f.reference} onChange={(x) => setF({ ...f, reference: x.target.value })} /></Label>
          <Label text="Enrolment date"><input type="date" className={field} value={f.enrolled_on} max={today()} onChange={(x) => setF({ ...f, enrolled_on: x.target.value })} /></Label>
          <Label text="Programme fee (₹, optional)"><input className={field} inputMode="decimal" value={f.fee_amount_inr} onChange={(x) => setF({ ...f, fee_amount_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
          <Label text="Fee paid (₹, optional)"><input className={field} inputMode="decimal" value={f.fee_paid_inr} onChange={(x) => setF({ ...f, fee_paid_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
        </div>
        <Label text="How you know (optional)"><input className={field} value={f.proof_ref} maxLength={300} placeholder="e.g. partner email of 6 Oct" onChange={(x) => setF({ ...f, proof_ref: x.target.value })} /></Label>
      </Modal>
    </>
  );
}

/** A signed adjustment agreed with the partner (a goodwill credit, a missed payout), realised at once and invoiced at the next close. */
export function AdjustmentButton({ partners }: { partners: { id: number; name: string }[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({ partner_id: "", enrollment_id: "", net_inr: "", note: "" });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const submit = async () => {
    setPending(true); setError(null);
    try {
      const r = await addAdjustment({ ...f, partner_id: Number(f.partner_id) });
      if (!r.ok) { setError(r.error); return; }
      toast.success("Adjustment recorded; it goes on the next invoice");
      setOpen(false); setF({ partner_id: "", enrollment_id: "", net_inr: "", note: "" }); router.refresh();
    } finally { setPending(false); }
  };
  return (
    <>
      <Button size="sm" variant="ghost" onClick={() => setOpen(true)}><Scale className="size-3.5" /> Adjustment</Button>
      <Modal open={open} onClose={() => setOpen(false)} title="Record an adjustment" error={error} pending={pending} onSubmit={submit} submitLabel="Record">
        <p className="text-[12.5px] text-muted">Net of GST; GST is added at the configured rate. Use a minus sign for a credit to the partner.</p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Label text="Partner">
            <select className={field} value={f.partner_id} onChange={(x) => setF({ ...f, partner_id: x.target.value })}>
              <option value="" disabled>Choose…</option>
              {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Label>
          <Label text="Amount, net (₹)"><input className={field} inputMode="decimal" placeholder="-2500" value={f.net_inr} onChange={(x) => setF({ ...f, net_inr: x.target.value.replace(/[^\d.-]/g, "") })} /></Label>
          <Label text="Enrolment ID (optional)"><input className={field} inputMode="numeric" value={f.enrollment_id} onChange={(x) => setF({ ...f, enrollment_id: x.target.value.replace(/\D/g, "") })} /></Label>
          <Label text="What was agreed"><input className={field} value={f.note} maxLength={300} onChange={(x) => setF({ ...f, note: x.target.value })} /></Label>
        </div>
      </Modal>
    </>
  );
}
