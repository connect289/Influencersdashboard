"use client";
import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { LoaderCircle, Receipt as ReceiptIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { Label, field } from "@/components/ui/Modal";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { dayLabel, formatInr, type ReceiptsData } from "@/lib/money";
import { applyReceipt, recordReceipt, voidReceipt } from "./actions";

const today = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
const empty = { partner_id: "", received_on: today(), amount_inr: "", tds_inr: "", bank_ref: "", note: "", invoice_id: "" };
const METHOD: Record<string, string> = { auto_exact: "matched exactly", auto_oldest: "oldest first", manual: "by hand" };

export function ReceiptForm({ partners, invoices }: { partners: { id: number; name: string }[]; invoices: ReceiptsData["open_invoices"] }) {
  const router = useRouter();
  const [f, setF] = useState(empty);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const open = useMemo(() => invoices.filter((i) => String(i.partner_id) === f.partner_id), [invoices, f.partner_id]);
  const credit = (Number(f.amount_inr) || 0) + (Number(f.tds_inr) || 0);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPending(true); setError(null);
    try {
      const r = await recordReceipt({ ...f, partner_id: Number(f.partner_id) });
      if (!r.ok) { setError(r.error); return; }
      toast.success(r.data.unapplied_inr > 0 ? `Recorded; ${formatInr(r.data.unapplied_inr)} is not on any invoice yet` : "Recorded and matched");
      setF({ ...empty, received_on: today() }); router.refresh();
    } finally { setPending(false); }
  };
  return (
    <form onSubmit={submit} className="space-y-3 px-5 py-4" noValidate>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Partner">
          <select className={field} value={f.partner_id} onChange={(x) => setF({ ...f, partner_id: x.target.value, invoice_id: "" })}>
            <option value="" disabled>Choose…</option>
            {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Label>
        <Label text="Received on"><input type="date" className={field} value={f.received_on} max={today()} onChange={(x) => setF({ ...f, received_on: x.target.value })} /></Label>
        <Label text="Amount in the bank (₹)"><input className={field} inputMode="decimal" value={f.amount_inr} onChange={(x) => setF({ ...f, amount_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
        <Label text="TDS deducted (₹)" hint="Claim it against Form 26AS / 16A"><input className={field} inputMode="decimal" value={f.tds_inr} onChange={(x) => setF({ ...f, tds_inr: x.target.value.replace(/[^\d.]/g, "") })} /></Label>
        <Label text="Bank reference (UTR)"><input className={cn(field, "font-mono")} value={f.bank_ref} maxLength={80} onChange={(x) => setF({ ...f, bank_ref: x.target.value })} /></Label>
        <Label text="Against invoice">
          <select className={field} value={f.invoice_id} onChange={(x) => setF({ ...f, invoice_id: x.target.value })} disabled={!f.partner_id}>
            <option value="">Match automatically</option>
            {open.map((i) => <option key={i.id} value={i.id}>{i.number} · {formatInr(i.outstanding_inr, true)} open</option>)}
          </select>
        </Label>
      </div>
      <Label text="Note (optional)"><input className={field} value={f.note} maxLength={300} onChange={(x) => setF({ ...f, note: x.target.value })} /></Label>
      {credit > 0 && <p className="text-[12px] text-muted">Credit to invoices: <span className="tabular text-fg">{formatInr(credit, true)}</span> (amount + TDS).</p>}
      {error && <Notice tone="error">{error}</Notice>}
      <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Record receipt</Button>
    </form>
  );
}

export function ReceiptList({ receipts, invoices }: { receipts: ReceiptsData["receipts"]; invoices: ReceiptsData["open_invoices"] }) {
  const router = useRouter();
  const [voiding, setVoiding] = useState<number | null>(null);
  const [busy, setBusy] = useState<number | null>(null);
  if (receipts.length === 0) return <EmptyState icon={ReceiptIcon} title="No receipts yet">Record each payment as it reaches the bank; invoices move to part paid and paid.</EmptyState>;
  const apply = async (id: number, invoice: string) => {
    if (!invoice) return;
    setBusy(id);
    try {
      const r = await applyReceipt(id, Number(invoice));
      if (!r.ok) toast.error(r.error); else { toast.success(`${formatInr(r.data, true)} applied`); router.refresh(); }
    } finally { setBusy(null); }
  };
  return (
    <>
      <ul className="divide-y divide-border">
        {receipts.map((r) => {
          const open = invoices.filter((i) => i.partner_id === r.partner_id);
          return (
            <li key={r.id} className={cn("space-y-1.5 px-5 py-3 text-[12.5px]", r.status === "void" && "opacity-60")}>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span className="tabular font-medium text-fg">{formatInr(r.amount_inr, true)}</span>
                {r.tds_inr > 0 && <span className="tabular text-muted">+ {formatInr(r.tds_inr, true)} TDS</span>}
                <span className="text-fg">{r.partner_name}</span>
                <span className="text-muted">{dayLabel(r.received_on)}</span>
                {r.bank_ref && <span className="font-mono text-subtle">{r.bank_ref}</span>}
                {r.status === "void" ? <Badge tone="danger">Void</Badge> : r.unapplied_inr > 0 ? <Badge tone="warning">{formatInr(r.unapplied_inr, true)} not applied</Badge> : <Badge tone="success">Applied</Badge>}
                {r.status === "active" && <Button size="sm" variant="ghost" className="ml-auto" onClick={() => setVoiding(r.id)}>Void</Button>}
              </div>
              {r.applied.length > 0 && (
                <p className="text-muted">On {r.applied.map((a, i) => (
                  <span key={i}>{i > 0 && ", "}<Link href={`/money/invoices/${a.invoice_id}`} className="font-mono text-info hover:underline">{a.number}</Link> {formatInr(a.amount_inr + a.tds_inr, true)} <span className="text-subtle">({METHOD[a.method] ?? a.method})</span></span>
                ))}</p>
              )}
              {r.status === "void" && r.void_reason && <p className="text-subtle">Void: {r.void_reason}</p>}
              {r.status === "active" && r.unapplied_inr > 0 && open.length > 0 && (
                <label className="flex items-center gap-2 text-muted">Apply to
                  <select className="h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px] text-fg" defaultValue="" disabled={busy === r.id}
                    onChange={(e) => apply(r.id, e.target.value)}>
                    <option value="" disabled>an open invoice…</option>
                    {open.map((i) => <option key={i.id} value={i.id}>{i.number} · {formatInr(i.outstanding_inr, true)}</option>)}
                  </select>
                  {busy === r.id && <LoaderCircle className="size-3.5 animate-spin" />}
                </label>
              )}
            </li>
          );
        })}
      </ul>
      <ConfirmDialog open={voiding !== null} onClose={() => setVoiding(null)} title="Void this receipt?" confirmLabel="Void receipt" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. entered against the wrong partner" }}
        onConfirm={async (reason) => { const r = await voidReceipt(voiding!, reason); if (!r.ok) return r.error; toast.success("Receipt voided"); router.refresh(); }}>
        <p className="text-[13px] text-muted">Its amounts come off the invoices, which reopen. The receipt stays in the list as void.</p>
      </ConfirmDialog>
    </>
  );
}
