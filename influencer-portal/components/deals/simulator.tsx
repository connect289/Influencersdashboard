"use client";
// The earnings simulator (spec 6.2). Staff: computed in the browser from the builder's live config, including
// Eduwit's economics. Creators: computed on the server from their own deal, returning their earnings only.
import { useTranslations } from "next-intl";
import { useDeferredValue, useEffect, useMemo, useState } from "react";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Banner } from "@/components/ui/states";
import { simulateMyDeal } from "@/lib/actions/deals";
import type { EngineContext } from "@/lib/compensation/engine";
import type { CompConfig } from "@/lib/compensation/schema";
import {
  scenario as scenarioSchema,
  simulate,
  type CreatorSimulation,
  type Scenario,
} from "@/lib/compensation/simulator";
import type { TdsSection } from "@/lib/compensation/tax";
import { formatPaise } from "@/lib/format";
import { IntInput, RupeeInput } from "./inputs";

const COUNTS = [
  "leads",
  "qualified_leads",
  "applications",
  "enrollments",
  "cancellations",
  "views",
  "days_late",
  "disclosure_issues",
  "months",
] as const;

const DEFAULT: Scenario = scenarioSchema.parse({
  leads: 20,
  qualified_leads: 8,
  applications: 5,
  enrollments: 3,
  views: 50_000,
  months: 1,
});

function ScenarioForm({
  value,
  onChange,
  staff,
}: {
  value: Scenario;
  onChange: (s: Scenario) => void;
  staff: boolean;
}) {
  const t = useTranslations();
  const set = (patch: Partial<Scenario>) => onChange({ ...value, ...patch });
  return (
    <div className="flex flex-col gap-3">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {COUNTS.map((k) => (
          <Field key={k} id={`sim-${k}`} label={t(`deals.scenario.${k}`)}>
            <IntInput
              id={`sim-${k}`}
              int={value[k]}
              onInt={(n) => set({ [k]: k === "months" ? Math.min(Math.max(n, 1), 24) : n })}
            />
          </Field>
        ))}
        <Field id="sim-fee" label={t("deals.scenario.avg_fee")}>
          <RupeeInput
            id="sim-fee"
            paise={value.avg_fee_paise ?? null}
            onPaise={(p) => set({ avg_fee_paise: p || undefined })}
          />
        </Field>
        {staff ? (
          <Field id="sim-comm" label={t("deals.scenario.avg_commission")} hint={t("deals.scenario.avgCommissionHint")}>
            <RupeeInput
              id="sim-comm"
              paise={value.avg_commission_gross_paise ?? null}
              onPaise={(p) => set({ avg_commission_gross_paise: p || undefined })}
            />
          </Field>
        ) : null}
      </div>
      <div className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
        {(["commission_received", "has_pan", "gst_registered"] as const).map((k) => (
          <label key={k} className="flex items-center gap-2">
            <input type="checkbox" checked={value[k]} onChange={(e) => set({ [k]: e.target.checked })} />
            {t(`deals.scenario.${k}`)}
          </label>
        ))}
      </div>
    </div>
  );
}

function Row({ label, value, strong, muted }: { label: string; value: number; strong?: boolean; muted?: boolean }) {
  return (
    <div
      className={`flex justify-between gap-3 py-1 text-sm ${strong ? "font-semibold" : ""} ${muted ? "text-muted" : ""}`}
    >
      <dt>{label}</dt>
      <dd className="tabular-nums">{formatPaise(value)}</dd>
    </div>
  );
}

function ResultView({ r }: { r: CreatorSimulation }) {
  const t = useTranslations();
  return (
    <dl className="flex flex-col divide-y divide-line" aria-live="polite">
      <div className="pb-2">
        {r.breakdown.length === 0 ? <p className="py-1 text-sm text-muted">{t("deals.simulator.nothing")}</p> : null}
        {r.breakdown.map((b) => (
          <Row key={b.key} label={t(`deals.breakdown.${b.key}`)} value={b.amount_paise} />
        ))}
      </div>
      <div className="py-2">
        <Row label={t("deals.simulator.gross")} value={r.gross_paise} strong />
        {r.tax.sections
          .filter((s) => s.borne_by === "creator")
          .map((s) => (
            <Row
              key={s.code}
              label={t("deals.simulator.tds", { code: s.code, rate: s.rate_bps / 100 })}
              value={-s.tds_paise}
              muted
            />
          ))}
        {r.tax.gst_paise ? <Row label={t("deals.simulator.gst")} value={r.tax.gst_paise} muted /> : null}
        {r.penalties_paise ? <Row label={t("deals.simulator.penalties")} value={-r.penalties_paise} muted /> : null}
      </div>
      <div className="pt-2">
        <Row label={t("deals.simulator.net")} value={r.net_payout_paise} strong />
        {r.non_cash_paise ? <Row label={t("deals.simulator.nonCash")} value={r.non_cash_paise} muted /> : null}
      </div>
    </dl>
  );
}

/** Staff simulator, live on the builder's (unsaved) config. */
export function StaffSimulator({
  config,
  startsOn,
  context,
  gstRateBps,
  sections,
  estimatePaise,
  taxConfirmed,
}: {
  config: CompConfig | null;
  startsOn: string;
  context: EngineContext;
  gstRateBps: number;
  sections: TdsSection[];
  estimatePaise: number | null;
  taxConfirmed: boolean;
}) {
  const t = useTranslations();
  const [s, setS] = useState<Scenario>({ ...DEFAULT, avg_commission_gross_paise: estimatePaise ?? undefined });
  const deferred = useDeferredValue(s);
  const result = useMemo(() => {
    if (!config) return null;
    const parsed = scenarioSchema.safeParse(deferred);
    if (!parsed.success) return { error: true as const };
    return simulate(config, parsed.data, { starts_on: startsOn, context, sections, gst_rate_bps: gstRateBps });
  }, [config, deferred, startsOn, context, sections, gstRateBps]);
  return (
    <Card>
      <CardHeader title={t("deals.simulator.title")} description={t("deals.simulator.staffHint")} />
      <div className="flex flex-col gap-4">
        <ScenarioForm value={s} onChange={setS} staff />
        {!taxConfirmed ? <Banner tone="warning">{t("deals.simulator.confirmWithCa")}</Banner> : null}
        {!config ? <p className="text-sm text-muted">{t("deals.simulator.fixErrors")}</p> : null}
        {result && "error" in result ? <p className="text-sm text-danger">{t("deals.errors.scenario")}</p> : null}
        {result && !("error" in result) ? (
          <>
            <ResultView r={result} />
            <div className="rounded-xl bg-surface-2 p-3">
              <h4 className="mb-1 text-sm font-semibold">{t("deals.simulator.eduwit")}</h4>
              <dl>
                <Row label={t("deals.simulator.revenue")} value={result.eduwit.revenue_paise} />
                <Row label={t("deals.simulator.cost")} value={result.eduwit.cost_paise} />
                {result.eduwit.cost_per_enrollment_paise !== null ? (
                  <Row label={t("deals.simulator.costPerEnrolment")} value={result.eduwit.cost_per_enrollment_paise} />
                ) : null}
                <Row label={t("deals.simulator.margin")} value={result.eduwit.margin_paise} strong />
              </dl>
              {result.eduwit.margin_bps !== null ? (
                <p className="text-xs text-muted">
                  {t("deals.simulator.marginPct", { pct: result.eduwit.margin_bps / 100 })}
                </p>
              ) : (
                <p className="text-xs text-muted">{t("deals.simulator.noRevenue")}</p>
              )}
            </div>
          </>
        ) : null}
      </div>
    </Card>
  );
}

/** The creator's read-only simulator on their own deal (server-computed; no Eduwit figures). */
export function CreatorSimulator({ dealId, versionId }: { dealId: string; versionId?: string }) {
  const t = useTranslations();
  const [s, setS] = useState<Scenario>(DEFAULT);
  const deferred = useDeferredValue(s);
  const [state, setState] = useState<{ result: CreatorSimulation | null; error: string | null; key: string }>({
    result: null,
    error: null,
    key: "",
  });
  const key = JSON.stringify(deferred);
  useEffect(() => {
    let live = true;
    const id = setTimeout(() => {
      const { avg_commission_gross_paise: _drop, ...scenario } = deferred;
      void simulateMyDeal({ dealId, versionId, scenario }).then((r) => {
        if (!live) return;
        setState(r.ok ? { result: r.data ?? null, error: null, key } : { result: null, error: r.error, key });
      });
    }, 350);
    return () => {
      live = false;
      clearTimeout(id);
    };
  }, [deferred, dealId, versionId, key]);
  const loading = state.key !== key;
  return (
    <Card>
      <CardHeader title={t("deals.simulator.title")} description={t("deals.simulator.creatorHint")} />
      <div className="flex flex-col gap-4">
        <ScenarioForm value={s} onChange={setS} staff={false} />
        {state.error ? <p className="text-sm text-danger">{state.error}</p> : null}
        <div className={loading ? "opacity-60" : undefined} aria-busy={loading}>
          {state.result ? (
            <ResultView r={state.result} />
          ) : loading ? (
            <p className="text-sm text-muted">{t("common.loading")}</p>
          ) : null}
        </div>
        <p className="text-xs text-muted">{t("deals.simulator.estimateNote")}</p>
      </div>
    </Card>
  );
}
