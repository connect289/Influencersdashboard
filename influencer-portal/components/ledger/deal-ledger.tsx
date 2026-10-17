// A deal's ledger (staff): what is posted, what the next run would change (a dry run against posted entries, spec 6.3),
// manual milestones waiting for release, and recording a breach. Penalty proposals stay on the Content tab.
import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { ErrorState } from "@/components/ui/states";
import type { Permission } from "@/lib/auth/permissions";
import type { CompConfig } from "@/lib/compensation/schema";
import { listLedger } from "@/lib/ledger/data";
import { previewDeal } from "@/lib/ledger/runner";
import type { Db } from "@/lib/contracts/data";
import { formatPaise } from "@/lib/format";
import { Amount, LedgerTable } from "./ledger-table";
import { RecordBreachButton, ReleaseMilestoneButton, RunNowButton } from "./deal-ledger-actions";

export async function DealLedger({
  supabase,
  dealId,
  config,
  released,
  permissions,
}: {
  supabase: Db;
  dealId: string;
  /** The deal's current terms (manual milestones come from here). */
  config: CompConfig | null;
  /** Milestones already released ("<component>.<milestone>"). */
  released: readonly string[];
  permissions: ReadonlySet<Permission>;
}) {
  const t = await getTranslations();
  const canAct = permissions.has("deal.write") || permissions.has("ledger.adjust");
  const [posted, preview] = await Promise.all([
    listLedger(supabase, {
      creator_id: null,
      deal_id: dealId,
      status: null,
      type: null,
      period: null,
      q: null,
      page: 1,
    }).catch(() => null),
    previewDeal(dealId).catch(() => null),
  ]);
  const manual = (config?.fixed ?? []).flatMap((f) =>
    f.milestones
      .filter((m) => m.trigger.type === "manual_release")
      .map((m) => ({ ref: `${f.id}.${m.id}`, label: `${f.label}: ${m.label}` })),
  );
  const plan = preview?.plan;
  const changes = plan ? plan.create.length + plan.confirm.length + plan.reverse.length : 0;
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader
          title={t("finance.deal.posted")}
          description={t("finance.deal.postedHint")}
          actions={canAct ? <RunNowButton dealId={dealId} /> : undefined}
        />
        {posted === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : (
          <LedgerTable
            rows={posted.rows}
            showDeal={false}
            emptyTitle={t("finance.deal.emptyTitle")}
            emptyHint={t("finance.deal.emptyHint")}
          />
        )}
      </Card>
      <Card>
        <CardHeader title={t("finance.deal.preview")} description={t("finance.deal.previewHint")} />
        {plan === undefined ? (
          <p className="text-sm text-muted">{t("finance.deal.noTerms")}</p>
        ) : changes === 0 ? (
          <p className="text-sm text-muted">{t("finance.deal.upToDate")}</p>
        ) : (
          <ul className="flex flex-col gap-1.5 text-sm">
            {plan.create.map((c) => (
              <li key={c.key} className="flex justify-between gap-3">
                <span>
                  <Badge family="progress">{t("finance.deal.willPost")}</Badge> {c.note || t(`finance.types.${c.type}`)}
                </span>
                <Amount paise={c.amount_paise} direction={c.direction} />
              </li>
            ))}
            {plan.confirm.map((c) => (
              <li key={c.key} className="flex justify-between gap-3">
                <span>
                  <Badge family="success">{t("finance.deal.willConfirm")}</Badge>{" "}
                  {c.key.split(":").slice(1, 3).join(" · ")}
                </span>
                <span className="tabular-nums">{formatPaise(c.confirmed_paise)}</span>
              </li>
            ))}
            {plan.reverse.map((r) => (
              <li key={r.key} className="flex justify-between gap-3">
                <span>
                  <Badge family="problem">{t("finance.deal.willReverse")}</Badge>{" "}
                  {r.key.split(":").slice(1, 3).join(" · ")}
                </span>
                <span className="text-muted">{t(`finance.deal.reasons.${r.reason}`)}</span>
              </li>
            ))}
          </ul>
        )}
        {plan?.deferred.length ? (
          <p className="mt-2 text-xs text-muted">{t("finance.deal.deferred", { count: plan.deferred.length })}</p>
        ) : null}
      </Card>
      {manual.length || canAct ? (
        <Card>
          <CardHeader title={t("finance.deal.manualTitle")} description={t("finance.deal.manualHint")} />
          {manual.length ? (
            <ul className="flex flex-col divide-y divide-line">
              {manual.map((m) => (
                <li key={m.ref} className="flex items-center justify-between gap-3 py-2 text-sm">
                  <span>{m.label}</span>
                  {released.includes(m.ref) ? (
                    <Badge family="success">{t("finance.deal.releasedBadge")}</Badge>
                  ) : permissions.has("deal.write") ? (
                    <ReleaseMilestoneButton dealId={dealId} milestone={m.ref} label={m.label} />
                  ) : null}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">{t("finance.deal.noManual")}</p>
          )}
          {permissions.has("deal.write") ? (
            <div className="mt-3 border-t border-line pt-3">
              <RecordBreachButton dealId={dealId} />
            </div>
          ) : null}
        </Card>
      ) : null}
    </div>
  );
}
