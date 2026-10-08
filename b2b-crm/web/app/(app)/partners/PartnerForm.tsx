"use client";
import { startTransition, useActionState, useEffect, useState } from "react";
import { Lock, LoaderCircle } from "lucide-react";
import Link from "next/link";
import { toast } from "sonner";
import { Button, buttonClass } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { Input } from "@/components/ui/Field";
import { isCrmAdapter } from "@/lib/adapters";
import {
  ADAPTER_LABEL, ADAPTERS, asksDedupeConfirmation, CRITERIA_UNKNOWN, CRITERIA_UNKNOWN_LABEL, DAY_LABEL, DAYS, DEDUPE_LABEL, DEDUPE_MODES,
  DEFAULT_WORKING_HOURS, duplicateWindowText, holdWindowText, SLA_FIELDS, slaMax, slugify, type Partner,
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

/** A value Addendum 3 fixes: shown like an input, never posted. */
function Fixed({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="space-y-1.5">
      <p className="text-[13px] font-medium text-fg">{label}</p>
      <p className="flex h-10 items-center gap-2 rounded-lg border border-dashed border-border bg-surface-2 px-3 text-sm text-muted">
        <Lock className="size-3.5 shrink-0 text-subtle" aria-hidden /> {value}
      </p>
      <p className="text-xs text-muted">{hint}</p>
    </div>
  );
}

const lines = (v: string[] | undefined) => (v ?? []).join(", ");
const num = (v: number | null | undefined) => (v == null ? "" : String(v));

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
  const [adapter, setAdapter] = useState<string>(partner?.adapter_type ?? "leadsquared");
  const [dedupe, setDedupe] = useState(partner?.dedupe_mode ?? "async");
  const [unknown, setUnknown] = useState<string>(partner?.lead_criteria?.unknown ?? "");
  const hours = { ...DEFAULT_WORKING_HOURS, ...(partner?.working_hours ?? {}) };
  const [open, setOpen] = useState<Record<string, boolean>>(Object.fromEntries(DAYS.map((d) => [d, Boolean(hours[d])])));

  useEffect(() => {
    if (state?.saved) toast.success("Partner saved");
  }, [state?.saved]);

  const inv = (k: string) => (e[k] ? { "aria-invalid": true, "aria-describedby": `${k}-error` } : {});
  const validColor = /^#[0-9a-f]{6}$/i.test(color);
  const dedupeConfirmed = Boolean(partner?.dedupe_confirmed_at);
  // A CRM adapter may be 'sync' only once the Admin confirmed, in the Connection tab, that the CRM blocks duplicates on create (D37).
  const syncNeedsConfirmation = dedupe === "sync" && isCrmAdapter(adapter) && !dedupeConfirmed;
  // A partner on Eduwit's API contract or a webhook has no adapter settings: it is confirmed here.
  const asksConfirmation = asksDedupeConfirmation(adapter, dedupe);
  const c = partner?.lead_criteria ?? {};

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
          <F id="adapter_type" label="CRM type" error={e.adapter_type}
            hint="A partner with its own CRM: In-house CRM if it already has an API (Eduwit adapts to it), or Eduwit's API contract if their developer builds it. A partner with no API cannot be routed to automatically yet.">
            <select id="adapter_type" name="adapter_type" value={adapter} onChange={(ev) => setAdapter(ev.target.value)} className={cn(control, "h-10")}>
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
          {e.dedupe_mode ? (
            <p id="dedupe_mode-error" role="alert" className="mt-2 text-xs text-danger">{e.dedupe_mode}</p>
          ) : syncNeedsConfirmation && (
            <p className="mt-2 text-xs text-warning">
              This CRM adapter is not yet confirmed to block duplicates on create. Confirm it in the{" "}
              {partner ? <Link href={`/partners/${partner.id}?tab=connection`} className="underline">Connection tab</Link> : "Connection tab (after the partner is created)"}, or keep “Later, by webhook or poll”: the save is refused otherwise.
            </p>
          )}
          {asksConfirmation && (
            <label className="mt-3 flex items-start gap-3 rounded-lg border border-border px-3 py-2.5">
              <input type="checkbox" name="dedupe_confirmed" defaultChecked={dedupeConfirmed} className="mt-0.5 size-4 accent-[var(--primary)]" />
              <span className="text-[13px] text-fg">
                I confirm the partner's endpoint refuses a duplicate in the create call
                <span className="block text-[12px] text-muted">
                  Under Eduwit's API contract a duplicate answers HTTP 409 at once. The go-live checklist item “Confirm whether the CRM blocks duplicates on create” is done once this is ticked.
                </span>
              </span>
            </label>
          )}
        </fieldset>
        <div className="grid gap-4 sm:grid-cols-2">
          <Fixed label="Hold window" value={holdWindowText({ dedupe_mode: dedupe, dedupe_confirmed_at: partner?.dedupe_confirmed_at ?? null })}
            hint={dedupe === "sync"
              ? "No hold: duplicates are refused in the create call, so the student is told who will call at once (Addendum 3, PART 5.1)."
              : "The student is told who will call only after 30 minutes pass without a duplicate or rejection (Addendum 3, PART 5.1)."} />
          <Fixed label="Duplicate claim window" value={duplicateWindowText()}
            hint="A duplicate claimed within 24 hours of acceptance becomes a commission dispute for you to decide; later claims are ignored (PART 5.8)." />
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

      <Section title="SLAs" description="What the partner promised. Addendum 3 fixes the first call, the status update and the enrolment proof: a partner may promise less time, never more. Breaches feed the SLA-adherence factor, the scorecard and alerts; five first-contact breaches in a row pause the partner automatically.">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {SLA_FIELDS.map((f) => f.fixed !== undefined ? (
            <Fixed key={f.key} label={f.label} value={duplicateWindowText()} hint="Not an SLA the partner sets: the rulebook's window for duplicate claims after acceptance." />
          ) : (
            <F key={f.key} id={`sla_${f.key}`} label={`${f.label} (${f.unit})`} error={e[`sla_${f.key}`]}
              hint={f.rulebook !== undefined ? `At most ${f.rulebook} ${f.unit} (Addendum 3). A smaller number is a tighter promise.` : `1 to ${slaMax(f)} ${f.unit}.`}>
              <Input id={`sla_${f.key}`} name={`sla_${f.key}`} inputMode="numeric" min={1} max={slaMax(f)} defaultValue={partner?.sla?.[f.key] ?? f.def} {...inv(`sla_${f.key}`)} />
            </F>
          ))}
        </div>
      </Section>

      <Section title="Lead criteria" description="What the partner agreed to accept (PART 4, Step 1). A lead that fails these never routes to it. Names are matched case-insensitively; leave a list empty for no restriction.">
        <div className="grid gap-4 sm:grid-cols-2">
          <F id="states_include" label="Only these states" hint="Comma-separated. Empty means all of India." error={e.states_include}>
            <Input id="states_include" name="states_include" maxLength={2000} defaultValue={lines(c.states_include)} {...inv("states_include")} />
          </F>
          <F id="states_exclude" label="Never these states" error={e.states_exclude}>
            <Input id="states_exclude" name="states_exclude" maxLength={2000} defaultValue={lines(c.states_exclude)} {...inv("states_exclude")} />
          </F>
          <F id="cities_include" label="Only these cities" hint="Comma-separated. Empty means every city." error={e.cities_include}>
            <Input id="cities_include" name="cities_include" maxLength={2000} defaultValue={lines(c.cities_include)} {...inv("cities_include")} />
          </F>
          <F id="cities_exclude" label="Never these cities" error={e.cities_exclude}>
            <Input id="cities_exclude" name="cities_exclude" maxLength={2000} defaultValue={lines(c.cities_exclude)} {...inv("cities_exclude")} />
          </F>
          <F id="qualifications_include" label="Only these qualifications" hint="Comma-separated, e.g. Graduate, Postgraduate, Diploma. Empty means any." error={e.qualifications_include} className="sm:col-span-2">
            <Input id="qualifications_include" name="qualifications_include" maxLength={2000} defaultValue={lines(c.qualifications_include)} {...inv("qualifications_include")} />
          </F>
          <F id="min_academic_pct" label="Minimum academic score (%)" hint="0 to 100. Empty means no minimum." error={e.min_academic_pct}>
            <Input id="min_academic_pct" name="min_academic_pct" inputMode="decimal" placeholder="e.g. 50" defaultValue={num(c.min_academic_pct)} {...inv("min_academic_pct")} />
          </F>
          <F id="min_work_experience_years" label="Minimum work experience (years)" hint="0 to 40. Empty means no minimum." error={e.min_work_experience_years}>
            <Input id="min_work_experience_years" name="min_work_experience_years" inputMode="decimal" placeholder="e.g. 2" defaultValue={num(c.min_work_experience_years)} {...inv("min_work_experience_years")} />
          </F>
          <F id="sources_exclude" label="Never leads from these sources" hint="Source codes, e.g. meta_lead_ad." error={e.sources_exclude}>
            <Input id="sources_exclude" name="sources_exclude" maxLength={2000} defaultValue={lines(c.sources_exclude)} {...inv("sources_exclude")} />
          </F>
          <F id="criteria_other" label="Other rules" hint="Free text for the record; the engine does not apply it." error={e.criteria_other}>
            <Input id="criteria_other" name="criteria_other" maxLength={2000} defaultValue={c.other ?? ""} {...inv("criteria_other")} />
          </F>
        </div>
        <fieldset>
          <legend className="mb-1 text-[13px] font-medium text-fg">When the lead's data is unknown</legend>
          <p className="mb-2 text-xs text-muted">A lead whose state, city, qualification, score or experience is missing cannot be shown to meet a criterion. What did this partner agree?</p>
          <div className="grid gap-2 sm:grid-cols-3">
            {(["", ...CRITERIA_UNKNOWN] as const).map((v) => {
              const text = v === ""
                ? { label: "Follow the engine setting", hint: "Routing → Engine → “Criteria with unknown data” decides (the rulebook default is: do not send)." }
                : CRITERIA_UNKNOWN_LABEL[v];
              return (
                <label key={v || "default"} className={cn("cursor-pointer rounded-lg border p-3 transition-colors", unknown === v ? "border-ring bg-amber/10" : "border-border hover:bg-surface-hover")}>
                  <span className="flex items-center gap-2 text-[13px] font-medium text-fg">
                    <input type="radio" name="criteria_unknown" value={v} checked={unknown === v} onChange={() => setUnknown(v)} className="accent-[var(--primary)]" />
                    {text.label}
                  </span>
                  <span className="mt-1 block text-[12px] leading-4 text-muted">{text.hint}</span>
                </label>
              );
            })}
          </div>
          {e.criteria_unknown && <p id="criteria_unknown-error" role="alert" className="mt-2 text-xs text-danger">{e.criteria_unknown}</p>}
        </fieldset>
      </Section>

      <Section title="Push options" description="What the push to the partner's CRM carries beyond the lead itself.">
        <label className="flex items-start gap-3">
          <input type="checkbox" name="push_interests_array" defaultChecked={partner?.push_options?.interests_array ?? false} className="mt-0.5 size-4 accent-[var(--primary)]"
            aria-invalid={Boolean(e.push_interests_array)} aria-describedby={e.push_interests_array ? "push_interests_array-error" : undefined} />
          <span className="text-[13px] text-fg">
            Send interests as a list (<code className="font-mono text-[12px]">interests[]</code>)
            <span className="block text-[12px] text-muted">
              Off by default: strict CRM APIs reject unknown keys. The push note always lists every interest the student named (“Interested in … Also asked about: …”), whatever this setting.
            </span>
          </span>
        </label>
        {e.push_interests_array && <p id="push_interests_array-error" role="alert" className="text-xs text-danger">{e.push_interests_array}</p>}
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
