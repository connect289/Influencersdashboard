"use client";
import { useState } from "react";
import Link from "next/link";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { OUTLOOK_LABEL, ROUTE_CHOICE } from "@/lib/intake";
import { enterLead, type ManualForm } from "./actions";
import { area, field, label } from "./ui";

const empty: ManualForm = {
  lead: { full_name: "", phone: "", email: "", city: "", state: "", course: "", specialization: "", university: "", programme_level: "", highest_qualification: "", work_experience: "", notes: "" },
  source: "", campaign: "", route: "route", b2c_lane: "sales", consent_purposes: ["sales", "partner_share"], consent_where: "", note: "",
};

const LEAD_FIELDS: { k: keyof ManualForm["lead"]; l: string; ph?: string; type?: string }[] = [
  { k: "full_name", l: "Name" }, { k: "phone", l: "Phone", ph: "+91 98765 43210", type: "tel" }, { k: "email", l: "Email", type: "email" },
  { k: "city", l: "City" }, { k: "state", l: "State" }, { k: "course", l: "Course", ph: "e.g. Online MBA" }, { k: "specialization", l: "Specialisation" },
  { k: "university", l: "University" }, { k: "programme_level", l: "Level", ph: "UG, PG, diploma…" }, { k: "highest_qualification", l: "Highest qualification" },
  { k: "work_experience", l: "Work experience", ph: "e.g. 3 years" },
];

const HINT: Record<keyof typeof ROUTE_CHOICE, string> = {
  route: "Through the normal rules as soon as it is ready: a partner, or B2C when the rules say so.",
  hold: "Waits in the pre-routing pool until you release it or route it by hand.",
  b2c: "Goes to Eduwit's own team (junk and programme mismatch are still held back).",
};

/** The Admin types in a lead from a call, walk-in or event. It goes through lead_intake() like every other source. */
export function NewLead() {
  const [f, setF] = useState<ManualForm>(empty);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<{ lead_id: number; action: string; outlook: string; status: string; waiting: string[] } | null>(null);
  const [pending, setPending] = useState(false);
  const purposes = f.consent_purposes as string[];
  const setLead = (k: keyof ManualForm["lead"], v: string) => setF({ ...f, lead: { ...f.lead, [k]: v } });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPending(true); setError(null); setErrors({});
    try {
      const r = await enterLead({ ...f, b2c_lane: f.route === "b2c" ? f.b2c_lane : undefined });
      if (!r.ok) { setError(r.error); setErrors(r.errors ?? {}); return; }
      setDone({ lead_id: r.lead_id, action: r.action, outlook: r.routing.outlook, status: r.routing.status, waiting: r.routing.waiting_for ?? [] });
      toast.success(r.action === "created" ? "Lead added" : "Added to the existing lead");
      setF(empty);
    } finally { setPending(false); }
  };

  return (
    <form onSubmit={submit} className="space-y-5 p-5" noValidate>
      {done && (
        <Notice tone="success">
          <Link href={`/leads?lead=${done.lead_id}`} className="font-medium underline">Lead #{done.lead_id}</Link> {done.action === "created" ? "was created" : `was ${done.action} (the phone was already known)`}.
          {" "}{done.status === "queued" ? "It routes on the next run" : done.status === "already_routed" ? "It was already routed" : `It waits for: ${done.waiting.join(", ") || "review"}`}
          {done.outlook && <> · outlook: {OUTLOOK_LABEL[done.outlook] ?? done.outlook}</>}.
        </Notice>
      )}
      {error && <Notice tone="error">{error}</Notice>}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {LEAD_FIELDS.map((x) => {
          const err = errors[`lead.${x.k}`];
          return (
            <label key={x.k} className="block space-y-1">
              <span className={label}>{x.l}{(x.k === "full_name" || x.k === "phone") && <span className="text-danger"> *</span>}</span>
              <input className={field} type={x.type ?? "text"} value={f.lead[x.k] ?? ""} placeholder={x.ph} aria-invalid={Boolean(err)} onChange={(e) => setLead(x.k, e.target.value)} />
              {err && <span className="text-xs text-danger">{err}</span>}
            </label>
          );
        })}
        <label className="block space-y-1">
          <span className={label}>Source</span>
          <input className={field} value={f.source ?? ""} maxLength={60} placeholder="manual_entry" onChange={(e) => setF({ ...f, source: e.target.value })} />
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
        </label>
        <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-[13px]">
          <label className="flex items-center gap-2 text-muted"><input type="checkbox" checked disabled className="accent-[var(--primary)]" /> Contact about courses</label>
          {(["partner_share", "marketing"] as const).map((p) => (
            <label key={p} className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={purposes.includes(p)}
              onChange={(e) => setF({ ...f, consent_purposes: (e.target.checked ? [...purposes, p] : purposes.filter((x) => x !== p)) as ManualForm["consent_purposes"] })} />
              {p === "partner_share" ? "Share with partner institutions" : "Marketing messages"}</label>
          ))}
        </div>
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
