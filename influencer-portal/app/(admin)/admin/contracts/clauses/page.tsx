import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { ContractsNav } from "@/components/contracts/contracts-nav";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadLibrary } from "@/lib/contracts/data";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.area.clauses") };
}

export default async function ClauseLibraryPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const { supabase, me } = await requireStaff("contract.read");
  const t = await getTranslations();
  const show = (await searchParams).show;
  const filter = show === "unreviewed" || show === "archived" ? show : "all";
  const all = await loadLibrary(supabase, filter === "archived");
  const rows =
    filter === "unreviewed"
      ? all.filter((c) => !c.reviewed_at)
      : filter === "archived"
        ? all.filter((c) => c.archived)
        : all;
  const unreviewed = all.filter((c) => !c.reviewed_at && !c.archived).length;
  const canWrite = me.permissions.has("clause.write");
  return (
    <>
      <PageHeader
        title={t("contracts.area.clauses")}
        description={t("contracts.library.subtitle")}
        help="/admin/help/influencer-manager#contracts"
        actions={
          canWrite ? (
            <Button asChild>
              <Link href="/admin/contracts/clauses/new">
                <Plus /> {t("contracts.library.new")}
              </Link>
            </Button>
          ) : null
        }
      />
      <ContractsNav current="clauses" />
      {unreviewed > 0 ? (
        <Banner tone="warning">{t("contracts.library.unreviewedBanner", { count: unreviewed })}</Banner>
      ) : null}
      <nav className="my-3 flex gap-1" aria-label={t("contracts.library.filter")}>
        {(["all", "unreviewed", "archived"] as const).map((f) => (
          <Link
            key={f}
            href={f === "all" ? "/admin/contracts/clauses" : `/admin/contracts/clauses?show=${f}`}
            aria-current={filter === f ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm",
              filter === f ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`contracts.library.filters.${f}`)}
          </Link>
        ))}
      </nav>
      <Card>
        {rows.length === 0 ? (
          <EmptyState title={t("contracts.library.empty")} description={t("contracts.library.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("contracts.library.fields.title")}</Th>
                <Th>{t("contracts.library.fields.category")}</Th>
                <Th>{t("contracts.library.flags")}</Th>
                <Th>{t("contracts.library.review")}</Th>
                <Th>{t("contracts.library.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((c) => (
                <tr key={c.id} className={c.archived ? "opacity-60" : undefined}>
                  <Td>
                    <Link
                      href={`/admin/contracts/clauses/${c.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {c.title}
                    </Link>
                    <span className="block text-xs text-muted">
                      {c.key} · {t("contracts.library.versionLabel", { version: c.version })}
                    </span>
                  </Td>
                  <Td>{t(`contracts.categories.${c.category as "other"}`)}</Td>
                  <Td>
                    <span className="flex flex-wrap gap-1">
                      {c.required ? <Badge>{t("contracts.flags.required")}</Badge> : null}
                      {c.negotiable ? <Badge family="progress">{t("contracts.flags.negotiable")}</Badge> : null}
                      {c.locked ? <Badge family="closed">{t("contracts.flags.locked")}</Badge> : null}
                      {c.archived ? <Badge>{t("contracts.library.archivedBadge")}</Badge> : null}
                    </span>
                  </Td>
                  <Td>
                    {c.reviewed_at ? (
                      <Badge family="success">{t("contracts.library.reviewedBadge")}</Badge>
                    ) : (
                      <Badge family="attention">{t("contracts.library.unreviewedBadge")}</Badge>
                    )}
                  </Td>
                  <Td className="whitespace-nowrap">{formatDate(c.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
