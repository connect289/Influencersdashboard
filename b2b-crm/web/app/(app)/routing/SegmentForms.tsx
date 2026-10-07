"use client";
import { useEffect, useState, useTransition } from "react";
import { LoaderCircle, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { useFormAction } from "@/components/ui/useFormAction";
import type { EnginePolicy, SegmentModeInfo, SegmentPartner, SegmentPolicy } from "@/lib/segments";
import { refreshStats, saveEnginePolicy, savePartnerWeight, saveSegmentPolicy, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

function L({ label, error, hint, children }: { label: string; error?: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-[12px] text-muted">{label}</span>
      {children}
      {hint && !error && <span className="block text-[11.5px] text-subtle">{hint}</span>}
      {error && <span className="block text-xs text-danger">{error}</span>}
    </label>
  );
}

function Footer({ error, pending, label }: { error?: string; pending: boolean; label: string }) {
  return (
    <div className="flex items-center justify-end gap-3 pt-1">
      {error && <span role="alert" className="mr-auto text-[13px] text-danger">{error}</span>}
      <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} {label}</Button>
    </div>
  );
}

/** One segment's policy: mode pin, exploration share, share cap and its own kill switch. Versioned with a reason. */
export function SegmentPolicyForm({ segment, policy, mode }: { segment: string; policy: SegmentPolicy; mode: SegmentModeInfo }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveSegmentPolicy, undefined);
  const [pin, setPin] = useState(policy.pin && policy.pin.source === "admin" ? policy.pin.mode : "auto");
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Segment saved"); }, [state?.ok]);
  const pct = (v?: { value: number }) => (v ? String(Math.round(v.value * 1000) / 10) : "");
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3">
      <input type="hidden" name="segment" value={segment} />
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Mode" error={e.pin} hint={`Automatic is ${mode.auto === "performance" ? "performance" : "commission first"} now.`}>
          <select name="pin" value={pin} onChange={(x) => setPin(x.target.value as typeof pin)} className={field}>
            <option value="auto">Automatic</option>
            <option value="commission_first">Pin: commission first</option>
            <option value="performance">Pin: performance</option>
          </select>
        </L>
        <L label="Pin ends on" error={e.pin_until} hint="Empty: until you remove it.">
          <input type="date" name="pin_until" disabled={pin === "auto"} defaultValue={policy.pin?.until?.slice(0, 10) ?? ""} className={field} aria-invalid={Boolean(e.pin_until)} />
        </L>
        <L label="Exploration share (%)" error={e.exploration_share} hint="Empty: the engine's share.">
          <input name="exploration_share" inputMode="decimal" defaultValue={pct(policy.exploration_share)} className={field} aria-invalid={Boolean(e.exploration_share)} />
        </L>
        <L label="Share cap (%)" error={e.share_cap} hint="Empty: no cap. It overrides highest commission.">
          <input name="share_cap" inputMode="decimal" defaultValue={pct(policy.share_cap)} className={field} aria-invalid={Boolean(e.share_cap)} />
        </L>
      </div>
      <label className="flex items-start gap-2 text-[13px]">
        <input type="checkbox" name="killed" defaultChecked={mode.killed} className="mt-0.5 size-4 accent-[var(--primary)]" />
        <span><span className="font-medium text-fg">Kill switch for this segment</span><span className="block text-[12px] text-muted">Leads split between partners in the fixed shares from Engine settings.</span></span>
      </label>
      <L label="Reason" error={e.reason}><input name="reason" maxLength={300} placeholder="e.g. new partner, keep the commission rule for a month" className={field} aria-invalid={Boolean(e.reason)} /></L>
      <Footer error={state?.error} pending={pending} label="Save segment" />
    </form>
  );
}

/** A temporary ±10% weight on a partner's net commission per lead (performance mode), at most 14 days. */
export function PartnerWeightForm({ partners }: { partners: Pick<SegmentPartner, "partner_id" | "name" | "weight">[] }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(savePartnerWeight, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Partner weight saved"); }, [state?.ok]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="sm:col-span-2"><L label="Partner" error={e.partner_id}>
          <select name="partner_id" defaultValue="" className={field} aria-invalid={Boolean(e.partner_id)}>
            <option value="" disabled>Choose</option>
            {partners.map((p) => <option key={p.partner_id} value={p.partner_id}>{p.name}{p.weight ? ` (now ${Math.round(p.weight.weight * 100)}%)` : ""}</option>)}
          </select>
        </L></div>
        <L label="Weight (%)" error={e.weight} hint="90 to 110; empty removes it.">
          <input name="weight" inputMode="decimal" placeholder="105" className={field} aria-invalid={Boolean(e.weight)} />
        </L>
        <L label="For (days)" error={e.days}><input name="days" inputMode="numeric" defaultValue="7" className={field} aria-invalid={Boolean(e.days)} /></L>
      </div>
      <L label="Reason" error={e.reason}><input name="reason" maxLength={300} placeholder="e.g. new counsellor team, give them a week" className={field} aria-invalid={Boolean(e.reason)} /></L>
      <Footer error={state?.error} pending={pending} label="Save weight" />
    </form>
  );
}

/** The holdout and how performance scoring samples (engine_policy). */
export function PolicyForm({ policy, version }: { policy: EnginePolicy; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveEnginePolicy, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Policy saved"); }, [state?.ok]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="AI holdout (% of leads)" error={e.holdout_share} hint="These leads always use your settings, never an AI change, so the AI's value is measured.">
          <input name="holdout_share" inputMode="decimal" defaultValue={Math.round((policy.holdout_share ?? 0.1) * 1000) / 10} className={field} aria-invalid={Boolean(e.holdout_share)} />
        </L>
        <L label="Draws per decision" error={e.mc_draws} hint="Seeded samples that estimate each choice's probability (50–1000).">
          <input name="mc_draws" inputMode="numeric" defaultValue={policy.mc_draws ?? 200} className={field} aria-invalid={Boolean(e.mc_draws)} />
        </L>
        <L label="Young leads' weight (%)" error={e.leading_weight} hint="How much leads not yet matured count, through their stage (leading indicators).">
          <input name="leading_weight" inputMode="decimal" defaultValue={Math.round((policy.leading_weight ?? 0.5) * 1000) / 10} className={field} aria-invalid={Boolean(e.leading_weight)} />
        </L>
        <L label="Young leads count after (days)" error={e.leading_min_days}>
          <input name="leading_min_days" inputMode="numeric" defaultValue={policy.leading_min_days ?? 3} className={field} aria-invalid={Boolean(e.leading_min_days)} />
        </L>
      </div>
      <L label="Reason" error={e.reason} hint={`Saved as policy version ${version + 1}.`}>
        <input name="reason" maxLength={300} className={field} aria-invalid={Boolean(e.reason)} />
      </L>
      <Footer error={state?.error} pending={pending} label="Save policy" />
    </form>
  );
}

export function RefreshStatsButton() {
  const [busy, start] = useTransition();
  return (
    <Button size="sm" variant="secondary" disabled={busy} onClick={() => start(async () => {
      const err = await refreshStats();
      if (err) toast.error(err); else toast.success("Statistics refreshed");
    })}>
      {busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />} Refresh now
    </Button>
  );
}
