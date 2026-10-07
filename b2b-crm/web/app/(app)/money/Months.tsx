"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { CircleCheck, Download, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { field } from "@/components/ui/Modal";
import { toCsv } from "@/lib/intake";
import { monthLabel, type MoneyOverview } from "@/lib/money";
import { download } from "../intake/ui";
import { closeMonth, exportRows } from "./actions";

/** The last six months: closed ones, and a Close button for the rest (tiers settled, invoices drafted). */
export function CloseMonth({ months }: { months: MoneyOverview["months"] }) {
  const router = useRouter();
  const [period, setPeriod] = useState<string | null>(null);
  return (
    <>
      <ul className="divide-y divide-border">
        {months.map((m) => (
          <li key={m.period} className="flex items-center justify-between gap-3 px-5 py-2 text-[12.5px]">
            <span className="text-fg">{monthLabel(m.period)}</span>
            {m.closed
              ? <span className="flex items-center gap-1 text-success"><CircleCheck className="size-3.5" /> Closed{m.partners_settled > 0 && <span className="text-muted"> · {m.partners_settled} {m.partners_settled === 1 ? "partner" : "partners"} settled</span>}</span>
              : <Button size="sm" variant="secondary" onClick={() => setPeriod(m.period)}>Close month</Button>}
          </li>
        ))}
      </ul>
      <ConfirmDialog open={Boolean(period)} onClose={() => setPeriod(null)} title={`Close ${period ? monthLabel(period) : ""}?`} confirmLabel="Close month"
        onConfirm={async () => {
          const r = await closeMonth(period!);
          if (!r.ok) return r.error;
          toast.success(`${monthLabel(period!)} closed: ${r.data.partners_settled} partners settled, ${r.data.tier_adjustments} tier adjustments, ${r.data.drafts} draft invoices`);
          router.refresh();
        }}>
        <p className="text-[13px] text-muted">Tiered rates settle at the month&apos;s verified enrolments ÷ leads accepted; realised commission goes onto one draft invoice per partner.
          Nothing is sent: you approve each invoice. Enrolments verified later in this month&apos;s name use the settled tier and go on the next invoice.</p>
      </ConfirmDialog>
    </>
  );
}

const KINDS = [["invoices", "Invoices (sales register)"], ["receipts", "Receipts"], ["earnings", "Earning lines (realised)"]] as const;

export function ExportPanel() {
  const now = new Date(Date.now() + 5.5 * 3600e3);
  const fyStart = `${now.getUTCMonth() >= 3 ? now.getUTCFullYear() : now.getUTCFullYear() - 1}-04-01`;
  const [kind, setKind] = useState<(typeof KINDS)[number][0]>("invoices");
  const [from, setFrom] = useState(fyStart);
  const [to, setTo] = useState(now.toISOString().slice(0, 10));
  const [pending, setPending] = useState(false);
  const go = async () => {
    setPending(true);
    try {
      const r = await exportRows(kind, from, to);
      if (!r.ok) { toast.error(r.error); return; }
      if (r.data.length === 0) { toast.info("Nothing in those dates"); return; }
      download(`eduwit-${kind}-${from}-to-${to}.csv`, toCsv(r.data, Object.keys(r.data[0]!)));
    } finally { setPending(false); }
  };
  return (
    <div className="grid gap-3 px-5 py-4 sm:grid-cols-2">
      <label className="space-y-1 sm:col-span-2"><span className="text-[12px] text-muted">What</span>
        <select className={field} value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>{KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
      <label className="space-y-1"><span className="text-[12px] text-muted">From</span><input type="date" className={field} value={from} onChange={(e) => setFrom(e.target.value)} /></label>
      <label className="space-y-1"><span className="text-[12px] text-muted">To</span><input type="date" className={field} value={to} onChange={(e) => setTo(e.target.value)} /></label>
      <Button size="sm" variant="secondary" className="sm:col-span-2" onClick={go} disabled={pending}>
        {pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <Download className="size-3.5" />} Download CSV
      </Button>
    </div>
  );
}
