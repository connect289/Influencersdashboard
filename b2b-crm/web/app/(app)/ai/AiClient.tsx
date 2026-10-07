"use client";
import { useEffect, useState } from "react";
import { Check, LoaderCircle, Play, RotateCcw, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { useFormAction } from "@/components/ui/useFormAction";
import { editable, RUN_KIND_LABEL, type AiSettings, type Change, type MlModel } from "@/lib/ai/labels";
import { decideRecommendation, rollbackModel, rollbackRecommendation, runNow, saveAiSettings, setModelStatus, trainModel, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

/** Approve (optionally with an edited value), reject with a reason. */
export function DecideButtons({ id, change, current }: { id: number; change: Change | null; current: string }) {
  const [dialog, setDialog] = useState<"approve" | "reject" | null>(null);
  const [typed, setTyped] = useState("");
  const canEdit = editable(change);
  return (
    <div className="flex flex-wrap gap-2">
      <Button size="sm" onClick={() => { setTyped(""); setDialog("approve"); }}><Check className="size-3.5" /> Approve{canEdit ? " or edit" : ""}</Button>
      <Button size="sm" variant="secondary" onClick={() => setDialog("reject")}><X className="size-3.5" /> Reject</Button>
      <ConfirmDialog open={dialog === "approve"} onClose={() => setDialog(null)} title="Approve this recommendation" confirmLabel="Approve and apply"
        reason={{ label: "Note for the change log", placeholder: "e.g. agreed, review in a week" }}
        onConfirm={async (note) => {
          const err = await decideRecommendation(id, "approve", note, change, canEdit ? typed : undefined);
          if (!err) toast.success("Applied. The change log keeps the previous value for rollback.");
          return err;
        }}>
        <p className="text-[13px] text-muted">It is applied now and versioned with this recommendation and your name. Holdout leads never use it.</p>
        {canEdit && (
          <label className="mt-3 block space-y-1">
            <span className="text-[12px] text-muted">Edit the value (optional; now {current})</span>
            <input value={typed} onChange={(e) => setTyped(e.target.value)} inputMode="decimal" placeholder={change?.lever === "maturity_days" || change?.lever === "half_life_days" || change?.lever === "prior_weight" ? "e.g. 45" : "e.g. 15 (%)"} className={field} />
          </label>
        )}
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "reject"} onClose={() => setDialog(null)} title="Reject this recommendation" confirmLabel="Reject" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. the partner is changing its team anyway" }}
        onConfirm={async (note) => {
          const err = await decideRecommendation(id, "reject", note, null);
          if (!err) toast.success("Rejected");
          return err;
        }} />
    </div>
  );
}

export function RollbackRecommendation({ id }: { id: number }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}><RotateCcw className="size-3.5" /> Roll back</Button>
      <ConfirmDialog open={open} onClose={() => setOpen(false)} title="Roll back this change" confirmLabel="Roll back" tone="danger"
        reason={{ label: "Why" }}
        onConfirm={async (r) => { const err = await rollbackRecommendation(id, r); if (!err) toast.success("Rolled back to the previous value"); return err; }}>
        <p className="text-[13px] text-muted">The setting goes back to what it was before this recommendation was applied (a new version, with your reason).</p>
      </ConfirmDialog>
    </>
  );
}

export function RunNow({ enabled }: { enabled: boolean }) {
  const [kind, setKind] = useState<keyof typeof RUN_KIND_LABEL>("optimise");
  const [open, setOpen] = useState(false);
  return (
    <div className="flex items-center gap-2">
      <select value={kind} onChange={(e) => setKind(e.target.value)} className="h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px]" aria-label="Kind of run">
        {Object.entries(RUN_KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
      </select>
      <Button size="sm" variant="secondary" disabled={!enabled} onClick={() => setOpen(true)} title={enabled ? undefined : "Switch the optimiser on in AI settings first"}>
        <Play className="size-3.5" /> Run now
      </Button>
      <ConfirmDialog open={open} onClose={() => setOpen(false)} title={`Run: ${RUN_KIND_LABEL[kind]}`} confirmLabel="Queue the run"
        reason={{ label: "Why now", placeholder: "e.g. new partner went live" }}
        onConfirm={async (r) => { const err = await runNow(kind, r); if (!err) toast.success("Queued: the worker picks it up within a minute"); return err; }}>
        <p className="text-[13px] text-muted">It counts toward the daily budget. Results arrive in the inbox.</p>
      </ConfirmDialog>
    </div>
  );
}

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

export function AiSettingsForm({ s, version }: { s: AiSettings; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveAiSettings, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("AI settings saved"); }, [state?.ok]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-4">
      <label className="flex items-start gap-2 text-[13px]">
        <input type="checkbox" name="enabled" defaultChecked={s.enabled} className="mt-0.5 size-4 accent-[var(--primary)]" />
        <span><span className="font-medium text-fg">Optimiser on</span>
          <span className="block text-[12px] text-muted">Advisory: Claude recommends; nothing changes until you approve. Autopilot is not available yet.</span></span>
      </label>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Daily budget (US$)" error={e.daily_budget_usd} hint="Runs stop for the day once it is spent.">
          <input name="daily_budget_usd" inputMode="decimal" defaultValue={s.daily_budget_usd} className={field} aria-invalid={Boolean(e.daily_budget_usd)} />
        </L>
        <L label="Worker address" error={e.worker_url} hint="This CRM's https:// address; the database wakes /v1/ai/tick there.">
          <input name="worker_url" defaultValue={s.worker_url ?? ""} placeholder="https://b2b.eduwit.in" className={field} aria-invalid={Boolean(e.worker_url)} />
        </L>
        <L label="Model: regular passes" error={e.model_regular}><input name="model_regular" defaultValue={s.models.regular} className={field} /></L>
        <L label="Model: deep review and weekly report" error={e.model_deep}><input name="model_deep" defaultValue={s.models.deep} className={field} /></L>
        <L label="Model: light checks" error={e.model_quick}><input name="model_quick" defaultValue={s.models.quick} className={field} /></L>
      </div>
      <fieldset className="space-y-1.5 text-[13px]">
        <legend className="mb-1 text-[12px] text-muted">When it runs</legend>
        <label className="flex items-center gap-2"><input type="checkbox" name="light" defaultChecked={s.schedules.light} className="size-4 accent-[var(--primary)]" /> Light check every 15 minutes, only when new alerts arrived</label>
        <label className="flex items-center gap-2"><input type="checkbox" name="hourly" defaultChecked={s.schedules.hourly} className="size-4 accent-[var(--primary)]" /> Hourly optimisation, only when decisions or outcomes changed</label>
        <label className="flex items-center gap-2"><input type="checkbox" name="nightly" defaultChecked={s.schedules.nightly} className="size-4 accent-[var(--primary)]" /> Nightly deep review</label>
        <label className="flex items-center gap-2"><input type="checkbox" name="weekly" defaultChecked={s.schedules.weekly} className="size-4 accent-[var(--primary)]" /> Weekly partner report (Monday morning)</label>
      </fieldset>
      <L label="Reason" error={e.reason} hint={`Saved as version ${version + 1}.`}><input name="reason" maxLength={300} className={field} aria-invalid={Boolean(e.reason)} /></L>
      <div className="flex items-center justify-end gap-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save settings</Button>
      </div>
    </form>
  );
}

/** Train now, promote along shadow → challenger → champion, retire, and the champion's one-click rollback. */
export function ModelActions({ m }: { m?: MlModel }) {
  const [dialog, setDialog] = useState<null | { title: string; label: string; tone?: "danger"; run: (r: string) => Promise<string | void>; body: string }>(null);
  const open = (d: NonNullable<typeof dialog>) => setDialog(d);
  return (
    <div className="flex flex-wrap gap-2">
      {!m && <Button size="sm" variant="secondary" onClick={() => open({ title: "Train a new model", label: "Queue training", body: "It trains inside the database within 10 minutes and starts in shadow (scores, never decides).", run: trainModel })}>Train now</Button>}
      {m?.status === "shadow" && <Button size="sm" disabled={!m.gate.passed} title={m.gate.passed ? undefined : "The activation gate has not passed"}
        onClick={() => open({ title: `Make ${m.version} the challenger`, label: "Promote", body: "It will decide its share of performance-mode leads (holdout leads never).", run: (r) => setModelStatus(m.id, "challenger", r) })}>Make challenger</Button>}
      {m?.status === "challenger" && <Button size="sm" disabled={!m.champion_check?.ready} title={m.champion_check?.ready ? undefined : "Not yet better with confidence"}
        onClick={() => open({ title: `Make ${m.version} the champion`, label: "Promote", body: "It will decide every performance-mode lead outside the holdout.", run: (r) => setModelStatus(m.id, "champion", r) })}>Make champion</Button>}
      {m?.status === "challenger" && <Button size="sm" variant="secondary" onClick={() => open({ title: `Send ${m.version} back to shadow`, label: "Back to shadow", body: "It stops deciding and only scores.", run: (r) => setModelStatus(m.id, "shadow", r) })}>Back to shadow</Button>}
      {m?.status === "champion" && <Button size="sm" variant="secondary" onClick={() => open({ title: "Roll back the champion", label: "Roll back", tone: "danger", body: "The champion is retired and the previous champion, if any, comes back. Without one, the engine uses segment P̂.", run: rollbackModel })}><RotateCcw className="size-3.5" /> Roll back</Button>}
      {m && ["shadow", "challenger"].includes(m.status) && <Button size="sm" variant="secondary" onClick={() => open({ title: `Retire ${m.version}`, label: "Retire", tone: "danger", body: "It stops scoring and deciding.", run: (r) => setModelStatus(m.id, "retired", r) })}>Retire</Button>}
      {dialog && (
        <ConfirmDialog open onClose={() => setDialog(null)} title={dialog.title} confirmLabel={dialog.label} tone={dialog.tone} reason={{ label: "Why" }}
          onConfirm={async (r) => { const err = await dialog.run(r); if (!err) toast.success("Done"); return err; }}>
          <p className="text-[13px] text-muted">{dialog.body}</p>
        </ConfirmDialog>
      )}
    </div>
  );
}
