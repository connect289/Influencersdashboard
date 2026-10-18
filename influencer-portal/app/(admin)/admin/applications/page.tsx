import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { formatCompact, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";

const VIEWS = {
  review: ["submitted", "countered", "shortlisted"],
  accepted: ["accepted"],
  closed: ["rejected", "withdrawn"],
} as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.applications") };
}

export default async function ApplicationsPage({ searchParams }: { searchParams: Promise<{ view?: string }> }) {
  const { supabase } = await requireStaff("campaign.read");
  const t = await getTranslations();
  const v = (await searchParams).view;
  const view = v === "accepted" || v === "closed" ? v : "review";
  const { data, error } = await supabase.rpc("applications_list", { p_status: [...VIEWS[view]] });
  const rows = data ?? [];
  return (
    <>
      <PageHeader title={t("nav.admin.applications")} description={t("campaigns.applicationsSubtitle")} />
      <nav className="mb-4 flex gap-1" aria-label={t("campaigns.filterByStatus")}>
        {(Object.keys(VIEWS) as (keyof typeof VIEWS)[]).map((k) => (
          <Link
            key={k}
            href={k === "review" ? "/admin/applications" : `/admin/applications?view=${k}`}
            aria-current={view === k ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm",
              view === k ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`campaigns.applicationViews.${k}`)}
          </Link>
        ))}
      </nav>
      <Card>
        {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
        {!error && rows.length === 0 ? <EmptyState title={t("campaigns.applicationsEmpty")} /> : null}
        {rows.length ? (
          <Table>
            <thead>
              <tr>
                <Th>{t("campaigns.application.creator")}</Th>
                <Th>{t("campaigns.application.campaign")}</Th>
                <Th>{t("campaigns.table.status")}</Th>
                <Th>{t("creators.table.followers")}</Th>
                <Th>{t("campaigns.table.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => (
                <tr key={a.id}>
                  <Td>
                    <Link href={`/admin/applications/${a.id}`} className="font-medium text-primary hover:underline">
                      {a.display_name}
                    </Link>
                    <span className="block text-xs text-muted">@{a.handle}</span>
                  </Td>
                  <Td>
                    <Link href={`/admin/campaigns/${a.campaign_id}`} className="hover:underline">
                      {a.campaign_name}
                    </Link>
                  </Td>
                  <Td>
                    <span className="flex flex-col items-start gap-1">
                      <StatusBadge
                        status={a.status}
                        label={t(`campaigns.applicationStatuses.${a.status as "submitted"}`)}
                      />
                      {a.open_offer_from === "creator" ? (
                        <Badge family="attention">{t("campaigns.application.yourMove")}</Badge>
                      ) : null}
                    </span>
                  </Td>
                  <Td className="tabular-nums">{formatCompact(a.followers)}</Td>
                  <Td>{formatRelative(a.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        ) : null}
      </Card>
    </>
  );
}
