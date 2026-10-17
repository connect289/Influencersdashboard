"use client";
// The compensation builder (spec 6.1): every component type of a deal version, edited as one validated document.
// Each section edits its slice of the config; ids are assigned on creation and never change (ledger keys use them).
import { Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import {
  BASIS_TYPES,
  BONUS_METRICS,
  CONFIRMATIONS,
  FEE_KINDS,
  FIXED_BASES,
  FLAT_BASES,
  METRICS,
  TRIGGER_TYPES,
  type AdditionalFee,
  type Basis,
  type BonusRule,
  type CommissionRule,
  type CompConfig,
  type FixedComponent,
  type FloorRule,
  type Milestone,
  type PenaltyRule,
  type Scope,
  type Trigger,
} from "@/lib/compensation/schema";
import {
  BONUS_AMOUNTS,
  BONUS_WINDOWS,
  defaultMilestones,
  defaultTrigger,
  newBonus,
  newFee,
  newFixed,
  newFloor,
  newMilestone,
  newNonCash,
  newPenalty,
  newRule,
  PENALTY_TYPES,
  RECOUP_MODES,
  SCOPE_TYPES,
  SLAB_MODES,
  SLAB_PERIODS,
  type NonCash,
} from "@/lib/deals/builder";
import { cn } from "@/lib/utils";
import { IntInput, PctInput, RupeeInput } from "./inputs";

type Set<T> = (v: T) => void;
const replace = <T,>(xs: readonly T[], i: number, v: T): T[] => xs.map((x, j) => (j === i ? v : x));
const remove = <T,>(xs: readonly T[], i: number): T[] => xs.filter((_, j) => j !== i);
const csv = (v: string) =>
  v
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
const ints = (v: string) =>
  csv(v)
    .map(Number)
    .filter((n) => Number.isInteger(n) && n > 0);

function Item({
  title,
  onRemove,
  removeLabel,
  children,
}: {
  title: string;
  onRemove: () => void;
  removeLabel: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 rounded-xl p-3 ring-1 ring-line ring-inset">
      <div className="flex items-center justify-between gap-2">
        <h4 className="truncate text-sm font-semibold">{title}</h4>
        <Button type="button" variant="ghost" size="sm" onClick={onRemove} aria-label={removeLabel}>
          <Trash2 />
        </Button>
      </div>
      {children}
    </div>
  );
}

const grid = "grid gap-3 sm:grid-cols-2";

// ---------------------------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------------------------
function TriggerEditor({ id, value, onChange }: { id: string; value: Trigger; onChange: Set<Trigger> }) {
  const t = useTranslations();
  return (
    <div className={grid}>
      <Field id={`${id}-type`} label={t("deals.builder.trigger")}>
        <Select
          id={`${id}-type`}
          value={value.type}
          onChange={(e) => onChange(defaultTrigger(e.target.value as Trigger["type"]))}
        >
          {TRIGGER_TYPES.map((x) => (
            <option key={x} value={x}>
              {t(`deals.triggers.${x}`)}
            </option>
          ))}
        </Select>
      </Field>
      {"deliverable" in value ||
      [
        "on_concept_approved",
        "on_draft_approved",
        "on_deliverable_live",
        "after_n_days_live",
        "on_metric_threshold",
      ].includes(value.type) ? (
        <Field id={`${id}-deliv`} label={t("deals.builder.deliverable")} hint={t("deals.builder.deliverableHint")}>
          <Input
            id={`${id}-deliv`}
            value={"deliverable" in value ? (value.deliverable ?? "") : ""}
            maxLength={40}
            onChange={(e) =>
              onChange({ ...value, deliverable: e.target.value.trim().toLowerCase() || undefined } as Trigger)
            }
          />
        </Field>
      ) : null}
      {value.type === "after_n_days_live" ? (
        <Field id={`${id}-days`} label={t("deals.builder.daysLive")}>
          <IntInput id={`${id}-days`} int={value.days} onInt={(n) => onChange({ ...value, days: n })} />
        </Field>
      ) : null}
      {value.type === "on_metric_threshold" ? (
        <>
          <Field id={`${id}-metric`} label={t("deals.builder.metric")}>
            <Select
              id={`${id}-metric`}
              value={value.metric}
              onChange={(e) => onChange({ ...value, metric: e.target.value as (typeof METRICS)[number] })}
            >
              {METRICS.map((m) => (
                <option key={m} value={m}>
                  {t(`deals.metrics.${m}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id={`${id}-thr`} label={t("deals.builder.threshold")}>
            <IntInput id={`${id}-thr`} int={value.threshold} onInt={(n) => onChange({ ...value, threshold: n })} />
          </Field>
        </>
      ) : null}
      {value.type === "on_specific_date" ? (
        <Field id={`${id}-date`} label={t("deals.builder.date")}>
          <Input
            id={`${id}-date`}
            type="date"
            value={value.date}
            onChange={(e) => onChange({ ...value, date: e.target.value })}
          />
        </Field>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// A. Fixed fees
// ---------------------------------------------------------------------------------------------------------------
function MilestoneEditor({ id, m, onChange }: { id: string; m: Milestone; onChange: Set<Milestone> }) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-3">
      <div className={grid}>
        <Field id={`${id}-label`} label={t("deals.builder.label")}>
          <Input
            id={`${id}-label`}
            value={m.label}
            maxLength={80}
            onChange={(e) => onChange({ ...m, label: e.target.value })}
          />
        </Field>
        <Field
          id={`${id}-share`}
          label={m.share.type === "pct" ? t("deals.builder.sharePct") : t("deals.builder.shareAmount")}
        >
          {m.share.type === "pct" ? (
            <PctInput
              id={`${id}-share`}
              pct={m.share.pct}
              onPct={(pct) => onChange({ ...m, share: { type: "pct", pct } })}
            />
          ) : (
            <RupeeInput
              id={`${id}-share`}
              paise={m.share.amount_paise}
              onPaise={(p) => onChange({ ...m, share: { type: "amount", amount_paise: p } })}
            />
          )}
        </Field>
      </div>
      <TriggerEditor id={`${id}-trg`} value={m.trigger} onChange={(trigger) => onChange({ ...m, trigger })} />
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-offset`} label={t("deals.builder.dueOffset")}>
          <IntInput id={`${id}-offset`} int={m.due_offset_days} onInt={(n) => onChange({ ...m, due_offset_days: n })} />
        </Field>
        <Field id={`${id}-terms`} label={t("deals.builder.paymentTerms")}>
          <IntInput
            id={`${id}-terms`}
            int={m.payment_terms_days}
            onInt={(n) => onChange({ ...m, payment_terms_days: n })}
          />
        </Field>
        <Field id={`${id}-cancel`} label={t("deals.builder.onCancel")}>
          <Select
            id={`${id}-cancel`}
            value={m.on_cancel.type}
            onChange={(e) =>
              onChange({
                ...m,
                on_cancel: e.target.value === "forfeit" ? { type: "forfeit" } : { type: "pay_pct", pct: 50 },
              })
            }
          >
            <option value="forfeit">{t("deals.builder.forfeit")}</option>
            <option value="pay_pct">{t("deals.builder.payPct")}</option>
          </Select>
        </Field>
        {m.on_cancel.type === "pay_pct" ? (
          <Field id={`${id}-cpct`} label={t("deals.builder.cancelPct")}>
            <PctInput
              id={`${id}-cpct`}
              pct={m.on_cancel.pct}
              onPct={(pct) => onChange({ ...m, on_cancel: { type: "pay_pct", pct } })}
            />
          </Field>
        ) : null}
      </div>
    </div>
  );
}

type Retainer = NonNullable<FixedComponent["retainer"]>;

function RetainerEditor({ id, value, onChange }: { id: string; value: Retainer; onChange: Set<Retainer> }) {
  const t = useTranslations();
  return (
    <div className="grid gap-3 sm:grid-cols-4">
      <Field id={`${id}-periods`} label={t("deals.builder.periods")}>
        <IntInput
          id={`${id}-periods`}
          int={value.periods}
          onInt={(n) => onChange({ ...value, periods: Math.max(n, 1) })}
        />
      </Field>
      <Field id={`${id}-every`} label={t("deals.builder.every")}>
        <Select
          id={`${id}-every`}
          value={value.every}
          onChange={(e) => onChange({ ...value, every: e.target.value as "week" | "month" })}
        >
          <option value="week">{t("deals.builder.week")}</option>
          <option value="month">{t("deals.builder.month")}</option>
        </Select>
      </Field>
      <Field id={`${id}-payon`} label={t("deals.builder.payOn")}>
        <Select
          id={`${id}-payon`}
          value={value.pay_on}
          onChange={(e) => onChange({ ...value, pay_on: e.target.value as "period_start" | "period_end" })}
        >
          <option value="period_start">{t("deals.builder.periodStart")}</option>
          <option value="period_end">{t("deals.builder.periodEnd")}</option>
        </Select>
      </Field>
      <Field id={`${id}-rterms`} label={t("deals.builder.paymentTerms")}>
        <IntInput
          id={`${id}-rterms`}
          int={value.payment_terms_days}
          onInt={(n) => onChange({ ...value, payment_terms_days: n })}
        />
      </Field>
    </div>
  );
}

type Slabs = NonNullable<CommissionRule["slabs"]>;

function SlabEditor({ id, flat, slabs, onChange }: { id: string; flat: boolean; slabs: Slabs; onChange: Set<Slabs> }) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-3 rounded-xl bg-surface-2 p-3">
      <div className={grid}>
        <Field id={`${id}-sp`} label={t("deals.builder.slabPeriod")}>
          <Select
            id={`${id}-sp`}
            value={slabs.period}
            onChange={(e) => onChange({ ...slabs, period: e.target.value as (typeof SLAB_PERIODS)[number] })}
          >
            {SLAB_PERIODS.map((p) => (
              <option key={p} value={p}>
                {t(`deals.slabPeriods.${p}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={`${id}-sm`} label={t("deals.builder.slabMode")}>
          <Select
            id={`${id}-sm`}
            value={slabs.mode}
            onChange={(e) => onChange({ ...slabs, mode: e.target.value as (typeof SLAB_MODES)[number] })}
          >
            {SLAB_MODES.map((m) => (
              <option key={m} value={m}>
                {t(`deals.slabModes.${m}`)}
              </option>
            ))}
          </Select>
        </Field>
      </div>
      {slabs.tiers.map((tier, i) => (
        <div key={i} className="grid grid-cols-[1fr_1fr_auto] items-end gap-2">
          <Field id={`${id}-tf${String(i)}`} label={t("deals.builder.fromUnit")}>
            <IntInput
              id={`${id}-tf${String(i)}`}
              int={tier.from}
              onInt={(n) => onChange({ ...slabs, tiers: replace(slabs.tiers, i, { ...tier, from: n }) })}
            />
          </Field>
          <Field id={`${id}-tr${String(i)}`} label={flat ? t("deals.builder.amountPerUnit") : t("deals.builder.rate")}>
            {flat ? (
              <RupeeInput
                id={`${id}-tr${String(i)}`}
                paise={tier.amount_paise ?? null}
                onPaise={(p) => onChange({ ...slabs, tiers: replace(slabs.tiers, i, { ...tier, amount_paise: p }) })}
              />
            ) : (
              <PctInput
                id={`${id}-tr${String(i)}`}
                pct={tier.pct ?? null}
                onPct={(pct) => onChange({ ...slabs, tiers: replace(slabs.tiers, i, { ...tier, pct }) })}
              />
            )}
          </Field>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            disabled={slabs.tiers.length <= 2}
            aria-label={t("deals.builder.removeTier")}
            onClick={() => onChange({ ...slabs, tiers: remove(slabs.tiers, i) })}
          >
            <Trash2 />
          </Button>
        </div>
      ))}
      <Button
        type="button"
        variant="secondary"
        size="sm"
        className="self-start"
        disabled={slabs.tiers.length >= 20}
        onClick={() => {
          const last = slabs.tiers.at(-1);
          onChange({ ...slabs, tiers: [...slabs.tiers, { ...last, from: (last?.from ?? 0) + 10 }] });
        }}
      >
        <Plus /> {t("deals.builder.addTier")}
      </Button>
    </div>
  );
}

function FixedEditor({ f, onChange }: { f: FixedComponent; onChange: Set<FixedComponent> }) {
  const t = useTranslations();
  const id = `fx-${f.id}`;
  const shareType = f.milestones[0]?.share.type ?? "pct";
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-label`} label={t("deals.builder.label")}>
          <Input
            id={`${id}-label`}
            value={f.label}
            maxLength={80}
            onChange={(e) => onChange({ ...f, label: e.target.value })}
          />
        </Field>
        <Field id={`${id}-basis`} label={t("deals.builder.fixedBasis")}>
          <Select
            id={`${id}-basis`}
            value={f.basis}
            onChange={(e) => {
              const basis = e.target.value as FixedComponent["basis"];
              onChange(
                basis === "retainer"
                  ? {
                      ...f,
                      basis,
                      units: 1,
                      milestones: [],
                      retainer: f.retainer ?? {
                        periods: 3,
                        every: "month",
                        pay_on: "period_end",
                        payment_terms_days: 7,
                      },
                    }
                  : {
                      ...f,
                      basis,
                      retainer: undefined,
                      milestones: f.milestones.length ? f.milestones : defaultMilestones(t("deals.builder.whenLive")),
                    },
              );
            }}
          >
            {FIXED_BASES.map((b) => (
              <option key={b} value={b}>
                {t(`deals.fixedBases.${b}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id={`${id}-amount`}
          label={
            f.basis === "lump_sum"
              ? t("deals.builder.amount")
              : f.basis === "retainer"
                ? t("deals.builder.perPeriod")
                : t("deals.builder.perUnit")
          }
        >
          <RupeeInput id={`${id}-amount`} paise={f.amount_paise} onPaise={(p) => onChange({ ...f, amount_paise: p })} />
        </Field>
        {f.basis === "per_deliverable" || f.basis === "per_unit" ? (
          <>
            <Field id={`${id}-units`} label={t("deals.builder.units")}>
              <IntInput id={`${id}-units`} int={f.units} onInt={(n) => onChange({ ...f, units: Math.max(n, 1) })} />
            </Field>
            <Field id={`${id}-ulabel`} label={t("deals.builder.unitLabel")}>
              <Input
                id={`${id}-ulabel`}
                value={f.unit_label ?? ""}
                maxLength={40}
                onChange={(e) => onChange({ ...f, unit_label: e.target.value || undefined })}
              />
            </Field>
          </>
        ) : null}
      </div>
      {f.basis === "retainer" && f.retainer ? (
        <RetainerEditor id={id} value={f.retainer} onChange={(retainer) => onChange({ ...f, retainer })} />
      ) : null}
      {f.basis !== "retainer" ? (
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h5 className="text-sm font-medium">{t("deals.builder.milestones")}</h5>
            <Select
              aria-label={t("deals.builder.splitBy")}
              className="w-auto"
              value={shareType}
              onChange={(e) =>
                onChange({
                  ...f,
                  milestones: f.milestones.map((m) => ({
                    ...m,
                    share:
                      e.target.value === "pct"
                        ? { type: "pct" as const, pct: 0 }
                        : { type: "amount" as const, amount_paise: 0 },
                  })),
                })
              }
            >
              <option value="pct">{t("deals.builder.splitPct")}</option>
              <option value="amount">{t("deals.builder.splitAmount")}</option>
            </Select>
          </div>
          {f.milestones.map((m, i) => (
            <Item
              key={m.id}
              title={m.label || t("deals.builder.untitled")}
              removeLabel={t("deals.builder.remove", { name: m.label })}
              onRemove={() => onChange({ ...f, milestones: remove(f.milestones, i) })}
            >
              <MilestoneEditor
                id={`${id}-${m.id}`}
                m={m}
                onChange={(x) => onChange({ ...f, milestones: replace(f.milestones, i, x) })}
              />
            </Item>
          ))}
          <Button
            type="button"
            variant="secondary"
            size="sm"
            className="self-start"
            disabled={f.milestones.length >= 50}
            onClick={() =>
              onChange({ ...f, milestones: [...f.milestones, newMilestone(f, t("deals.builder.newMilestone"))] })
            }
          >
            <Plus /> {t("deals.builder.addMilestone")}
          </Button>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// B. Commission
// ---------------------------------------------------------------------------------------------------------------
function basisFor(type: Basis["type"], prev: Basis): Basis {
  const amount = "amount_paise" in prev ? prev.amount_paise : 1_000_00;
  const pct = "pct" in prev ? prev.pct : 10;
  if (type === "pct_of_eduwit_commission") return { type, pct, base: "net_of_gst" };
  if (type === "pct_of_programme_fee") return { type, pct };
  return { type, amount_paise: amount };
}

function scopeFor(type: Scope["type"]): Scope {
  switch (type) {
    case "all":
      return { type };
    case "levels":
      return { type, levels: ["PG"] };
    case "links":
      return { type, codes: ["CODE"] };
    case "deliverables":
      return { type, ids: ["reel"] };
    default:
      return { type, ids: [1] };
  }
}

function RuleEditor({ r, onChange }: { r: CommissionRule; onChange: Set<CommissionRule> }) {
  const t = useTranslations();
  const id = `cr-${r.id}`;
  const flat = FLAT_BASES.includes(r.basis.type);
  const scopeText =
    r.scope.type === "all"
      ? ""
      : r.scope.type === "levels"
        ? r.scope.levels.join(", ")
        : r.scope.type === "links"
          ? r.scope.codes.join(", ")
          : r.scope.ids.join(", ");
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-label`} label={t("deals.builder.label")}>
          <Input
            id={`${id}-label`}
            value={r.label}
            maxLength={80}
            onChange={(e) => onChange({ ...r, label: e.target.value })}
          />
        </Field>
        <Field id={`${id}-basis`} label={t("deals.builder.basis")}>
          <Select
            id={`${id}-basis`}
            value={r.basis.type}
            onChange={(e) =>
              onChange({ ...r, basis: basisFor(e.target.value as Basis["type"], r.basis), slabs: undefined })
            }
          >
            {BASIS_TYPES.map((b) => (
              <option key={b} value={b}>
                {t(`deals.bases.${b}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={`${id}-rate`} label={flat ? t("deals.builder.amountPerUnit") : t("deals.builder.rate")}>
          {"amount_paise" in r.basis ? (
            <RupeeInput
              id={`${id}-rate`}
              paise={r.basis.amount_paise}
              onPaise={(p) => onChange({ ...r, basis: { ...r.basis, amount_paise: p } as Basis })}
            />
          ) : (
            <PctInput
              id={`${id}-rate`}
              pct={r.basis.pct}
              onPct={(pct) => onChange({ ...r, basis: { ...r.basis, pct } as Basis })}
            />
          )}
        </Field>
        {r.basis.type === "pct_of_eduwit_commission" ? (
          <Field id={`${id}-base`} label={t("deals.builder.commissionBase")}>
            <Select
              id={`${id}-base`}
              value={r.basis.base}
              onChange={(e) =>
                onChange({
                  ...r,
                  basis: { ...r.basis, base: e.target.value as "net_of_gst" | "gross_incl_gst" } as Basis,
                })
              }
            >
              <option value="net_of_gst">{t("deals.builder.netOfGst")}</option>
              <option value="gross_incl_gst">{t("deals.builder.grossInclGst")}</option>
            </Select>
          </Field>
        ) : null}
        <Field id={`${id}-scope`} label={t("deals.builder.scope")}>
          <Select
            id={`${id}-scope`}
            value={r.scope.type}
            onChange={(e) => onChange({ ...r, scope: scopeFor(e.target.value as Scope["type"]) })}
          >
            {SCOPE_TYPES.map((s) => (
              <option key={s} value={s}>
                {t(`deals.scopes.${s}`)}
              </option>
            ))}
          </Select>
        </Field>
        {r.scope.type !== "all" ? (
          <Field id={`${id}-scopev`} label={t("deals.builder.scopeValues")} hint={t("deals.builder.commaSeparated")}>
            <Input
              id={`${id}-scopev`}
              value={scopeText}
              onChange={(e) => {
                const sc = r.scope;
                const v = e.target.value;
                onChange({
                  ...r,
                  scope:
                    sc.type === "levels"
                      ? { type: "levels", levels: csv(v) }
                      : sc.type === "links"
                        ? { type: "links", codes: csv(v).map((x) => x.toUpperCase()) }
                        : sc.type === "deliverables"
                          ? { type: "deliverables", ids: csv(v).map((x) => x.toLowerCase()) }
                          : sc.type === "programmes"
                            ? { type: "programmes", ids: ints(v) }
                            : { type: "universities", ids: ints(v) },
                });
              }}
            />
          </Field>
        ) : null}
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-conf`} label={t("deals.builder.confirmation")}>
          <Select
            id={`${id}-conf`}
            value={r.confirmation.type}
            onChange={(e) => {
              const type = e.target.value as CommissionRule["confirmation"]["type"];
              onChange({ ...r, confirmation: type === "after_hold_days" ? { type, days: 30 } : { type } });
            }}
          >
            {CONFIRMATIONS.map((c) => (
              <option key={c} value={c}>
                {t(`deals.confirmations.${c}`)}
              </option>
            ))}
          </Select>
        </Field>
        {r.confirmation.type === "after_hold_days" ? (
          <Field id={`${id}-hold`} label={t("deals.builder.holdDays")}>
            <IntInput
              id={`${id}-hold`}
              int={r.confirmation.days ?? null}
              onInt={(n) => onChange({ ...r, confirmation: { type: "after_hold_days", days: n } })}
            />
          </Field>
        ) : null}
        <Field id={`${id}-claw`} label={t("deals.builder.clawbackDays")} hint={t("deals.builder.defaultSetting")}>
          <IntInput
            id={`${id}-claw`}
            int={r.clawback_window_days ?? null}
            onInt={(n) => onChange({ ...r, clawback_window_days: n || undefined })}
          />
        </Field>
        <Field id={`${id}-from`} label={t("deals.builder.effectiveFrom")}>
          <Input
            id={`${id}-from`}
            type="date"
            value={r.effective_from ?? ""}
            onChange={(e) => onChange({ ...r, effective_from: e.target.value || undefined })}
          />
        </Field>
        <Field id={`${id}-to`} label={t("deals.builder.effectiveTo")}>
          <Input
            id={`${id}-to`}
            type="date"
            value={r.effective_to ?? ""}
            onChange={(e) => onChange({ ...r, effective_to: e.target.value || undefined })}
          />
        </Field>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        {(["per_unit_paise", "per_month_paise", "lifetime_paise"] as const).map((k) => (
          <Field key={k} id={`${id}-${k}`} label={t(`deals.caps.${k}`)} hint={t("deals.builder.optional")}>
            <RupeeInput
              id={`${id}-${k}`}
              paise={r.caps[k] ?? null}
              onPaise={(p) => onChange({ ...r, caps: { ...r.caps, [k]: p > 0 ? p : undefined } })}
            />
          </Field>
        ))}
      </div>

      <div className="flex flex-col gap-3">
        <label className="flex items-center gap-2 text-sm font-medium">
          <input
            type="checkbox"
            checked={!!r.slabs}
            onChange={(e) =>
              onChange({
                ...r,
                slabs: e.target.checked
                  ? {
                      period: "deal",
                      mode: "marginal",
                      tiers: flat
                        ? [
                            { from: 1, amount_paise: "amount_paise" in r.basis ? r.basis.amount_paise : 0 },
                            { from: 10, amount_paise: "amount_paise" in r.basis ? r.basis.amount_paise : 0 },
                          ]
                        : [
                            { from: 1, pct: "pct" in r.basis ? r.basis.pct : 0 },
                            { from: 10, pct: "pct" in r.basis ? r.basis.pct : 0 },
                          ],
                    }
                  : undefined,
              })
            }
          />
          {t("deals.builder.useSlabs")}
        </label>
        {r.slabs ? (
          <SlabEditor id={id} flat={flat} slabs={r.slabs} onChange={(slabs) => onChange({ ...r, slabs })} />
        ) : null}
      </div>
    </div>
  );
}

function FloorEditor({ f, rules, onChange }: { f: FloorRule; rules: CommissionRule[]; onChange: Set<FloorRule> }) {
  const t = useTranslations();
  const id = `fl-${f.id}`;
  return (
    <div className="grid gap-3 sm:grid-cols-3">
      <Field id={`${id}-label`} label={t("deals.builder.label")}>
        <Input
          id={`${id}-label`}
          value={f.label}
          maxLength={80}
          onChange={(e) => onChange({ ...f, label: e.target.value })}
        />
      </Field>
      <Field id={`${id}-amount`} label={t("deals.builder.minimum")}>
        <RupeeInput id={`${id}-amount`} paise={f.amount_paise} onPaise={(p) => onChange({ ...f, amount_paise: p })} />
      </Field>
      <Field id={`${id}-period`} label={t("deals.builder.per")}>
        <Select
          id={`${id}-period`}
          value={f.period}
          onChange={(e) => onChange({ ...f, period: e.target.value as "month" | "deal" })}
        >
          <option value="month">{t("deals.builder.month")}</option>
          <option value="deal">{t("deals.builder.wholeDeal")}</option>
        </Select>
      </Field>
      {rules.length > 1 ? (
        <fieldset className="flex flex-col gap-1 sm:col-span-3">
          <legend className="text-sm font-medium">{t("deals.builder.floorRules")}</legend>
          {rules.map((r) => (
            <label key={r.id} className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={f.rules.includes(r.id)}
                onChange={(e) =>
                  onChange({ ...f, rules: e.target.checked ? [...f.rules, r.id] : f.rules.filter((x) => x !== r.id) })
                }
              />
              {r.label}
            </label>
          ))}
        </fieldset>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// C. Bonuses, D. penalties, E. fees, F. non-cash
// ---------------------------------------------------------------------------------------------------------------
function BonusEditor({ b, onChange }: { b: BonusRule; onChange: Set<BonusRule> }) {
  const t = useTranslations();
  const id = `bn-${b.id}`;
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-label`} label={t("deals.builder.label")}>
          <Input
            id={`${id}-label`}
            value={b.label}
            maxLength={80}
            onChange={(e) => onChange({ ...b, label: e.target.value })}
          />
        </Field>
        <Field id={`${id}-win`} label={t("deals.builder.window")}>
          <Select
            id={`${id}-win`}
            value={b.window.type}
            onChange={(e) => {
              const type = e.target.value as (typeof BONUS_WINDOWS)[number];
              const today = new Date().toISOString().slice(0, 10);
              onChange({ ...b, window: type === "dates" ? { type, from: today, to: today } : { type } });
            }}
          >
            {BONUS_WINDOWS.map((w) => (
              <option key={w} value={w}>
                {t(`deals.windows.${w}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={`${id}-repeat`} label={t("deals.builder.repeat")}>
          <Select
            id={`${id}-repeat`}
            value={b.repeat}
            onChange={(e) => onChange({ ...b, repeat: e.target.value as "once" | "every" })}
          >
            <option value="once">{t("deals.builder.once")}</option>
            <option value="every">{t("deals.builder.everyWindow")}</option>
          </Select>
        </Field>
        {b.window.type === "dates" ? (
          <>
            <Field id={`${id}-wf`} label={t("deals.builder.from")}>
              <Input
                id={`${id}-wf`}
                type="date"
                value={b.window.from}
                onChange={(e) =>
                  onChange({ ...b, window: { ...b.window, from: e.target.value } as BonusRule["window"] })
                }
              />
            </Field>
            <Field id={`${id}-wt`} label={t("deals.builder.to")}>
              <Input
                id={`${id}-wt`}
                type="date"
                value={b.window.to}
                onChange={(e) => onChange({ ...b, window: { ...b.window, to: e.target.value } as BonusRule["window"] })}
              />
            </Field>
          </>
        ) : null}
      </div>
      <div className="flex flex-col gap-2">
        <div className="flex items-center gap-2 text-sm">
          <span className="font-medium">{t("deals.builder.when")}</span>
          <Select
            aria-label={t("deals.builder.combine")}
            className="w-auto"
            value={b.conditions.op}
            onChange={(e) => onChange({ ...b, conditions: { ...b.conditions, op: e.target.value as "and" | "or" } })}
          >
            <option value="and">{t("deals.builder.all")}</option>
            <option value="or">{t("deals.builder.any")}</option>
          </Select>
        </div>
        {b.conditions.items.map((c, i) => (
          <div key={i} className="grid grid-cols-[1fr_auto_1fr_auto] items-end gap-2">
            <Select
              aria-label={t("deals.builder.metric")}
              value={c.metric}
              onChange={(e) =>
                onChange({
                  ...b,
                  conditions: {
                    ...b.conditions,
                    items: replace(b.conditions.items, i, {
                      ...c,
                      metric: e.target.value as (typeof BONUS_METRICS)[number],
                    }),
                  },
                })
              }
            >
              {BONUS_METRICS.map((m) => (
                <option key={m} value={m}>
                  {t(`deals.bonusMetrics.${m}`)}
                </option>
              ))}
            </Select>
            <Select
              aria-label={t("deals.builder.comparator")}
              className="w-auto"
              value={c.comparator}
              onChange={(e) =>
                onChange({
                  ...b,
                  conditions: {
                    ...b.conditions,
                    items: replace(b.conditions.items, i, { ...c, comparator: e.target.value as "gte" | "lte" }),
                  },
                })
              }
            >
              <option value="gte">≥</option>
              <option value="lte">≤</option>
            </Select>
            <IntInput
              aria-label={t("deals.builder.value")}
              int={c.value}
              onInt={(n) =>
                onChange({
                  ...b,
                  conditions: { ...b.conditions, items: replace(b.conditions.items, i, { ...c, value: n }) },
                })
              }
            />
            <Button
              type="button"
              variant="ghost"
              size="sm"
              disabled={b.conditions.items.length <= 1}
              aria-label={t("deals.builder.removeCondition")}
              onClick={() => onChange({ ...b, conditions: { ...b.conditions, items: remove(b.conditions.items, i) } })}
            >
              <Trash2 />
            </Button>
          </div>
        ))}
        <Button
          type="button"
          variant="secondary"
          size="sm"
          className="self-start"
          disabled={b.conditions.items.length >= 10}
          onClick={() =>
            onChange({
              ...b,
              conditions: {
                ...b.conditions,
                items: [...b.conditions.items, { metric: "leads", comparator: "gte", value: 10 }],
              },
            })
          }
        >
          <Plus /> {t("deals.builder.addCondition")}
        </Button>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id={`${id}-at`} label={t("deals.builder.bonusAmount")}>
          <Select
            id={`${id}-at`}
            value={b.amount.type}
            onChange={(e) => {
              const type = e.target.value as (typeof BONUS_AMOUNTS)[number];
              onChange({ ...b, amount: type === "fixed" ? { type, amount_paise: 1_000_00 } : { type, pct: 10 } });
            }}
          >
            {BONUS_AMOUNTS.map((a) => (
              <option key={a} value={a}>
                {t(`deals.bonusAmounts.${a}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={`${id}-av`} label={b.amount.type === "fixed" ? t("deals.builder.amount") : t("deals.builder.rate")}>
          {b.amount.type === "fixed" ? (
            <RupeeInput
              id={`${id}-av`}
              paise={b.amount.amount_paise}
              onPaise={(p) => onChange({ ...b, amount: { type: "fixed", amount_paise: p } })}
            />
          ) : (
            <PctInput
              id={`${id}-av`}
              pct={b.amount.pct}
              onPct={(pct) => onChange({ ...b, amount: { ...b.amount, pct } as BonusRule["amount"] })}
            />
          )}
        </Field>
      </div>
    </div>
  );
}

function PenaltyEditor({ p, onChange }: { p: PenaltyRule; onChange: Set<PenaltyRule> }) {
  const t = useTranslations();
  const id = `pn-${p.id}`;
  return (
    <div className="grid gap-3 sm:grid-cols-3">
      <Field id={`${id}-label`} label={t("deals.builder.label")}>
        <Input
          id={`${id}-label`}
          value={p.label}
          maxLength={80}
          onChange={(e) => onChange({ ...p, label: e.target.value })}
        />
      </Field>
      {p.type === "late_delivery" ? (
        <>
          <Field id={`${id}-grace`} label={t("deals.builder.graceDays")}>
            <IntInput id={`${id}-grace`} int={p.grace_days} onInt={(n) => onChange({ ...p, grace_days: n })} />
          </Field>
          <Field id={`${id}-pdt`} label={t("deals.builder.perDay")}>
            <Select
              id={`${id}-pdt`}
              value={p.per_day.type}
              onChange={(e) =>
                onChange({
                  ...p,
                  per_day:
                    e.target.value === "pct" ? { type: "pct", pct: 1 } : { type: "amount", amount_paise: 500_00 },
                })
              }
            >
              <option value="pct">{t("deals.builder.pctOfMilestone")}</option>
              <option value="amount">{t("deals.builder.fixedAmount")}</option>
            </Select>
          </Field>
          <Field id={`${id}-pdv`} label={t("deals.builder.perDayValue")}>
            {p.per_day.type === "pct" ? (
              <PctInput
                id={`${id}-pdv`}
                pct={p.per_day.pct}
                onPct={(pct) => onChange({ ...p, per_day: { type: "pct", pct } })}
              />
            ) : (
              <RupeeInput
                id={`${id}-pdv`}
                paise={p.per_day.amount_paise}
                onPaise={(a) => onChange({ ...p, per_day: { type: "amount", amount_paise: a } })}
              />
            )}
          </Field>
          <Field id={`${id}-cap`} label={t("deals.builder.penaltyCap")} hint={t("deals.builder.optional")}>
            <RupeeInput
              id={`${id}-cap`}
              paise={p.cap?.type === "amount" ? p.cap.amount_paise : null}
              onPaise={(a) => onChange({ ...p, cap: a > 0 ? { type: "amount", amount_paise: a } : undefined })}
            />
          </Field>
        </>
      ) : null}
      {p.type === "missed_deliverable" ? (
        <>
          <Field id={`${id}-act`} label={t("deals.builder.action")}>
            <Select
              id={`${id}-act`}
              value={p.action.type}
              onChange={(e) =>
                onChange({
                  ...p,
                  action:
                    e.target.value === "fixed"
                      ? { type: "fixed", amount_paise: 1_000_00 }
                      : { type: "forfeit_milestones" },
                })
              }
            >
              <option value="forfeit_milestones">{t("deals.builder.forfeitMilestones")}</option>
              <option value="fixed">{t("deals.builder.fixedPenalty")}</option>
            </Select>
          </Field>
          {p.action.type === "fixed" ? (
            <Field id={`${id}-amt`} label={t("deals.builder.amount")}>
              <RupeeInput
                id={`${id}-amt`}
                paise={p.action.amount_paise}
                onPaise={(a) => onChange({ ...p, action: { type: "fixed", amount_paise: a } })}
              />
            </Field>
          ) : null}
        </>
      ) : null}
      {p.type === "disclosure" ? (
        <Field id={`${id}-amt`} label={t("deals.builder.amount")}>
          <RupeeInput id={`${id}-amt`} paise={p.amount_paise} onPaise={(a) => onChange({ ...p, amount_paise: a })} />
        </Field>
      ) : null}
      {p.type === "breach_clawback" ? (
        <Field id={`${id}-pct`} label={t("deals.builder.breachPct")}>
          <PctInput id={`${id}-pct`} pct={p.pct} onPct={(pct) => onChange({ ...p, pct })} />
        </Field>
      ) : null}
    </div>
  );
}

function FeeEditor({ f, onChange }: { f: AdditionalFee; onChange: Set<AdditionalFee> }) {
  const t = useTranslations();
  const id = `fe-${f.id}`;
  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`${id}-kind`} label={t("deals.builder.kind")}>
          <Select
            id={`${id}-kind`}
            value={f.kind}
            onChange={(e) => onChange({ ...f, kind: e.target.value as AdditionalFee["kind"] })}
          >
            {FEE_KINDS.map((k) => (
              <option key={k} value={k}>
                {t(`deals.feeKinds.${k}`)}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={`${id}-label`} label={t("deals.builder.label")}>
          <Input
            id={`${id}-label`}
            value={f.label}
            maxLength={80}
            onChange={(e) => onChange({ ...f, label: e.target.value })}
          />
        </Field>
        <Field id={`${id}-amount`} label={t("deals.builder.amount")}>
          <RupeeInput id={`${id}-amount`} paise={f.amount_paise} onPaise={(p) => onChange({ ...f, amount_paise: p })} />
        </Field>
        {f.kind !== "reimbursement" ? (
          <>
            <Field id={`${id}-plat`} label={t("deals.builder.platforms")} hint={t("deals.builder.commaSeparated")}>
              <Input
                id={`${id}-plat`}
                value={f.platforms.join(", ")}
                onChange={(e) => onChange({ ...f, platforms: csv(e.target.value).slice(0, 8) })}
              />
            </Field>
            <Field id={`${id}-dur`} label={t("deals.builder.durationDays")}>
              <IntInput
                id={`${id}-dur`}
                int={f.duration_days ?? null}
                onInt={(n) => onChange({ ...f, duration_days: n || undefined })}
              />
            </Field>
          </>
        ) : null}
        {f.kind === "exclusivity" ? (
          <Field id={`${id}-cat`} label={t("deals.builder.category")}>
            <Input
              id={`${id}-cat`}
              value={f.category ?? ""}
              maxLength={80}
              onChange={(e) => onChange({ ...f, category: e.target.value || undefined })}
            />
          </Field>
        ) : null}
        <Field id={`${id}-due`} label={t("deals.builder.dueOffset")}>
          <IntInput id={`${id}-due`} int={f.due_offset_days} onInt={(n) => onChange({ ...f, due_offset_days: n })} />
        </Field>
      </div>
      <TriggerEditor id={`${id}-trg`} value={f.trigger} onChange={(trigger) => onChange({ ...f, trigger })} />
    </div>
  );
}

function NonCashEditor({ n, onChange }: { n: NonCash; onChange: Set<NonCash> }) {
  const t = useTranslations();
  const id = `nc-${n.id}`;
  return (
    <div className={grid}>
      <Field id={`${id}-label`} label={t("deals.builder.label")}>
        <Input
          id={`${id}-label`}
          value={n.label}
          maxLength={80}
          onChange={(e) => onChange({ ...n, label: e.target.value })}
        />
      </Field>
      <Field id={`${id}-value`} label={t("deals.builder.value")}>
        <RupeeInput id={`${id}-value`} paise={n.value_paise} onPaise={(p) => onChange({ ...n, value_paise: p })} />
      </Field>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// The builder
// ---------------------------------------------------------------------------------------------------------------
function Section({
  title,
  hint,
  invalid,
  children,
}: {
  title: string;
  hint: string;
  invalid: boolean;
  children: ReactNode;
}) {
  return (
    <Card className={cn(invalid && "ring-2 ring-danger")}>
      <CardHeader title={title} description={hint} />
      <div className="flex flex-col gap-3">{children}</div>
    </Card>
  );
}

function AddButton({ label, onClick, disabled }: { label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <Button type="button" variant="secondary" size="sm" className="self-start" onClick={onClick} disabled={disabled}>
      <Plus /> {label}
    </Button>
  );
}

export function CompBuilder({
  value: c,
  onChange,
  invalidSections,
}: {
  value: CompConfig;
  onChange: Set<CompConfig>;
  invalidSections: ReadonlySet<string>;
}) {
  const t = useTranslations();
  const patch = (p: Partial<CompConfig>) => onChange({ ...c, ...p });
  const removeLabel = (name: string) => t("deals.builder.remove", { name: name || t("deals.builder.untitled") });
  return (
    <div className="flex flex-col gap-4">
      <Section
        title={t("deals.sections.fixed")}
        hint={t("deals.sectionHints.fixed")}
        invalid={invalidSections.has("fixed")}
      >
        {c.fixed.map((f, i) => (
          <Item
            key={f.id}
            title={f.label || t("deals.builder.untitled")}
            removeLabel={removeLabel(f.label)}
            onRemove={() => patch({ fixed: remove(c.fixed, i) })}
          >
            <FixedEditor f={f} onChange={(x) => patch({ fixed: replace(c.fixed, i, x) })} />
          </Item>
        ))}
        <AddButton
          label={t("deals.builder.addFixed")}
          disabled={c.fixed.length >= 20}
          onClick={() =>
            patch({ fixed: [...c.fixed, newFixed(c, t("deals.builder.contentFee"), t("deals.builder.whenLive"))] })
          }
        />
      </Section>

      <Section
        title={t("deals.sections.commission")}
        hint={t("deals.sectionHints.commission")}
        invalid={invalidSections.has("commission")}
      >
        {c.commission.map((r, i) => (
          <Item
            key={r.id}
            title={r.label || t("deals.builder.untitled")}
            removeLabel={removeLabel(r.label)}
            onRemove={() =>
              patch({
                commission: remove(c.commission, i),
                floors: c.floors.map((f) => ({ ...f, rules: f.rules.filter((x) => x !== r.id) })),
              })
            }
          >
            <RuleEditor r={r} onChange={(x) => patch({ commission: replace(c.commission, i, x) })} />
          </Item>
        ))}
        <AddButton
          label={t("deals.builder.addRule")}
          disabled={c.commission.length >= 20}
          onClick={() => patch({ commission: [...c.commission, newRule(c, t("deals.builder.perEnrolment"))] })}
        />
      </Section>

      {c.commission.length ? (
        <Section
          title={t("deals.sections.floors")}
          hint={t("deals.sectionHints.floors")}
          invalid={invalidSections.has("floors")}
        >
          {c.floors.map((f, i) => (
            <Item
              key={f.id}
              title={f.label || t("deals.builder.untitled")}
              removeLabel={removeLabel(f.label)}
              onRemove={() => patch({ floors: remove(c.floors, i) })}
            >
              <FloorEditor f={f} rules={c.commission} onChange={(x) => patch({ floors: replace(c.floors, i, x) })} />
            </Item>
          ))}
          <AddButton
            label={t("deals.builder.addFloor")}
            disabled={c.floors.length >= 10}
            onClick={() => patch({ floors: [...c.floors, newFloor(c, t("deals.builder.monthlyMinimum"))] })}
          />
        </Section>
      ) : null}

      {c.commission.length && c.fixed.length ? (
        <Section
          title={t("deals.sections.recoupment")}
          hint={t("deals.sectionHints.recoupment")}
          invalid={invalidSections.has("recoupment")}
        >
          <div className={grid}>
            <Field id="recoup-mode" label={t("deals.builder.recoupMode")}>
              <Select
                id="recoup-mode"
                value={c.recoupment.mode}
                onChange={(e) => {
                  const mode = e.target.value as (typeof RECOUP_MODES)[number];
                  patch({
                    recoupment:
                      mode === "none" ? { mode } : mode === "full" ? { mode, fixed: [] } : { mode, pct: 50, fixed: [] },
                  });
                }}
              >
                {RECOUP_MODES.map((m) => (
                  <option key={m} value={m}>
                    {t(`deals.recoupModes.${m}`)}
                  </option>
                ))}
              </Select>
            </Field>
            {c.recoupment.mode === "partial" ? (
              <Field id="recoup-pct" label={t("deals.builder.recoupPct")}>
                <PctInput
                  id="recoup-pct"
                  pct={c.recoupment.pct}
                  onPct={(pct) => patch({ recoupment: { ...c.recoupment, pct } as CompConfig["recoupment"] })}
                />
              </Field>
            ) : null}
          </div>
        </Section>
      ) : null}

      <Section
        title={t("deals.sections.bonuses")}
        hint={t("deals.sectionHints.bonuses")}
        invalid={invalidSections.has("bonuses")}
      >
        {c.bonuses.map((b, i) => (
          <Item
            key={b.id}
            title={b.label || t("deals.builder.untitled")}
            removeLabel={removeLabel(b.label)}
            onRemove={() => patch({ bonuses: remove(c.bonuses, i) })}
          >
            <BonusEditor b={b} onChange={(x) => patch({ bonuses: replace(c.bonuses, i, x) })} />
          </Item>
        ))}
        <AddButton
          label={t("deals.builder.addBonus")}
          disabled={c.bonuses.length >= 20}
          onClick={() => patch({ bonuses: [...c.bonuses, newBonus(c, t("deals.builder.performanceBonus"))] })}
        />
      </Section>

      <Section
        title={t("deals.sections.penalties")}
        hint={t("deals.sectionHints.penalties")}
        invalid={invalidSections.has("penalties")}
      >
        {c.penalties.map((p, i) => (
          <Item
            key={p.id}
            title={`${t(`deals.penaltyTypes.${p.type}`)}: ${p.label}`}
            removeLabel={removeLabel(p.label)}
            onRemove={() => patch({ penalties: remove(c.penalties, i) })}
          >
            <PenaltyEditor p={p} onChange={(x) => patch({ penalties: replace(c.penalties, i, x) })} />
          </Item>
        ))}
        <div className="flex flex-wrap gap-2">
          {PENALTY_TYPES.map((type) => (
            <AddButton
              key={type}
              label={t(`deals.penaltyTypes.${type}`)}
              disabled={c.penalties.length >= 20}
              onClick={() =>
                patch({ penalties: [...c.penalties, newPenalty(c, type, t(`deals.penaltyTypes.${type}`))] })
              }
            />
          ))}
        </div>
      </Section>

      <Section
        title={t("deals.sections.fees")}
        hint={t("deals.sectionHints.fees")}
        invalid={invalidSections.has("fees")}
      >
        {c.fees.map((f, i) => (
          <Item
            key={f.id}
            title={f.label || t("deals.builder.untitled")}
            removeLabel={removeLabel(f.label)}
            onRemove={() => patch({ fees: remove(c.fees, i) })}
          >
            <FeeEditor f={f} onChange={(x) => patch({ fees: replace(c.fees, i, x) })} />
          </Item>
        ))}
        <AddButton
          label={t("deals.builder.addFee")}
          disabled={c.fees.length >= 20}
          onClick={() => patch({ fees: [...c.fees, newFee(c, t("deals.feeKinds.usage_rights"))] })}
        />
      </Section>

      <Section
        title={t("deals.sections.non_cash")}
        hint={t("deals.sectionHints.non_cash")}
        invalid={invalidSections.has("non_cash")}
      >
        {c.non_cash.map((n, i) => (
          <Item
            key={n.id}
            title={n.label || t("deals.builder.untitled")}
            removeLabel={removeLabel(n.label)}
            onRemove={() => patch({ non_cash: remove(c.non_cash, i) })}
          >
            <NonCashEditor n={n} onChange={(x) => patch({ non_cash: replace(c.non_cash, i, x) })} />
          </Item>
        ))}
        <AddButton
          label={t("deals.builder.addNonCash")}
          disabled={c.non_cash.length >= 20}
          onClick={() => patch({ non_cash: [...c.non_cash, newNonCash(c, t("deals.builder.inKind"))] })}
        />
      </Section>
    </div>
  );
}
