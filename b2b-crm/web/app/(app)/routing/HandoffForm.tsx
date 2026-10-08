"use client";
import { useEffect } from "react";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import type { EngineSettings } from "@/lib/routing-data";
import { saveHandoffSettings, type FormState } from "./actions";

const field = "w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const grid = "grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]";

function Section({ title, lead, children }: { title: string; lead?: string; children?: React.ReactNode }) {
  return (
    <section className="pt-5 first:pt-1">
      <h3 className="text-[11px] font-medium uppercase tracking-wider text-subtle">{title}</h3>
      {lead && <p className="mt-1 max-w-3xl text-[12.5px] leading-5 text-muted">{lead}</p>}
      {children && <div className="divide-y divide-border">{children}</div>}
    </section>
  );
}

function ListField({ name, label, hint, value, error, rows = 1, mono }: { name: string; label: string; hint: string; value: string[] | undefined; error?: string; rows?: number; mono?: boolean }) {
  return (
    <div className={cn(grid, "sm:items-start")}>
      <div>
        <label htmlFor={`h-${name}`} className="text-[13px] font-medium text-fg">{label}</label>
        <p className="text-[12px] leading-5 text-muted">{hint}</p>
      </div>
      <div>
        <textarea id={`h-${name}`} name={name} rows={rows} defaultValue={(value ?? []).join(rows > 1 ? "\n" : ", ")} aria-invalid={Boolean(error)}
          className={cn(field, mono && "font-mono text-[12.5px]")} spellCheck={false} />
        {error && <p className="mt-1 text-xs text-danger">{error}</p>}
      </div>
    </div>
  );
}

function Toggle({ name, label, hint, checked, error }: { name: string; label: string; hint: string; checked: boolean; error?: string }) {
  return (
    <div className={cn(grid, "sm:items-center")}>
      <div>
        <p className="text-[13px] font-medium text-fg">{label}</p>
        <p className="text-[12px] leading-5 text-muted">{hint}</p>
      </div>
      <div>
        <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name={name} defaultChecked={checked} className="size-4 accent-[var(--primary)]" /> On</label>
        {error && <p className="mt-1 text-xs text-danger">{error}</p>}
      </div>
    </div>
  );
}

function NumField({ name, label, hint, value, error }: { name: string; label: string; hint: string; value: number | undefined; error?: string }) {
  return (
    <div className={cn(grid, "sm:items-center")}>
      <div>
        <label htmlFor={`h-${name}`} className="text-[13px] font-medium text-fg">{label}</label>
        <p className="text-[12px] leading-5 text-muted">{hint}</p>
      </div>
      <div className="flex items-center gap-2">
        <input id={`h-${name}`} name={name} inputMode="numeric" defaultValue={String(value ?? 5)} aria-invalid={Boolean(error)} className={cn(field, "tabular h-9 w-28 py-0")} />
        <span className="text-[12px] text-muted">leads an hour</span>
        {error && <p className="text-xs text-danger">{error}</p>}
      </div>
    </div>
  );
}

/**
 * Hand-off rules (Addenda 1–3): which leads were created in the B2C CRM (R6), which numbers are blocked, the spam rules (R5)
 * and the junk CAPI signal. Saved through b2b.handoff_settings_save as a versioned change with a reason. The paid-campaign
 * rule is gone: paid is an attribution label and no longer changes routing (D38).
 */
export function HandoffForm({ v, version }: { v: EngineSettings; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveHandoffSettings, undefined);
  const e = state?.errors ?? {};
  const spam = v.spam ?? {};
  useEffect(() => { if (state?.ok) toast.success("Hand-off rules saved"); }, [state?.ok]);

  return (
    <form onSubmit={onSubmit} noValidate className="px-5 py-2">
      <Section title="Created in the B2C CRM (R6)"
        lead="Leads the B2C CRM created itself go straight back to B2C sales (reason b2c_created). They are checked right after R1–R4, before the not-passed checks, so a B2C-created lead is never 'not passed'.">
        <ListField name="b2c_sources" label="B2C-created sources" hint="lead_source values the B2C CRM writes (comma-separated, lower-cased on save)." value={v.b2c_sources} error={e.b2c_sources} />
      </Section>

      <Section title="Not passed (R5)"
        lead="Checked for every source, in this order: blocked numbers, invalid phones, spam, Witty's junk label, programme mismatch (no interest in the catalogue). A not-passed lead reaches no CRM until you pass it from the Leads list; it is then judged on its details.">
        <ListField name="blocked_phones" label="Blocked phone numbers" hint="One per line, 10 to 15 digits. Leads from these numbers are not passed (reason blocked_phone)." value={v.blocked_phones} error={e.blocked_phones} rows={3} mono />
        <Toggle name="spam_use_witty_blocks" label="Treat numbers Witty blocked as spam" hint="A phone currently on Witty's block list (w2_blocks) is spam: detail spam:witty_block." checked={spam.use_witty_blocks ?? true} error={e.spam_use_witty_blocks} />
        <ListField name="spam_disposable_email_domains" label="Disposable email domains" hint="One per line (or comma-separated). A lead whose email ends in one of these is spam: detail spam:disposable_email. Up to 500." value={spam.disposable_email_domains} error={e.spam_disposable_email_domains} rows={4} mono />
        <NumField name="spam_max_leads_per_ip_hour" label="Leads from one IP address in an hour" hint="More than this many non-test leads from the same IP address in the hour before a lead arrived make it spam (spam:ip_burst). 1 to 100." value={spam.max_leads_per_ip_hour} error={e.spam_max_leads_per_ip_hour} />
        <NumField name="spam_max_leads_per_fingerprint_hour" label="Leads from one device in an hour" hint="The same, by browser fingerprint (spam:fingerprint_burst). 1 to 100." value={spam.max_leads_per_fingerprint_hour} error={e.spam_max_leads_per_fingerprint_hour} />
        <Toggle name="junk_capi_signal" label='Send a "disqualified" signal for junk' hint="To Meta and Google through conversions (CAPI), so the ad platforms learn what junk looks like. Off by default." checked={v.junk_capi_signal ?? false} error={e.junk_capi_signal} />
      </Section>

      <Section title="Paid campaigns"
        lead="Paid Meta and Google leads are routed like every other lead: 'paid' is an attribution label on the lead and in the hand-off (D38), set by the Attribution settings, not a hand-off rule. A routing rule can still send paid leads to B2C if you want that." />

      <Section title="Reason for the audit log">
        <div className={cn(grid, "sm:items-center")}>
          <div>
            <label htmlFor="h-reason" className="text-[13px] font-medium text-fg">Reason for this change</label>
            <p className="text-[12px] leading-5 text-muted">Saved as version {version + 1} of the engine settings, with your reason.</p>
          </div>
          <div>
            <input id="h-reason" name="reason" maxLength={300} placeholder="e.g. add the B2C CRM's new web form source" aria-invalid={Boolean(e.reason)} className={cn(field, "h-9 py-0")} />
            {e.reason && <p className="mt-1 text-xs text-danger">{e.reason}</p>}
          </div>
        </div>
      </Section>
      <div className="flex items-center justify-end gap-3 border-t border-border py-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save hand-off rules</Button>
      </div>
    </form>
  );
}
