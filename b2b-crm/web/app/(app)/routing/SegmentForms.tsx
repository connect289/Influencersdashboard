"use client";
import { useEffect, useTransition } from "react";
import Link from "next/link";
import { LoaderCircle, RefreshCw, Scale } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { useFormAction } from "@/components/ui/useFormAction";
import { STAGE_LABEL } from "@/lib/routing";
import type { EnginePolicy, SegmentModeInfo } from "@/lib/segments";
import { refreshStats, saveEnginePolicy, type FormState } from "./actions";

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

/** A segment's policy, read-only (Addendum 3, D24): pins, share caps, per-segment exploration, the kill toggle and partner
 *  weights were retired; the Admin's only override tool is a routing rule. */
export function SegmentPolicySummary({ mode, rulesActive }: { mode: SegmentModeInfo; rulesActive?: number | null }) {
  return (
    <div className="space-y-3 text-[13px]">
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5">
        <dt className="text-muted">Stage now</dt>
        <dd className="text-fg">Stage {mode.stage}: {STAGE_LABEL[mode.stage]}</dd>
        <dt className="text-muted">Stored stage</dt>
        <dd className="text-fg">{mode.auto_stage ? `Stage ${mode.auto_stage}` : "not yet computed"}<span className="text-subtle"> (from the hourly statistics; the gates are the rulebook's fixed numbers)</span></dd>
        <dt className="text-muted">Parameters</dt>
        <dd className="text-fg">{mode.variant === "ai" ? <Badge tone="info" className="font-normal">AI-steered</Badge> : "the Admin's settings"}<span className="text-subtle"> · holdout leads always use the Admin&apos;s settings</span></dd>
        <dt className="text-muted">Overrides</dt>
        <dd className="text-fg">
          {rulesActive == null
            ? <Link href="/routing?tab=rules" className="inline-flex items-center gap-1 text-info hover:underline"><Scale className="size-3.5" /> Routing rules on this course, level, mode or university</Link>
            : rulesActive > 0 ? <Link href="/routing?tab=rules" className="inline-flex items-center gap-1 text-info hover:underline"><Scale className="size-3.5" /> {rulesActive} active routing rule{rulesActive === 1 ? "" : "s"}</Link> : "none"}
        </dd>
      </dl>
      <p className="text-[12.5px] text-muted">
        Addendum 3 removed segment pins, share caps, per-segment exploration, the kill toggle and partner weights. To steer this segment,
        add a <Link href="/routing?tab=rules" className="text-info hover:underline">routing rule</Link> (always send to, only consider, never send to, send to B2C) on its course,
        level, mode or university, or pause the partner. The AI tunes only the effort weights and bounds, the SLA floor and P(enrol)&apos;s half-life and prior, inside your ranges.
      </p>
    </div>
  );
}

/** The AI holdout share (engine_policy): the only policy value the Admin can change (C29, C63). */
export function PolicyForm({ policy, version }: { policy: EnginePolicy; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveEnginePolicy, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Policy saved"); }, [state?.ok]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="AI holdout (% of leads, 0–50)" error={e.holdout_share} hint="These leads always use your settings, never an AI change, so the AI's value can be measured. Nothing else of the routing policy is editable: Addendum 3 fixed the lane, the limits and the stage gates.">
          <input name="holdout_share" inputMode="decimal" defaultValue={String(Math.round((policy.holdout_share ?? 0.1) * 1000) / 10)} className={field} aria-invalid={Boolean(e.holdout_share)} />
        </L>
        <L label="Reason" error={e.reason} hint={`Saved as policy version ${version + 1}.`}>
          <input name="reason" maxLength={300} placeholder="e.g. more holdout while the AI is new" className={field} aria-invalid={Boolean(e.reason)} />
        </L>
      </div>
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
