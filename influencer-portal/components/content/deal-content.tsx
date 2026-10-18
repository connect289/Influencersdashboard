// The Content tab of a deal (staff): its brief, its deliverables and any penalty proposals.
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import type { Permission } from "@/lib/auth/permissions";
import { listDeliverables, listPenalties } from "@/lib/content/data";
import { formatDate, formatPaise } from "@/lib/format";
import type { ServerSupabase } from "@/lib/supabase/server";
import { AddDeliverable } from "./add-deliverable";
import { CreateBriefButton } from "./create-brief-button";
import { DeliverableStatusBadge, NextStep } from "./deliverable-bits";

export async function DealContent({
  supabase,
  deal,
  permissions,
}: {
  supabase: ServerSupabase;
  deal: { id: string; status: string };
  permissions: ReadonlySet<Permission>;
}) {
  const t = await getTranslations();
  const open = !["completed", "terminated", "expired"].includes(deal.status);
  const canWrite = permissions.has("brief.write") && open;
  const [brief, deliverables, penalties] = await Promise.all([
    supabase.from("briefs").select("id, current_version_id, updated_at").eq("deal_id", deal.id).maybeSingle(),
    permissions.has("deliverable.read")
      ? listDeliverables(supabase, { view: "all", dealId: deal.id }).catch(() => [])
      : Promise.resolve([]),
    permissions.has("penalty.approve") || permissions.has("ledger.read")
      ? listPenalties(supabase, { dealId: deal.id }).catch(() => [])
      : Promise.resolve([]),
  ]);
  const b = brief.data;
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader
          title={t("content.brief.title")}
          description={
            b
              ? b.current_version_id
                ? t("content.deal.briefPublished")
                : t("content.deal.briefDraft")
              : t("content.deal.noBrief")
          }
          actions={
            b ? (
              <Link href={`/admin/briefs/${b.id}`} className="text-sm text-primary hover:underline">
                {t("content.deal.openBrief")}
              </Link>
            ) : canWrite ? (
              <CreateBriefButton dealId={deal.id} />
            ) : null
          }
        />
      </Card>
      {permissions.has("deliverable.read") ? (
        <Card>
          <CardHeader
            title={t("content.brief.deliverables")}
            actions={canWrite ? <AddDeliverable dealId={deal.id} /> : null}
          />
          {deliverables.length === 0 ? (
            <EmptyState title={t("content.deal.noDeliverables")} description={t("content.deal.noDeliverablesHint")} />
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>{t("content.columns.deliverable")}</Th>
                  <Th>{t("content.columns.status")}</Th>
                  <Th>{t("content.columns.next")}</Th>
                </tr>
              </thead>
              <tbody>
                {deliverables.map((d) => (
                  <tr key={d.id}>
                    <Td>
                      <Link href={`/admin/content/${d.id}`} className="font-medium text-primary hover:underline">
                        {d.title}
                      </Link>
                      <span className="block text-xs text-muted">
                        {d.code} · {t(`platforms.${d.platform}`)}
                      </span>
                    </Td>
                    <Td>
                      <DeliverableStatusBadge status={d.status} overdueDays={d.overdue_days} />
                    </Td>
                    <Td>
                      <NextStep stage={d.pending_stage} due={d.due_dates} />
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
        </Card>
      ) : null}
      {penalties.length ? (
        <Card>
          <CardHeader
            title={t("content.penalties.title")}
            actions={
              <Link href="/admin/content/penalties" className="text-sm text-primary hover:underline">
                {t("content.penalties.openAll")}
              </Link>
            }
          />
          <ul className="flex flex-col divide-y divide-line text-sm">
            {penalties.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <span>
                  {p.reason}
                  <span className="block text-xs text-muted">{formatDate(p.proposed_at)}</span>
                </span>
                <span className="flex items-center gap-2">
                  {p.amount_paise ? <span className="tabular-nums">{formatPaise(p.amount_paise)}</span> : null}
                  {p.forfeits.length ? (
                    <Badge family="attention">{t("content.penalties.forfeits", { count: p.forfeits.length })}</Badge>
                  ) : null}
                  <StatusBadge status={p.status} label={t(`content.penalties.statuses.${p.status}`)} />
                </span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
