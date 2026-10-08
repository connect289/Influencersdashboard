"use client";
import { useEffect, useState } from "react";
import { Info, LoaderCircle, Plus, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import type { LostDelays } from "@/lib/routing-data";
import { saveLostDelays, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

type RowState = { id: number; key: string; days: string };

/** Lost reasons partners commonly report, offered as a datalist so the spelling matches what the sync writes. */
const COMMON_REASONS = ["not interested", "not reachable", "joined elsewhere", "fee too high", "wrong number", "wants a different course", "postponed"];

/**
 * The `lost_nurture_delays` setting (PART 6.1, D36): when a partner marks a lead lost and the 7-day grace ends, the lead
 * moves to B2C nurture, unassigned and partner-barred; the lost reason sets how many days pass before B2C's first nurture
 * message (3 to 90). Saved whole through b2b.lost_delays_save with a reason. The per-reason values await Vikas: until he
 * confirms them, only the default is set and every lost reason uses it.
 */
export function LostDelaysForm({ v, version }: { v: LostDelays; version: number | null }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveLostDelays, undefined);
  const e = state?.errors ?? {};
  const [rows, setRows] = useState<RowState[]>(() => Object.entries(v.reasons ?? {}).map(([key, days], i) => ({ id: i + 1, key, days: String(days) })));
  const [nextId, setNextId] = useState(rows.length + 1);
  useEffect(() => { if (state?.ok) toast.success("Lost delays saved"); }, [state?.ok]);

  const addRow = () => { setRows((r) => [...r, { id: nextId, key: "", days: "" }]); setNextId((n) => n + 1); };
  const removeRow = (id: number) => setRows((r) => r.filter((x) => x.id !== id));
  const rowError = (i: number) => e[`row_${i}`];

  return (
    <form onSubmit={onSubmit} noValidate className="px-5 py-2">
      <div className="flex gap-2.5 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2.5 text-[12.5px] leading-5 text-warning">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        <p>
          The per-reason values await Vikas (D36). Until he confirms them, only the default is set and every lost reason uses it. The hand-off to the B2C CRM
          carries the days chosen (nurture_first_message_after_days) and the date they end (nurture_first_message_at).
        </p>
      </div>

      <div className="divide-y divide-border">
        <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_240px] sm:items-start">
          <div>
            <label htmlFor="ld-default" className="text-[13px] font-medium text-fg">Default delay</label>
            <p className="text-[12px] leading-5 text-muted">For every lost reason without its own row below, and when the partner gave no reason. 3 to 90 days; the seeded value is 14.</p>
          </div>
          <div>
            <div className="flex items-center gap-2">
              <input id="ld-default" name="default" inputMode="numeric" defaultValue={String(v.default ?? 14)} className={cn(field, "tabular w-28")} aria-invalid={Boolean(e.default)} />
              <span className="text-[12px] text-muted">days</span>
            </div>
            {e.default && <p className="mt-1 text-xs text-danger">{e.default}</p>}
          </div>
        </div>

        <div className="py-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-[13px] font-medium text-fg">Delay by lost reason</p>
              <p className="text-[12px] leading-5 text-muted">
                The reason as the partner reports it (matched exactly, case-insensitive) and the days before B2C&apos;s first nurture message. Up to 50 reasons, 3 to 90 days each.
                An empty row is ignored.
              </p>
            </div>
            <Button type="button" size="sm" variant="secondary" onClick={addRow} disabled={rows.length >= 50}><Plus className="size-3.5" /> Add a reason</Button>
          </div>
          {rows.length === 0 ? (
            <p className="mt-3 rounded-lg border border-dashed border-border px-3 py-3 text-center text-[12.5px] text-subtle">No per-reason delay yet: every lost lead waits the default.</p>
          ) : (
            <ol className="mt-3 space-y-2">
              {rows.map((r, i) => {
                const err = rowError(i);
                return (
                  <li key={r.id} className="grid grid-cols-[minmax(0,1fr)_7rem_auto] items-start gap-2">
                    <div>
                      <input name="lost_reason" list="ld-common-reasons" defaultValue={r.key} maxLength={60} placeholder="e.g. not interested" className={field}
                        aria-label={`Lost reason ${i + 1}`} aria-invalid={Boolean(err)} />
                      {err && <p className="mt-1 text-xs text-danger">{err}</p>}
                    </div>
                    <div className="flex items-center gap-2">
                      <input name="days" inputMode="numeric" defaultValue={r.days} placeholder="days" className={cn(field, "tabular")} aria-label={`Days for lost reason ${i + 1}`} aria-invalid={Boolean(err)} />
                      <span className="text-[12px] text-muted">days</span>
                    </div>
                    <Button type="button" size="icon" variant="ghost" onClick={() => removeRow(r.id)} aria-label={`Remove lost reason ${i + 1}`} className="h-9 w-9"><X className="size-4" /></Button>
                  </li>
                );
              })}
            </ol>
          )}
          <datalist id="ld-common-reasons">{COMMON_REASONS.map((r) => <option key={r} value={r} />)}</datalist>
          {e.reasons && <p className="mt-2 text-xs text-danger">{e.reasons}</p>}
        </div>

        <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)] sm:items-start">
          <div>
            <label htmlFor="ld-reason" className="text-[13px] font-medium text-fg">Reason for this change</label>
            <p className="text-[12px] leading-5 text-muted">Saved as version {(version ?? 0) + 1} of the lost delays, with your reason.</p>
          </div>
          <div>
            <input id="ld-reason" name="reason" maxLength={300} placeholder="e.g. Vikas confirmed the delays on 10 Oct" className={field} aria-invalid={Boolean(e.reason)} />
            {e.reason && <p className="mt-1 text-xs text-danger">{e.reason}</p>}
          </div>
        </div>
      </div>
      <div className="flex items-center justify-end gap-3 border-t border-border py-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save lost delays</Button>
      </div>
    </form>
  );
}
