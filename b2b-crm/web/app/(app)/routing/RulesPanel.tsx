"use client";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { LoaderCircle, Plus, Scale } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { ACTION_LABEL, describeConditions, LANE_LABEL } from "@/lib/routing";
import type { Rule } from "@/lib/routing-data";
import { saveRule, setRuleActive, type FormState } from "./actions";

type Partner = { id: number; name: string; status: string };
type University = { id: number; name: string; short_name: string | null };
const field = "w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const arr = (c: Record<string, unknown>, k: string) => (Array.isArray(c[k]) ? (c[k] as unknown[]).map(String) : []);
const NO_UNIVERSITIES: University[] = [];

/** What a rule's action does under Addendum 3 (PART 4 Step 2, D14, D33). */
const ACTION_HINT: Record<string, string> = {
  fix_partner: "The lead goes to one of these partners (the best eligible one among them), whatever its score. Skipped when none of them is eligible for this lead.",
  narrow: "Only these partners compete for the lead. Skipped when none of them is eligible for this lead.",
  exclude: "These partners never receive a matching lead.",
  to_b2c: "The lead is handed to Eduwit's B2C CRM and stays there (R4) until you send it to partners by hand. Skipped on manual routes.",
};

function UniversityPicker({ universities, selected }: { universities: University[]; selected: string[] }) {
  const [filter, setFilter] = useState("");
  const shown = useMemo(() => {
    const f = filter.trim().toLowerCase();
    const list = f ? universities.filter((u) => u.name.toLowerCase().includes(f) || (u.short_name ?? "").toLowerCase().includes(f) || selected.includes(String(u.id))) : universities;
    return list;
  }, [universities, filter, selected]);
  return (
    <div className="space-y-1 sm:col-span-2">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-[12px] text-muted">Universities</span>
        {universities.length > 8 && (
          <input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Find a university" aria-label="Find a university"
            className={cn(field, "h-7 max-w-[220px] text-[12px]")} />
        )}
      </div>
      <div className="grid max-h-32 gap-x-4 gap-y-1 overflow-y-auto rounded-lg border border-border p-2 sm:grid-cols-2">
        {shown.map((u) => (
          <label key={u.id} className="flex items-center gap-2 text-[12.5px]">
            <input type="checkbox" name="university_ids" value={u.id} defaultChecked={selected.includes(String(u.id))} className="accent-[var(--primary)]" />
            <span className="truncate" title={u.name}>{u.short_name ? `${u.short_name} · ${u.name}` : u.name}</span>
          </label>
        ))}
        {shown.length === 0 && <p className="text-[12px] text-subtle">{universities.length === 0 ? "No universities in the catalogue yet." : "No university matches."}</p>}
      </div>
      <span className="block text-[11px] text-subtle">Matches the university the student named (any of the ticked ones). Empty means any university.</span>
    </div>
  );
}

function RuleDialog({ rule, partners, universities, open, onClose }: { rule: Rule | null; partners: Partner[]; universities: University[]; open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [state, onSubmit, pending] = useFormAction<FormState>(saveRule, undefined);
  const e = state?.errors ?? {};
  const c = rule?.conditions ?? {};
  const [action, setAction] = useState(rule?.action ?? "fix_partner");
  const paidDefault = typeof c.paid === "boolean" ? (c.paid ? "yes" : "no") : "any";

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  // Close once a save succeeds (state.ok is a fresh timestamp per save).
  useEffect(() => { if (state?.ok) { toast.success("Rule saved"); onClose(); } }, [state?.ok, onClose]);

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="rule-title"
      className="m-auto w-[min(680px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <form key={rule?.id ?? "new"} onSubmit={onSubmit} noValidate>
        <input type="hidden" name="id" value={rule?.id ?? ""} />
        <div className="space-y-4 p-5">
          <h2 id="rule-title" className="text-[15px] font-semibold">{rule ? "Edit rule" : "New routing rule"}</h2>
          <div className="grid gap-3 sm:grid-cols-[1fr_120px]">
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Name</span>
              <input name="name" defaultValue={rule?.name ?? ""} maxLength={120} className={cn(field, "h-9")} aria-invalid={Boolean(e.name)} placeholder="e.g. Delhi MBA leads to Acme" />
              {e.name && <span className="text-xs text-danger">{e.name}</span>}
            </label>
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Priority</span>
              <input name="priority" defaultValue={rule?.priority ?? 100} inputMode="numeric" className={cn(field, "h-9")} aria-invalid={Boolean(e.priority)} />
              <span className="block text-[11px] text-subtle">Lower runs first; one order for partner and B2C rules</span>
            </label>
          </div>

          <fieldset className="space-y-2 rounded-lg border border-border p-3">
            <legend className="px-1 text-[13px] font-medium">When the lead matches (empty means any)</legend>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1"><span className="text-[12px] text-muted">Course keys</span>
                <input name="course_keys" defaultValue={arr(c, "course_keys").join(", ")} placeholder="mba, bba" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Specialisations</span>
                <input name="specializations" defaultValue={arr(c, "specializations").join(", ")} placeholder="Finance, Marketing" className={cn(field, "h-9")} aria-invalid={Boolean(e.specializations)} />
                <span className="block text-[11px] text-subtle">Comma-separated; matched on the student&apos;s specialisation, spelling and case ignored</span></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Lead sources</span>
                <input name="sources" defaultValue={arr(c, "sources").join(", ")} placeholder="meta_lead_ad, whatsapp_direct" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">States</span>
                <input name="states" defaultValue={arr(c, "states").join(", ")} placeholder="Delhi, Haryana" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Campaign contains</span>
                <input name="campaign_contains" defaultValue={typeof c.campaign_contains === "string" ? c.campaign_contains : ""} maxLength={100} className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Paid attribution</span>
                <select name="paid" defaultValue={paidDefault} className={cn(field, "h-9")} aria-invalid={Boolean(e.paid)}>
                  <option value="any">Any lead</option>
                  <option value="yes">Paid Meta or Google ad leads only</option>
                  <option value="no">Not from paid ads</option>
                </select>
                <span className="block text-[11px] text-subtle">Paid is an attribution label (Meta Lead Ads, Google lead forms, ad click IDs); it no longer changes routing by itself</span></label>
              <UniversityPicker universities={universities} selected={arr(c, "university_ids")} />
            </div>
            <div className="flex flex-wrap gap-x-5 gap-y-2 pt-1 text-[13px]">
              {["Online", "ODL", "Regular"].map((m) => (
                <label key={m} className="flex items-center gap-1.5"><input type="checkbox" name="modes" value={m} defaultChecked={arr(c, "modes").includes(m)} className="accent-[var(--primary)]" /> {m}</label>
              ))}
              <span className="text-border">|</span>
              {["UG", "PG", "DIPLOMA", "CERTIFICATE"].map((l) => (
                <label key={l} className="flex items-center gap-1.5"><input type="checkbox" name="levels" value={l} defaultChecked={arr(c, "levels").includes(l)} className="accent-[var(--primary)]" /> {l}</label>
              ))}
            </div>
          </fieldset>

          <div className="grid gap-3 sm:grid-cols-[200px_1fr]">
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Then</span>
              <select name="action" value={action} onChange={(x) => setAction(x.target.value)} className={cn(field, "h-9")}>
                {Object.entries(ACTION_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
              <span className="block text-[11px] text-subtle">{ACTION_HINT[action]}</span>
            </label>
            {action === "to_b2c" ? (
              <fieldset className="space-y-1">
                <legend className="text-[13px] font-medium">B2C lane</legend>
                <div className={cn("space-y-1.5 rounded-lg border p-2 text-[13px]", e.b2c_lane ? "border-danger" : "border-border")}>
                  <label className="flex items-center gap-2"><input type="radio" name="b2c_lane" value="sales" defaultChecked={rule?.b2c_lane !== "nurture"} className="accent-[var(--primary)]" /> Sales: a B2C counsellor is assigned and calls the student</label>
                  <label className="flex items-center gap-2"><input type="radio" name="b2c_lane" value="nurture" defaultChecked={rule?.b2c_lane === "nurture"} className="accent-[var(--primary)]" /> Nurture: the B2C CRM nurtures the student, unassigned until they show interest</label>
                </div>
                {e.b2c_lane && <span className="text-xs text-danger">{e.b2c_lane}</span>}
              </fieldset>
            ) : (
            <fieldset className="space-y-1">
              <legend className="text-[13px] font-medium">Partners</legend>
              <div className={cn("max-h-36 space-y-1 overflow-y-auto rounded-lg border p-2", e.partner_ids ? "border-danger" : "border-border")}>
                {partners.map((p) => (
                  <label key={p.id} className="flex items-center gap-2 text-[13px]">
                    <input type="checkbox" name="partner_ids" value={p.id} defaultChecked={rule?.partner_ids.includes(p.id)} className="accent-[var(--primary)]" />
                    {p.name} {p.status !== "active" && <span className="text-[11px] text-subtle">({p.status})</span>}
                  </label>
                ))}
                {partners.length === 0 && <p className="text-[12px] text-subtle">Add a partner first.</p>}
              </div>
              {e.partner_ids && <span className="text-xs text-danger">{e.partner_ids}</span>}
            </fieldset>
            )}
          </div>
          <p className="text-[12px] text-subtle">
            Rules run inside partner routing (R9), after the consent check (R8) and the candidate filter (live partners offering the programme,
            under their caps, no earlier duplicate, criteria met), in one priority order, for the interest being tried. A rule never reaches a
            partner-barred lead, a lead with a partner or a lead held by B2C (R2–R4). &quot;Send to B2C&quot; rules are skipped when the Admin routes a
            lead by hand.
          </p>
          {state?.error && <p role="alert" className="text-[13px] text-danger">{state.error}</p>}
        </div>
        <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
          <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save rule</Button>
        </div>
      </form>
    </dialog>
  );
}

/** Step 2 routing rules (PART 4): the Admin's only override tool under Addendum 3. Pins, share caps and partner weights were retired. */
export function RulesPanel({ rules, partners, universities = NO_UNIVERSITIES }: { rules: Rule[]; partners: Partner[]; universities?: University[] }) {
  const [editing, setEditing] = useState<Rule | null | "new">(null);
  const close = useCallback(() => setEditing(null), []);
  const uniNames = useMemo(() => Object.fromEntries(universities.map((u) => [String(u.id), u.short_name || u.name])), [universities]);
  const toggle = async (r: Rule) => {
    const err = await setRuleActive(r.id, !r.active);
    if (err) toast.error(err); else toast.success(r.active ? "Rule turned off" : "Rule turned on");
  };
  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-3">
        <div className="min-w-0 flex-1 space-y-1 text-[13px] text-muted">
          <p>
            Rules are your override tool for partner routing. They run in one priority order (lower first), after the consent check and the candidate
            filter, for the interest being tried. A partner rule fixes, narrows or excludes partners; a <strong className="font-medium text-fg">Send to B2C</strong> rule
            hands the lead to Eduwit&apos;s B2C CRM, where it stays until you send it to partners by hand.
          </p>
          <p className="text-[12.5px]">
            Fix and narrow rules whose partners are not eligible are skipped; Send-to-B2C rules are skipped on manual routes. Conditions can test the
            course, specialisation, level, mode, university, source, state, campaign and the paid attribution label. Segment pins, share caps and
            partner weights were retired by Addendum 3: use a rule, or pause the partner.
          </p>
        </div>
        <Button size="sm" onClick={() => setEditing("new")}><Plus className="size-3.5" /> New rule</Button>
      </div>
      {rules.length === 0 ? (
        <EmptyState icon={Scale} title="No routing rules">
          Without rules, every qualified lead goes to the eligible partner with the best score: commission per enrolment net of GST (Stage A), adjusted
          by sales effort and SLA adherence once there is data (Stages B and C).
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border">
          {rules.map((r) => (
            <li key={r.id} className={cn("flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3", !r.active && "opacity-60")}>
              <span className="tabular w-10 text-[12px] text-subtle">#{r.priority}</span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13.5px] font-medium text-fg">{r.name}</p>
                <p className="text-[12.5px] text-muted">
                  {describeConditions(r.conditions, uniNames)} → {r.action === "to_b2c"
                    ? <>send to <span className="text-fg">{LANE_LABEL[r.b2c_lane ?? "sales"]}</span> (stays with B2C)</>
                    : <>{ACTION_LABEL[r.action]?.toLowerCase()} {(r.partner_names ?? []).join(", ")}</>}
                </p>
              </div>
              <Badge tone={r.action === "to_b2c" ? "warning" : "neutral"}>{r.action === "to_b2c" ? "B2C" : "Partners"}</Badge>
              <Badge tone={r.active ? "success" : "neutral"}>{r.active ? "On" : "Off"}</Badge>
              <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>Edit</Button>
              <Button size="sm" variant="secondary" onClick={() => toggle(r)}>{r.active ? "Turn off" : "Turn on"}</Button>
            </li>
          ))}
        </ul>
      )}
      <RuleDialog key={editing === null ? "closed" : editing === "new" ? "new" : editing.id} rule={editing === "new" ? null : editing}
        partners={partners} universities={universities} open={editing !== null} onClose={close} />
    </>
  );
}
