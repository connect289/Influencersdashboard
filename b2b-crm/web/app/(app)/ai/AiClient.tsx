"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { Check, LoaderCircle, MessageSquareText, Play, RotateCcw, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { useFormAction } from "@/components/ui/useFormAction";
import { periodBounds } from "@/lib/ai/ask";
import { drillHref, PERIOD_LABEL, type Period } from "@/lib/analytics";
import {
  AI_MODEL_ROLES, editable, PRICE_PARTS, rupees, RUN_KIND_LABEL, RUN_NOW_KINDS,
  type AiModelRole, type AiOverview, type AiSettings, type Change, type MlModel, type MlOverview, type RunNowKind,
} from "@/lib/ai/labels";
import {
  askCrm, type AskAnswer, decideRecommendation, rollbackModel, rollbackRecommendation, runNow, saveAiSettings, saveMlSettings, setModelStatus, trainModel, type FormState,
} from "./actions";

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
  const [kind, setKind] = useState<RunNowKind>("optimise");
  const [open, setOpen] = useState(false);
  return (
    <div className="flex items-center gap-2">
      <select value={kind} onChange={(e) => setKind(e.target.value as RunNowKind)} className="h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px]" aria-label="Kind of run">
        {RUN_NOW_KINDS.map((k) => <option key={k} value={k}>{RUN_KIND_LABEL[k]}</option>)}
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

const ROLE_LABEL: Record<AiModelRole, string> = { regular: "Regular passes", deep: "Deep review and weekly report", quick: "Light checks" };
const PRICE_LABEL: Record<(typeof PRICE_PARTS)[number], string> = { in: "Input", out: "Output", cache_read: "Cache read", cache_write: "Cache write" };

export function AiSettingsForm({ s, version, gate }: { s: AiSettings; version: number; gate?: AiOverview["autopilot_gate"] }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveAiSettings, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("AI settings saved"); }, [state?.ok]);
  // Autopilot can be switched on only once the gate is open (the database checks it too); absent gate: older database
  const locked = !!gate && !gate.open && s.mode !== "autopilot";
  // the price rows follow the model names as typed, so a new model never inherits the old model's prices
  const [models, setModels] = useState<Record<AiModelRole, string>>({ ...s.models });
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-4">
      <label className="flex items-start gap-2 text-[13px]">
        <input type="checkbox" name="enabled" defaultChecked={s.enabled} className="mt-0.5 size-4 accent-[var(--primary)]" />
        <span><span className="font-medium text-fg">Optimiser on</span>
          <span className="block text-[12px] text-muted">Scheduled runs and recommendations. Ask the CRM works whenever the API key is set.</span></span>
      </label>
      <fieldset className="space-y-2 rounded-lg border border-border p-3 text-[13px]">
        <legend className="px-1 text-[12px] text-muted">Mode</legend>
        <label className="flex items-start gap-2"><input type="radio" name="mode" value="advisory" defaultChecked={s.mode !== "autopilot"} className="mt-0.5 accent-[var(--primary)]" />
          <span><span className="font-medium text-fg">Advisory</span><span className="block text-[12px] text-muted">Every change waits for your approval.</span></span></label>
        <label className={`flex items-start gap-2${locked ? " opacity-70" : ""}`}><input type="radio" name="mode" value="autopilot" defaultChecked={s.mode === "autopilot"} disabled={locked} className="mt-0.5 accent-[var(--primary)]" />
          <span><span className="font-medium text-fg">Autopilot (bounded)</span><span className="block text-[12px] text-muted">A setting change inside the bounds applies by itself when its simulation is confident; drafts and everything else still wait for you. Each one is reviewed after 7 days against the holdout and rolled back automatically if it did worse.</span>
            {locked && gate && <span className="mt-1 block text-[12px] text-muted">Locked until AI-steered leads beat the holdout over 4 weeks of matured leads (now {gate.steered.leads} steered at {rupees(gate.steered.ncpl)} vs {gate.holdout.leads} holdout at {rupees(gate.holdout.ncpl)}).</span>}</span></label>
        <div className="grid gap-3 pl-6 sm:grid-cols-2">
          <L label="Minimum simulated gain (%)" error={e.min_gain_pct}><input name="min_gain_pct" inputMode="decimal" defaultValue={s.autopilot?.min_gain_pct ?? 3} className={field} /></L>
          <L label="At most per day" error={e.max_per_day}><input name="max_per_day" inputMode="numeric" defaultValue={s.autopilot?.max_per_day ?? 3} className={field} /></L>
        </div>
      </fieldset>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Daily budget (US$)" error={e.daily_budget_usd} hint="Runs stop for the day once it is spent.">
          <input name="daily_budget_usd" inputMode="decimal" defaultValue={s.daily_budget_usd} className={field} aria-invalid={Boolean(e.daily_budget_usd)} />
        </L>
        <L label="Worker address" error={e.worker_url} hint="This CRM's https:// address; the database wakes /v1/ai/tick there.">
          <input name="worker_url" defaultValue={s.worker_url ?? ""} placeholder="https://b2b.eduwit.in" className={field} aria-invalid={Boolean(e.worker_url)} />
        </L>
        {AI_MODEL_ROLES.map((role) => (
          <L key={role} label={`Model: ${ROLE_LABEL[role].toLowerCase()}`} error={e[`model_${role}`]}>
            <input name={`model_${role}`} defaultValue={s.models[role]} onChange={(ev) => { const v = ev.target.value; setModels((m) => ({ ...m, [role]: v })); }}
              className={field} aria-invalid={Boolean(e[`model_${role}`])} />
          </L>
        ))}
      </div>
      <fieldset className="space-y-3 rounded-lg border border-border p-3 text-[13px]">
        <legend className="px-1 text-[12px] text-muted">Prices (US$ per million tokens)</legend>
        <p className="text-[12px] text-muted">For the model named above, from Anthropic&apos;s price list. The cost log and the daily budget use them, and every model in use needs one. Cache read and cache write are optional.</p>
        {AI_MODEL_ROLES.map((role) => {
          const model = (models[role] ?? "").trim();
          const pr = s.prices_per_mtok?.[model];
          return (
            <div key={`${role}:${model}`} className="space-y-1.5">
              <p className="text-[12px]"><span className="font-medium text-fg">{ROLE_LABEL[role]}</span>{model && <span className="ml-1.5 break-all font-mono text-[11.5px] text-subtle">{model}</span>}</p>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {PRICE_PARTS.map((part) => {
                  const k = `price_${role}_${part}`;
                  return (
                    <L key={part} label={PRICE_LABEL[part]} error={e[k]}>
                      <input name={k} inputMode="decimal" defaultValue={pr?.[part] ?? ""} className={field} aria-invalid={Boolean(e[k])} />
                    </L>
                  );
                })}
              </div>
            </div>
          );
        })}
      </fieldset>
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
      {m?.status === "champion" && <Button size="sm" variant="secondary" onClick={() => open({ title: "Roll back the champion", label: "Roll back", tone: "danger", body: "The champion is retired and the champion it replaced, if any, comes back. Without one, the engine uses segment P̂.", run: rollbackModel })}><RotateCcw className="size-3.5" /> Roll back</Button>}
      {m && ["shadow", "challenger"].includes(m.status) && <Button size="sm" variant="secondary" onClick={() => open({ title: `Retire ${m.version}`, label: "Retire", tone: "danger", body: "It stops scoring and deciding.", run: (r) => setModelStatus(m.id, "retired", r) })}>Retire</Button>}
      {m?.status === "training" && <Button size="sm" variant="secondary" onClick={() => open({ title: `Cancel training ${m.version}`, label: "Cancel training", tone: "danger", body: "The queued training run is cancelled; you can queue a new one.", run: (r) => setModelStatus(m.id, "retired", r) })}><X className="size-3.5" /> Cancel training</Button>}
      {dialog && (
        <ConfirmDialog open onClose={() => setDialog(null)} title={dialog.title} confirmLabel={dialog.label} tone={dialog.tone} reason={{ label: "Why" }}
          onConfirm={async (r) => { const err = await dialog.run(r); if (!err) toast.success("Done"); return err; }}>
          <p className="text-[13px] text-muted">{dialog.body}</p>
        </ConfirmDialog>
      )}
    </div>
  );
}

/** The model registry's thresholds and the nightly switch (versioned, like the AI settings). */
export function MlSettingsForm({ s, version }: { s: MlOverview["settings"]; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveMlSettings, undefined);
  const e = state?.errors ?? {};
  useEffect(() => { if (state?.ok) toast.success("Model settings saved"); }, [state?.ok]);
  return (
    <form onSubmit={onSubmit} noValidate className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Matured outcomes to train" error={e.min_outcomes} hint="100 to 100000">
          <input name="min_outcomes" inputMode="numeric" defaultValue={s.min_outcomes} className={field} aria-invalid={Boolean(e.min_outcomes)} />
        </L>
        <L label="Challenger share (%)" error={e.challenger_pct} hint="Of performance-mode leads, 1 to 50">
          <input name="challenger_pct" inputMode="decimal" defaultValue={Math.round(s.challenger_share * 1000) / 10} className={field} aria-invalid={Boolean(e.challenger_pct)} />
        </L>
        <L label="Fall back above calibration error" error={e.ece_fallback} hint="0.01 to 0.30">
          <input name="ece_fallback" inputMode="decimal" defaultValue={s.ece_fallback} className={field} aria-invalid={Boolean(e.ece_fallback)} />
        </L>
        <L label="Nightly training hour (IST)" error={e.train_hour_ist} hint="0 to 23">
          <input name="train_hour_ist" inputMode="numeric" defaultValue={s.train_hour_ist} className={field} aria-invalid={Boolean(e.train_hour_ist)} />
        </L>
      </div>
      <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name="auto_train" defaultChecked={s.auto_train} className="size-4 accent-[var(--primary)]" /> Train a new model nightly</label>
      <L label="Reason" error={e.reason} hint={`Saved as version ${version + 1}.`}><input name="reason" maxLength={500} className={field} aria-invalid={Boolean(e.reason)} /></L>
      <div className="flex items-center justify-end gap-3">
        {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
        <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save model settings</Button>
      </div>
    </form>
  );
}

/** Ask the CRM: answers come only from the metric layer, with their sources; unverifiable answers are not shown. */
export function AskPanel() {
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<AskAnswer | null>(null);
  const examples = ["How many leads went to each partner this month?", "Which partner has the best SLA compliance in the last 30 days?", "What is the duplicate rate by partner this quarter?"];
  const submit = async (text: string) => {
    if (!text.trim()) return;
    setBusy(true); setRes(null);
    try { setRes(await askCrm(text)); } finally { setBusy(false); }
  };
  return (
    <div className="space-y-4">
      <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); void submit(q); }}>
        <input value={q} onChange={(e) => setQ(e.target.value)} maxLength={500} placeholder="Ask about leads, partners, SLAs, commission…" className={`${field} flex-1`} aria-label="Question" />
        <Button type="submit" size="sm" disabled={busy || q.trim().length < 5}>{busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <MessageSquareText className="size-3.5" />} Ask</Button>
      </form>
      <div className="flex flex-wrap gap-2">
        {examples.map((x) => <button key={x} type="button" onClick={() => { setQ(x); void submit(x); }} className="rounded-full border border-border px-3 py-1 text-[12px] text-muted hover:text-fg">{x}</button>)}
      </div>
      {busy && <p className="text-[13px] text-muted">Reading the metrics…</p>}
      {res && !res.ok && <p role="alert" className="text-[13px] text-danger">{res.error}</p>}
      {res && res.ok && (
        <div className="space-y-2 rounded-lg border border-border bg-surface-2/50 p-4 text-[13px]">
          {res.answer ? <p className="whitespace-pre-line text-fg">{res.answer}</p>
            : <p className="text-warning">The answer contained numbers that could not be traced to the data ({res.unverified.join(", ")}), so it is not shown. Try asking more specifically.</p>}
          {res.sources.length > 0 && (
            <p className="text-[12px] text-subtle">Sources:{" "}
              {res.sources.map((s, i) => {
                const { from, to } = periodBounds(s.period);
                return <span key={i}>{i > 0 && " · "}<Link className="text-info hover:underline" href={drillHref(s.metric, s.filters ?? {}, from, to, s.period)}>{s.metric}{s.dims?.length ? ` by ${s.dims.join(", ")}` : ""}{s.period ? ` (${PERIOD_LABEL[s.period as Period] ?? s.period})` : ""}</Link></span>;
              })}
            </p>
          )}
          <p className="text-[11.5px] text-subtle">Cost ${res.cost_usd.toFixed(4)}</p>
        </div>
      )}
    </div>
  );
}
