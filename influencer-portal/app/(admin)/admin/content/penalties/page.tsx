import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ContentNav } from "@/components/content/content-nav";
import { PenaltyActions } from "@/components/content/penalty-actions";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { listPenalties, PENALTY_STATUSES, type PenaltyStatus } from "@/lib/content/data";
import { formatDate, formatPaise } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("content.area.penalties") };
}

export default async function PenaltiesPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { supabase, me } = await requireStaff("deliverable.read");
  const t = await getTranslations();
  const raw = (await searchParams).status;
  const status: PenaltyStatus | null =
    raw === "all"
      ? null
      : (PENALTY_STATUSES as readonly string[]).includes(raw ?? "")
        ? (raw as PenaltyStatus)
        : "proposed";
  const allowed =
    me.permissions.has("penalty.approve") || me.permissions.has("ledger.read") || me.permissions.has("deal.read");
  const rows = allowed ? await listPenalties(supabase, { status }).catch(() => null) : [];
  const canDecide = me.permissions.has("penalty.approve");
  return (
    <>
      <PageHeader
        title={t("nav.admin.content")}
        description={t("content.penalties.subtitle")}
        help="/admin/help/influencer-manager#penalties"
      />
      <ContentNav current="penalties" />
      <nav
        className="-mx-4 mb-3 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("content.penalties.filter")}
      >
        {([...PENALTY_STATUSES, null] as (PenaltyStatus | null)[]).map((s) => (
          <Link
            key={s ?? "all"}
            href={`/admin/content/penalties?status=${s ?? "all"}`}
            aria-current={status === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              status === s ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {s ? t(`content.penalties.statuses.${s}`) : t("content.penalties.all")}
          </Link>
        ))}
      </nav>
      <Card>
        {rows === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : rows.length === 0 ? (
          <EmptyState title={t("content.penalties.empty")} description={t("content.penalties.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("content.penalties.columns.what")}</Th>
                <Th>{t("content.penalties.columns.deal")}</Th>
                <Th className="text-right">{t("content.penalties.columns.amount")}</Th>
                <Th>{t("content.penalties.columns.status")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}>
                  <Td>
                    <span className="font-medium">{p.reason}</span>
                    {p.deliverable_id ? (
                      <Link
                        href={`/admin/content/${p.deliverable_id}`}
                        className="block text-xs text-primary hover:underline"
                      >
                        {p.deliverable_title}
                      </Link>
                    ) : null}
                    <span className="block text-xs text-muted">{formatDate(p.proposed_at)}</span>
                  </Td>
                  <Td>
                    <Link href={`/admin/deals/${p.deal_id}?tab=content`} className="hover:underline">
                      {p.deal_title}
                    </Link>
                    <span className="block text-xs text-muted">{p.creator_name}</span>
                  </Td>
                  <Td className="text-right tabular-nums">
                    {formatPaise(p.amount_paise)}
                    {p.forfeits.length ? (
                      <Badge family="attention" className="mt-1">
                        {t("content.penalties.forfeits", { count: p.forfeits.length })}
                      </Badge>
                    ) : null}
                  </Td>
                  <Td>
                    {p.status === "proposed" && canDecide ? (
                      <PenaltyActions id={p.id} />
                    ) : (
                      <>
                        <StatusBadge status={p.status} label={t(`content.penalties.statuses.${p.status}`)} />
                        {p.decision_note ? <span className="block text-xs text-muted">{p.decision_note}</span> : null}
                      </>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
