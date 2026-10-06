"use client";
import { useState, useTransition } from "react";
import { BadgeIndianRupee, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { formatDateTime } from "@/lib/format";
import { inr } from "@/lib/programmes";
import type { Rate, RoutingOverview } from "@/lib/routing-data";
import { confirmFileRates, endRate, saveRate, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const date = (d: string | null) => (d ? formatDateTime(`${d}T00:00:00+05:30`).replace(/,.*$/, "") : "open");

/** Commission rates (B5.3): confirm what partners' files state, or set a partner-wide rate. Rates are versioned, never edited. */
export function RatesPanel({ rates, partners }: { rates: Rate[]; partners: RoutingOverview["partners"] }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveRate, undefined);
  const [busy, start] = useTransition();
  const e = state?.errors ?? {};
  const live = rates.filter((r) => r.valid_to === null || r.valid_to >= new Date().toISOString().slice(0, 10));
  const proposed = partners.filter((p) => p.proposed > 0);

  const confirm = (id: number, name: string) => start(async () => {
    const r = await confirmFileRates(id);
    if ("error" in r) { toast.error(r.error); return; }
    toast.success(`${name}: ${r.created} rates confirmed${r.unchanged ? `, ${r.unchanged} unchanged` : ""}${r.tiers_skipped ? `, ${r.tiers_skipped} tier references to set by hand` : ""}`);
  });

  return (
    <div className="divide-y divide-border">
      {proposed.length > 0 && (
        <section className="space-y-2 px-5 py-4">
          <h3 className="text-[13px] font-semibold text-fg">Commission stated in partners&apos; files, waiting for you</h3>
          <p className="text-[12.5px] text-muted">A file&apos;s commission column is only a proposal. Routing uses it once you confirm it here.</p>
          <ul className="flex flex-wrap gap-2">
            {proposed.map((p) => (
              <li key={p.id}>
                <Button size="sm" variant="secondary" disabled={busy} onClick={() => confirm(p.id, p.name)}>
                  {busy && <LoaderCircle className="size-3.5 animate-spin" />} Confirm {p.proposed} for {p.name}
                </Button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="px-5 py-4">
        <h3 className="mb-3 text-[13px] font-semibold text-fg">Add a partner-wide rate</h3>
        <form onSubmit={onSubmit} noValidate className="grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-[1.4fr_0.8fr_0.8fr_1fr_1fr_auto]">
          <label className="space-y-1"><span className="text-[12px] text-muted">Partner</span>
            <select name="partner_id" className={field} aria-invalid={Boolean(e.partner_id)} defaultValue="">
              <option value="" disabled>Choose…</option>
              {partners.filter((p) => p.status !== "closed").map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label className="space-y-1"><span className="text-[12px] text-muted">Type</span>
            <select name="rate_type" className={field} defaultValue="percent"><option value="percent">% of fee</option><option value="fixed">Fixed ₹</option></select>
          </label>
          <label className="space-y-1"><span className="text-[12px] text-muted">Value</span>
            <input name="value" inputMode="decimal" className={field} aria-invalid={Boolean(e.value)} placeholder="20" /></label>
          <label className="space-y-1"><span className="text-[12px] text-muted">Percent of</span>
            <select name="fee_base" className={field} defaultValue="first_year"><option value="first_year">First-year fee</option><option value="total">Total fee</option></select>
          </label>
          <label className="space-y-1"><span className="text-[12px] text-muted">From</span>
            <input name="valid_from" type="date" className={field} aria-invalid={Boolean(e.valid_from)} /></label>
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Add rate</Button>
          <label className="flex items-center gap-2 text-[12.5px] text-muted sm:col-span-2"><input type="checkbox" name="gst_inclusive" className="accent-[var(--primary)]" /> The rate includes 18% GST</label>
          <input name="note" placeholder="Note (optional), e.g. per agreement of 1 Oct" maxLength={300} className={cn(field, "sm:col-span-2 lg:col-span-4")} />
        </form>
        {(state?.error || Object.keys(e).length > 0) && <p role="alert" className="mt-2 text-[13px] text-danger">{Object.values(e)[0] ?? state?.error}</p>}
        <p className="mt-2 text-[12px] text-subtle">The most specific rate in force wins: partner + programme, then partner. A new rate ends the previous one the day before it starts.</p>
      </section>

      {live.length === 0 ? (
        <EmptyState icon={BadgeIndianRupee} title="No commission rates yet">Without a rate, a partner still receives leads but ranks below partners with one, and its commission shows as unknown.</EmptyState>
      ) : (
        <div className="relative overflow-x-auto">{/* relative keeps the sr-only header inside the scroll box on phones */}
          <table className="w-full min-w-[760px] text-left text-[13px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2.5 font-medium">Partner</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Applies to</th>
                <th scope="col" className="px-3 py-2.5 text-right font-medium">Rate</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Valid</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Source</th>
                <th scope="col" className="px-5 py-2.5"><span className="sr-only">Action</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {live.map((r) => (
                <tr key={r.id} className={cn(r.valid_to && "text-subtle")}>
                  <td className="px-5 py-2.5 font-medium text-fg">{r.partner_name}</td>
                  <td className="max-w-[280px] truncate px-3 py-2.5 text-muted">{r.programme ? `${r.programme.university_short || r.programme.university} · ${r.programme.course} · ${r.programme.specialization}` : "Every programme"}</td>
                  <td className="px-3 py-2.5 text-right text-fg">
                    {r.rate_type === "percent"
                      ? <><span className="tabular">{r.value}%</span> <span className="text-muted">of {r.fee_base === "total" ? "total" : "first-year"} fee</span></>
                      : <span className="tabular">{inr(r.value)}</span>}
                    {r.gst_inclusive && <span className="block text-[11px] text-subtle">incl. GST</span>}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted">{date(r.valid_from)} → {date(r.valid_to)}</td>
                  <td className="px-3 py-2.5"><Badge>{r.source === "file" ? "Partner file" : "Manual"}</Badge></td>
                  <td className="px-5 py-2.5 text-right">
                    {!r.valid_to && <Button size="sm" variant="ghost" onClick={async () => { const err = await endRate(r.id); if (err) toast.error(err); else toast.success("Rate ended"); }}>End</Button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
