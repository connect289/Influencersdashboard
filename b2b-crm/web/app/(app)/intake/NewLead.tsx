"use client";
import { useState } from "react";
import Link from "next/link";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { CONSENT_CHANNEL_LABEL, CONSENT_PURPOSE_LABEL, OUTLOOK_LABEL, ROUTE_CHOICE, coveringTexts, textCovers, type ConsentText } from "@/lib/intake";
import { enterLead, type ManualForm, type ManualResult } from "./actions";
import { area, field, label } from "./ui";

type LeadKey = keyof ManualForm["lead"];
type FieldDef = { k: LeadKey; l: string; ph?: string; type?: string; wide?: boolean; hint?: string };

const SECTIONS: { title: string; fields: FieldDef[] }[] = [
  { title: "Student", fields: [
    { k: "full_name", l: "Name" }, { k: "phone", l: "Phone", ph: "+91 98765 43210", type: "tel" }, { k: "email", l: "Email", type: "email" },
    { k: "city", l: "City" }, { k: "state", l: "State" },
  ] },
  { title: "Interest", fields: [
    { k: "course", l: "Course", ph: "e.g. Online MBA" }, { k: "specialization", l: "Specialisation" }, { k: "university", l: "University" },
    { k: "programme_level", l: "Level", ph: "UG, PG, diploma…" },
    { k: "other_courses", l: "Other courses the student mentioned", ph: "e.g. Online MCA, Executive MBA", wide: true,
      hint: "Comma-separated, up to 9. They become secondary interests: tried in order when no partner offers the main course, and listed in the partner's push note." },
  ] },
  { title: "Background", fields: [{ k: "highest_qualification", l: "Highest qualification" }, { k: "work_experience", l: "Work experience", ph: "e.g. 3 years" }] },
];

const HINT: Record<keyof typeof ROUTE_CHOICE, string> = {
  route: "Through the normal rules as soon as it is ready: a partner, or B2C when the rules say so. Without partner-sharing consent that counts, the student is asked for it first.",
  hold: "Waits in the pre-routing pool until you release it or route it by hand.",
  b2c: "Goes to Eduwit's own team (junk and programme mismatch are still held back).",
};

/** intake_lead's warnings (m31h) in the Admin's words. */
const WARNING_TEXT: Record<string, string> = {
  "consent text version not registered": "The consent text version is not registered under Consent texts, so the stamp cannot be traced to a wording.",
  "consent text does not cover admission partners": "The consent text does not cover our admission partners: the partner-sharing tick does not count and the student will be asked for consent before any partner sees the lead.",
};

/** The registered covering texts a manual entry may stamp partner sharing under; manual-channel texts first. */
function manualTexts(texts: ConsentText[]): ConsentText[] {
  return coveringTexts(texts).sort((a, b) => Number(b.channel === "manual") - Number(a.channel === "manual") || a.version.localeCompare(b.version));
}

const empty = (defaultVersion: string): ManualForm => ({
  lead: { full_name: "", phone: "", email: "", city: "", state: "", course: "", specialization: "", university: "", programme_level: "", other_courses: "", highest_qualification: "", work_experience: "", notes: "" },
  source: "", campaign: "", route: "route", b2c_lane: "sales", consent_purposes: ["sales", "partner_share"], consent_where: "", consent_version: defaultVersion, note: "",
});

/** The Admin types in a lead from a call, walk-in or event. It goes through lead_intake() like every other source. */
export function NewLead({ texts }: { texts: ConsentText[] }) {
  const options = manualTexts(texts);
  const defaultVersion = options.find((t) => t.channel === "manual")?.version ?? "";
  const [f, setF] = useState<ManualForm>(() => empty(defaultVersion));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<ManualResult | null>(null);
  const [pending, setPending] = useState(false);
  const purposes = f.consent_purposes as string[];
  const shares = purposes.includes("partner_share");
  const chosen = texts.find((t) => t.version === f.consent_version);
  const setLead = (k: LeadKey, v: string) => setF({ ...f, lead: { ...f.lead, [k]: v } });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPending(true); setError(null); setErrors({});
    try {
      const r = await enterLead({ ...f, b2c_lane: f.route === "b2c" ? f.b2c_lane : undefined, consent_version: shares ? f.consent_version : "" });
      if (!r.ok) { setError(r.error); setErrors(r.errors ?? {}); return; }
      setDone(r);
      toast.success(r.action === "created" ? "Lead added" : "Added to the existing lead");
      setF(empty(defaultVersion));
    } finally { setPending(false); }
  };

  const outlook = done?.outlook ?? done?.routing.outlook ?? null;

  return (
    <form onSubmit={submit} className="space-y-5 p-5" noValidate>
      {done && (
        <div className="space-y-2">
          <Notice tone="success">
            <Link href={`/leads?lead=${done.lead_id}`} className="font-medium underline">Lead #{done.lead_id}</Link> {done.action === "created" ? "was created" : `was ${done.action} (the phone was already known)`}.
            {" "}{done.routing.status === "queued" ? "It routes on the next run" : done.routing.status === "already_routed" ? "It was already routed" : `It waits for: ${done.routing.waiting_for?.join(", ") || "review"}`}
            {outlook && <> · outlook: <span className="font-medium">{OUTLOOK_LABEL[outlook] ?? outlook}</span></>}
            {done.routing.outlook_reason && <span className="text-[12.5px]"> ({done.routing.outlook_reason})</span>}
            {(done.interests_added ?? 0) > 0 && <> · {done.interests_added} other {done.interests_added === 1 ? "course" : "courses"} recorded as secondary interests</>}.
          </Notice>
          {(done.warnings ?? []).map((w) => <Notice key={w} tone="warning">{WARNING_TEXT[w] ?? w}</Notice>)}
        </div>
      )}
      {error && <Notice tone="error">{error}</Notice>}

      {SECTIONS.map((s) => (
        <fieldset key={s.title} className="space-y-3">
          <legend className="mb-1 text-[13px] font-semibold text-fg">{s.title}</legend>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {s.fields.map((x) => {
              const err = errors[`lead.${x.k}`];
              return (
                <label key={x.k} className={cn("block space-y-1", x.wide && "sm:col-span-2 lg:col-span-3")}>
                  <span className={label}>{x.l}{(x.k === "full_name" || x.k === "phone") && <span className="text-danger"> *</span>}</span>
                  <input className={field} type={x.type ?? "text"} value={f.lead[x.k] ?? ""} placeholder={x.ph} aria-invalid={Boolean(err)} onChange={(e) => setLead(x.k, e.target.value)} />
                  {err ? <span className="text-xs text-danger">{err}</span> : x.hint && <span className="text-xs text-muted">{x.hint}</span>}
                </label>
              );
            })}
          </div>
        </fieldset>
      ))}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <label className="block space-y-1">
          <span className={label}>Source</span>
          <input className={field} value={f.source ?? ""} maxLength={60} placeholder="manual_entry" onChange={(e) => setF({ ...f, source: e.target.value })} />
        </label>
        <label className="block space-y-1">
          <span className={label}>Campaign <span className="font-normal text-subtle">(optional)</span></span>
          <input className={field} value={f.campaign ?? ""} maxLength={120} placeholder="e.g. delhi_fair_oct" onChange={(e) => setF({ ...f, campaign: e.target.value })} />
        </label>
      </div>
      <label className="block space-y-1">
        <span className={label}>Notes</span>
        <textarea className={area} value={f.lead.notes ?? ""} maxLength={2000} onChange={(e) => setLead("notes", e.target.value)} />
      </label>

      <fieldset className="space-y-3 rounded-lg border border-border p-4">
        <legend className="px-1 text-[13px] font-semibold text-fg">Consent</legend>
        <label className="block space-y-1">
          <span className={label}>How the student agreed <span className="text-danger">*</span></span>
          <input className={field} value={f.consent_where} maxLength={80} placeholder="e.g. on a call on 7 Oct, walk-in at the Noida office" aria-invalid={Boolean(errors.consent_where)}
            onChange={(e) => setF({ ...f, consent_where: e.target.value })} />
          {errors.consent_where && <span className="text-xs text-danger">{errors.consent_where}</span>}
        </label>
        <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-[13px]">
          <label className="flex items-center gap-2 text-muted"><input type="checkbox" checked disabled className="accent-[var(--primary)]" /> {CONSENT_PURPOSE_LABEL.sales}</label>
          {(["partner_share", "marketing"] as const).map((p) => (
            <label key={p} className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={purposes.includes(p)}
              onChange={(e) => setF({ ...f, consent_purposes: (e.target.checked ? [...purposes, p] : purposes.filter((x) => x !== p)) as ManualForm["consent_purposes"] })} />
              {CONSENT_PURPOSE_LABEL[p]}</label>
          ))}
        </div>
        {shares && (
          <label className="block space-y-1 md:w-[28rem]">
            <span className={label}>Wording the student agreed to</span>
            <select className={field} value={f.consent_version ?? ""} onChange={(e) => setF({ ...f, consent_version: e.target.value })}>
              <option value="">Not a registered text (does not count)</option>
              {options.map((t) => <option key={t.version} value={t.version}>{t.version} · {CONSENT_CHANNEL_LABEL[t.channel] ?? t.channel}</option>)}
            </select>
            <span className="text-xs text-muted">
              Partner sharing counts only under a registered text that names our admission partners (edtech companies).{" "}
              {options.length === 0 && <>None is registered yet: add one under <Link href="/intake?tab=consent" className="text-info hover:underline">Consent texts</Link> (channel Manual entry).</>}
            </span>
          </label>
        )}
        {shares && !textCovers(chosen) && (
          <Notice tone="warning">Without a registered covering text the partner-sharing tick does not count: the student is asked for consent (one-tap WhatsApp request) before any partner sees the lead.</Notice>
        )}
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="mb-1 text-[13px] font-semibold text-fg">What happens to the lead</legend>
        <div className="grid gap-2 md:grid-cols-3">
          {(Object.keys(ROUTE_CHOICE) as (keyof typeof ROUTE_CHOICE)[]).map((k) => (
            <label key={k} className={cn("flex cursor-pointer gap-3 rounded-lg border p-3", f.route === k ? "border-amber bg-amber/5" : "border-border hover:border-border-strong")}>
              <input type="radio" name="route" className="mt-0.5 accent-[var(--primary)]" checked={f.route === k} onChange={() => setF({ ...f, route: k })} />
              <span><span className="block text-[13px] font-medium text-fg">{ROUTE_CHOICE[k].label}</span><span className="block text-[12px] text-muted">{HINT[k]}</span></span>
            </label>
          ))}
        </div>
        {f.route === "b2c" && (
          <label className="block w-64 space-y-1">
            <span className={label}>B2C lane</span>
            <select className={field} value={f.b2c_lane} onChange={(e) => setF({ ...f, b2c_lane: e.target.value as "sales" | "nurture" })}>
              <option value="sales">Sales (call them now)</option><option value="nurture">Nurture (keep warm)</option>
            </select>
          </label>
        )}
      </fieldset>
      <div className="flex justify-end">
        <Button type="submit" disabled={pending}>{pending && <LoaderCircle className="size-4 animate-spin" />} Add the lead</Button>
      </div>
    </form>
  );
}
