"use client";
import { useEffect, useState, useTransition } from "react";
import { History, LoaderCircle, Lock } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { formatDateTime } from "@/lib/format";
import { A3_FIXED_LABELS, a3FixedText } from "@/lib/routing";
import type { EngineSettings, SettingsHistoryRow } from "@/lib/routing-data";
import {
  EFFORT_LOWER_IS_BETTER, EFFORT_METRIC_LABEL, EFFORT_METRICS, EFFORT_RANGE, performanceDefaults, SLA_KEYS, SLA_LABEL, SLA_RANGE, SLA_STEP_RANGE, WEIGHT_RANGE,
} from "@/lib/segments";
import { loadSettingsHistory, saveEngineSettings, type FormState } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger disabled:bg-surface-2 disabled:text-subtle";
const check = "size-4 accent-[var(--primary)]";

function Row({ label, hint, error, wide, children }: { label: string; hint?: string; error?: string; wide?: boolean; children: React.ReactNode }) {
  return (
    <div className={cn("grid gap-x-6 gap-y-1 py-3 sm:items-start", wide ? "sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]" : "sm:grid-cols-[minmax(0,1fr)_240px]")}>
      <div>
        <p className="text-[13px] font-medium text-fg">{label}</p>
        {hint && <p className="text-[12px] leading-5 text-muted">{hint}</p>}
      </div>
      <div>{children}{error && <p className="mt-1 text-xs text-danger">{error}</p>}</div>
    </div>
  );
}

function Section({ title, lead, children }: { title: string; lead?: string; children: React.ReactNode }) {
  return (
    <section className="pt-5 first:pt-1">
      <h3 className="text-[11px] font-medium uppercase tracking-wider text-subtle">{title}</h3>
      {lead && <p className="mt-1 max-w-3xl text-[12.5px] leading-5 text-muted">{lead}</p>}
      <div className="divide-y divide-border">{children}</div>
    </section>
  );
}

function Check({ name, label, defaultChecked }: { name: string; label: string; defaultChecked: boolean }) {
  return (
    <label className="flex items-center gap-2 py-1.5 text-[13px] text-fg">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} className={check} /> {label}
    </label>
  );
}

/** A number typed as text: a blank is a validation error (reqNum, C63), never a silent 0. */
function Num({ name, value, error, decimal = true, suffix, label }: { name: string; value: string; error?: string; decimal?: boolean; suffix?: string; label?: string }) {
  return (
    <div className="flex items-center gap-2">
      <input name={name} inputMode={decimal ? "decimal" : "numeric"} defaultValue={value} className={cn(field, "tabular")} aria-invalid={Boolean(error)} aria-label={label} />
      {suffix && <span className="shrink-0 text-[12px] text-muted">{suffix}</span>}
    </div>
  );
}

/** Weights (0–5) for a factor's metrics, one small input each; the factor's positive-sum check reports at `error`. */
function Weights({ prefix, keys, labels, lowerIsBetter, errors, defaults }: {
  prefix: string; keys: readonly string[]; labels: Record<string, string>; lowerIsBetter?: readonly string[]; errors: Record<string, string>; defaults: Record<string, string>;
}) {
  return (
    <div className="grid gap-x-4 gap-y-2 sm:grid-cols-2">
      {keys.map((k) => {
        const name = `${prefix}${k}`;
        const err = errors[name];
        return (
          <label key={k} className="flex items-center justify-between gap-3 text-[12.5px] text-fg">
            <span className="min-w-0">
              {labels[k]}
              {lowerIsBetter?.includes(k) && <span className="block text-[11px] text-subtle">lower is better</span>}
            </span>
            <span className="w-20 shrink-0">
              <input name={name} inputMode="decimal" defaultValue={defaults[name] ?? "1"} className={cn(field, "tabular text-right")} aria-invalid={Boolean(err)} aria-label={`${labels[k]} weight`} />
              {err && <span className="block text-[11px] text-danger">{err}</span>}
            </span>
          </label>
        );
      })}
    </div>
  );
}

const str = (x: number | string | undefined | null, dflt: number | string) => String(x ?? dflt);

/**
 * Engine settings (Addendum 3): only the keys b2b.engine_settings_save accepts, grouped by what they decide. Every save
 * is a versioned partial update with a reason (b2b.settings_versions); the rulebook's numbers are listed read-only below
 * and refused by the save ('fixed by Addendum 3'). Numbers are typed as text and parsed by EngineSchema, so a blank is an
 * error and never a silent 0 (C63).
 */
export function EngineForm({ v, version }: { v: EngineSettings; version: number }) {
  const [state, onSubmit, pending] = useFormAction<FormState>(saveEngineSettings, undefined);
  const e = state?.errors ?? {};
  const perf = performanceDefaults(v);
  const [policy, setPolicy] = useState<"ask" | "b2c_sales">(v.consent_policy ?? "ask");
  useEffect(() => { if (state?.ok) toast.success("Engine settings saved"); }, [state?.ok]);

  return (
    <>
      <form onSubmit={onSubmit} noValidate className="px-5 py-2">
        <Section title="Partner-sharing consent (R8, PART 7)"
          lead="A qualified lead reaches a partner only with recorded partner-sharing consent under a lawyer-approved text that names our admission partners. Leads without it are asked at their decision point.">
          <Row label="When a qualified lead has no consent" error={e.consent_policy}
            hint={policy === "ask"
              ? "The student gets the one-tap WhatsApp request (from Witty's number once W2 is live, otherwise from the B2C number) and the lead waits up to 48 hours. YES routes it to partners; NO sends it to B2C sales; no answer sends it to B2C nurture, where the request is repeated."
              : "The pre-Addendum behaviour: the lead goes to B2C sales with reason no_partner_consent and is never asked. There is no 'off': a partner never receives a lead without consent."}>
            <select name="consent_policy" value={policy} onChange={(x) => setPolicy(x.target.value as "ask" | "b2c_sales")} className={field} aria-invalid={Boolean(e.consent_policy)}>
              <option value="ask">Ask the student (R8)</option>
              <option value="b2c_sales">Hand to B2C sales</option>
            </select>
          </Row>
          <Row label="Admin may record a YES given on a call" error={e.consent_admin_yes}
            hint="Off by default (D9, awaiting Vikas). A refusal can always be recorded from the lead drawer; a YES recorded by hand needs a written evidence reference and this switch.">
            <Check name="consent_admin_yes" label="Allowed" defaultChecked={v.consent_admin_yes ?? false} />
          </Row>
          <Row label="Consent requests per hour from the B2C number" error={e.consent_requests_per_hour}
            hint="Requests over this limit wait in a queue and their 48 hours start when they are sent. Protects the B2C number's WhatsApp quality rating during imports. 10 to 1000.">
            <Num name="consent_requests_per_hour" value={str(v.consent_requests_per_hour, 100)} error={e.consent_requests_per_hour} decimal={false} suffix="an hour" />
          </Row>
        </Section>

        <Section title="Witty leads (Amendment 1)">
          <Row label="Inactivity before an unqualified Witty lead is decided" error={e.witty_unqualified_idle_hours}
            hint="An unqualified Witty lead goes to B2C qualification nurture only once the student has been quiet this long; every new message restarts the clock. A lead that qualifies meanwhile is routed at the usual hand-off points (HOT escalation, programme confirmed, 30 minutes idle). 1 to 72 hours; the rulebook says 18.">
            <Num name="witty_unqualified_idle_hours" value={str(v.witty_unqualified_idle_hours, 18)} error={e.witty_unqualified_idle_hours} suffix="hours" />
          </Row>
        </Section>

        <Section title="Deciding leads">
          <Row label="Re-enquiry quiet period" error={e.reenquiry_quiet_hours}
            hint="A student who writes again while a partner or B2C holds the lead counts as one re-enquiry per quiet period: the holder is told, the lead does not move (D18). 1 to 168 hours.">
            <Num name="reenquiry_quiet_hours" value={str(v.reenquiry_quiet_hours, 24)} error={e.reenquiry_quiet_hours} decimal={false} suffix="hours" />
          </Row>
          <Row label="Interests tried" error={e.max_interests}
            hint="When no partner offers the student's primary interest, the secondary interests are tried in order, up to this many in total, before the lead falls back to B2C (D30). 1 to 10.">
            <Num name="max_interests" value={str(v.max_interests, 5)} error={e.max_interests} decimal={false} suffix="interests" />
          </Row>
          <Row label="Partner criteria when the lead's data is unknown" error={e.criteria_unknown}
            hint="A partner's agreed criteria (state, qualification, …) cannot be checked when the lead has not given that field. 'Fail' keeps the partner out of the running for that lead; 'Pass' lets it compete.">
            <select name="criteria_unknown" defaultValue={v.criteria_unknown ?? "fail"} className={field} aria-invalid={Boolean(e.criteria_unknown)}>
              <option value="fail">Fail: do not send</option>
              <option value="pass">Pass: let the partner compete</option>
            </select>
          </Row>
          <Row label="Welcome request for every nurture hand-off" error={e.welcome_for_all_nurture}
            hint="The hand-off asks the B2C CRM to send its welcome WhatsApp message to every nurture lead, not only to unqualified Witty leads (Amendment 1).">
            <Check name="welcome_for_all_nurture" label="Every nurture lead" defaultChecked={v.welcome_for_all_nurture ?? false} />
          </Row>
          <Row label="Sources whose phone must be verified" error={e.require_verified_phone_sources} wide
            hint="Leads from these sources (comma-separated lead_source values) are qualified only once their phone is verified by OTP. Default: website_agent, web_agent.">
            <input name="require_verified_phone_sources" defaultValue={(v.require_verified_phone_sources ?? ["website_agent", "web_agent"]).join(", ")} className={field} spellCheck={false} aria-invalid={Boolean(e.require_verified_phone_sources)} />
          </Row>
        </Section>

        <Section title="Requalification (R7 to R9)"
          lead="A lead in B2C qualification nurture comes back to partner routing once its details are complete, without a trigger from the B2C CRM (D15).">
          <Row label="Re-decide qualification-nurture leads" error={e.requalify_enabled}
            hint="Every minute while routing is on: the nurture hand-off is closed (b2c.lead_requalified) and the lead is routed again.">
            <Check name="requalify_enabled" label="On" defaultChecked={v.requalify?.enabled ?? true} />
          </Row>
          <Row label="Wait for Witty's chat gate" error={e.requalify_wait_for_chat_gate}
            hint="A Witty lead is re-decided only once its chat has been quiet for the usual 30 minutes.">
            <Check name="requalify_wait_for_chat_gate" label="Wait" defaultChecked={v.requalify?.wait_for_chat_gate ?? true} />
          </Row>
          <Row label="Leads per run" error={e.requalify_max_per_run} hint="How many leads one minute's run re-decides at most. 10 to 100.">
            <Num name="requalify_max_per_run" value={str(v.requalify?.max_per_run, 25)} error={e.requalify_max_per_run} decimal={false} suffix="leads" />
          </Row>
        </Section>

        <Section title="Sales-effort factor (PART 4, Stages B and C)"
          lead={`Compares each partner with the segment median over the last 30 days on six activity metrics from its CRM sync, and scales the commission between the bounds (1.00 = the median). A partner that syncs no activity is capped at 1.00. Bounds, weights and the minimum sample are versioned Admin settings inside the rulebook range ${EFFORT_RANGE[0]}–${EFFORT_RANGE[1]}; the AI optimiser may tune them only inside your bounds.`}>
          <Row label="Use the factor" error={e.effort_enabled} hint="On by default. Off, every partner counts as 1.00.">
            <Check name="effort_enabled" label="On" defaultChecked={perf.effort_enabled === "on"} />
          </Row>
          <Row label="Bounds" error={e.effort_lo ?? e.effort_hi} hint={`The lowest and highest factor a partner can get. Low ${EFFORT_RANGE[0].toFixed(2)}–1.00, high 1.00–${EFFORT_RANGE[1].toFixed(2)}.`}>
            <div className="grid grid-cols-2 gap-2">
              <Num name="effort_lo" value={perf.effort_lo} error={e.effort_lo} label="Lower bound" />
              <Num name="effort_hi" value={perf.effort_hi} error={e.effort_hi} label="Upper bound" />
            </div>
          </Row>
          <Row label={`Weights (${WEIGHT_RANGE[0]}–${WEIGHT_RANGE[1]})`} error={e.effort_weights} wide
            hint="How much each metric counts in the partner's effort score. At least one weight above 0; equal weights by default.">
            <Weights prefix="effort_w_" keys={EFFORT_METRICS} labels={EFFORT_METRIC_LABEL} lowerIsBetter={EFFORT_LOWER_IS_BETTER} errors={e} defaults={perf} />
          </Row>
          <Row label="Minimum sample" error={e.effort_min_sample}
            hint="A metric's segment median counts only partners with at least this many observations of it; below that, the partner's own partner-wide value is compared with the all-partner median. 3 to 100.">
            <Num name="effort_min_sample" value={perf.effort_min_sample} error={e.effort_min_sample} decimal={false} suffix="observations" />
          </Row>
        </Section>

        <Section title="SLA-adherence factor (PART 4, Stages B and C)"
          lead={`The share of a partner's SLAs met on time over the last 30 days: first attempt within 2 working hours, a status update at least every 7 days, enrolment proof within 7 days. 100% adherence = the ceiling; every full 10 points below subtracts the step, down to the floor. Rulebook range ${SLA_RANGE[0].toFixed(2)}–${SLA_RANGE[1].toFixed(2)}, step 0.05.`}>
          <Row label="Use the factor" error={e.sla_enabled} hint="On by default. Off, every partner counts as 1.00.">
            <Check name="sla_enabled" label="On" defaultChecked={perf.sla_enabled === "on"} />
          </Row>
          <Row label="Floor and ceiling" error={e.sla_floor ?? e.sla_ceiling} hint={`Both ${SLA_RANGE[0].toFixed(2)}–${SLA_RANGE[1].toFixed(2)}, floor at or below the ceiling. Raising the floor softens the penalty.`}>
            <div className="grid grid-cols-2 gap-2">
              <Num name="sla_floor" value={perf.sla_floor} error={e.sla_floor} label="Floor" />
              <Num name="sla_ceiling" value={perf.sla_ceiling} error={e.sla_ceiling} label="Ceiling" />
            </div>
          </Row>
          <Row label="Step per 10 points below 100%" error={e.sla_step} hint={`factor = max(floor, ceiling − step × ⌊(100 − adherence) ÷ 10⌋). ${SLA_STEP_RANGE[0]}–${SLA_STEP_RANGE[1].toFixed(2)}; the rulebook's reading is 0.05.`}>
            <Num name="sla_step" value={perf.sla_step} error={e.sla_step} />
          </Row>
          <Row label={`Weights (${WEIGHT_RANGE[0]}–${WEIGHT_RANGE[1]})`} error={e.sla_weights} wide hint="How much each SLA counts in the adherence share. At least one weight above 0.">
            <Weights prefix="sla_w_" keys={SLA_KEYS} labels={SLA_LABEL} errors={e} defaults={perf} />
          </Row>
        </Section>

        <Section title="P(enrol) for Stage C"
          lead="From Stage C the score is commission per lead: CPE × P(enrol) × (1 − refunds) × both factors. P(enrol) is the partner's real matured conversion in the segment (a lead matures 60 days after it was sent, fixed), weighted toward recent months and shrunk toward the segment average while the partner has few leads.">
          <Row label="Recency half-life" error={e.half_life_days} hint="A matured lead this many days older counts half as much. 7 to 120 days.">
            <Num name="half_life_days" value={str(v.half_life_days, 30)} error={e.half_life_days} decimal={false} suffix="days" />
          </Row>
          <Row label="Prior strength" error={e.prior_weight} hint="How many leads' worth of the segment average each partner starts with, so a few early results cannot swing it. 1 to 100.">
            <Num name="prior_weight" value={str(v.prior_weight, 20)} error={e.prior_weight} suffix="leads" />
          </Row>
          <Row label="Default enrolment rate" error={e.default_p_enroll} hint="Used while a segment has no matured leads at all. 0.1% to 50%.">
            <Num name="default_p_enroll" value={String(Math.round((v.default_p_enroll ?? 0.05) * 1000) / 10)} error={e.default_p_enroll} suffix="%" />
          </Row>
        </Section>

        <Section title="Guardrails">
          <Row label="Pause a partner on a duplicate-rate spike" error={e.guard_duplicate_rate_pause}
            hint="When a partner's duplicate claims spike against its own history, the guard pauses it and alerts you; its leads fail over to the next partner. Off by default.">
            <Check name="guard_duplicate_rate_pause" label="On" defaultChecked={v.guard?.duplicate_rate_pause ?? false} />
          </Row>
        </Section>

        <Section title="Reason for the audit log">
          <Row label="Reason for this change" error={e.reason} hint={`Saved as version ${version + 1} of the engine settings, with your reason, and shown in the history below.`} wide>
            <input name="reason" maxLength={300} placeholder="e.g. second partner signed, raise the SLA floor" className={field} aria-invalid={Boolean(e.reason)} />
          </Row>
        </Section>
        <div className="flex items-center justify-end gap-3 border-t border-border py-3">
          {state?.error && <span role="alert" className="mr-auto text-[13px] text-danger">{state.error}</span>}
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save settings</Button>
        </div>
      </form>
      <FixedPanel fixed={v.a3_fixed} />
      <HistoryCard reloadKey={state?.ok ?? version} />
    </>
  );
}

// ---------- read-only: the rulebook's numbers (D24) ----------

/** The a3_fixed keys in display groups; keys the labels list but no group names fall under "Other". */
const FIXED_GROUPS: { title: string; keys: string[] }[] = [
  { title: "Stage gates and the exploration lane", keys: ["stage_b_min_leads", "stage_b_min_age_days", "stage_c_min_matured", "stage_c_min_partners", "matured_days", "learn_leads", "exploration_share", "exact_segment_min_leads", "tier_projected_min_matured"] },
  { title: "Factor ranges the settings above must stay inside", keys: ["effort_range", "sla_range", "sla_step_range", "weight_range", "factor_window_days"] },
  { title: "Push, hold and duplicates", keys: ["attempt_limit", "partner_limit", "hold_minutes_sync", "hold_minutes_async", "duplicate_window_hours", "push_retry_seconds"] },
  { title: "Waits", keys: ["lost_grace_days", "consent_wait_hours", "witty_idle_minutes"] },
  { title: "Partners and commission", keys: ["auto_pause_breaches", "auto_pause_sync_minutes", "cpe_aggregate"] },
];

/** engine.a3_fixed as the rulebook fixes it: read-only, refused by every save; a routing rule is the only override (D24). */
function FixedPanel({ fixed }: { fixed: EngineSettings["a3_fixed"] | undefined }) {
  const values = (fixed ?? {}) as Record<string, unknown>;
  const grouped = new Set(FIXED_GROUPS.flatMap((g) => g.keys));
  const rest = [...Object.keys(A3_FIXED_LABELS), ...Object.keys(values)].filter((k, i, a) => !grouped.has(k) && a.indexOf(k) === i);
  const groups = rest.length ? [...FIXED_GROUPS, { title: "Other", keys: rest }] : FIXED_GROUPS;
  return (
    <section className="border-t border-border px-5 py-4">
      <div className="flex items-start gap-2">
        <Lock className="mt-0.5 size-4 shrink-0 text-subtle" aria-hidden />
        <div>
          <h3 className="text-sm font-semibold text-fg">Fixed by Addendum 3</h3>
          <p className="mt-0.5 text-[12.5px] leading-5 text-muted">
            The rulebook&apos;s numbers, read by the engine and refused by every save (&quot;fixed by Addendum 3&quot;). The kill switch, fixed splits, segment pins, share caps and partner
            weights were retired: a routing rule is the Admin&apos;s only override.
          </p>
        </div>
      </div>
      {!fixed ? (
        <p className="mt-3 text-[12.5px] text-subtle">Not available yet: the rulebook numbers appear once the Addendum 3 schema (m31a) is applied.</p>
      ) : (
        <div className="mt-3 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {groups.map((g) => (
            <div key={g.title} className="rounded-lg border border-border bg-surface-2/50 p-3">
              <p className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">{g.title}</p>
              <dl className="space-y-1 text-[12.5px]">
                {g.keys.map((k) => (
                  <div key={k} className="flex items-baseline justify-between gap-3">
                    <dt className="min-w-0 text-muted">{A3_FIXED_LABELS[k] ?? k.replace(/_/g, " ")}</dt>
                    <dd className="tabular shrink-0 text-right font-medium text-fg">{a3FixedText(k, values[k])}</dd>
                  </div>
                ))}
              </dl>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

// ---------- version history (C62) ----------

const short = (x: unknown) => {
  const s = JSON.stringify(x) ?? "null";
  return s.length > 90 ? `${s.slice(0, 87)}…` : s;
};

/** Every version of the engine settings, newest first (b2b.settings_history): who, when, why, and `key: from → to` per changed key. */
function HistoryCard({ reloadKey }: { reloadKey: number }) {
  const [rows, setRows] = useState<SettingsHistoryRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  useEffect(() => {
    start(async () => {
      const r = await loadSettingsHistory("engine", 30);
      if (r.ok) { setRows(r.rows); setError(null); } else { setRows([]); setError(r.error); }
    });
  }, [reloadKey]);

  return (
    <section className="border-t border-border px-5 py-4">
      <div className="flex items-center gap-2">
        <History className="size-4 text-subtle" aria-hidden />
        <h3 className="text-sm font-semibold text-fg">History</h3>
        {busy && <LoaderCircle className="size-3.5 animate-spin text-subtle" aria-label="Loading" />}
        <span className="ml-auto text-[12px] text-subtle">Last 30 versions</span>
      </div>
      {error && <p className="mt-2 text-[12.5px] text-muted">{error}</p>}
      {rows && rows.length === 0 && !error && <p className="mt-2 text-[12.5px] text-subtle">No versions yet.</p>}
      {rows && rows.length > 0 && (
        <ol className="mt-3 divide-y divide-border">
          {rows.map((r) => {
            const changed = Object.entries(r.changed ?? {});
            return (
              <li key={r.version} className="py-2.5">
                <p className="flex flex-wrap items-baseline gap-x-2 text-[12.5px]">
                  <span className="tabular font-medium text-fg">v{r.version}</span>
                  <span className="text-muted">{formatDateTime(r.at)}</span>
                  <span className="text-muted">{r.actor ?? (r.ai_run_id ? "AI optimiser" : "system")}{r.ai_run_id ? ` · AI run #${r.ai_run_id}` : ""}</span>
                  {r.reason && <span className="min-w-0 text-fg">{r.reason}</span>}
                </p>
                {changed.length === 0
                  ? <p className="mt-0.5 text-[12px] text-subtle">No visible change</p>
                  : (
                    <ul className="mt-1 space-y-0.5 font-mono text-[11.5px] text-muted">
                      {changed.map(([k, c]) => (
                        <li key={k} className="break-all"><span className="text-fg">{k}</span>: {short(c.from)} <span className="text-subtle">→</span> {short(c.to)}</li>
                      ))}
                    </ul>
                  )}
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}
