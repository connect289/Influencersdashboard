import type { Metadata } from "next";
import Link from "next/link";
import { BrainCircuit, CircleCheck, CircleDashed, FlaskConical, Inbox, Scale, Sparkles, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { aiOverview, mlOverview } from "@/lib/ai/data";
import {
  describeChange, MODEL_STATUS_LABEL, REC_STATUS_LABEL, RUN_KIND_LABEL, setupSteps, simulationText, TRIGGER_LABEL,
  type AiOverview, type MlModel, type MlOverview, type Recommendation,
} from "@/lib/ai/labels";
import { formatDateTime, relativeTime } from "@/lib/format";
import { routingOverview } from "@/lib/routing-data";
import { AiSettingsForm, DecideButtons, ModelActions, RollbackRecommendation, RunNow } from "./AiClient";

export const metadata: Metadata = { title: "AI Optimiser" };

const TABS = [
  { id: "inbox", label: "Inbox" },
  { id: "uplift", label: "AI vs holdout" },
  { id: "runs", label: "Runs" },
  { id: "models", label: "Model registry" },
  { id: "settings", label: "Settings" },
] as const;
type Tab = (typeof TABS)[number]["id"];
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const usd = (v: number) => `$${v.toFixed(v < 1 ? 3 : 2)}`;
const pct = (v: number | null | undefined, d = 1) => (v == null ? "—" : `${(v * 100).toFixed(d)}%`);

function currentValue(r: Recommendation): string {
  const v = r.change?.value;
  return typeof v === "number" && ["exploration_share", "partner_weight", "share_cap"].includes(r.change!.lever) ? `${Math.round(v * 1000) / 10}%` : String(v ?? "—");
}

function RecCard({ r, names }: { r: Recommendation; names: Record<string, string> }) {
  const open = r.status === "open";
  return (
    <li className="space-y-2.5 px-5 py-4">
      <div className="flex flex-wrap items-start gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-[14px] font-semibold text-fg">{r.title}</p>
          <p className="text-[12px] text-subtle">
            Run <Link href={`/ai/runs/${r.run_id}`} className="text-info hover:underline">#{r.run_id}</Link>
            {r.run_kind && <> · {RUN_KIND_LABEL[r.run_kind] ?? r.run_kind}</>} · {relativeTime(r.created_at)}
            {open && <> · expires {relativeTime(r.expires_at)}</>}
          </p>
        </div>
        {!open && <Badge tone={r.status === "applied" ? "success" : r.status === "rolled_back" ? "warning" : "neutral"}>{REC_STATUS_LABEL[r.status]}</Badge>}
        {r.kind !== "setting_change" && <Badge tone={r.kind === "insight" ? "neutral" : "info"}>{r.kind === "insight" ? "Observation" : r.kind === "rule_draft" ? "Rule draft" : "Pause draft"}</Badge>}
      </div>
      <p className="text-[13px] text-fg"><Scale className="mr-1 inline size-3.5 text-subtle" /><span className="font-medium">{describeChange(r.change, names)}</span></p>
      <p className="whitespace-pre-line text-[13px] text-muted">{r.rationale}</p>
      {r.kind === "setting_change" && (
        <p className={cn("rounded-lg border px-3 py-2 text-[12.5px]", r.simulation?.enough ? "border-info/25 bg-info-bg text-info" : "border-border bg-surface-2/60 text-muted")}>
          <FlaskConical className="mr-1 inline size-3.5" /> Simulated on logged decisions: {simulationText(r.simulation)}
        </p>
      )}
      {r.risk && <p className="text-[12.5px] text-warning"><TriangleAlert className="mr-1 inline size-3.5" /> {r.risk}</p>}
      {r.evidence.length > 0 && (
        <ul className="flex flex-wrap gap-1.5">
          {r.evidence.slice(0, 8).map((e, i) => (
            <li key={i} className="rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[11.5px] text-muted">
              {e.tool && <span className="text-subtle">{e.tool}: </span>}{e.metric} {e.value !== undefined && <span className="text-fg">{String(e.value)}</span>}
            </li>
          ))}
        </ul>
      )}
      {open && <DecideButtons id={r.id} change={r.change} current={currentValue(r)} />}
      {!open && r.decided_by && (
        <p className="text-[12px] text-subtle">{REC_STATUS_LABEL[r.status]} by {r.decided_by} {r.decided_at && relativeTime(r.decided_at)}
          {r.decision_note && <> · “{r.decision_note}”</>}{r.applied?.edited && " · value edited"}{r.applied?.version && <> · engine policy v{r.applied.version}</>}</p>
      )}
      {r.status === "applied" && r.kind === "setting_change" && <RollbackRecommendation id={r.id} />}
    </li>
  );
}

function Inbox_({ o, names }: { o: AiOverview; names: Record<string, string> }) {
  const steps = setupSteps(o);
  const ready = steps.every((s) => s.done);
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)]">
      <div className="min-w-0 space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Recommendations" description="Advisory mode: Claude proposes, you approve, edit or reject. Every number was checked against the data it read; each change is simulated on logged decisions first." action={<RunNow enabled={o.settings.enabled} />} />
          {o.open.length === 0
            ? <EmptyState icon={Inbox} title="Nothing waiting">{o.settings.enabled ? "New recommendations appear after the next run." : "Recommendations appear once the optimiser is set up and on."}</EmptyState>
            : <ul className="divide-y divide-border">{o.open.map((r) => <RecCard key={r.id} r={r} names={names} />)}</ul>}
        </Card>
        <Card className="min-w-0">
          <CardHeader title="Change log" description="Decided recommendations, with what was applied and one-click rollback." />
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
  return (
    <Card className="min-w-0">
      <CardHeader title="AI-steered against holdout" description={`Realised net commission per lead after ${u.maturity_days} days. ${pct(holdout ?? 0.1, 0)} of leads are held out from every AI change.`} />
      <div className="grid grid-cols-2 gap-2 px-5 pb-3">
        <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">AI-steered</p>
          <p className="tabular text-xl font-semibold text-fg">₹{u.steered.ncpl}</p><p className="text-[11.5px] text-subtle">{u.steered.leads} matured leads</p></div>
        <div className="rounded-lg border border-border bg-surface-2/50 px-3 py-2"><p className="text-[11px] uppercase tracking-wider text-subtle">Holdout</p>
          <p className="tabular text-xl font-semibold text-fg">₹{u.holdout.ncpl}</p><p className="text-[11.5px] text-subtle">{u.holdout.leads} matured leads</p></div>
      </div>
      <p className="px-5 pb-4 text-[12.5px] text-muted">
        {enough
          ? <>Uplift {u.uplift_pct != null ? `${u.uplift_pct >= 0 ? "+" : ""}${u.uplift_pct}%` : "—"} (z = {u.z}{Math.abs(u.z) >= 1.96 ? ", significant" : ", not yet significant"}).</>
          : "Not enough matured leads in both groups to compare yet (30 each). Until then the AI's value is unproven."}
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
        {u.by_month.length === 0 ? <EmptyState icon={Scale} title="No matured leads yet">Months appear once leads are older than the maturity window.</EmptyState> : (
          <ul className="space-y-3 px-5 pb-5">
            {u.by_month.map((m) => (
              <li key={m.month} className="grid grid-cols-[80px_minmax(0,1fr)] items-center gap-3 text-[12px]">
                <span className="text-muted">{new Date(m.month).toLocaleDateString("en-IN", { month: "short", year: "numeric" })}</span>
                <span className="space-y-1">
                  <span className="flex items-center gap-2"><span className="h-2 rounded bg-primary" style={{ width: `${((m.steered ?? 0) / max) * 100}%` }} /><span className="tabular text-fg">₹{m.steered ?? "—"} · {m.steered_n}</span></span>
                  <span className="flex items-center gap-2"><span className="h-2 rounded border border-primary" style={{ width: `${((m.holdout ?? 0) / max) * 100}%` }} /><span className="tabular text-muted">₹{m.holdout ?? "—"} · {m.holdout_n}</span></span>
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
      <CardHeader title="Runs" description="Every run is logged with its trigger, model, tools called, tokens and cost." action={<RunNow enabled={o.settings.enabled} />} />
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

function Models({ ml }: { ml: MlOverview }) {
  const active = ml.models.filter((m) => ["shadow", "challenger", "champion", "training"].includes(m.status));
  const rest = ml.models.filter((m) => !active.includes(m));
  const ModelCard = ({ m }: { m: MlModel }) => (
    <li className="space-y-3 px-5 py-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-[13px] font-semibold text-fg">{m.version}</span>
        <Badge tone={m.status === "champion" ? "success" : m.status === "challenger" ? "info" : m.status === "failed" ? "danger" : "neutral"}>{MODEL_STATUS_LABEL[m.status]}</Badge>
        <span className="text-[12px] text-subtle">{m.trained_at ? `trained ${relativeTime(m.trained_at)}` : `queued ${relativeTime(m.created_at)}`}{m.status_reason && ` · ${m.status_reason}`}</span>
      </div>
      {m.error && <p className="text-[12.5px] text-danger">{m.error}</p>}
      {m.metrics.holdout && (
        <div className="flex flex-wrap gap-5">
          <Calibration d={m.metrics.holdout.deciles} />
          <dl className="grid min-w-[240px] flex-1 grid-cols-2 gap-x-4 gap-y-1 text-[12.5px]">
            <dt className="text-muted">Rows (train / holdout)</dt><dd className="tabular text-right">{m.trained_on.train} / {m.trained_on.valid}</dd>
            <dt className="text-muted">Log loss: model / segment P̂</dt><dd className="tabular text-right">{m.metrics.holdout.log_loss} / {m.metrics.baseline?.log_loss}</dd>
            <dt className="text-muted">Calibration error: model / P̂</dt><dd className="tabular text-right">{m.metrics.holdout.ece} / {m.metrics.baseline?.ece}</dd>
            <dt className="text-muted">Policy value (logged decisions)</dt><dd className="tabular text-right">₹{m.metrics.policy?.model_value ?? "—"} vs ₹{m.metrics.policy?.logged_value ?? "—"} ({m.metrics.policy?.decisions ?? 0})</dd>
            {m.metrics.monitor?.matured && <><dt className="text-muted">Live calibration error</dt><dd className="tabular text-right">{m.metrics.monitor.matured.ece} on {m.metrics.monitor.matured.n}</dd></>}
            {m.champion_check && <><dt className="text-muted">Challenger vs rest (NCPL)</dt><dd className="tabular text-right">₹{m.champion_check.model_ncpl} vs ₹{m.champion_check.other_ncpl} · z {m.champion_check.z}</dd></>}
          </dl>
        </div>
      )}
      {m.status !== "failed" && m.trained_at && (
        <ul className="flex flex-wrap gap-1.5 text-[11.5px]">
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
        <CardHeader title="Per-lead model" description="Predicts each partner's chance of enrolling this student. Shadow scores only; a challenger decides its share of performance-mode leads; the champion decides the rest. Holdout leads never use it." action={<ModelActions />} />
        {active.length === 0 ? <EmptyState icon={BrainCircuit} title="No model in use">Segment P̂ decides performance mode. A model trains nightly once enough leads have matured, or press Train now.</EmptyState>
          : <ul className="divide-y divide-border">{active.map((m) => <ModelCard key={m.id} m={m} />)}</ul>}
        {rest.length > 0 && (
          <details className="border-t border-border">
            <summary className="cursor-pointer px-5 py-3 text-[13px] text-muted">Retired and failed ({rest.length})</summary>
            <ul className="divide-y divide-border">{rest.map((m) => <ModelCard key={m.id} m={m} />)}</ul>
          </details>
        )}
      </Card>
      <Card className="min-w-0">
        <CardHeader title="Training data" description={`Outcomes count once leads are ${ml.maturity_days} days old.`} />
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 px-5 pb-4 text-[12.5px]">
          <dt className="text-muted">Matured leads</dt><dd className="tabular text-right">{ml.data.matured} / {ml.settings.min_outcomes} needed</dd>
          <dt className="text-muted">of which enrolled</dt><dd className="tabular text-right">{ml.data.matured_enrolled}</dd>
          <dt className="text-muted">Partners</dt><dd className="tabular text-right">{ml.data.partners}</dd>
          <dt className="text-muted">Younger leads</dt><dd className="tabular text-right">{ml.data.young}</dd>
          <dt className="text-muted">Challenger share</dt><dd className="tabular text-right">{pct(ml.settings.challenger_share, 0)}</dd>
          <dt className="text-muted">Automatic fallback above</dt><dd className="tabular text-right">calibration error {ml.settings.ece_fallback}</dd>
          <dt className="text-muted">Nightly training</dt><dd className="tabular text-right">{ml.settings.auto_train ? `${ml.settings.train_hour_ist}:00 IST` : "off"}</dd>
        </dl>
        {Object.keys(ml.decided_30d).length > 0 && (
          <div className="border-t border-border px-5 py-3 text-[12.5px]">
            <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Performance decisions, 30 days</p>
            {Object.entries(ml.decided_30d).map(([k, n]) => <p key={k} className="flex justify-between"><span className="text-muted">{k}</span><span className="tabular">{n}</span></p>)}
          </div>
        )}
      </Card>
    </div>
  );
}

export default async function AiPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "inbox";
  const [o, ml, ro] = await Promise.all([aiOverview(), tab === "models" ? mlOverview() : Promise.resolve(null), routingOverview()]);
  const names = Object.fromEntries(ro.partners.map((p) => [String(p.id), p.name]));
  return (
    <>
      <PageHeader title="AI Optimiser"
        description="Claude watches outcomes, partner effort and money, and recommends bounded changes to the routing engine. It reads only aggregated, pseudonymised data, never touches rules, consent, rates or switches, and changes nothing without your approval." />
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
      {tab === "uplift" && <Uplift u={o.uplift} holdout={o.holdout_share} />}
      {tab === "runs" && <Runs o={o} />}
      {tab === "models" && ml && <Models ml={ml} />}
      {tab === "settings" && (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
          <Card className="min-w-0"><CardHeader title="AI settings" description="Every change is versioned with your reason." />
            <div className="px-5 pb-5"><AiSettingsForm key={o.settings_version} s={o.settings} version={o.settings_version} /></div></Card>
          <Card className="min-w-0"><CardHeader title="Worker" description="The server-side worker that talks to Claude." />
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 px-5 pb-4 text-[12.5px]">
              <dt className="text-muted">Last seen</dt><dd className="text-right">{o.worker?.seen_at ? relativeTime(o.worker.seen_at) : "never"}</dd>
              <dt className="text-muted">Anthropic key on the server</dt><dd className="text-right">{o.worker?.has_anthropic_key ? "yes" : "not seen"}</dd>
              <dt className="text-muted">Worker API key</dt><dd className="text-right">{o.worker_key ? "created" : <Link href="/system?tab=integrations" className="text-info hover:underline">create one</Link>}</dd>
              <dt className="text-muted">Mode</dt><dd className="text-right">Advisory</dd>
            </dl></Card>
        </div>
      )}
    </>
  );
}
