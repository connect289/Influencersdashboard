"use client";
// Amendment dry-run (spec 6.3): what the working copy would change if it took effect at a chosen time.
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { useAction } from "@/components/ui/use-action";
import { dryRunAmendment } from "@/lib/actions/deals";
import type { CompConfig } from "@/lib/compensation/schema";
import { scenario as scenarioSchema } from "@/lib/compensation/simulator";
import type { DryRunResult } from "@/lib/deals/dry-run";
import { formatPaise } from "@/lib/format";
import { IntInput } from "./inputs";

const signed = (p: number | null) => (p === null ? "—" : formatPaise(p));

export function DryRunPanel({ dealId, draft }: { dealId: string; draft: CompConfig }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [effectiveFrom, setEffectiveFrom] = useState("");
  const [leads, setLeads] = useState(30);
  const [enrollments, setEnrollments] = useState(5);
  const [views, setViews] = useState(50_000);
  const [result, setResult] = useState<DryRunResult | null>(null);
  return (
    <Card>
      <CardHeader title={t("deals.dryRun.title")} description={t("deals.dryRun.hint")} />
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () =>
              dryRunAmendment({
                dealId,
                config: draft,
                effectiveFrom,
                scenario: scenarioSchema.parse({
                  leads,
                  qualified_leads: Math.round(leads / 3),
                  enrollments,
                  views,
                }),
              }),
            (data) => setResult(data ?? null),
          );
        }}
      >
        <div className="grid gap-3 sm:grid-cols-4">
          <Field id="dr-from" label={t("deals.actions.effectiveFrom")} className="sm:col-span-2">
            <Input
              id="dr-from"
              type="datetime-local"
              value={effectiveFrom}
              onChange={(e) => setEffectiveFrom(e.target.value)}
            />
          </Field>
          <Field id="dr-leads" label={t("deals.scenario.leads")}>
            <IntInput id="dr-leads" int={leads} onInt={setLeads} />
          </Field>
          <Field id="dr-enr" label={t("deals.scenario.enrollments")}>
            <IntInput id="dr-enr" int={enrollments} onInt={setEnrollments} />
          </Field>
          <Field id="dr-views" label={t("deals.scenario.views")}>
            <IntInput id="dr-views" int={views} onInt={setViews} />
          </Field>
        </div>
        <div className="flex justify-end">
          <Button type="submit" variant="secondary" disabled={pending}>
            {t("deals.dryRun.run")}
          </Button>
        </div>
      </form>
      {result ? (
        <div className="mt-4 flex flex-col gap-3" aria-live="polite">
          <dl className="grid grid-cols-3 gap-3 text-center">
            <div>
              <dt className="text-xs text-muted">{t("deals.dryRun.before")}</dt>
              <dd className="font-semibold tabular-nums">{formatPaise(result.before.net_paise)}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">{t("deals.dryRun.after")}</dt>
              <dd className="font-semibold tabular-nums">{formatPaise(result.after.net_paise)}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">{t("deals.dryRun.delta")}</dt>
              <dd className={`font-semibold tabular-nums ${result.delta_paise < 0 ? "text-danger" : "text-success"}`}>
                {formatPaise(result.delta_paise)}
              </dd>
            </div>
          </dl>
          {result.changes.length === 0 ? (
            <EmptyState title={t("deals.dryRun.noChanges")} description={t("deals.dryRun.noChangesHint")} />
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>{t("deals.dryRun.line")}</Th>
                  <Th>{t("deals.dryRun.before")}</Th>
                  <Th>{t("deals.dryRun.after")}</Th>
                </tr>
              </thead>
              <tbody>
                {result.changes.slice(0, 200).map((c) => (
                  <tr key={c.key}>
                    <Td>
                      {t(`deals.entryTypes.${c.type}`)}
                      <span className="block text-xs text-muted">{c.subject}</span>
                    </Td>
                    <Td className="tabular-nums">{signed(c.before_paise)}</Td>
                    <Td className="tabular-nums">{signed(c.after_paise)}</Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
        </div>
      ) : null}
    </Card>
  );
}
