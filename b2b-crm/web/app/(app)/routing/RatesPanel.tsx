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

type University = { id: number; name: string; short_name: string | null };

/** Commission rates (B5.3): per programme from the partner's sheet, per university at a partner, or partner-wide. Versioned, never edited. */
export function RatesPanel({ rates, partners, universities }: { rates: Rate[]; partners: RoutingOverview["partners"]; universities: University[] }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveRate, undefined);
  const [busy, start] = useTransition();
  const [type, setType] = useState("percent");
  const [scope, setScope] = useState<"partner" | "partner_university">("partner");
  const uniName = (id: number | null) => { const u = universities.find((x) => x.id === id); return u ? (u.short_name || u.name) : `University #${id}`; };
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
          <p className="text-[12.5px] text-muted">Publishing a reviewed programme sheet confirms its commission column as programme rates. These were published before that, or changed since: confirm them here.</p>
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
        <h3 className="mb-1 text-[13px] font-semibold text-fg">Add a rate</h3>
        <p className="mb-3 text-[12.5px] text-muted">Commission is set at three levels. <span className="text-fg">Programme</span>: the commission % column of the partner&apos;s programme sheet (published on the partner&apos;s Programmes tab).
          <span className="text-fg"> University</span>: one rate for every programme of a university at this partner. <span className="text-fg">Partner</span>: everything else the partner offers.</p>
        <form onSubmit={onSubmit} noValidate className="grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-[1.2fr_1fr_1.2fr_0.8fr_0.8fr_1fr_1fr_auto]">
          <label className="space-y-1"><span className="text-[12px] text-muted">Partner</span>
            <select name="partner_id" className={field} aria-invalid={Boolean(e.partner_id)} defaultValue="">
              <option value="" disabled>Choose…</option>
              {partners.filter((p) => p.status !== "closed").map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label className="space-y-1"><span className="text-[12px] text-muted">Level</span>
            <select name="scope" className={field} value={scope} onChange={(x) => setScope(x.target.value as typeof scope)}>
              <option value="partner">Partner-wide</option><option value="partner_university">One university</option>
            </select>
          </label>
          {scope === "partner_university" ? (
            <label className="space-y-1"><span className="text-[12px] text-muted">University</span>
              <select name="university_id" className={field} aria-invalid={Boolean(e.university_id)} defaultValue="">
                <option value="" disabled>Choose…</option>
                {universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
              </select>
            </label>
          ) : <span className="hidden lg:block" aria-hidden />}
          <label className="space-y-1"><span className="text-[12px] text-muted">Type</span>
            <select name="rate_type" className={field} value={type} onChange={(x) => setType(x.target.value)}>
              <option value="percent">% of fee</option><option value="fixed">Fixed ₹</option><option value="tiered">Tiered %</option>
            </select>
          </label>
          {type === "tiered" ? (
            <label className="space-y-1"><span className="text-[12px] text-muted">Tiers (conversion: rate)</span>
              <input name="tiers" className={field} aria-invalid={Boolean(e.tiers)} placeholder="0: 22.42, 7: 20.42, 9: 18.42" /></label>
          ) : (
            <label className="space-y-1"><span className="text-[12px] text-muted">Value</span>
              <input name="value" inputMode="decimal" className={field} aria-invalid={Boolean(e.value)} placeholder="20" /></label>
          )}
          <label className="space-y-1"><span className="text-[12px] text-muted">Percent of</span>
            <select name="fee_base" className={field} defaultValue="first_year"><option value="first_year">First-year fee</option><option value="total">Total fee</option></select>
          </label>
          <label className="space-y-1"><span className="text-[12px] text-muted">From</span>
            <input name="valid_from" type="date" className={field} aria-invalid={Boolean(e.valid_from)} /></label>
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Add rate</Button>
          <label className="flex items-center gap-2 text-[12.5px] text-muted sm:col-span-2"><input type="checkbox" name="gst_inclusive" className="accent-[var(--primary)]" /> The rate includes 18% GST</label>
          <input name="note" placeholder="Note (optional), e.g. per agreement of 1 Oct" maxLength={300} className={cn(field, "sm:col-span-2 lg:col-span-6")} />
        </form>
        {(state?.error || Object.keys(e).length > 0) && <p role="alert" className="mt-2 text-[13px] text-danger">{Object.values(e)[0] ?? state?.error}</p>}
        <p className="mt-2 text-[12px] text-subtle">The most specific rate in force wins: programme (from the partner&apos;s sheet), then university, then partner-wide. A new rate ends the previous one at the same level the day before it starts.
          {type === "tiered" && <> Tiered: the rate depends on the partner&apos;s lead-to-enrolment conversion in the month (enrolments ÷ leads accepted); &quot;7: 20.42&quot; means 20.42% from 7% conversion. Provisional until the month is closed in Commission &amp; Finance.</>}</p>
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
                  <td className="max-w-[280px] truncate px-3 py-2.5 text-muted">
                    {r.programme ? `${r.programme.university_short || r.programme.university} · ${r.programme.course} · ${r.programme.specialization}`
                      : r.scope === "partner_university" ? <><span className="text-fg">{uniName(r.university_id)}</span> · every programme</> : "Every programme"}
                  </td>
                  <td className="px-3 py-2.5 text-right text-fg">
                    {r.rate_type === "percent"
                      ? <><span className="tabular">{r.value}%</span> <span className="text-muted">of {r.fee_base === "total" ? "total" : "first-year"} fee</span></>
                      : r.rate_type === "tiered"
                        ? <><span className="tabular">{r.tiers?.map((t) => `${t.pct}%`).join(" / ") ?? "Tiered"}</span> <span className="text-muted">by conversion</span>
                            {r.tiers && <span className="block text-[11px] text-subtle">{r.tiers.map((t) => `from ${t.from_pct}%`).join(" · ")}</span>}</>
                        : <span className="tabular">{inr(r.value)}</span>}
                    {r.gst_inclusive && <span className="block text-[11px] text-subtle">incl. GST</span>}
                  </td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted">{date(r.valid_from)} → {date(r.valid_to)}</td>
                  <td className="px-3 py-2.5"><Badge>{r.source === "file" ? "Programme sheet" : "Manual"}</Badge>
                    <span className="mt-0.5 block text-[11px] text-subtle">{r.scope === "partner_programme" ? "Programme" : r.scope === "partner_university" ? "University" : "Partner"} level</span></td>
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
