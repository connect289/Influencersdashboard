"use client";
import { startTransition, useActionState, useEffect, useState } from "react";
import { LoaderCircle } from "lucide-react";
import Link from "next/link";
import { toast } from "sonner";
import { Button, buttonClass } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { Input } from "@/components/ui/Field";
import {
  ADAPTER_LABEL, ADAPTERS, DAY_LABEL, DAYS, DEDUPE_LABEL, DEDUPE_MODES, DEFAULT_WORKING_HOURS, SLA_FIELDS, slugify, type Partner,
} from "@/lib/partners";
import { savePartner } from "./actions";
import { PartnerLogo } from "./PartnerLogo";

const control = "w-full rounded-lg border border-border bg-surface px-3 text-sm text-fg placeholder:text-subtle transition-colors hover:border-border-strong focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="grid gap-x-8 gap-y-4 border-t border-border py-6 first:border-t-0 first:pt-0 lg:grid-cols-[260px_minmax(0,1fr)]">
      <div>
        <h2 className="text-sm font-semibold text-fg">{title}</h2>
        {description && <p className="mt-1 text-[13px] leading-5 text-muted">{description}</p>}
      </div>
      <div className="space-y-4">{children}</div>
    </section>
  );
}

function F({ id, label, hint, error, children, className }: { id: string; label: string; hint?: string; error?: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("space-y-1.5", className)}>
      <label htmlFor={id} className="text-[13px] font-medium text-fg">{label}</label>
      {children}
      {error ? <p id={`${id}-error`} className="text-xs text-danger">{error}</p> : hint && <p className="text-xs text-muted">{hint}</p>}
    </div>
  );
}

const lines = (v: string[] | undefined) => (v ?? []).join(", ");

/** Create or edit a partner. Every value is validated again by b2b.partner_save. */
export function PartnerForm({ partner }: { partner?: Partner }) {
  const [state, action, pending] = useActionState(savePartner, undefined);
  const e = state?.errors ?? {};
  const isNew = !partner;
  const slugLocked = Boolean(partner && (partner.status !== "onboarding" || partner.live));

  const [name, setName] = useState(partner?.name ?? "");
  const [slug, setSlug] = useState(partner?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(!isNew);
  const [displayName, setDisplayName] = useState(partner?.display_name ?? "");
  const [logo, setLogo] = useState(partner?.logo_url ?? "");
  const [color, setColor] = useState(partner?.brand_color ?? "");
  const [dedupe, setDedupe] = useState(partner?.dedupe_mode ?? "async");
  const hours = { ...DEFAULT_WORKING_HOURS, ...(partner?.working_hours ?? {}) };
  const [open, setOpen] = useState<Record<string, boolean>>(Object.fromEntries(DAYS.map((d) => [d, Boolean(hours[d])])));

  useEffect(() => {
    if (state?.saved) toast.success("Partner saved");
  }, [state?.saved]);

  const inv = (k: string) => (e[k] ? { "aria-invalid": true, "aria-describedby": `${k}-error` } : {});
  const validColor = /^#[0-9a-f]{6}$/i.test(color);

  return (
    // Submitted by hand, not via the action prop: React resets a form after its action, which would wipe the
    // Admin's input whenever validation fails.
    <form
      noValidate
      onSubmit={(ev) => {
        ev.preventDefault();
        const data = new FormData(ev.currentTarget);
        startTransition(() => action(data));
      }}
    >
      <input type="hidden" name="id" value={partner?.id ?? ""} />

      <Section title="Identity" description="The display name, logo and colour are what students see in the WhatsApp message and email.">
        <div className="grid gap-4 sm:grid-cols-2">
          <F id="name" label="Company name" error={e.name}>
            <Input id="name" name="name" required maxLength={120} value={name} {...inv("name")}
              onChange={(ev) => { setName(ev.target.value); if (!slugTouched) setSlug(slugify(ev.target.value)); }} />
          </F>
          <F id="slug" label="Slug" error={e.slug} hint={slugLocked ? "Fixed: the partner's system uses it in its webhook address." : "Used in the partner's webhook address. Lowercase, digits, hyphens."}>
            <Input id="slug" name="slug" required maxLength={40} value={slug} readOnly={slugLocked} className={cn("font-mono", slugLocked && "bg-surface-2 text-muted")} {...inv("slug")}
              onChange={(ev) => { setSlug(ev.target.value); setSlugTouched(true); }} />
          </F>
          <F id="display_name" label="Display name" hint="Shown to students, e.g. the brand rather than the legal name." error={e.display_name}>
            <Input id="display_name" name="display_name" maxLength={120} value={displayName} onChange={(ev) => setDisplayName(ev.target.value)} {...inv("display_name")} />
          </F>
          <F id="brand_color" label="Brand colour" error={e.brand_color}>
            <div className="flex gap-2">
              <input type="color" aria-label="Pick brand colour" value={validColor ? color : "#0b2f5e"} onChange={(ev) => setColor(ev.target.value.toUpperCase())}
                className="h-10 w-12 shrink-0 cursor-pointer rounded-lg border border-border bg-surface p-1" />
              <Input id="brand_color" name="brand_color" maxLength={7} placeholder="#0B2F5E" value={color} className="font-mono" onChange={(ev) => setColor(ev.target.value)} {...inv("brand_color")} />
            </div>
          </F>
          <F id="logo_url" label="Logo URL" hint="An https link to a PNG or SVG on the partner's site." error={e.logo_url} className="sm:col-span-2">
            <Input id="logo_url" name="logo_url" type="url" inputMode="url" maxLength={500} placeholder="https://" value={logo} onChange={(ev) => setLogo(ev.target.value)} {...inv("logo_url")} />
          </F>
        </div>
        <div className="flex items-center gap-3 rounded-lg border border-dashed border-border px-4 py-3">
          <PartnerLogo partner={{ logo_url: /^https:\/\//.test(logo) ? logo : null, brand_color: validColor ? color : null, display_name: displayName, name: name || "New partner" }} />
          <p className="text-[13px] text-muted">Students will read: <span className="font-medium text-fg">“{displayName || name || "Partner"} will call you shortly.”</span></p>
        </div>
      </Section>

      <Section title="Connection" description="How leads reach the partner's CRM and how it reports duplicates. The API credential and signing secret are set in the Connection tab and stored in Vault, never here.">
        <div className="grid gap-4 sm:grid-cols-2">
          <F id="adapter_type" label="CRM type" error={e.adapter_type}>
            <select id="adapter_type" name="adapter_type" defaultValue={partner?.adapter_type ?? "leadsquared"} className={cn(control, "h-10")}>
              {ADAPTERS.map((a) => <option key={a} value={a}>{ADAPTER_LABEL[a]}</option>)}
            </select>
          </F>
          <F id="api_base_url" label="API base URL" error={e.api_base_url} hint="Production endpoint. Optional until the adapter is set up.">
            <Input id="api_base_url" name="api_base_url" type="url" inputMode="url" maxLength={500} placeholder="https://" defaultValue={partner?.api_base_url ?? ""} {...inv("api_base_url")} />
          </F>
          <F id="test_endpoint" label="Test endpoint" error={e.test_endpoint} hint="The partner's sandbox. Test leads only ever go here." className="sm:col-span-2">
            <Input id="test_endpoint" name="test_endpoint" type="url" inputMode="url" maxLength={500} placeholder="https://" defaultValue={partner?.test_endpoint ?? ""} {...inv("test_endpoint")} />
          </F>
        </div>
        <fieldset>
          <legend className="mb-2 text-[13px] font-medium text-fg">When does the partner report a duplicate?</legend>
          <div className="grid gap-2 sm:grid-cols-3">
            {DEDUPE_MODES.map((m) => (
              <label key={m} className={cn("cursor-pointer rounded-lg border p-3 transition-colors", dedupe === m ? "border-ring bg-amber/10" : "border-border hover:bg-surface-hover")}>
                <span className="flex items-center gap-2 text-[13px] font-medium text-fg">
                  <input type="radio" name="dedupe_mode" value={m} checked={dedupe === m} onChange={() => setDedupe(m)} className="accent-[var(--primary)]" />
                  {DEDUPE_LABEL[m].label}
                </span>
                <span className="mt-1 block text-[12px] leading-4 text-muted">{DEDUPE_LABEL[m].hint}</span>
              </label>
            ))}
          </div>
        </fieldset>
        <div className="grid gap-4 sm:grid-cols-2">
          <F id="hold_minutes" label="Hold window (minutes)" error={e.hold_minutes}
            hint={dedupe === "sync" ? "Not needed: duplicates are refused at once." : "The student is told who will call only after this window passes without a duplicate."}>
            <Input id="hold_minutes" name="hold_minutes" inputMode="numeric" disabled={dedupe === "sync"} defaultValue={partner?.hold_minutes ?? 30} {...inv("hold_minutes")} />
          </F>
          <F id="duplicate_window_hours" label="Duplicate claim window (hours)" error={e.duplicate_window_hours} hint="Later duplicate claims are logged as commission disputes.">
            <Input id="duplicate_window_hours" name="duplicate_window_hours" inputMode="numeric" defaultValue={partner?.duplicate_window_hours ?? 24} {...inv("duplicate_window_hours")} />
          </F>
        </div>
      </Section>

      <Section title="Capacity" description="Leave empty for no limit. Contractual minimums are routed first when behind schedule.">
        <div className="grid gap-4 sm:grid-cols-3">
          <F id="daily_cap" label="Daily cap" error={e.daily_cap}>
            <Input id="daily_cap" name="daily_cap" inputMode="numeric" defaultValue={partner?.daily_cap ?? ""} {...inv("daily_cap")} />
          </F>
          <F id="monthly_cap" label="Monthly cap" error={e.monthly_cap}>
            <Input id="monthly_cap" name="monthly_cap" inputMode="numeric" defaultValue={partner?.monthly_cap ?? ""} {...inv("monthly_cap")} />
          </F>
          <F id="contract_min_monthly" label="Contract minimum / month" error={e.contract_min_monthly}>
            <Input id="contract_min_monthly" name="contract_min_monthly" inputMode="numeric" defaultValue={partner?.contract_min_monthly ?? ""} {...inv("contract_min_monthly")} />
          </F>
        </div>
      </Section>

      <Section title="Working hours" description="India time. SLA clocks run only inside these hours and skip holidays.">
        <div className="divide-y divide-border rounded-lg border border-border">
          {DAYS.map((d) => {
            const h = hours[d];
            return (
              <div key={d} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2">
                <label className="flex w-32 items-center gap-2 text-[13px] text-fg">
                  <input type="checkbox" name={`wh_${d}_on`} checked={open[d]} onChange={(ev) => setOpen((o) => ({ ...o, [d]: ev.target.checked }))} className="size-4 accent-[var(--primary)]" />
                  {DAY_LABEL[d]}
                </label>
                {open[d] ? (
                  <div className="flex items-center gap-2">
                    <input type="time" name={`wh_${d}_open`} aria-label={`${DAY_LABEL[d]} opens`} defaultValue={h?.open ?? "10:00"} className={cn(control, "h-9 w-28")} aria-invalid={Boolean(e[`wh_${d}`])} />
                    <span className="text-subtle">to</span>
                    <input type="time" name={`wh_${d}_close`} aria-label={`${DAY_LABEL[d]} closes`} defaultValue={h?.close ?? "19:00"} className={cn(control, "h-9 w-28")} aria-invalid={Boolean(e[`wh_${d}`])} />
                  </div>
                ) : <span className="text-[13px] text-subtle">Closed</span>}
                {e[`wh_${d}`] && <span className="text-xs text-danger">{e[`wh_${d}`]}</span>}
              </div>
            );
          })}
        </div>
        <F id="holidays" label="Holidays" hint="One date per line or comma-separated, as YYYY-MM-DD." error={e.holidays}>
          <textarea id="holidays" name="holidays" rows={3} maxLength={4000} defaultValue={(partner?.holidays ?? []).join("\n")} className={cn(control, "py-2 font-mono text-[13px]")} {...inv("holidays")} />
        </F>
      </Section>

      <Section title="SLAs" description="Defaults from the partner agreement template; edit per partner. Breaches feed the scorecard and alerts.">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {SLA_FIELDS.map((f) => (
            <F key={f.key} id={`sla_${f.key}`} label={`${f.label} (${f.unit})`} error={e[`sla_${f.key}`]}>
              <Input id={`sla_${f.key}`} name={`sla_${f.key}`} inputMode="numeric" defaultValue={partner?.sla?.[f.key] ?? f.def} {...inv(`sla_${f.key}`)} />
            </F>
          ))}
        </div>
      </Section>

      <Section title="Lead criteria" description="What the partner agreed to accept. Leads that fail these never route to it.">
        <div className="grid gap-4 sm:grid-cols-2">
          <F id="states_include" label="Only these states" hint="Comma-separated. Empty means all of India.">
            <Input id="states_include" name="states_include" maxLength={2000} defaultValue={lines(partner?.lead_criteria?.states_include)} />
          </F>
          <F id="states_exclude" label="Never these states">
            <Input id="states_exclude" name="states_exclude" maxLength={2000} defaultValue={lines(partner?.lead_criteria?.states_exclude)} />
          </F>
          <F id="sources_exclude" label="Never leads from these sources" hint="Source codes, e.g. meta_lead_ad.">
            <Input id="sources_exclude" name="sources_exclude" maxLength={2000} defaultValue={lines(partner?.lead_criteria?.sources_exclude)} />
          </F>
          <F id="criteria_other" label="Other rules" hint="For example minimum qualification.">
            <Input id="criteria_other" name="criteria_other" maxLength={2000} defaultValue={partner?.lead_criteria?.other ?? ""} />
          </F>
        </div>
      </Section>

      <Section title="Student notification" description="After the partner accepts a lead, the student is told who will call (WhatsApp and email).">
        <label className="flex items-start gap-3">
          <input type="checkbox" name="notify_enabled" defaultChecked={partner?.notify_enabled ?? false} className="mt-0.5 size-4 accent-[var(--primary)]" />
          <span className="text-[13px] text-fg">
            Notify students for this partner
            <span className="block text-[12px] text-muted">Messages go out only when the WhatsApp or email live switch is also on.</span>
          </span>
        </label>
      </Section>

      <Section title="Notes" description="Private to Eduwit.">
        <textarea id="notes" name="notes" aria-label="Notes" rows={4} maxLength={4000} defaultValue={partner?.notes ?? ""} className={cn(control, "py-2 text-[13px]")} />
      </Section>

      <div className="sticky bottom-0 z-10 -mx-4 mt-2 flex items-center justify-end gap-2 border-t border-border bg-bg/90 px-4 py-3 backdrop-blur-md sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Link href={partner ? `/partners/${partner.id}` : "/partners"} className={buttonClass("secondary", "sm")}>Cancel</Link>
        <Button type="submit" size="sm" disabled={pending} aria-busy={pending}>
          {pending && <LoaderCircle className="size-3.5 animate-spin" />}
          {pending ? "Saving…" : isNew ? "Create partner" : "Save changes"}
        </Button>
      </div>
    </form>
  );
}
