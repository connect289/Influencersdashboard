// A deal version's terms in plain language (spec 6: creators must understand exactly how they earn). Works in server
// and client components. Shows only the creator's own terms: no Eduwit margin or commission amounts.
import { useTranslations } from "next-intl";
import type { ReactNode } from "react";
import type { CompConfig, Milestone, Trigger } from "@/lib/compensation/schema";
import { fixedValue } from "@/lib/compensation/schema";
import { formatDate, formatNumber, formatPaise } from "@/lib/format";

type T = ReturnType<typeof useTranslations>;
const money = (p: number) => formatPaise(p, { whole: p % 100 === 0 });

function triggerText(t: T, x: Trigger): string {
  const deliverable = "deliverable" in x && x.deliverable ? x.deliverable : "";
  const base =
    x.type === "after_n_days_live"
      ? t("deals.summary.triggerAfterDays", { days: x.days })
      : x.type === "on_metric_threshold"
        ? t("deals.summary.triggerMetric", {
            metric: t(`deals.metrics.${x.metric}`),
            threshold: formatNumber(x.threshold),
          })
        : x.type === "on_specific_date"
          ? t("deals.summary.triggerDate", { date: formatDate(x.date) })
          : t(`deals.triggers.${x.type}`);
  return deliverable ? t("deals.summary.triggerFor", { trigger: base, deliverable }) : base;
}

function milestoneText(t: T, m: Milestone, total: number): string {
  const share =
    m.share.type === "pct"
      ? t("deals.summary.pctOf", {
          pct: m.share.pct,
          amount: money(Math.round((total * m.share.pct) / 100)),
        })
      : money(m.share.amount_paise);
  const days = m.due_offset_days + m.payment_terms_days;
  const parts = [`${m.label}: ${share}, ${triggerText(t, m.trigger)}`];
  if (days) parts.push(t("deals.summary.paidWithin", { days }));
  if (m.on_cancel.type === "pay_pct") parts.push(t("deals.summary.cancelPays", { pct: m.on_cancel.pct }));
  return parts.join(" · ");
}

function Block({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-1.5">
      <h3 className="text-sm font-semibold">{title}</h3>
      <ul className="flex list-disc flex-col gap-1 pl-5 text-sm">{children}</ul>
    </section>
  );
}

export function TermsSummary({ config: c }: { config: CompConfig }) {
  const t = useTranslations();
  const empty = !c.fixed.length && !c.commission.length && !c.bonuses.length && !c.fees.length && !c.non_cash.length;
  if (empty) return <p className="text-sm text-muted">{t("deals.summary.empty")}</p>;
  return (
    <div className="flex flex-col gap-4">
      {c.fixed.length ? (
        <Block title={t("deals.sections.fixed")}>
          {c.fixed.map((f) => {
            const total = f.amount_paise * f.units;
            return (
              <li key={f.id}>
                <span className="font-medium">{f.label}</span>:{" "}
                {f.basis === "retainer" && f.retainer
                  ? t("deals.summary.retainer", {
                      amount: money(f.amount_paise),
                      periods: f.retainer.periods,
                      every: t(`deals.builder.${f.retainer.every}`),
                      when: t(
                        f.retainer.pay_on === "period_start" ? "deals.builder.periodStart" : "deals.builder.periodEnd",
                      ),
                    })
                  : f.units > 1
                    ? t("deals.summary.perUnit", {
                        amount: money(f.amount_paise),
                        units: f.units,
                        unit: f.unit_label ?? t("deals.builder.units"),
                        total: money(total),
                      })
                    : money(total)}
                {f.milestones.length ? (
                  <ul className="mt-1 list-[circle] pl-5 text-muted">
                    {f.milestones.map((m) => (
                      <li key={m.id}>{milestoneText(t, m, total)}</li>
                    ))}
                  </ul>
                ) : null}
              </li>
            );
          })}
        </Block>
      ) : null}

      {c.commission.length ? (
        <Block title={t("deals.sections.commission")}>
          {c.commission.map((r) => {
            const rate = "amount_paise" in r.basis ? money(r.basis.amount_paise) : `${String(r.basis.pct)}%`;
            const extras: string[] = [];
            if (r.scope.type !== "all")
              extras.push(t("deals.summary.scope", { scope: t(`deals.scopes.${r.scope.type}`) }));
            if (r.slabs)
              extras.push(
                t("deals.summary.slabs", {
                  mode: t(`deals.slabModes.${r.slabs.mode}`),
                  period: t(`deals.slabPeriods.${r.slabs.period}`),
                  tiers: r.slabs.tiers
                    .map(
                      (x) =>
                        `${String(x.from)}+: ${x.amount_paise !== undefined ? money(x.amount_paise) : `${String(x.pct ?? 0)}%`}`,
                    )
                    .join(", "),
                }),
              );
            if (r.caps.per_unit_paise !== undefined)
              extras.push(t("deals.summary.capUnit", { amount: money(r.caps.per_unit_paise) }));
            if (r.caps.per_month_paise !== undefined)
              extras.push(t("deals.summary.capMonth", { amount: money(r.caps.per_month_paise) }));
            if (r.caps.lifetime_paise !== undefined)
              extras.push(t("deals.summary.capLife", { amount: money(r.caps.lifetime_paise) }));
            extras.push(t(`deals.confirmations.${r.confirmation.type}`));
            if (r.clawback_window_days !== undefined)
              extras.push(t("deals.summary.clawback", { days: r.clawback_window_days }));
            if (r.effective_from || r.effective_to)
              extras.push(
                t("deals.summary.between", {
                  from: r.effective_from ? formatDate(r.effective_from) : "—",
                  to: r.effective_to ? formatDate(r.effective_to) : "—",
                }),
              );
            return (
              <li key={r.id}>
                <span className="font-medium">{r.label}</span>: {t(`deals.summary.bases.${r.basis.type}`, { rate })}
                {r.basis.type === "pct_of_eduwit_commission"
                  ? ` (${t(r.basis.base === "net_of_gst" ? "deals.builder.netOfGst" : "deals.builder.grossInclGst")})`
                  : ""}
                <span className="block text-muted">{extras.join(" · ")}</span>
              </li>
            );
          })}
          {c.recoupment.mode !== "none" ? (
            <li>
              {c.recoupment.mode === "full"
                ? t("deals.summary.recoupFull", {
                    amount: money(fixedValue(c, c.recoupment.fixed)),
                  })
                : t("deals.summary.recoupPartial", {
                    pct: c.recoupment.pct,
                    amount: money(fixedValue(c, c.recoupment.fixed)),
                  })}
            </li>
          ) : null}
          {c.floors.map((f) => (
            <li key={f.id}>
              {t("deals.summary.floor", {
                amount: money(f.amount_paise),
                period: t(f.period === "month" ? "deals.builder.month" : "deals.builder.wholeDeal"),
              })}
            </li>
          ))}
        </Block>
      ) : null}

      {c.bonuses.length ? (
        <Block title={t("deals.sections.bonuses")}>
          {c.bonuses.map((b) => (
            <li key={b.id}>
              <span className="font-medium">{b.label}</span>:{" "}
              {b.amount.type === "fixed"
                ? money(b.amount.amount_paise)
                : t(`deals.summary.bonusPct.${b.amount.type}`, { pct: b.amount.pct })}
              {" — "}
              {b.conditions.items
                .map(
                  (x) =>
                    `${t(`deals.bonusMetrics.${x.metric}`)} ${x.comparator === "gte" ? "≥" : "≤"} ${formatNumber(x.value)}`,
                )
                .join(b.conditions.op === "and" ? ` ${t("deals.summary.and")} ` : ` ${t("deals.summary.or")} `)}
              {" · "}
              {b.window.type === "dates"
                ? t("deals.summary.dates", {
                    from: formatDate(b.window.from),
                    to: formatDate(b.window.to),
                  })
                : t(`deals.windows.${b.window.type}`)}
              {b.repeat === "every" ? ` · ${t("deals.builder.everyWindow")}` : ""}
            </li>
          ))}
        </Block>
      ) : null}

      {c.penalties.length ? (
        <Block title={t("deals.sections.penalties")}>
          {c.penalties.map((p) => (
            <li key={p.id}>
              <span className="font-medium">{p.label}</span>:{" "}
              {p.type === "late_delivery"
                ? t("deals.summary.late", {
                    grace: p.grace_days,
                    rate: p.per_day.type === "pct" ? `${String(p.per_day.pct)}%` : money(p.per_day.amount_paise),
                  })
                : p.type === "missed_deliverable"
                  ? p.action.type === "fixed"
                    ? t("deals.summary.missedFixed", { amount: money(p.action.amount_paise) })
                    : t("deals.summary.missedForfeit")
                  : p.type === "disclosure"
                    ? money(p.amount_paise)
                    : t("deals.summary.breach", { pct: p.pct })}
            </li>
          ))}
          <li className="list-none text-muted">{t("deals.summary.penaltiesApproved")}</li>
        </Block>
      ) : null}

      {c.fees.length ? (
        <Block title={t("deals.sections.fees")}>
          {c.fees.map((f) => (
            <li key={f.id}>
              <span className="font-medium">{f.label}</span> ({t(`deals.feeKinds.${f.kind}`)}): {money(f.amount_paise)},{" "}
              {triggerText(t, f.trigger)}
              {f.duration_days ? ` · ${t("deals.summary.duration", { days: f.duration_days })}` : ""}
              {f.platforms.length ? ` · ${f.platforms.join(", ")}` : ""}
            </li>
          ))}
        </Block>
      ) : null}

      {c.non_cash.length ? (
        <Block title={t("deals.sections.non_cash")}>
          {c.non_cash.map((n) => (
            <li key={n.id}>
              {n.label}: {money(n.value_paise)} <span className="text-muted">({t("deals.summary.notPaidOut")})</span>
            </li>
          ))}
        </Block>
      ) : null}
    </div>
  );
}
