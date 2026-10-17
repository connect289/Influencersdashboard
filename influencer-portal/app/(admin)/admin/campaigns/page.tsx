import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { CAMPAIGN_STATUSES, type CampaignStatus } from "@/lib/campaigns/schemas";
import { formatDate, formatPaise } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.campaigns") };
}

export default async function CampaignsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { supabase, me } = await requireStaff("campaign.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const status = (CAMPAIGN_STATUSES as readonly string[]).includes(sp.status ?? "")
    ? (sp.status as CampaignStatus)
    : null;
  let q = supabase
    .from("campaigns")
    .select("id, name, status, objective, apply_by, ends_on, budget_paise, slots, updated_at")
    .order("updated_at", { ascending: false })
    .limit(200);
  q = status ? q.eq("status", status) : q.neq("status", "archived");
  const [campaigns, apps] = await Promise.all([
    q,
    supabase.from("campaign_applications").select("campaign_id, status").limit(10000),
  ]);
  const counts = new Map<string, { review: number; accepted: number }>();
  for (const a of apps.data ?? []) {
    const c = counts.get(a.campaign_id) ?? { review: 0, accepted: 0 };
    if (a.status === "submitted" || a.status === "countered") c.review++;
    if (a.status === "accepted") c.accepted++;
    counts.set(a.campaign_id, c);
  }
  const rows = campaigns.data ?? [];
  const tabs: (CampaignStatus | null)[] = [
    null,
    "draft",
    "open",
    "invite_only",
    "active",
    "paused",
    "completed",
    "archived",
  ];
  return (
    <>
      <PageHeader
        title={t("nav.admin.campaigns")}
        description={t("campaigns.subtitle")}
        actions={
          me.permissions.has("campaign.write") ? (
            <Button asChild>
              <Link href="/admin/campaigns/new">
                <Plus /> {t("campaigns.new")}
              </Link>
            </Button>
          ) : null
        }
      />
      <nav
        className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("campaigns.filterByStatus")}
      >
        {tabs.map((s) => (
          <Link
            key={s ?? "all"}
            href={s ? `/admin/campaigns?status=${s}` : "/admin/campaigns"}
            aria-current={status === s ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              status === s ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {s ? t(`campaigns.statuses.${s}`) : t("campaigns.allLive")}
          </Link>
        ))}
      </nav>
      <Card>
        {campaigns.error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
        {!campaigns.error && rows.length === 0 ? (
          <EmptyState title={t("campaigns.empty")} description={t("campaigns.emptyHint")} />
        ) : null}
        {rows.length ? (
          <Table>
            <thead>
              <tr>
                <Th>{t("campaigns.fields.name")}</Th>
                <Th>{t("campaigns.table.status")}</Th>
                <Th>{t("campaigns.fields.applyBy")}</Th>
                <Th>{t("campaigns.table.toReview")}</Th>
                <Th>{t("campaigns.table.accepted")}</Th>
                <Th>{t("campaigns.fields.budget")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((c) => {
                const n = counts.get(c.id) ?? { review: 0, accepted: 0 };
                return (
                  <tr key={c.id}>
                    <Td>
                      <Link href={`/admin/campaigns/${c.id}`} className="font-medium text-primary hover:underline">
                        {c.name}
                      </Link>
                      <span className="block text-xs text-muted">
                        {t(`campaigns.objectives.${c.objective as "leads"}`)}
                      </span>
                    </Td>
                    <Td>
                      <StatusBadge status={c.status} label={t(`campaigns.statuses.${c.status as CampaignStatus}`)} />
                    </Td>
                    <Td>{c.apply_by ? formatDate(c.apply_by) : "—"}</Td>
                    <Td>{n.review ? <Badge family="attention">{n.review}</Badge> : "0"}</Td>
                    <Td className="tabular-nums">
                      {n.accepted}
                      {c.slots ? ` / ${String(c.slots)}` : ""}
                    </Td>
                    <Td className="tabular-nums">
                      {c.budget_paise !== null ? formatPaise(c.budget_paise, { whole: true }) : "—"}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        ) : null}
      </Card>
    </>
  );
}
