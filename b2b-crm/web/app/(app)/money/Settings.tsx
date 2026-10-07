"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { CircleCheck, CircleDashed, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Card";
import { Label, Modal, field } from "@/components/ui/Modal";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { GST_STATES, stateOfGstin, type MoneySettings } from "@/lib/money";
import type { PartnerListItem } from "@/lib/partners";
import { saveBilling, saveMoneySettings, type BillingForm } from "./actions";

const pct = (v: number | null | undefined) => (v === null || v === undefined ? "" : String(Math.round(v * 10000) / 100));
const area = "min-h-16 w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

export function SettingsForm({ s }: { s: MoneySettings }) {
  const router = useRouter();
  const [f, setF] = useState({
    gst_pct: pct(s.gst_rate), sac_code: s.sac_code ?? "", tds_pct: pct(s.tds_rate), refund_window_days: String(s.refund_window_days ?? 30),
    invoice_prefix: s.invoice_prefix ?? "EDW", tier_min_leads: String(s.tier_min_leads ?? 20), close_day: String(s.close_day ?? 7),
    auto_close: s.auto_close !== false, confirmed_by_ca: Boolean(s.confirmed_by_ca),
    eduwit: { legal_name: s.eduwit?.legal_name ?? "", gstin: s.eduwit?.gstin ?? "", address: s.eduwit?.address ?? "", state_code: s.eduwit?.state_code ?? "", bank: s.eduwit?.bank ?? "" },
    reason: "",
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const ed = (k: keyof typeof f.eduwit, v: string) => setF({ ...f, eduwit: { ...f.eduwit, [k]: v } });
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPending(true); setError(null);
    try {
      const r = await saveMoneySettings(f);
      if (!r.ok) { setError(r.error); return; }
      toast.success("Money settings saved"); setF({ ...f, reason: "" }); router.refresh();
    } finally { setPending(false); }
  };
  const stateHint = f.eduwit.state_code ? GST_STATES[f.eduwit.state_code] : stateOfGstin(f.eduwit.gstin) ? `${GST_STATES[stateOfGstin(f.eduwit.gstin)!] ?? ""} (from the GSTIN)` : undefined;
  return (
    <form onSubmit={submit} className="space-y-5 px-5 py-4" noValidate>
      <fieldset className="space-y-3">
        <legend className="mb-1 text-[12px] font-semibold uppercase tracking-wider text-subtle">Tax</legend>
        <div className="grid gap-3 sm:grid-cols-3">
          <Label text="GST rate (%)"><input className={field} inputMode="decimal" value={f.gst_pct} onChange={(x) => setF({ ...f, gst_pct: x.target.value })} /></Label>
          <Label text="SAC code" hint="Ask the CA, e.g. 998599"><input className={field} inputMode="numeric" value={f.sac_code} onChange={(x) => setF({ ...f, sac_code: x.target.value.replace(/\D/g, "") })} /></Label>
          <Label text="Usual TDS (%)" hint="Shown as a guide only"><input className={field} inputMode="decimal" value={f.tds_pct} onChange={(x) => setF({ ...f, tds_pct: x.target.value })} /></Label>
        </div>
        <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" className="accent-[var(--primary)]" checked={f.confirmed_by_ca} onChange={(x) => setF({ ...f, confirmed_by_ca: x.target.checked })} />
          Eduwit&apos;s CA has confirmed the GST rate, SAC code, TDS and refund window</label>
      </fieldset>
      <fieldset className="space-y-3">
        <legend className="mb-1 text-[12px] font-semibold uppercase tracking-wider text-subtle">Eduwit on the invoice</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          <Label text="Legal name"><input className={field} value={f.eduwit.legal_name} onChange={(x) => ed("legal_name", x.target.value)} /></Label>
          <Label text="GSTIN"><input className={cn(field, "font-mono uppercase")} maxLength={15} value={f.eduwit.gstin} onChange={(x) => ed("gstin", x.target.value.toUpperCase())} /></Label>
          <Label text="State code" hint={stateHint}><input className={field} inputMode="numeric" maxLength={2} placeholder="07" value={f.eduwit.state_code} onChange={(x) => ed("state_code", x.target.value.replace(/\D/g, ""))} /></Label>
          <Label text="Invoice prefix" hint={`Numbers look like ${f.invoice_prefix || "EDW"}/2026-27/0001`}><input className={cn(field, "font-mono uppercase")} maxLength={10} value={f.invoice_prefix} onChange={(x) => setF({ ...f, invoice_prefix: x.target.value.toUpperCase() })} /></Label>
        </div>
        <Label text="Registered address"><textarea className={area} value={f.eduwit.address} onChange={(x) => ed("address", x.target.value)} /></Label>
        <Label text="Bank details for payment" hint="Account name, number, IFSC; printed on every invoice"><textarea className={area} value={f.eduwit.bank} onChange={(x) => ed("bank", x.target.value)} /></Label>
      </fieldset>
      <fieldset className="space-y-3">
        <legend className="mb-1 text-[12px] font-semibold uppercase tracking-wider text-subtle">Rules</legend>
        <div className="grid gap-3 sm:grid-cols-3">
          <Label text="Refund window (days)" hint="From the enrolment date"><input className={field} inputMode="numeric" value={f.refund_window_days} onChange={(x) => setF({ ...f, refund_window_days: x.target.value.replace(/\D/g, "") })} /></Label>
          <Label text="Tier: minimum leads" hint="Below this, last month's settled tier is used"><input className={field} inputMode="numeric" value={f.tier_min_leads} onChange={(x) => setF({ ...f, tier_min_leads: x.target.value.replace(/\D/g, "") })} /></Label>
          <Label text="Close last month on day" hint="1 to 28"><input className={field} inputMode="numeric" value={f.close_day} onChange={(x) => setF({ ...f, close_day: x.target.value.replace(/\D/g, "") })} /></Label>
        </div>
        <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" className="accent-[var(--primary)]" checked={f.auto_close} onChange={(x) => setF({ ...f, auto_close: x.target.checked })} />
          Close last month automatically on that day (drafts only; nothing is sent)</label>
      </fieldset>
      <Label text="Reason for this change"><input className={field} value={f.reason} maxLength={300} placeholder="e.g. details confirmed by the CA on 7 Oct" onChange={(x) => setF({ ...f, reason: x.target.value })} /></Label>
      {error && <Notice tone="error">{error}</Notice>}
      <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save settings</Button>
    </form>
  );
}

export function BillingTable({ partners }: { partners: PartnerListItem[] }) {
  const router = useRouter();
  const [edit, setEdit] = useState<PartnerListItem | null>(null);
  const [f, setF] = useState<BillingForm>({ legal_name: "", gstin: "", billing_address: "", billing_state_code: "", billing_email: "", payment_terms_days: "30" });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const open = (p: PartnerListItem) => {
    setEdit(p); setError(null);
    setF({ legal_name: p.legal_name ?? "", gstin: p.gstin ?? "", billing_address: p.billing_address ?? "", billing_state_code: p.billing_state_code ?? "",
           billing_email: p.billing_email ?? "", payment_terms_days: String(p.payment_terms_days ?? 30) });
  };
  const submit = async () => {
    setPending(true); setError(null);
    try {
      const r = await saveBilling(edit!.id, f);
      if (!r.ok) { setError(r.error); return; }
      toast.success("Billing details saved"); setEdit(null); router.refresh();
    } finally { setPending(false); }
  };
  const g = String(f.gstin ?? "");
  return (
    <>
      <ul className="divide-y divide-border">
        {partners.map((p) => {
          const ready = Boolean(p.legal_name && p.billing_address && (p.billing_state_code || stateOfGstin(p.gstin)));
          return (
            <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[12.5px]">
              {ready ? <CircleCheck className="size-4 text-success" /> : <CircleDashed className="size-4 text-subtle" />}
              <span className="font-medium text-fg">{p.display_name ?? p.name}</span>
              {p.legal_name && <span className="text-muted">{p.legal_name}</span>}
              {p.gstin ? <span className="font-mono text-subtle">{p.gstin}</span> : <Badge>no GSTIN</Badge>}
              <span className="text-subtle">{p.payment_terms_days ?? 30} days</span>
              <Button size="sm" variant="ghost" className="ml-auto" onClick={() => open(p)}>Edit</Button>
            </li>
          );
        })}
      </ul>
      <Modal open={Boolean(edit)} onClose={() => setEdit(null)} title={`Billing · ${edit?.display_name ?? edit?.name ?? ""}`} error={error} pending={pending} onSubmit={submit}>
        <div className="grid gap-3 sm:grid-cols-2">
          <Label text="Legal name"><input className={field} value={f.legal_name} onChange={(x) => setF({ ...f, legal_name: x.target.value })} /></Label>
          <Label text="GSTIN" hint={stateOfGstin(g) ? GST_STATES[stateOfGstin(g)!] : undefined}>
            <input className={cn(field, "font-mono uppercase")} maxLength={15} value={g} onChange={(x) => setF({ ...f, gstin: x.target.value.toUpperCase() })} /></Label>
          <Label text="State code" hint="Only if there is no GSTIN"><input className={field} inputMode="numeric" maxLength={2} value={f.billing_state_code} onChange={(x) => setF({ ...f, billing_state_code: x.target.value.replace(/\D/g, "") })} /></Label>
          <Label text="Payment terms (days)"><input className={field} inputMode="numeric" value={String(f.payment_terms_days)} onChange={(x) => setF({ ...f, payment_terms_days: x.target.value.replace(/\D/g, "") })} /></Label>
        </div>
        <Label text="Billing address"><textarea className={area} value={f.billing_address} onChange={(x) => setF({ ...f, billing_address: x.target.value })} /></Label>
        <Label text="Accounts email" hint="Shown on the invoice; nothing is emailed from here"><input className={field} type="email" value={f.billing_email} onChange={(x) => setF({ ...f, billing_email: x.target.value })} /></Label>
      </Modal>
    </>
  );
}
