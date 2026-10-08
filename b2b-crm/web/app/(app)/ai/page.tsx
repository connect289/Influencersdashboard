import type { Metadata } from "next";
import Link from "next/link";
import { BrainCircuit, CircleCheck, CircleDashed, FlaskConical, Inbox, Scale, SlidersHorizontal, Sparkles, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { aiOverview, askHistory, mlOverview } from "@/lib/ai/data";
import {
  ADMIN_LEVER_RANGES, AI_LEVER_RANGES, autopilotRuleText, changeLine, evidenceHref, expiresText, fromToText, LEVER_LABEL, leverRangeText, leverValueText,
  MODEL_STATUS_LABEL, realisedText, REC_STATUS_LABEL, reviewText, RUN_KIND_LABEL, rupees, SETTING_LEVERS, setupSteps, signedRupees, simulationText, supportText,
  TRIGGER_LABEL, type AiOverview, type MlModel, type MlOverview, type Recommendation,
} from "@/lib/ai/labels";
import { formatDateTime, relativeTime } from "@/lib/format";
import { routingOverview } from "@/lib/routing-data";
import { AiSettingsForm, AskPanel, DecideButtons, MlSettingsForm, ModelActions, RollbackRecommendation, RunNow } from "./AiClient";

export const metadata: Metadata = { title: "AI Optimiser" };
// Ask the CRM runs as a server action of this page and stops itself at 240 s (lib/ai/ask.ts)
export const maxDuration = 300;

const TABS = [
  { id: "inbox", label: "Inbox" },
  { id: "ask", label: "Ask the CRM" },
  { id: "uplift", label: "AI vs holdout" },
  { id: "runs", label: "Runs" },
  { id: "models", label: "Model registry" },
  { id: "settings", label: "Settings" },
] as const;
type Tab = (typeof TABS)[number]["id"];
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const usd = (v: number) => `$${v.toFixed(v < 1 ? 3 : 2)}`;
const pct = (v: number | null | undefined, d = 1) => (v == null ? "—" : `${(v * 100).toFixed(d)}%`);
const day = (iso: string) => new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });

/** The proposed value in the Admin's units (a percent only for the SLA floor; days; leads), for the edit field's "now …" (C100). */
function currentValue(r: Recommendation): string {
  return r.change ? leverValueText(r.change.lever, r.change.value) : "—";
}

function RecCard({ r, names }: { r: Recommendation; names: Record<string, string> }) {
  const open = r.status === "open";
  const fromTo = fromToText(r);
  const support = supportText(r.simulation);
  const win = r.simulation?.window;
  const realised = realisedText(r);
  const review = reviewText(r.check_result);
  return (
    <li className="space-y-2.5 px-5 py-4">
      <div className="flex flex-wrap items-start gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-[14px] font-semibold text-fg">{r.title}</p>
          <p className="text-[12px] text-subtle">
            Run <Link href={`/ai/runs/${r.run_id}`} className="text-info hover:underline">#{r.run_id}</Link>
            {r.run_kind && <> · {RUN_KIND_LABEL[r.run_kind] ?? r.run_kind}</>} · {relativeTime(r.created_at)}
            {open && <> · {expiresText(r.expires_at)}</>}
          </p>
        </div>
        {!open && <Badge tone={r.status === "applied" ? "success" : r.status === "rolled_back" ? "warning" : "neutral"}>{REC_STATUS_LABEL[r.status]}</Badge>}
        {r.kind !== "setting_change" && <Badge tone={r.kind === "insight" ? "neutral" : "info"}>{r.kind === "insight" ? "Observation" : r.kind === "rule_draft" ? "Rule draft" : "Pause draft"}</Badge>}
      </div>
      {/* the value that went live (edited by the Admin when so), with the proposal in brackets (C42) */}
      <p className="text-[13px] text-fg"><Scale className="mr-1 inline size-3.5 text-subtle" /><span className="font-medium">{changeLine(r, names)}</span></p>
      {fromTo && <p className="text-[12.5px] text-muted">Setting {fromTo}</p>}
      <p className="whitespace-pre-line text-[13px] text-muted">{r.rationale}</p>
      {r.kind === "setting_change" && (
        <div className={cn("space-y-0.5 rounded-lg border px-3 py-2 text-[12.5px]", r.simulation?.enough ? "border-info/25 bg-info-bg text-info" : "border-border bg-surface-2/60 text-muted")}>
          <p><FlaskConical className="mr-1 inline size-3.5" /> Simulated on logged decisions: {simulationText(r.simulation)}</p>
          {(support || win) && (
            <p className="pl-5 text-[12px] opacity-90">
              {support}{support && win && " · "}{win && <>decisions routed {day(win.from)} to {day(win.to)}</>}
            </p>
          )}
        </div>
      )}
      {r.risk && <p className="text-[12.5px] text-warning"><TriangleAlert className="mr-1 inline size-3.5" /> {r.risk}</p>}
      {r.evidence.length > 0 && (
        <ul className="flex flex-wrap gap-1.5" aria-label="Evidence">
          {r.evidence.slice(0, 8).map((e, i) => (
            <li key={i}>
              <Link href={evidenceHref(r, e)} title="Open the run at this tool's output"
                className="block rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[11.5px] text-muted hover:border-ring hover:text-fg">
                {typeof e?.tool === "string" && <span className="text-subtle">{e.tool}: </span>}{typeof e?.metric === "string" ? e.metric : null} {e?.value !== undefined && e?.value !== null && <span className="text-fg">{typeof e.value === "object" ? "…" : String(e.value)}</span>}
              </Link>
            </li>
          ))}
        </ul>
      )}
      {open && <DecideButtons id={r.id} change={r.change} current={currentValue(r)} />}
      {!open && r.decided_by && (
        <p className="text-[12px] text-subtle">{REC_STATUS_LABEL[r.status]} by {r.decided_by} {r.decided_at && relativeTime(r.decided_at)}
          {r.decision_note && <> · “{r.decision_note}”</>}{r.applied?.edited && " · value edited"}{r.applied?.version && <> · engine policy v{r.applied.version}</>}
          {r.check_result?.superseded_by && <> · superseded by #{r.check_result.superseded_by}</>}</p>
      )}
      {review && <p className={cn("text-[12px]", r.check_result?.verdict === "worse" ? "text-danger" : "text-muted")}>{review}</p>}
      {realised && <p className="text-[12px] text-muted">{realised}</p>}
      {r.status === "applied" && r.kind === "setting_change" && <RollbackRecommendation id={r.id} />}
    </li>
  );
}

function Inbox_({ o, names }: { o: AiOverview; names: Record<string, string> }) {
  const steps = setupSteps(o);
  const ready = steps.every((s) => s.done);
  const autopilot = o.settings.mode === "autopilot";
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)]">
      <div className="min-w-0 space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Recommendations"
            description={`${autopilot
              ? "Autopilot: a setting change applies by itself once its simulation clears the gain, interval and support bar (see Settings); drafts and everything else wait here."
              : "Advisory: Claude proposes, you approve, edit or reject."} Every number was checked against the data it read; each change is replayed on logged decisions first, with the share of decisions the log can speak for (support).`} />
          <div className="border-b border-border px-5 pb-4"><RunNow enabled={o.settings.enabled} /></div>
          {o.open.length === 0
            ? <EmptyState icon={Inbox} title="Nothing waiting">{o.settings.enabled ? "New recommendations appear after the next run." : "Recommendations appear once the optimiser is set up and on."}</EmptyState>
            : <ul className="divide-y divide-border">{o.open.map((r) => <RecCard key={r.id} r={r} names={names} />)}</ul>}
        </Card>
        <Card id="change-log" className="min-w-0 scroll-mt-20">
          <CardHeader title="Change log" description="Decided recommendations: what went live (before → after), the 7-day review against the holdout, the realised effect once the leads have matured, and one-click rollback." />
          {o.decided.length === 0
            ? <EmptyState icon={CircleDashed} title="No decisions yet">Approved, rejected and expired recommendations are kept here.</EmptyState>
            : <ul className="divide-y divide-border">{o.decided.map((r) => <RecCard key={r.id} r={r} names={names} />)}</ul>}
        </Card>
      </div>
      <div className="min-w-0 space-y-6">
        {!ready && (
          <Card className="min-w-0">
            <CardHeader title="Set up" description="What is still needed before Claude can run. Nothing here costs anything until the optimiser is on." />
            <ul className="space-y-2 px-5 pb-4 text-[13px]">
              {steps.map((s) => (
                <li key={s.label} className="flex gap-2">
                  {s.done ? <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" />}
                  <span className={s.done ? "text-muted line-through" : "text-fg"}>{s.label}</span>
                </li>
              ))}
            </ul>
          </Card>
        )}
        <Card className="min-w-0">
          <CardHeader title="Spend" description={`Daily budget $${o.settings.daily_budget_usd}. Light checks and hourly passes run only when something changed.`} />
          <div className="grid grid-cols-2 gap-2 px-5 pb-4">
            <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">Today</p><p className="tabular text-xl font-semibold text-fg">{usd(o.spend.today_usd)}</p></div>
            <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">This month</p><p className="tabular text-xl font-semibold text-fg">{usd(o.spend.month_usd)}</p></div>
          </div>
        </Card>
        <UpliftCard u={o.uplift} holdout={o.holdout_share} />
      </div>
    </div>
  );
}

function UpliftCard({ u, holdout }: { u: AiOverview["uplift"]; holdout: number | null }) {
  const enough = u.steered.leads >= 30 && u.holdout.leads >= 30;
  const ci = u.diff_ci95;
  return (
    <Card className="min-w-0">
      <CardHeader title="AI-steered against holdout" description={`Realised net commission per lead once leads are ${u.maturity_days} days old (matured, fixed by Addendum 3). ${pct(holdout ?? 0.1, 0)} of leads are held out from every AI change and decided on your settings alone: they are the only measure of the AI's value.`} />
      <div className="grid grid-cols-2 gap-2 px-5 pb-3">
        <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">AI-steered</p>
          <p className="tabular text-xl font-semibold text-fg">{rupees(u.steered.ncpl)}</p><p className="text-[11.5px] text-subtle">{u.steered.leads} matured leads</p></div>
        <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">Holdout</p>
          <p className="tabular text-xl font-semibold text-fg">{rupees(u.holdout.ncpl)}</p><p className="text-[11.5px] text-subtle">{u.holdout.leads} matured leads</p></div>
      </div>
      <p className="px-5 pb-4 text-[12.5px] text-muted">
        {enough
          ? <>Uplift {u.uplift_pct != null ? `${u.uplift_pct >= 0 ? "+" : ""}${u.uplift_pct}%` : "—"} (z = {u.z}{Math.abs(u.z) >= 1.96 ? ", significant" : ", not yet significant"}).</>
          : "Not enough matured leads in both groups to compare yet (30 each). Until then the AI's value is unproven."}
        {ci && <> 95% interval {signedRupees(ci[0])} to {signedRupees(ci[1])} per lead{ci[0] > 0 ? ": the AI-steered leads earn more." : ci[1] < 0 ? ": the holdout earns more." : ": the difference could go either way."}</>}
      </p>
    </Card>
  );
}

function Uplift({ u, holdout }: { u: AiOverview["uplift"]; holdout: number | null }) {
  const max = Math.max(1, ...u.by_month.flatMap((m) => [m.steered ?? 0, m.holdout ?? 0]));
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)]">
      <UpliftCard u={u} holdout={holdout} />
      <Card className="min-w-0">
        <CardHeader title="By month of allocation" description="Net commission per matured lead. Bars: AI-steered (filled) and holdout (outline)." />
        {u.by_month.length === 0 ? <EmptyState icon={Scale} title="No matured leads yet">Months appear once leads are older than the maturity window ({u.maturity_days} days).</EmptyState> : (
          <ul className="space-y-3 px-5 pb-5">
            {u.by_month.map((m) => (
              <li key={m.month} className="grid grid-cols-[80px_minmax(0,1fr)] items-center gap-3 text-[12px]">
                <span className="text-muted">{new Date(m.month).toLocaleDateString("en-IN", { month: "short", year: "numeric" })}</span>
                <span className="space-y-1">
                  <span className="flex items-center gap-2"><span className="h-2 rounded bg-primary" style={{ width: `${((m.steered ?? 0) / max) * 100}%` }} /><span className="tabular text-fg">{rupees(m.steered)} · {m.steered_n}</span></span>
                  <span className="flex items-center gap-2"><span className="h-2 rounded border border-primary" style={{ width: `${((m.holdout ?? 0) / max) * 100}%` }} /><span className="tabular text-muted">{rupees(m.holdout)} · {m.holdout_n}</span></span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}

function Runs({ o }: { o: AiOverview }) {
  return (
    <Card className="min-w-0">
      <CardHeader title="Runs" description="Every run is logged with its trigger, model, tools called, tokens and cost. Open a run to read every tool output exactly as Claude received it." />
      <div className="border-b border-border px-5 pb-4"><RunNow enabled={o.settings.enabled} /></div>
      {o.runs.length === 0 ? <EmptyState icon={Sparkles} title="No runs yet">Runs appear once the optimiser is on.</EmptyState> : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-left text-[13px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2.5 font-medium">When</th><th scope="col" className="px-3 py-2.5 font-medium">Run</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Status</th><th scope="col" className="px-3 py-2.5 text-right font-medium">Tools</th>
                <th scope="col" className="px-3 py-2.5 text-right font-medium">Tokens in / out</th><th scope="col" className="px-5 py-2.5 text-right font-medium">Cost</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {o.runs.map((r) => (
                <tr key={r.id} className="align-top">
                  <td className="whitespace-nowrap px-5 py-2.5"><Link href={`/ai/runs/${r.id}`} className="text-info hover:underline" title={formatDateTime(r.created_at)}>{relativeTime(r.created_at)}</Link></td>
                  <td className="px-3 py-2.5"><span className="font-medium text-fg">{RUN_KIND_LABEL[r.kind] ?? r.kind}</span> <span className="text-[12px] text-subtle">· {TRIGGER_LABEL[r.trigger] ?? r.trigger} · {r.model}</span>
                    {r.summary && <p className="mt-0.5 line-clamp-2 text-[12px] text-muted">{r.summary}</p>}
                    {r.error && <p className="mt-0.5 text-[12px] text-danger">{r.error}</p>}</td>
                  <td className="px-3 py-2.5"><Badge tone={r.status === "done" ? "success" : r.status === "failed" || r.status === "rejected" ? "danger" : "neutral"}>{r.status}</Badge></td>
                  <td className="tabular px-3 py-2.5 text-right">{r.tools}</td>
                  <td className="tabular px-3 py-2.5 text-right text-muted">{r.tokens_in.toLocaleString("en-IN")} / {r.tokens_out.toLocaleString("en-IN")}</td>
                  <td className="tabular px-5 py-2.5 text-right">{usd(Number(r.cost_usd))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

/** Predicted against actual enrolment by decile (calibration plot), as plain SVG. */
function Calibration({ d }: { d: NonNullable<NonNullable<MlModel["metrics"]["holdout"]>["deciles"]> }) {
  const max = Math.max(0.05, ...d.flatMap((x) => [x.pred, x.actual]));
  const s = (v: number) => 140 - (v / max) * 130;
  const x = (v: number) => 10 + (v / max) * 130;
  return (
    <svg viewBox="0 0 150 150" className="h-36 w-36 shrink-0" role="img" aria-label="Calibration: predicted against actual by decile">
      <rect x="10" y="10" width="130" height="130" className="fill-none stroke-[var(--border)]" />
      <line x1="10" y1="140" x2="140" y2="10" className="stroke-[var(--subtle)]" strokeDasharray="3 3" />
      {d.map((p) => <circle key={p.bin} cx={x(p.pred)} cy={s(p.actual)} r="3" className="fill-[var(--primary)]"><title>{`bin ${p.bin}: predicted ${pct(p.pred)}, actual ${pct(p.actual)} (${p.n})`}</title></circle>)}
    </svg>
  );
}

/** The daily monitor's drift rows: the model's mean P (30 days against its holdout reference) and feature drift (PSI). */
function MonitorRows({ mon }: { mon: NonNullable<MlModel["metrics"]["monitor"]> }) {
  const psi = mon.feature_psi;
  const top = psi?.top?.[0];
  return (
    <>
      {(mon.mean_p_30d != null || mon.mean_p_reference != null) && <><dt className="text-muted">Mean prediction, 30 days / reference</dt><dd className="tabular text-right">{pct(mon.mean_p_30d, 2)} / {pct(mon.mean_p_reference, 2)}</dd></>}
      {psi && <><dt className="text-muted">Feature drift (max PSI)</dt>
        <dd className="tabular text-right">{psi.max}{top && <span className="text-muted"> · {top.feature} {pct(top.training, 0)} → {pct(top.recent, 0)}</span>}</dd></>}
    </>
  );
}

function Models({ ml }: { ml: MlOverview }) {
  const active = ml.models.filter((m) => ["shadow", "challenger", "champion", "training"].includes(m.status));
  const rest = ml.models.filter((m) => !active.includes(m));
  const ModelCard = ({ m }: { m: MlModel }) => (
    <li className="space-y-3 px-5 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-[13px] font-semibold text-fg">{m.version}</span>
        <Badge tone={m.status === "champion" ? "success" : m.status === "challenger" ? "info" : m.status === "failed" ? "danger" : "neutral"}>{MODEL_STATUS_LABEL[m.status]}</Badge>
        {m.metrics.monitor?.drift && <Badge tone="warning"><TriangleAlert className="size-3" /> Drifted from training</Badge>}
        <span className="text-[12px] text-subtle">{m.trained_at ? `trained ${relativeTime(m.trained_at)}` : `queued ${relativeTime(m.created_at)}`}{m.status_reason && m.status_reason !== "trained" && ` · ${m.status_reason}`}</span>
      </div>
      {m.error && <p className="text-[12.5px] text-danger">{m.error}</p>}
      {m.metrics.holdout && (
        <div className="flex flex-wrap gap-5">
          <Calibration d={m.metrics.holdout.deciles} />
          <dl className="grid min-w-[240px] flex-1 grid-cols-2 gap-x-4 gap-y-1 text-[12.5px]">
            <dt className="text-muted">Rows (train / holdout)</dt><dd className="tabular text-right">{m.trained_on.train} / {m.trained_on.valid}</dd>
            <dt className="text-muted">Log loss: model / segment P̂</dt><dd className="tabular text-right">{m.metrics.holdout.log_loss} / {m.metrics.baseline?.log_loss}</dd>
            <dt className="text-muted">Calibration error: model / P̂</dt><dd className="tabular text-right">{m.metrics.holdout.ece} / {m.metrics.baseline?.ece}</dd>
            <dt className="text-muted">Policy value (logged Stage C decisions{m.metrics.policy?.estimator === "doubly_robust" ? ", doubly robust" : ""})</dt>
            <dd className="tabular text-right">{rupees(m.metrics.policy?.model_value)} vs {rupees(m.metrics.policy?.logged_value)} ({m.metrics.policy?.decisions ?? 0}{m.metrics.policy?.support != null && `, support ${pct(m.metrics.policy.support, 0)}`})</dd>
            {m.metrics.monitor?.matured && <><dt className="text-muted">Live calibration error</dt><dd className="tabular text-right">{m.metrics.monitor.matured.ece} on {m.metrics.monitor.matured.n}</dd></>}
            {m.metrics.monitor && <MonitorRows mon={m.metrics.monitor} />}
            {m.champion_check && <><dt className="text-muted">Challenger vs rest (NCPL)</dt><dd className="tabular text-right">{rupees(m.champion_check.model_ncpl)} vs {rupees(m.champion_check.other_ncpl)} · z {m.champion_check.z}</dd></>}
          </dl>
        </div>
      )}
      {m.status !== "failed" && m.trained_at && (
        <ul className="flex flex-wrap gap-1.5 text-[11.5px]" aria-label="Activation gate">
          {([["Matured outcomes", m.gate.outcomes_ok, `${m.gate.outcomes}/${m.gate.min_outcomes}`], ["2+ partners", m.gate.partners_ok, String(m.gate.partners)],
             ["Beats segment P̂", m.gate.beats_baseline, ""], ["Offline policy value", m.gate.policy_value_ok, ""]] as const).map(([label, ok, v]) => (
            <li key={label} className={cn("rounded-md border px-2 py-0.5", ok ? "border-success/30 text-success" : "border-border text-muted")}>{ok ? "✓" : "✗"} {label}{v && ` ${v}`}</li>
          ))}
        </ul>
      )}
      <ModelActions m={m} />
    </li>
  );
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)]">
      <Card className="min-w-0">
        <CardHeader title="Per-lead model" description="Predicts each partner's chance of enrolling this student: the P(enrol) of Stage C. A shadow only scores; a challenger decides its share of Stage C leads; the champion decides the rest. Stage A and B never use it, and holdout leads never do." action={<ModelActions />} />
        {/* D29: every pre-Addendum 3 model was retired at the cutover; the next one trains on A3 decisions and starts in shadow */}
        <div className="px-5 pt-4">
          <Notice tone="info">
            Addendum 3 (7 Oct 2026) changed the lead features and Stage C scoring, so every model trained before it was retired and none decides now:
            segment P̂ (matured conversion, recency-weighted and shrunk to the prior) does. The next model trains on Addendum 3 decisions, nightly once
            enough leads have matured or on Train now, and starts in shadow: it scores but never decides until it passes the gate and you promote it.
          </Notice>
        </div>
        {active.length === 0 ? <EmptyState icon={BrainCircuit} title="No model in use">Segment P̂ decides Stage C. A model trains nightly once {ml.settings.min_outcomes} leads have matured, or press Train now.</EmptyState>
          : <ul className="divide-y divide-border">{active.map((m) => <ModelCard key={m.id} m={m} />)}</ul>}
        {rest.length > 0 && (
          <details className="border-t border-border">
            <summary className="cursor-pointer px-5 py-3 text-[13px] text-muted">Retired and failed ({rest.length})</summary>
            <ul className="divide-y divide-border">{rest.map((m) => <ModelCard key={m.id} m={m} />)}</ul>
          </details>
        )}
      </Card>
      <Card className="min-w-0">
        <CardHeader title="Training data" description={`Outcomes count once leads are ${ml.maturity_days} days old (matured, fixed by Addendum 3).`} />
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 px-5 pb-4 text-[12.5px]">
          <dt className="text-muted">Matured leads</dt><dd className="tabular text-right">{ml.data.matured} / {ml.settings.min_outcomes} needed</dd>
          <dt className="text-muted">of which enrolled</dt><dd className="tabular text-right">{ml.data.matured_enrolled}</dd>
          <dt className="text-muted">Partners</dt><dd className="tabular text-right">{ml.data.partners}</dd>
          <dt className="text-muted">Younger leads</dt><dd className="tabular text-right">{ml.data.young}</dd>
        </dl>
        <div className="border-t border-border px-5 py-4"><MlSettingsForm key={ml.settings_version} s={ml.settings} version={ml.settings_version} /></div>
        {Object.keys(ml.decided_30d).length > 0 && (
          <div className="border-t border-border px-5 py-3 text-[12.5px]">
            <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Stage B and C decisions, 30 days</p>
            <p className="mb-1.5 text-[11.5px] text-subtle">By the model logged on the decision; “segment P̂” means no model was in use.</p>
            {Object.entries(ml.decided_30d).map(([k, n]) => <p key={k} className="flex justify-between"><span className="text-muted">{k}</span><span className="tabular">{n}</span></p>)}
          </div>
        )}
      </Card>
    </div>
  );
}

/** The five levers and how far each side may move them (C113): the AI inside the Admin's current setting, the Admin inside Addendum 3's fixed ranges. */
function LeverRanges() {
  return (
    <Card className="min-w-0">
      <CardHeader title="What the AI may change" description="Five levers of the routing engine, all stored as versioned settings. Everything else (stages, the 60-day maturity, the 0.2 exploration lane, limits, rules, consent, rates, switches) is out of reach." />
      <div className="overflow-x-auto">
        <table className="w-full min-w-[520px] text-left text-[12.5px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="px-5 py-2 font-medium">Lever</th>
              <th scope="col" className="px-3 py-2 font-medium">The AI may propose</th>
              <th scope="col" className="px-5 py-2 font-medium">You may set</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {SETTING_LEVERS.map((l) => (
              <tr key={l} className="align-top">
                <th scope="row" className="px-5 py-2 font-medium text-fg">{LEVER_LABEL[l]}</th>
                <td className="px-3 py-2 text-muted">{leverRangeText(l, AI_LEVER_RANGES)}</td>
                <td className="px-5 py-2 text-muted">{leverRangeText(l, ADMIN_LEVER_RANGES)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="space-y-1.5 border-t border-border px-5 py-3 text-[12px] text-muted">
        <p>At run time the AI is held inside your current setting as well: effort bounds between your low bound and 1 and between 1 and your high bound, the SLA floor between your floor and ceiling. The widest Admin ranges are fixed by Addendum 3.</p>
        <p>
          Your own levers live in <Link href="/routing?tab=settings" className="text-info hover:underline">Routing → Engine settings</Link>; to try a change before saving it, use the{" "}
          <Link href="/routing?tab=simulate" className="text-info hover:underline">What-if simulator</Link> (the same replay the AI uses, with your ranges).
        </p>
      </div>
    </Card>
  );
}

async function Ask() {
  const h = await askHistory();
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
      <Card className="min-w-0"><CardHeader title="Ask the CRM" description="Claude answers from the metric layer only (the same numbers as the dashboards), shows its sources, and never sees personal data. An answer whose numbers cannot be traced to the data is not shown." />
        <div className="px-5 pb-5"><AskPanel /></div></Card>
      <Card className="min-w-0"><CardHeader title="Recent questions" />
        {h.length === 0 ? <EmptyState icon={Sparkles} title="No questions yet" /> : (
          <ul className="divide-y divide-border text-[12.5px]">
            {h.map((x) => (
              <li key={x.id} className="space-y-1 px-5 py-3">
                <p className="font-medium text-fg">{x.question}</p>
                {x.status === "done" ? <p className="line-clamp-3 whitespace-pre-line text-muted">{x.answer}</p>
                  : <p className="text-warning">{x.error ?? `Not shown: unverified numbers ${(x.unverified ?? []).join(", ")}`}</p>}
                <p className="text-[11.5px] text-subtle">{relativeTime(x.at)} · ${Number(x.cost_usd).toFixed(4)}</p>
              </li>
            ))}
          </ul>
        )}</Card>
    </div>
  );
}

export default async function AiPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "inbox";
  const [o, ml, ro] = await Promise.all([aiOverview(), tab === "models" ? mlOverview() : Promise.resolve(null), routingOverview()]);
  const names = Object.fromEntries(ro.partners.map((p) => [String(p.id), p.name]));
  const ap = o.settings.autopilot;
  return (
    <>
      <PageHeader title="AI Optimiser"
        description="Claude watches outcomes, partner effort and money, and recommends changes to five bounded levers of the routing engine: the sales-effort weights and bounds, the SLA floor, and the recency half-life and prior of P(enrol). It reads only aggregated, pseudonymised data, never touches rules, consent, rates, switches or the numbers Addendum 3 fixed, and changes nothing without your approval." />
      <nav aria-label="AI sections" className="mb-6 flex gap-5 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <Link key={t.id} href={`/ai?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}{t.id === "inbox" && o.open.length > 0 && <span className="tabular ml-1.5 text-[11px] text-amber">{o.open.length}</span>}
            {t.id === "settings" && <span className={cn("ml-1.5 inline-block size-1.5 rounded-full align-middle", o.settings.enabled ? "bg-success" : "bg-subtle")} aria-label={o.settings.enabled ? "on" : "off"} />}
          </Link>
        ))}
      </nav>
      {tab === "inbox" && <Inbox_ o={o} names={names} />}
      {tab === "ask" && <Ask />}
      {tab === "uplift" && <Uplift u={o.uplift} holdout={o.holdout_share} />}
      {tab === "runs" && <Runs o={o} />}
      {tab === "models" && ml && <Models ml={ml} />}
      {tab === "settings" && (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
          <Card className="min-w-0"><CardHeader title="AI settings" description="Every change is versioned with your reason." />
            <div className="px-5 pb-5"><AiSettingsForm key={o.settings_version} s={o.settings} version={o.settings_version} gate={o.autopilot_gate} /></div></Card>
          <div className="min-w-0 space-y-6">
            <Card className="min-w-0">
              <CardHeader title="Autopilot's bar" description="What a setting change must show before Autopilot applies it without you. The support share is fixed by Addendum 3 and cannot be lowered here." />
              <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 px-5 pb-3 text-[12.5px]">
                <dt className="text-muted">Simulated gain</dt><dd className="tabular text-right">≥ {ap?.min_gain_pct ?? 3}%</dd>
                <dt className="text-muted">Matured decisions replayed</dt><dd className="tabular text-right">≥ {ap?.min_decisions ?? 30}</dd>
                <dt className="text-muted">95% interval</dt><dd className="text-right">above zero</dd>
                <dt className="text-muted">Support (decisions the log can speak for)</dt><dd className="tabular text-right">≥ {pct(ap?.min_support ?? 0.5, 0)}</dd>
                <dt className="text-muted">Changes a day</dt><dd className="tabular text-right">≤ {ap?.max_per_day ?? 3}</dd>
              </dl>
              <p className="border-t border-border px-5 py-3 text-[12px] text-muted"><SlidersHorizontal className="mr-1 inline size-3.5 text-subtle" /> {autopilotRuleText(ap)}</p>
            </Card>
            <LeverRanges />
            <Card className="min-w-0"><CardHeader title="Worker" description="The server-side worker that talks to Claude." />
              <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 px-5 pb-4 text-[12.5px]">
                <dt className="text-muted">Last seen</dt><dd className="text-right">{o.worker?.seen_at ? relativeTime(o.worker.seen_at) : "never"}</dd>
                <dt className="text-muted">Anthropic key on the server</dt><dd className="text-right">{o.worker?.has_anthropic_key ? "yes" : "not seen"}</dd>
                <dt className="text-muted">Worker API key</dt><dd className="text-right">{o.worker_key ? "created" : <Link href="/system?tab=integrations" className="text-info hover:underline">create one</Link>}</dd>
                <dt className="text-muted">Mode</dt><dd className="text-right">{o.settings.mode === "autopilot" ? `Autopilot (≥${ap?.min_gain_pct ?? 3}%, support ≥${pct(ap?.min_support ?? 0.5, 0)}, ≤${ap?.max_per_day ?? 3}/day)` : "Advisory"}</dd>
              </dl></Card>
          </div>
        </div>
      )}
    </>
  );
}
