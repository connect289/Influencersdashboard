"use client";
import { useEffect, useState } from "react";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import type { EngineSettings } from "@/lib/routing-data";
import { splitText } from "@/lib/segments";
import { saveEngineSettings, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function Row({ label, hint, error, children }: { label: string; hint: string; error?: string; children: React.ReactNode }) {
  return (
    <div className="grid gap-x-6 gap-y-1 py-3 sm:grid-cols-[minmax(0,1fr)_220px] sm:items-center">
      <div>
        <p className="text-[13px] font-medium text-fg">{label}</p>
        <p className="text-[12px] text-muted">{hint}</p>
      </div>
      <div>{children}{error && <p className="mt-1 text-xs text-danger">{error}</p>}</div>
    </div>
  );
}

/** Engine settings; every save is versioned with a reason (b2b.settings_versions). */
export function EngineForm({ v, version }: { v: EngineSettings; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveEngineSettings, undefined);
  const [share, setShare] = useState(Math.round((v.exploration_share ?? 0.2) * 100));
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Engine settings saved"); }, [state?.ok]);

  return (
    <form onSubmit={onSubmit} noValidate className="px-5 py-2">
      <div className="divide-y divide-border">
        <Row label="Exploration lane" hint="Share of leads sent to the best under-sampled partner while it has fewer than the learning leads, so its conversion can be learned. 0 means always the highest commission." error={e.exploration_share}>
          <div className="flex items-center gap-3">
            <input type="range" name="exploration_share" min={0} max={50} step={5} value={share} onChange={(x) => setShare(Number(x.target.value))} className="w-full accent-[var(--primary)]" aria-label="Exploration share" />
            <span className="tabular w-10 text-right text-[13px] text-fg">{share}%</span>
          </div>
        </Row>
        <Row label="Learning leads per partner and segment" hint="Exploration stops in a segment once every candidate has this many leads." error={e.min_learning_leads}>
          <input name="min_learning_leads" inputMode="numeric" defaultValue={v.min_learning_leads ?? 30} className={field} />
        </Row>
        <Row label="Commission when the university is not chosen" hint="How a partner's commission is summarised across the matching programmes it sells." error={e.cpe_aggregate}>
          <select name="cpe_aggregate" defaultValue={v.cpe_aggregate ?? "median"} className={field}>
            <option value="median">Median</option><option value="mean">Mean</option><option value="max">Maximum</option>
          </select>
        </Row>
        <Row label="Duplicate or rejection attempts" hint="Partners that report a duplicate or reject; then the lead goes to B2C." error={e.attempt_limit}>
          <input name="attempt_limit" inputMode="numeric" defaultValue={v.attempt_limit ?? 2} className={field} />
        </Row>
        <Row label="Partners tried in total" hint="Including technical failures; then the lead goes to B2C." error={e.partner_limit}>
          <input name="partner_limit" inputMode="numeric" defaultValue={v.partner_limit ?? 3} className={field} />
        </Row>
        <Row label="Witty idle minutes" hint="A Witty lead is ready once Witty has classified it and the chat has been quiet this long (or on hand-off)." error={e.witty_idle_minutes}>
          <input name="witty_idle_minutes" inputMode="numeric" defaultValue={v.witty_idle_minutes ?? 30} className={field} />
        </Row>
        <Row label="Require partner-sharing consent" hint="Leads without consent go to B2C. Witty does not ask for it yet." error={e.require_partner_consent}>
          <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name="require_partner_consent" defaultChecked={v.require_partner_consent ?? true} className="size-4 accent-[var(--primary)]" /> Required</label>
        </Row>
        <Row label="Trusted sources" hint="Sources whose phone numbers count as verified (comma-separated)." error={e.trusted_sources}>
          <input name="trusted_sources" defaultValue={(v.trusted_sources ?? []).join(", ")} className={field} />
        </Row>
        <p className="pt-5 pb-1 text-[11px] font-medium uppercase tracking-wider text-subtle">Performance mode (B7.2)</p>
        <Row label="Maturity" hint="A lead's outcome counts once it was sent to the partner this many days ago (days)." error={e.maturity_days}>
          <input name="maturity_days" inputMode="numeric" defaultValue={v.maturity_days ?? 60} className={field} aria-invalid={Boolean(e.maturity_days)} />
        </Row>
        <Row label="Recency half-life" hint="A matured lead this many days older counts half as much (days)." error={e.half_life_days}>
          <input name="half_life_days" inputMode="numeric" defaultValue={v.half_life_days ?? 30} className={field} aria-invalid={Boolean(e.half_life_days)} />
        </Row>
        <Row label="Prior strength" hint="How many leads' worth of the segment average each partner starts with, so a few early results cannot swing it (leads)." error={e.prior_weight}>
          <input name="prior_weight" inputMode="decimal" defaultValue={v.prior_weight ?? 20} className={field} aria-invalid={Boolean(e.prior_weight)} />
        </Row>
        <Row label="Default enrolment rate" hint="Used while a segment has no matured leads at all (%)." error={e.default_p_enroll}>
          <input name="default_p_enroll" inputMode="decimal" defaultValue={Math.round((v.default_p_enroll ?? 0.05) * 1000) / 10} className={field} aria-invalid={Boolean(e.default_p_enroll)} />
        </Row>
        <Row label="Matured leads for performance mode" hint="A segment switches from highest commission to net commission per lead once 2 partners each have this many." error={e.min_matured_leads}>
          <input name="min_matured_leads" inputMode="numeric" defaultValue={v.min_matured_leads ?? 30} className={field} aria-invalid={Boolean(e.min_matured_leads)} />
        </Row>
        <Row label="Optional factors" hint="Speed (0.85–1.15, time to first contact against all partners) and reliability (0.7–1.0, SLA breaches and sync errors in 7 days). Off by default." error={e.speed_factor ?? e.reliability_factor}>
          <div className="space-y-1.5 text-[13px]">
            <label className="flex items-center gap-2"><input type="checkbox" name="speed_factor" defaultChecked={v.speed_factor?.enabled ?? false} className="size-4 accent-[var(--primary)]" /> Speed</label>
            <label className="flex items-center gap-2"><input type="checkbox" name="reliability_factor" defaultChecked={v.reliability_factor?.enabled ?? false} className="size-4 accent-[var(--primary)]" /> Reliability</label>
          </div>
        </Row>
        <Row label="Fixed split for the kill switch" hint="Partner ID: share, e.g. 12: 60, 14: 40. Used only while the kill switch is on (globally or for a segment). B2C cannot be part of it." error={e.fixed_split}>
          <input name="fixed_split" defaultValue={splitText(v.fixed_split)} placeholder="12: 60, 14: 40" className={field} aria-invalid={Boolean(e.fixed_split)} />
        </Row>
        <Row label="Kill switch (all segments)" hint="Stops scoring, exploration and AI changes; leads are split between partners in the fixed shares. Rules, consent and B2C hand-offs still apply." error={e.kill_switch}>
          <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name="kill_switch" defaultChecked={v.kill_switch ?? false} className="size-4 accent-[var(--primary)]" /> On</label>
        </Row>
        <Row label="Reason for this change" hint={`Saved as version ${version + 1} of the engine settings, with your reason.`} error={e.reason}>
          <input name="reason" maxLength={300} placeholder="e.g. second partner signed" className={cn(field)} aria-invalid={Boolean(e.reason)} />
        </Row>
      </div>
      <div className="flex items-center justify-end gap-3 border-t border-border py-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save settings</Button>
      </div>
    </form>
  );
}
