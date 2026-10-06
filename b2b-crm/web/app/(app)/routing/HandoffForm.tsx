"use client";
import { useEffect } from "react";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { useFormAction } from "@/components/ui/useFormAction";
import type { EngineSettings } from "@/lib/routing-data";
import { saveHandoffSettings, type FormState } from "./actions";

const field = "w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function ListField({ name, label, hint, value, error, rows = 1 }: { name: string; label: string; hint: string; value: string[] | undefined; error?: string; rows?: number }) {
  return (
    <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] sm:items-start">
      <div>
        <label htmlFor={`h-${name}`} className="text-[13px] font-medium text-fg">{label}</label>
        <p className="text-[12px] text-muted">{hint}</p>
      </div>
      <div>
        <textarea id={`h-${name}`} name={name} rows={rows} defaultValue={(value ?? []).join(rows > 1 ? "\n" : ", ")} aria-invalid={Boolean(error)}
          className={field} spellCheck={false} />
        {error && <p className="mt-1 text-xs text-danger">{error}</p>}
      </div>
    </div>
  );
}

/** Hand-off rules (Addenda 1 and 2): which leads count as paid, which come from the B2C CRM, which numbers are junk. */
export function HandoffForm({ v, version }: { v: EngineSettings; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveHandoffSettings, undefined);
  const e = state?.errors ?? {};
  const r = v.paid_rule ?? {};
  useEffect(() => { if (state?.ok) toast.success("Hand-off rules saved"); }, [state?.ok]);

  return (
    <form onSubmit={onSubmit} noValidate className="px-5 py-2">
      <div className="divide-y divide-border">
        <p className="py-3 text-[12.5px] text-muted">
          Paid-campaign leads go to B2C sales and never to partners automatically. A lead counts as paid when any of the lists below matches
          (comma-separated). Junk and programme-mismatch leads are checked first and are not passed at all.
        </p>
        <ListField name="sources" label="Paid lead sources" hint="lead_source values from paid lead forms (Meta Lead Ads, Google Ads lead forms)." value={r.sources} error={e.sources} />
        <ListField name="click_ids" label="Paid click IDs" hint="A first touch carrying any of these click IDs is paid." value={r.click_ids} error={e.click_ids} />
        <ListField name="utm_mediums" label="Paid utm_medium values" hint="Matched exactly, ignoring case." value={r.utm_mediums} error={e.utm_mediums} />
        <ListField name="include_campaigns" label="Also paid: campaigns" hint="Campaign names or IDs (contains) that count as paid even without the signals above." value={r.include_campaigns} error={e.include_campaigns} />
        <ListField name="exclude_campaigns" label="Never paid: campaigns" hint="Campaign names or IDs (contains) that are never treated as paid; checked first." value={r.exclude_campaigns} error={e.exclude_campaigns} />
        <ListField name="b2c_sources" label="B2C-created sources" hint="Leads created by the B2C CRM go straight back to B2C sales." value={v.b2c_sources} error={e.b2c_sources} />
        <ListField name="blocked_phones" label="Blocked phone numbers" hint="One per line. Leads from these numbers are junk and not passed." value={v.blocked_phones} error={e.blocked_phones} rows={3} />
        <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] sm:items-center">
          <div>
            <p className="text-[13px] font-medium text-fg">Send a &quot;disqualified&quot; signal for junk</p>
            <p className="text-[12px] text-muted">To Meta and Google, once conversions (CAPI) are built. Off by default.</p>
          </div>
          <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name="junk_capi_signal" defaultChecked={v.junk_capi_signal ?? false} className="size-4 accent-[var(--primary)]" /> On</label>
        </div>
        <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] sm:items-center">
          <div>
            <label htmlFor="h-reason" className="text-[13px] font-medium text-fg">Reason for this change</label>
            <p className="text-[12px] text-muted">Saved as version {version + 1} of the engine settings, with your reason.</p>
          </div>
          <div>
            <input id="h-reason" name="reason" maxLength={300} placeholder="e.g. add the Google lead form source" aria-invalid={Boolean(e.reason)} className={`${field} h-9 py-0`} />
            {e.reason && <p className="mt-1 text-xs text-danger">{e.reason}</p>}
          </div>
        </div>
      </div>
      <div className="flex items-center justify-end gap-3 border-t border-border py-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save hand-off rules</Button>
      </div>
    </form>
  );
}
